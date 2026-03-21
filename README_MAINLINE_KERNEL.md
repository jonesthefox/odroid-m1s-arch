# Using the Arch Linux Kernel on Odroid M1S

As of March 21, 2026, the stock Arch Linux kernel runs fine on the Odroid M1S.

## ⚠️ Important

You **must** convert the Arch initramfs (`cpio`) to U-Boot format (`uInitrd`), otherwise the device will **not boot**.

## Setup

Boot files are stored on `/dev/mmcblk0p1` (not mounted as `/boot`). Only minimal changes are required.

### 1. Mount boot partition

```bash
mount /dev/mmcblk0p1 /mnt
```

---

### 2. Configure U-Boot boot script

Download [boot-arch.cmd](https://github.com/jonesthefox/odroid-m1s-arch/tree/main/scripts/u-boot/boot-arch.cmd) to `/mnt`.

Or create it manually:

```bash
setenv bootargs "root=/dev/mmcblk0p2 rw console=ttyS2,1500000"
load mmc 0:2 ${kernel_addr_r} boot/Image
load mmc 0:2 ${ramdisk_addr_r} boot/uInitrd
load mmc 0:2 ${fdt_addr_r} boot/dtbs/rockchip/rk3566-odroid-m1s.dtb
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
```

---

### 3. Build `boot.scr`

```bash
cd /mnt
cp boot.scr boot.scr.bak
mkimage -C none -A arm -T script -d boot-arch.cmd boot.scr
umount /mnt
```

---

### 4. Convert initramfs to `uInitrd`

```bash
cd /boot
pacman -S uboot-tools   # if not installed
mkimage -A arm -T ramdisk -C gzip -d initramfs-linux.img uInitrd
```

---

### 5. Automate `uInitrd` generation (required)

Arch updates the kernel regularly. Without automation, your system will eventually become unbootable.

Create hook directory:

```bash
mkdir -p /etc/initcpio/post
```

Create `/etc/initcpio/post/90-uinitrd` or download it [here](https://github.com/jonesthefox/odroid-m1s-arch/tree/main/scripts/build/initcpio/post/90-uinitrd):

```bash
#!/bin/sh
set -eu

kernel="${1:-}"
image="${2:-}"
uki="${3:-}"

[ -n "$image" ] || exit 0
[ -f "$image" ] || exit 0

case "$image" in
  /boot/initramfs-linux.img)
    out="/boot/uInitrd"
    ;;
  /boot/initramfs-linux-fallback.img)
    out="/boot/uInitrd-fallback"
    ;;
  *)
    exit 0
    ;;
esac

/usr/bin/mkimage -A arm -T ramdisk -C gzip -d "$image" "$out"
```

Make it executable:

```bash
chmod 755 /etc/initcpio/post/90-uinitrd
```

Test it:

```bash
mkinitcpio -P
```

You should now have:
- `/boot/uInitrd`
- `/boot/uInitrd-fallback`

Note: U-Boot does not use the fallback image.

---

## Done

Reboot and enjoy the Arch Linux kernel on your M1S.