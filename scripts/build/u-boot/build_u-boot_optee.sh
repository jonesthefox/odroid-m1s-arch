#!/usr/bin/env bash
#
# build_u-boot.sh – Build U-Boot with OP-TEE and TF-A for Rockchip
#
# Usage: ./build_u-boot.sh [--install-deps] [--defconfig] [--customconfig]
#

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(dirname "$(realpath "$0")")
PYTHON=$(which python3)

if [ -f "$SCRIPT_DIR/config-optee.env" ]; then
  . "$SCRIPT_DIR/config-optee.env"
else
  echo >&2 "Error: config-optee.env file not found in $SCRIPT_DIR." >&2
  exit 1
fi

# ensure we run as root for installs and symlinks
if (( EUID != 0 )); then
  echo "This script needs root privileges. Please run with sudo." >&2
  exit 1
fi

help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --install-deps    Install only the build dependencies.
  --clean-symlinks  Remove symlinks for cross compiler
  --defconfig       Override .config with default (${DEFCONFIG}).
  --customconfig    Override .config with ${CUSTOM_CONFIG}
  --help            Show this message and exit.
EOF
  exit 0
}

parse_args() {
  install_deps=false
  use_defconfig=false
  use_customconfig=false
  use_dotconfig=true

  while [ $# -gt 0 ]; do
    case $1 in
      --install-deps)   install_deps=true; shift ;;
      --clean-symlinks) remove_cross_symlinks; exit 0 ;;
      --defconfig)      use_defconfig=true; use_dotconfig=false; shift ;;
      --customconfig)   use_customconfig=true; use_dotconfig=false; shift ;;
      --help)           help ;;
      *) echo "Invalid option: $1"; help ;;
    esac
  done
}

install_dependencies() {
  echo "==> Installing dependencies..."

  apt-get update
  apt-get install -y \
    gcc-12 gcc-12-aarch64-linux-gnu gcc-12-arm-linux-gnueabi \
    python3-pyelftools confget libgnutls28-dev uuid-dev \
    binutils-aarch64-linux-gnu binutils-arm-linux-gnueabi

  echo "==> (Re)creating symlinks for cross-compilers..."
  for prefix in arm-linux-gnueabi aarch64-linux-gnu; do
    ln -sf "/usr/bin/${prefix}-gcc-12"      "/usr/bin/${prefix}-gcc"
    ln -sf "/usr/bin/${prefix}-g++-12"      "/usr/bin/${prefix}-g++"
    ln -sf "/usr/bin/${prefix}-gcc-ar-12"   "/usr/bin/${prefix}-gcc-ar"
    ln -sf "/usr/bin/${prefix}-gcc-nm-12"   "/usr/bin/${prefix}-gcc-nm"
    ln -sf "/usr/bin/${prefix}-gcc-ranlib-12" "/usr/bin/${prefix}-gcc-ranlib"
    ln -sf "/usr/bin/${prefix}-gcov-12"     "/usr/bin/${prefix}-gcov"
    ln -sf "/usr/bin/${prefix}-gcov-dump-12" "/usr/bin/${prefix}-gcov-dump"
    ln -sf "/usr/bin/${prefix}-gcov-tool-12" "/usr/bin/${prefix}-gcov-tool"
    ln -sf "/usr/bin/${prefix}-cpp-12"      "/usr/bin/${prefix}-cpp"
  done

  echo "Dependencies and symlinks created."
  exit 0
}

remove_cross_symlinks() {
  echo "==> Removing cross-compiler symlinks…"

  local prefixes=("arm-linux-gnueabi" "aarch64-linux-gnu")
  local tools=("gcc" "g++" "gcc-ar" "gcc-nm" "gcc-ranlib" \
               "gcov" "gcov-dump" "gcov-tool" "cpp")

  for prefix in "${prefixes[@]}"; do
    for tool in "${tools[@]}"; do
      local link="/usr/bin/${prefix}-${tool}"
      if [ -L "$link" ]; then
        echo "  Removing $link"
        rm -f "$link"
      fi
    done
  done

  echo "Done."
}

clone_git_repo() {
  local url=$1 dir=$2 branch="${3:-}"

  if [[ -d $dir ]]; then
    echo "Repo already cloned: $dir"
  else
    if [[ -n $branch ]]; then
      echo "Cloning $url (branch: $branch) into $dir…"
      git clone --branch "$branch" "$url" "$dir"
    else
      echo "Cloning $url into $dir…"
      git clone "$url" "$dir"
    fi
  fi
}

clone_repos() {
  echo "— Cloning repositories —"
  clone_git_repo "$REPO_RKBIN" "$ROOTPATH/rkbin"
  clone_git_repo "$REPO_TFA" "$ROOTPATH/arm-trusted-firmware"
  clone_git_repo "$REPO_OPTEE" "$ROOTPATH/optee_os"
  clone_git_repo "$REPO_UBOOT" "$ROOTPATH/u-boot" "$REPO_UBOOT_BRANCH"
  echo "— done —"
}

