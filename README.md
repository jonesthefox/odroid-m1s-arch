# Arch Linux on Odroid M1S

## Overview

This repository provides everything you need to install and run Arch Linux on the Odroid M1S. It includes:

* Prebuilt Arch Linux images for easy installation (see [INSTALL.md](INSTALL.md)).
* Scripts and instructions to build U-Boot, the Linux kernel, and initramfs.
* Guidance on flashing, partitioning, and backup & recovery procedures.

## ⚠️ Warning

* **Serial connection strongly recommended:** If something goes wrong, a UART console will save your device from a hard brick.
* Follow these instructions at your own risk; bricking is unlikely but possible. See [Recovery](#recovery) for rescue steps.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Install Arch Linux](#install-arch-linux)
3. [Building U-Boot](#building-u-boot)
4. [Partitioning & Flashing](#partitioning--flashing)
5. [Extract Arch Linux ARM generic image](#extract-arch-linux-arm-generic-image)
6. [Building the Linux Kernel](#building-the-linux-kernel)
7. [Initramfs](#initramfs)
8. [Booting the Device](#booting-the-device)
9. [Backup](#backup)
10. [Recovery](#recovery)
11. [Going Forward](#going-forward)

---

## Prerequisites

All commands assume root permissions. Use `sudo` or `sudo su` as needed.

**On Debian-based hosts:**

> You can use my [build\_u-boot.sh](https://github.com/jonesthefox/odroid-m1s-arch/tree/main/scripts/build/u-boot) script to install the dependencies automatically.

```bash
apt-get install -y gcc-12 gcc-12-aarch64-linux-gnu python3-pyelftools libgnutls28-dev uuid-dev u-boot-tools git wget bsdtar
```

**Create cross-compiler symlinks:**

```bash
for tool in cpp gcc gcc-ar gcc-nm gcc-ranlib gcov gcov-dump gcov-tool; do
  ln -sf aarch64-linux-gnu-$tool-12 /usr/bin/aarch64-linux-gnu-$tool
done
```

**Environment variables:**

```bash
# build.source
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
```

Alternatively, source [build.source](https://github.com/jonesthefox/odroid-m1s-arch/blob/main/scripts/build/build.source):

```bash
source build.source
```

---

## Install Arch Linux

For a quick setup using prebuilt images, see [INSTALL.md](INSTALL.md).

---

## Building U-Boot

1. Use the [build\_u-boot.sh](https://github.com/jonesthefox/odroid-m1s-arch/tree/main/scripts/build/u-boot) script (see its `README.md`).
2. The script outputs `u-boot-rockchip.bin` under `/usr/src/u-boot-rockchip/`.

---

## Partitioning & Flashing

> **Note:** `/dev/sdX` may refer to an SD card or the Odroid in UMS mode.

### Flash U-Boot

```bash
dd if=u-boot-rockchip.bin of=/dev/sdX bs=32k seek=1 conv=fsync
```

> **Warning:** Do *not* specify a partition (e.g., `/dev/sdX1`). U-Boot is written to the first 16 MB.

### Create Partitions

1. Run `gdisk /dev/sdX`, then:

   ```bash
   d                # delete existing partitions
   n 1 32768 +256M 8300  # create BOOT partition
   n 2     0   8300      # create rootfs partition
   w                      # write changes
   ```
2. Make filesystems:

   ```bash
   mkfs.ext4 /dev/sdX1 -L BOOT
   mkfs.ext4 /dev/sdX2 -L rootfs
   ```

---

## Extract Arch Linux ARM generic image

1. Download `ArchLinuxARM-aarch64-latest.tar.gz` from [https://archlinuxarm.org/platforms/armv8/generic](https://archlinuxarm.org/platforms/armv8/generic)

2. Extract the image:
   ```bash
   mount /dev/sdX2 /mnt
   bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C /mnt
   ```

---

## Building the Linux Kernel

1. Clone the kernel repo:

   ```bash
   git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
   cd linux
   ```
2. Copy [kernel/config-odroid-m1s](https://github.com/jonesthefox/odroid-m1s-arch/blob/main/kernel/config-odroid-m1s) to `.config` and run `make menuconfig`.
3. Compile:

   ```bash
   make -j$(nproc)
   make modules -j$(nproc)
   make dtbs -j$(nproc)
   make INSTALL_MOD_PATH=/usr/src/linux/arch/arm64/boot/modules modules_install
   ```
4. Copy kernel & DTB to BOOT:

   ```bash
   mount /dev/sdX1 /mnt
   cp arch/arm64/boot/Image /mnt/boot/
   cp arch/arm64/boot/dts/rockchip/rk3566-odroid-m1s.dtb /mnt/boot/
   umount /mnt
   ```
5. Copy modules to rootfs:

   ```bash
   mount /dev/sdX2 /mnt
   cp -r /usr/src/linux/arch/arm64/boot/modules/lib/modules/<version> /mnt/lib/modules/
   umount /mnt
   ```

---

## Initramfs

1. On the Odroid (running Arch):
   **WARNING:** You need a running arch linux arm to do this step, because **boot will fail** without the uInitrd present.
   ```bash
   pacman -S mkinitcpio
   mkinitcpio -k <version> -g /boot/initramfs-linux.img
   ```
2. On the host:

   ```bash
   mkimage -A arm -T ramdisk -C gzip -d initramfs-linux.img uInitrd
   cp uInitrd /mnt/boot/
   ```

---

## Booting the Device

> **WARNING:** Serial console access is required. FB and keyboard support are untested.

Access the U-Boot console by pressing `CTRL-C` or the `any key` rapidly after powering on the Odroid:

```bash
load mmc 0:1 ${kernel_addr_r} Image
load mmc 0:1 ${ramdisk_addr_r} /uInitrd
load mmc 0:1 ${fdt_addr_r} rk3566-odroid-m1s.dtb
setenv bootargs root=/dev/mmcblk0p2 console=ttyS2,1500000
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
```

### Generate boot.scr
Optionally generate `boot.scr` i.e. with my [boot.cmd](https://github.com/jonesthefox/odroid-m1s-arch/blob/main/scripts/u-boot/boot.cmd):

```bash
mkimage -C none -A arm -T script -d boot.cmd boot.scr
mount /dev/sdX1 /mnt
cp boot.scr /mnt/boot/
umount /mnt
```

---

## Backup

### With a handy script

Use the script [scripts/generate_image.sh](https://github.com/jonesthefox/odroid-m1s-arch/blob/main/scripts/generate_image.sh).
Usage: 
   ```bash
   ./generate_image.sh /dev/sdX
   ```

### Manually

1. Zero-fill partitions:

   ```bash
   for part in sdX1 sdX2; do
     mount /dev/$part /mnt
     dd if=/dev/zero of=/mnt/tmpfile bs=1M status=progress || true
     sync
     rm /mnt/tmpfile
     umount /mnt
   done
   ```
2. Create sparse image:

   ```bash
   dd if=/dev/sdX of=odroid-m1s.img bs=4M conv=sparse status=progress
   sync
   gzip odroid-m1s.img
   ```

---

## Recovery

1. Flash `ODROID-M1S_EMMC2UMS.img` to an SD card: see [wiki.odroid.com](https://wiki.odroid.com/odroid-m1s/getting_started/os_installation_guide?redirect=1#install_over_usb_from_pc).
2. Boot with the SD card while shorting the mask ROM pin to GND.
3. In U-Boot, press any key then run:

   ```bash
   ums 0 mmc 0
   ```

---

## Going Forward

Experiment with TPM, OP-TEE, and unified kernel images via `scripts/build/u-boot.sh`.
