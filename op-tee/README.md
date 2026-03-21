# OP-TEE for the odroid m1s rk3566

Let's try to implement OP-TEE on this funny little thing 🚀

> **WARNING:** This is not a production-ready implementation!

> **NOTE:** I gave up on this project after a few days. I don't think it's worth the effort. But if you want to try it, here some information.

I'm not sure anymore what i tinkered with, i have a `plat-rockchip` folder in my dev folder and the `rkbin` sources. I guess i built the
`rkbin` firmware and used the (u-boot?) `plat-rockchip` as a reference for the adresses and offsets.

## Adresses and offsets

* **GIC**: Without properly configured interrupt controller base addresses, secure-world interrupt handling will not work.
* **TZDRAM & SHMEM**: Core memory for the TEE heap, stack, and shared buffer must be defined early in the boot sequence.
* **CRU**: Clocks and resets are required to drive buses and peripherals within the secure-world context.
* **SGRF & GRF**: Security and system register files used to configure domain assignments and signal multiplexers.
* **UART2**: The debug console is essential for diagnosing bring-up issues.
* **Firewalls (DDR/DSU)**: Protect memory regions from unauthorized access.
* **TRNG & Secure OTP**: Cryptographic components—critical but typically initialized later in the boot process.

| Block                               | Makro               |        Basis-Adress |  Size | Important offsets / derivation                                                              |
|-------------------------------------|---------------------|--------------------:|------:|---------------------------------------------------------------------------------------------|
| GIC                                 | `GIC_BASE`          |        `0xFD400000` | 64 KB |                                                                                             |
| • Distributor                       | `GICD_BASE`         | `GIC_BASE+0x1000` ? |     — | Offset `0x1000`                                                                             |
| • CPU Interface                     | `GICC_BASE`         | `GIC_BASE+0x2000` ? |     — | Offset `0x2000`                                                                             |
| Secure DRAM (TZDRAM)                | `TZDRAM_BASE`       |      `0x0x68400000` |  2 MB |                                                                                             |
| Shared Mem (SHMEM)                  | `TEE_SHMEM_START`   |        `0x68600000` |  1 MB |                                                                                             |
| Clock & Reset Unit (CRU)            | `CRU_BASE`          |        `0xFDD00000` | 64 KB |                                                                                             |
| System General Register File (SGRF) | `SGRF_BASE`         |        `0xFDC00000` | 64 KB |                                                                                             |
| General Register File (GRF)         | `GRF_BASE`          |        `0xFDC20000` | 64 KB |                                                                                             |
| UART2 (Debug)                       | `UART2_BASE`        |        `0xFDD50000` | 64 KB |                                                                                             |
| Firewall DDR                        | `FIREWALL_DDR_BASE` |        `0xFE200000` | 32 KB | - Region-Regs: `FIREWALL_DDR_RGN(i) = i*0x4` - Control: `0xF0`                              |
| Firewall DSU                        | `FIREWALL_DSU_BASE` |             `0x???` | 32 KB | - Region-Regs: `FIREWALL_DSU_RGN(i) = i*0x4` - Control: `0xF0+4*i`                          |
| True RNG (TRNG)                     | `TRNG_S_BASE`       |        `0xFE370000` | 16 KB | - `CTRL=0x0000`, `STAT=0x0004`, `MODE=0x0008` - `RAND=0x0020`, `AUTO_RQSTS=0x0060`          |
| Secure OTP                          | `OTP_S_BASE`        |        `0xFE3A0000` | 64 KB | - `AUTO_CTRL=0x0004`, `AUTO_EN=0x0008` - `PROG_DATA=0x0010`, `DOUT=0x0020`, `INT_ST=0x0084` |

I don't know where i put this, but it was a note, so it may be important :) Maybe in the `op-tee` sources?
```
#define SEC_FIRMWARE_LOAD   0x00040000
#define SEC_FIRMWARE_SIZE   0x00029000
```

## Build

Should build, but won't boot. 

```shell
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- \
  ROCKCHIP_TPL=/tmp/build_u-boot/rkbin/bin/rk35/rk3566_ddr_1056MHz_v1.23.bin \
  BL31=/tmp/build_u-boot/arm-trusted-firmware/build/rk3568/release/bl31/bl31.elf \
  TEE=/tmp/build_u-boot/optee_os/out/arm-plat-rockchip/core/tee.bin -j$(nproc)
```

## Script

I added a [build_u-boot_optee.sh](scripts/build/u-boot/build_u-boot_optee.sh) script to build the u-boot and optee-os binaries, you may
find additional information in the script.
