# Install Arch Linux on Odroid M1S

This guide walks you through installing Arch Linux on your Odroid M1S using prebuilt images. It’s designed for simplicity and speed—while still allowing a full manual workflow.

## ⚠️ A Word of Caution

* **Serial connection recommended:** A UART console helps diagnose issues if booting fails.
* Follow these steps at your own risk; bricking is unlikely but possible. See [Backup & Recovery](#backup--recovery) for rescue procedures.

## Table of Contents

1. [Start Odroid M1S in UMS Mode](#start-odroid-m1s-in-ums-mode)
2. [The Easy Way](#the-easy-way)
3. [The Extended Way](#the-extended-way)
4. [Backup & Recovery](#backup--recovery)
5. [Going Forward](#going-forward)

---

## Start Odroid M1S in UMS Mode

Insert an SD card prepared with the official UMS image and boot your device into UMS mode:

```bash
ums 0 mmc 0
```

* **Usage:** `ums <USB_controller> [<devtype>] <dev[:part]>`
* Official UMS image: [wiki.odroid.com](https://wiki.odroid.com/odroid-m1s/getting_started/os_installation_guide?redirect=1#install_over_usb_from_pc)
* Run as root or via `sudo`.

---

## The Easy Way

1. **Download the prebuilt image** (`odroid-m1s.img.gz`, ~260 MB)
2. **Flash the image** to your device (SD or UMS-attached eMMC):

   ```bash
   gzip -dc odroid-m1s.img.gz | dd of=/dev/sdX bs=4M status=progress
   sync
   ```
3. **Reboot** the Odroid (remove SD if used for UMS).
4. **Enjoy** your Arch Linux setup!

### Resize rootfs partition

After flashing, verify that the rootfs on the Odroid takes up all free space.

1. **Launch parted**  
   On the host connected to the Odroid via UMS, run:

   ```bash
   sudo parted /dev/sdX
   ```

**Note:** When `parted` warns that not all of the space appears to be used, choose **Fix** to update the GPT header.

2. **Adjust partition size**
   In the `parted` prompt:

   ```bash
   (parted) unit MiB
   (parted) print
   (parted) resizepart 2 100%
   (parted) quit
   ```

3. **Check and grow the filesystem**

   ```bash
   # Repair ANY leftover filesystem inconsistencies and answer 'yes' to all prompts
   e2fsck -fy /dev/sdX2

   # Expand the ext4 filesystem to fill the resized partition
   resize2fs /dev/sdX2
   ```

---

## The Extended Way

Follow these steps if you want full control over U-Boot, partitions, filesystems, and rootfs.

### 1. Install U-Boot

1. **Download** `u-boot-rockchip.bin` (9.20 MB).
2. **Flash** to your device (SD or UMS-attached eMMC):

   ```bash
   dd if=u-boot-rockchip.bin of=/dev/sdX bs=32k seek=1 conv=fsync
   ```

> **Note:** Do *not* use a partition (e.g., `/dev/sdX1`). U-Boot occupies the first 16 MB.

### 2. Create Partitions

1. Run `gdisk /dev/sdX` and enter:

   ```bash
   d                 # delete partition 1 (if any)
   d                 # delete partition 2 (if any)
   n 1 32768 +256M 8300  # BOOT (256 MB)
   n 2     0      8300     # rootfs (remaining space)
   w                   # write changes
   ```

### 3. Create Filesystems

```bash
mkfs.ext4 /dev/sdX1 -L BOOT
mkfs.ext4 /dev/sdX2 -L rootfs
```

### 4. Install Root Filesystem

1. **Download** `ArchLinuxARM-aarch64-latest.tar.gz` from [archlinuxarm.org](https://archlinuxarm.org/platforms/armv8/generic).
2. **Extract** to rootfs partition:

   ```bash
   mount /dev/sdX2 /mnt
   bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C /mnt
   umount /mnt
   ```

### 5. Copy Kernel, DTB, and Modules

Assuming you have built the kernel and modules (see [main README](README.md)):

```bash
# BOOT partition
mount /dev/sdX1 /mnt
cp arch/arm64/boot/Image /mnt/boot/
cp arch/arm64/boot/dts/rockchip/rk3566-odroid-m1s.dtb /mnt/boot/
# copy boot.scr if you generated it
# cp scripts/u-boot/boot.scr /mnt/boot/
umount /mnt

# rootfs modules
mount /dev/sdX2 /mnt
cp -r /usr/src/linux/arch/arm64/boot/modules/lib/modules/<version> /mnt/lib/modules/
umount /mnt
```

### 6. Generate U-Boot `boot.scr`

```bash
mkimage -C none -A arm -T script -d scripts/u-boot/boot.cmd boot.scr
mount /dev/sdX1 /mnt
cp boot.scr /mnt/boot/
umount /mnt
```

---

## Backup & Recovery

### With a handy script

Use the script [scripts/generate_image.sh](https://github.com/jonesthefox/odroid-m1s-arch/blob/main/scripts/generate_image.sh).
Usage: 
   ```bash
   ./generate_image.sh /dev/sdX
   ```

### Manually

1. **Zero-fill partitions:**

   ```bash
   for part in sdX1 sdX2; do
     mount /dev/$part /mnt
     dd if=/dev/zero of=/mnt/tmpfile bs=1M status=progress || true
     sync; rm /mnt/tmpfile; umount /mnt
   done
   ```
2. **Create sparse eMMC image:**

   **Note:** With `count=2000` we read just the first 2 GB from the device for the image, to reduce size. This works with a fresh install and may need adjustment for custom data.

   ```bash
   dd if=/dev/sdX of=odroid-m1s.img bs=1M count=2000 conv=sparse status=progress
   sync; gzip odroid-m1s.img
   ```
3. **Recovery:** Boot official UMS SD, then:

   ```bash
   ums 0 mmc 0
   ```

---

## Going Forward

Customize further by building U-Boot, kernel, or initramfs. See [README.md](README.md) and `scripts/build/u-boot.sh` for advanced workflows like TPM, OP-TEE, and unified kernel images.