build_rkbin_ddr() {
  echo -e "— Configuring DDR init blob —"
  local ini="$ROOTPATH/rkbin/RKBOOT/${VARIANT}MINIALL.ini"
  local params="$(confget -f "$ini" -s LOADER_OPTION FlashData)"
  local soc="${VARIANT,,}"  # lowercase

  # backup with mktemp
  local tmp=$(mktemp)
  cp "$ROOTPATH/rkbin/tools/ddrbin_param.txt" "$tmp"

  sed -i "s/uart baudrate=/uart baudrate=${BAUDRATE}/" \
         "$ROOTPATH/rkbin/tools/ddrbin_param.txt"
  sed -i 's/dis_train_print=/dis_train_print=1/' \
         "$ROOTPATH/rkbin/tools/ddrbin_param.txt"

  "$PYTHON" "$ROOTPATH"/rkbin/tools/ddrbin_tool.py \
    "$soc" \
    "$ROOTPATH/rkbin/tools/ddrbin_param.txt" \
    "$ROOTPATH/rkbin/$params"

  # restore
  mv "$tmp" "$ROOTPATH/rkbin/tools/ddrbin_param.txt"
  ROCKCHIP_TPL="$ROOTPATH/rkbin/$params"
  SEC_FIRMWARE_LOAD=$(confget -f "$ROOTPATH"/rkbin/RKTRUST/RK3568TRUST.ini -s BL31_OPTION ADDR)

  echo "ROCKCHIP_TPL=$ROCKCHIP_TPL"
  echo "SEC_FIRMWARE_LOAD=$SEC_FIRMWARE_LOAD"
  echo "— done —"
  echo
}

build_trusted_firmware() {
  echo -e "— Building TF-A —"
  pushd "$ROOTPATH/arm-trusted-firmware" >/dev/null
  make PLAT="$TFA_PLATFORM" \
       CROSS_COMPILE="${CROSS_COMPILE64}" \
       -j"$(nproc)" fip
  BL31="$PWD/build/$TFA_PLATFORM/release/bl31/bl31.elf"
  popd >/dev/null
  echo "BL31=$BL31"
  echo "— done —"
  echo
}

build_optee() {
  echo -e "— Patching & Building OP-TEE —"
  pushd "$ROOTPATH/optee_os" >/dev/null
  local patch="$SCRIPT_DIR/patches/op-tee/rk3566-plat-rockchip.patch"

  if git apply --reverse --check "$patch" &>/dev/null; then
    echo "Patch already applied"
  else
    git apply --whitespace=fix -p1 "$patch"
  fi

# make PLATFORM=rockchip FLAVOR=rk3566 CROSS_COMPILE=arm-linux-gnueabi- CFG_USER_TA_TARGETS=ta_arm32 CFG_DT=y CFG_DT_ADDR=0x12000000 CFG_CORE_ARM64_PA_BITS=32 -j$(nproc)

  make ARCH="$OPTEE_ARCH" \
       PLATFORM="$OPTEE_PLATFORM" \
       FLAVOR="$OPTEE_FLAVOR" \
       CFG_ARM64_core=n \
       CFG_DT=y \
       CFG_DT_ADDR=$OPTEE_FDT_ADDR \
       CFG_CORE_ARM64_PA_BITS=$OPTEE_RAM_BITS \
       CFG_USER_TA_TARGETS=ta_arm32 \
       CROSS_COMPILE="$CROSS_COMPILE" \
       -j"$(nproc)"
  BL32="$ROOTPATH/optee_os/out/arm-plat-rockchip/core/tee.bin"
  [[ -f $BL32 ]] || { echo "BL32 not found!"; exit 1; }
  popd >/dev/null
  echo "TEE=$BL32"
  echo "— done —"
  echo
}

build_uboot() {
  echo -e "— Patching & Building U-Boot —"
  pushd "$ROOTPATH/u-boot" >/dev/null
  local patch="$SCRIPT_DIR/patches/u-boot/rk3568_sys_mem_reserve_secure.patch"

  if git apply --reverse --check "$patch" &>/dev/null; then
    echo "Patch already applied"
  else
    git apply --whitespace=fix -p1 "$patch"
  fi

  # .config handling
  if $use_dotconfig; then
    tmp_cfg=$(mktemp)
    cp .config "$tmp_cfg"
    make mrproper
    mv "$tmp_cfg" .config
  elif $use_defconfig; then
    make mrproper
    make "$DEFCONFIG"
  elif $use_customconfig; then
    make mrproper
    cp "${CUSTOM_CONFIG/#\.\//$SCRIPT_DIR/}" .config
  fi

  # make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- ROCKCHIP_TPL=/tmp/build_u-boot/rkbin/bin/rk35/rk3566_ddr_1056MHz_v1.23.bin BL31=/tmp/build_u-boot/arm-trusted-firmware/build/rk3568/release/bl31/bl31.elf TEE=/tmp/build_u-boot/optee_os/out/arm-plat-rockchip/core/tee.bin

  make KCFLAGS="-Werror" \
       ARCH=arm \
       CROSS_COMPILE="$CROSS_COMPILE64" \
       CROSS_COMPILE_ARM32="$CROSS_COMPILE" \
       ROCKCHIP_TPL="$ROCKCHIP_TPL" \
       BL31="$BL31" \
       TEE="$BL32" \
       -j"$(nproc)"

  ./tools/mkimage -l u-boot.itb
  # ./tools/mkimage -T rksd -n rk3568 -d /tmp/build_u-boot/rkbin/bin/rk35/rk3566_ddr_1056MHz_v1.23.bin:spl/u-boot-spl.bin idbloader.img
  # ./tools/mkimage -T "$UBOOT_IMG_TYPE" -n "$TFA_PLATFORM" -d "$ROCKCHIP_TPL":spl/u-boot-spl.bin idbloader.img

  popd >/dev/null
  echo "— done —"
}

main() {
  parse_args "$@"
  $install_deps && install_dependencies
  clone_repos
  build_rkbin_ddr
  build_trusted_firmware
  build_optee
  build_uboot
  echo -e "✅ Build complete!"
}

main "$@"
