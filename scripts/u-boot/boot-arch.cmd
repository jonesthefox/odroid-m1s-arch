setenv bootargs "root=/dev/mmcblk0p2 rw console=ttyS2,1500000"
load mmc 0:2 ${kernel_addr_r} boot/Image
load mmc 0:2 ${ramdisk_addr_r} boot/uInitrd
load mmc 0:2 ${fdt_addr_r} boot/dtbs/rockchip/rk3566-odroid-m1s.dtb
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
