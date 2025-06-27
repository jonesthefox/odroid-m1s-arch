# Arch Linux on Odroid M1S

## A Word Of Caution

You really should have a serial connection to your M1S, because it makes things a lot easier when
something wents wrong. And using my advice may turn things **terribly** wrong, so don't blame me
when you brick your device! Although it's not so easy to **really** brick your device, it's still possible. 
Check [Recovery steps](README.md#recovery-steps).

<!-- TOC -->

* [Arch Linux on Odroid M1S](#arch-linux-on-odroid-m1s)
    * [Install Images](#install-images)
    * [Assumptions](#assumptions)
    * [Install Toolchain](#install-toolchain)
    * [Set Environment Variables](#set-environment-variables)
    * [Build U-Boot (the easy way)](#build-u-boot-the-easy-way)
    * [Build U-Boot Locally (aka. the other easy way)](#build-u-boot-locally-aka-the-other-easy-way)
        * [Flash to eMMC (via UMS)](#flash-to-emmc-via-ums)
    * [Partitions](#partitions)
    * [Build the Kernel](#build-the-kernel)
        * [Get the Kernel](#get-the-kernel)
        * [Patch the Kernel](#patch-the-kernel)
        * [Compile](#compile)
        * [Kernel Files Needed](#kernel-files-needed)
        * [Build Initramdisk in Arch](#build-initramdisk-in-arch)
    * [Boot the Odroid](#boot-the-odroid)
        * [Commands to Run Kernel, DTB, and Initrd in U-Boot Console](#commands-to-run-kernel-dtb-and-initrd-in-u-boot-console)
    * [Save Boot Commands (Generate Boot.scr)](#save-boot-commands-generate-bootscr)
    * [Generate Backup Image of the whole EMMC via UMS](#generate-backup-image-of-the-whole-emmc-via-ums)
    * [Recovery Steps](#recovery-steps)

<!-- TOC -->

## Install Images

Check [INSTALL.md](INSTALL.md).

## Assumptions

All steps are executed as root. Use `sudo` when necessary or `sudo su` if you're lazy
like me.

## Install Toolchain

On Debian systems:

```bash
apt-get install -y gcc-12 gcc-12-aarch64-linux-gnu python3-pyelftools confget libgnutls28-dev uuid-dev
```

Create symlinks:

```bash
ln -sf aarch64-linux-gnu-cpp-12 /usr/bin/aarch64-linux-gnu-cpp
ln -sf aarch64-linux-gnu-gcc-12 /usr/bin/aarch64-linux-gnu-gcc
ln -sf aarch64-linux-gnu-gcc-ar-12 /usr/bin/aarch64-linux-gnu-gcc-ar
ln -sf aarch64-linux-gnu-gcc-nm-12 /usr/bin/aarch64-linux-gnu-gcc-nm
ln -sf aarch64-linux-gnu-gcc-ranlib-12 /usr/bin/aarch64-linux-gnu-gcc-ranlib
ln -sf aarch64-linux-gnu-gcov-12 /usr/bin/aarch64-linux-gnu-gcov
ln -sf aarch64-linux-gnu-gcov-dump-12 /usr/bin/aarch64-linux-gnu-gcov-dump
ln -sf aarch64-linux-gnu-gcov-tool-12 /usr/bin/aarch64-linux-gnu-gcov-tool
```

## Set Environment Variables

Create a file named `build.source` with the following content:

```bash
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
```

Source the file to set the environment variables:

```bash
source build.source
```

## Build U-Boot (the easy way)

Fork [jonesthefox/u-boot-build](https://github.com/jonesthefox/u-boot-build), it's a
fork
from [github.com/Kwiboo u-boot-build](https://github.com/Kwiboo/u-boot-build) modified
to only
generate binaries for the M1S. Run the Action, set `rk3xxx-2024.10` as u-boot ref,
`master` as rkbin ref and let it generate the artifact `rk3566-odroid-m1s.zip`. Continue
with [Flash to eMMC (via UMS)](#flash-to-emmc-via-ums)

## Build U-Boot Locally (aka. the other easy way)

> **Info:** There is
> a [github_workflow_to_build_uboot.yml](scripts/github_workflow_to_build_uboot.yml) you
> can use in your CI

> **Warning:** Going this route, you should **definitely** connect a serial console to
> the uart pins on your Odroid M1S!

Configure and use the script in [scripts/build/u-boot](scripts/build/u-boot)
named `build_u-boot.sh`. See the [README.md](scripts/build/u-boot/README.md) on how to
use it, it's super simple!

### Flash to eMMC (via UMS)

> **Info:** It _should_ be possible to flash it from the running OS on the Odroid M1S

1. Using the script above will produce the file `u-boot-rockchip.bin` in
   `/usr/src/u-boot-rockchip/` (Except you fiddled with `ROOTPATH`).
2. Using the GitHub workflow generates the artifact `rk3566-odroid-m1s.zip` Extract it
   and you get the `u-boot-rockchip.bin`.

3. Flash that:

Replace sdX with the actual device that your OS presents you for the attached USB mass storage.
Let's assume it's `/dev/sdc`. Note that we don't set a partition number like `/dev/sdc1`!
The u-boot bootloader will be written in the first 16MB on the emmc of your M1S.

```bash
dd if=u-boot-rockchip.bin of=/dev/sdX bs=32k seek=1 conv=fsync
```

## Partitions

Create two partitions: `BOOT` and `rootfs`. The BOOT partition starts at 16MB to allow
room for the U-Boot blob.

1. Use the following `gdisk` commands to create the partitions (i.E. `gdisk /dev/sdX`):

   ```bash
   d               # Delete partition 1
   d               # Delete partition 2 (if present)

   n               # Create a new partition
   1               # Partition number 1
   32768           # Start sector at 16MB so we won't overwrite u-boot
   +256M           # Size of the first partition
   8300            # Set type to Linux filesystem
   n               # Create a new partition
   2               # Partition number 2
   557056          # Start sector (right after the first partition)
   <Enter>         # End sector (uses the remaining space)
   8300            # Set type to Linux filesystem

   p               # Display the current partition table (for verification)
   w               # Save the changes and exit fdisk
   ```

2. Create filesystems:

   ```bash
   mkfs.ext4 /dev/<your usb storage device partition 1> -L BOOT
   mkfs.ext4 /dev/<your usb storage device partition 2> -L rootfs
   ```

## Build the Kernel

It's recommended to build the kernel on a powerful computer since building on the M1S
itself may take a long time.

### Get the Kernel

Clone the Linux kernel repository:

**Note:** When i was working on that, the patches were accepted in the kernel repo, but not yet merged.
The kernel version I used was v6.11-rc5-54-g4f4c35cc85fd

```bash
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux
```

> Ensure you have sourced [build.source](scripts/build/build.source)!

Copy the kernel configuration file [config-odroid-m1s](kernel/config-odroid-m1s) to
`.config` in the kernel source directory and edit it using `make menuconfig`.

### ~~Patch the Kernel~~

Not needed anymore 🥳


### Compile

Set `INSTALL_MOD_PATH` to prevent cluttering the module directory of the cross
compiler host during compilation:

```bash
make -j$(nproc)
make modules -j$(nproc)
make dtbs -j$(nproc)
make INSTALL_MOD_PATH=/usr/src/linux/arch/arm64/boot/modules modules_install
```

### Kernel Files Needed

Copy the compiled kernel files to your boot partition:

```bash
cp <compile cow>/usr/src/linux/arch/arm64/boot/Image <odroid mmcblk0p1>/Image
cp <compile cow>/usr/src/linux/arch/arm64/boot/dts/rockchip/rk3566-odroid-m1s.dtb <odroid mmcblk0p1>/odroid-m1s.dtb
```

Copy the kernel modules:

```bash
rm <compile cow>/usr/src/linux/arch/arm64/boot/modules/lib/modules/6.16.0-rc3-odroid-arm64+/build
cp -r <compile cow>/usr/src/linux/arch/arm64/boot/modules/lib/modules/6.16.0-rc3-odroid-arm64+ <odroid mmcblk0p2>/lib/modules
```

### Build Initramdisk in Arch

> **Note**: This part needs some elaboration. You have to copy your built kernel modules to the odroid running arch linux arm. 

#### On the odroid

Install `mkinitcpio`:

```bash
pacman -S mkinitcpio
```

Build `/initramfs-linux.img`:

copy the built modules of your kernel to your odroid running arch linux arm, 
e.g. `<where you compiled the kernel>/linux/arch/arm64/boot/modules/lib/modules/6.16.0-rc3-odroid-arm64+ -> <odroid mmcblk0p2>/lib/modules/6.16.0-rc3-odroid-arm64+` 

```bash
mkinitcpio -k 6.16.0-rc3-odroid-arm64+ -g /boot/initramfs-linux.img
```

Now transfer the `initramfs-linux.img` to your compile machine.

#### On the compile cow

Convert it to a format supported by U-Boot:

```bash
mkimage -A arm -T ramdisk -C gzip -d initramfs-linux.img uInitrd
```

Put `uInitrd` to the odroid /boot (or a boot partition on a SD card).

## Boot the Odroid

> **WARNING:** You **WILL** need serial console access.

Access the U-Boot console by pressing `CTRL-C` or the `any key` rapidly after powering
on the Odroid.

### Commands to Run Kernel, DTB, and Initrd in U-Boot Console

```bash
# Not needed, our initrd is smaller
# setenv fdt_addr_r 0x08000000
load mmc 0:1 ${kernel_addr_r} Image
load mmc 0:1 ${ramdisk_addr_r} /uInitrd
load mmc 0:1 ${fdt_addr_r} rk3566-odroid-m1s.dtb
setenv bootargs root=/dev/mmcblk0p2 console=ttyS2,1500000
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
```

## Save Boot Commands (Generate Boot.scr)

> **Note:** We mount the root filesystem as read-write because we can, and it's a
> deliberate choice. With an initrd in place (we use one), `fsck` can **and will** run
> properly from there.
> We acknowledge the risk of eMMC wear, which is acceptable given the expected device
> lifespan.

Install u-boot-tools `apt-get install u-boot-tools`

Create the file [boot.cmd](scripts/u-boot/boot.cmd) and generate boot.scr:

```bash
mkimage -C none -A arm -T script -d boot.cmd boot.scr
cp boot.scr <odroid mmcblk0p1>/
```

## Generate Backup Image of the whole EMMC via UMS

First, clean empty space:

> **Info:** Repeat this step for every partition.

```bash
mount /dev/sdX /mnt
dd if=/dev/zero of=/mnt/tmpfile bs=1M status=progress || true
sync
rm /mnt/partition/tmpfile
umount /mnt
```

Then write the image file.

```bash
dd if=/dev/sdX of=/path/to/full_device_image.img bs=4M conv=sparse status=progress
sync
gzip /path/to/image.img
```

To write the image file back to the emmc:

```bash
gzip -dc /path/to/full_device_image.img.gz | dd of=/dev/sdX bs=4M status=progress

```

## Recovery Steps

1. Flash `ODROID-M1S_EMMC2UMS.img` onto an SD card. You find it
   here: [wiki.odroid.com](https://wiki.odroid.com/odroid-m1s/getting_started/os_installation_guide?redirect=1#install_over_usb_from_pc)
2. Insert the SD card into the M1S.
3. Reboot the M1S while shorting the mask ROM pin with GND for a few seconds.

### UMS mode

Hit the `any key` when u-boot starts. Type `ums 0 mmc 0` to serve the whole internal emmc.

> **Usage**:
> ums <USB_controller> [\<devtype\>] <dev[:part]>

## Going forward

The last thing i started fiddling with, was TPM, OP-TEE (Truested Execution Environment), UKI and stuff.. You'll find a
starting point in the `build_u-boot.sh` script, but i never really continued on that. But it should be possible
to add this stuff as well.
