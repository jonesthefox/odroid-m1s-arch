# RK3566 Odroid M1S U-Boot Build Script

<!-- TOC -->
* [RK3566 Odroid M1S U-Boot Build Script](#rk3566-odroid-m1s-u-boot-build-script)
  * [Important Notes](#important-notes)
  * [Prerequisites](#prerequisites)
  * [Configuration](#configuration)
  * [Usage](#usage)
  * [How the Script Works](#how-the-script-works)
  * [Example](#example)
  * [Flashing](#flashing)
    * [Flash to eMMC (via UMS)](#flash-to-emmc-via-ums)
  * [Bootflow](#bootflow)
  * [License](#license)
<!-- TOC -->

This script is designed to automate the setup and build process for U-Boot on the
RK3566 Odroid M1S. It handles the necessary preparations, including setting
environment variables, configuring the build, and running the required commands.

> This script clones github repos `Kwiboo/u-boot-rockchip` and `rockchip-linux/rkbin`
to your build host. When the directories exist, it won't pull updates - that's your job
if you want to do so.

## Important Notes

> **Warning:** When you want to build end experiment with U-Boot, you should 
**definitely** connect a serial console to the uart pins on your Odroid M1S to be able
to see the output and troubleshoot/debug.

> **Info:** You find the default config we used in [u-boot.config](u-boot.config).
It has the UMS command to set the device to USB Mass Storage mode and has HDMI and 
USB keyboard support. Copy the file to `/usr/src/your-u-boot-source/.config`

- Ensure that you have the correct permissions to run the script and that your user
  has the necessary privileges to install packages if using the --install-deps option.
  The script expects certain paths to be defined, such as /usr/src for the root path
  where source files are located. Modify the script variables if your setup differs.
  Troubleshooting

## Prerequisites

Ensure that you have the following dependencies installed on your system:

- `gcc-12`
- `gcc-12-aarch64-linux-gnu`
- `python3-pyelftools`
- `confget`
- `libgnutls28-dev`

These can be installed automatically using the script with the optional parameter
described below.

## Configuration

Edit config.env according to your needs. Actually you should only edit `CUSTOM_CONFIG`
and `ROOTPATH`.

## Usage

1. **Standard Mode**: This mode uses the `.config` in the u-boot source directory and
   build U-Boot.

   > **Info:** Make sure that you configured your u-boot source properly, eg. with
   `make menuconfig`.

   ```bash
   ./build_u-boot.sh
   ```

2. Install Dependencies: This will install the required dependencies and
   create symbolic links for the GCC 12 toolchain. Use this mode if you are running
   the script for the first time or on a new system.

   ```bash
   ./build_u-boot.sh --install-deps
   ```

3. Build with Odroid M1S defconfig: If set, it will use
   `/configs/odroid-m1s-rk3566_defconfig`.

   ```bash
   ./build_u-boot.sh --defconfig
   ```

4. Build with custom config located elsewhere. It will copy the config file from
   `$CUSTOM_CONFIG` defined in `config.env` to the U-Boot source directory.

   ```bash
   ./build_u-boot.sh --customconfig
   ```

## How the Script Works

1. The script optionally installs dependencies when run with the `--install-deps`
   flag.

2. It clones the `Kwiboo/u-boot-rockchip` and `rockchip-linux/rkbin`

3. It sets parameter for the rkbin ddr initialisation binary and sets up environment
   variables required for the U-Boot build.

4. Configures the build with `odroid-m1s-rk3566_defconfig` if the flag `--defconfig`
   is set.

5. Builds U-Boot using the provided environment variables and configuration.

## Example

To run the script with dependency installation, use:

```bash
./build_u-boot.sh --install-deps
```

For subsequent builds with your own config, you can use:

```bash
./build_u-boot.sh
```

> **Note:** you have to specify a path to _your_ config in the script.

For builds with the board defconfig from u-boot you can use:

```bash
./build_u-boot.sh --defconfig
```

## Flashing

### Flash to eMMC (via UMS)

> **Info:** It _should_ be possible to flash it from the running OS on the Odroid M1S.
> Use `/dev/mmcblk0`.

Using the script above will produce the file `u-boot-rockchip.bin` in
`/usr/src/u-boot-rockchip/`. Flash that:

```bash
dd if=u-boot-rockchip.bin of=/dev/sdX bs=32k seek=1 conv=fsync
```

## Bootflow

I scripted `bootcmd` like this:

```bash
bootflow scan -l mmc; if bootflow select 0; then echo Booting; bootflow boot; else echo entering UMS mode; ums mmc 0; fi
```

This results in:

1. Scan emmc and SD card for a boot.scr
2. Try to select the first valid entry and boot it
3. If it fails, U-Boot starts UMS mode, so you can access the emmc device on a host
   computer

## License

This script is provided "as-is" without any warranties. Use at your own risk.
