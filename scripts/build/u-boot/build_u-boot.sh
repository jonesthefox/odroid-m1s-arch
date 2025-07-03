#!/bin/sh

SCRIPT_DIR=$(dirname "$(realpath "$0")")
PYTHON=$(which python3)

if [ -f "$SCRIPT_DIR/config.env" ]; then
    . "$SCRIPT_DIR/config.env"
else
    echo "Error: config.env file not found in $SCRIPT_DIR." >&2
    exit 1
fi

help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --install-deps       Only install required dependencies for building U-Boot."
    echo "  --defconfig          Use the default U-Boot defconfig specified in the script."
    echo "                       This will override the existing .config in the U-Boot directory."
    echo "  --customconfig       Use a custom .config file specified by the CUSTOM_CONFIG variable."
    echo "                       This will override the existing .config in the U-Boot directory."
    echo "  --help               Display this help message and exit."
    echo ""
    echo "If no configuration option (--defconfig or --customconfig) is specified, the script"
    echo "will default to using the existing .config file in the U-Boot directory."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                  # Use the existing .config in the U-Boot directory."
    echo "  $(basename "$0") --install-deps   # Install dependencies."
    echo "  $(basename "$0") --defconfig      # Use the default defconfig for U-Boot."
    echo "  $(basename "$0") --customconfig   # Use a custom .config file for U-Boot."
    echo ""
    exit 0
}

install_dependencies() {
    echo "Installing dependencies..."

    if ! apt-get update; then
        echo "Error: Failed to update package list." >&2
        exit 1
    fi

    if ! apt-get install -y gcc-12 gcc-12-aarch64-linux-gnu python3-pyelftools confget libgnutls28-dev uuid-dev; then
        echo "Error: Failed to install required packages." >&2
        exit 1
    fi

    echo "Creating symbolic links for GCC 12 toolchain..."

    for cmd in \
        "ln -sf aarch64-linux-gnu-cpp-12 /usr/bin/aarch64-linux-gnu-cpp" \
        "ln -sf aarch64-linux-gnu-gcc-12 /usr/bin/aarch64-linux-gnu-gcc" \
        "ln -sf aarch64-linux-gnu-gcc-ar-12 /usr/bin/aarch64-linux-gnu-gcc-ar" \
        "ln -sf aarch64-linux-gnu-gcc-nm-12 /usr/bin/aarch64-linux-gnu-gcc-nm" \
        "ln -sf aarch64-linux-gnu-gcc-ranlib-12 /usr/bin/aarch64-linux-gnu-gcc-ranlib" \
        "ln -sf aarch64-linux-gnu-gcov-12 /usr/bin/aarch64-linux-gnu-gcov" \
        "ln -sf aarch64-linux-gnu-gcov-dump-12 /usr/bin/aarch64-linux-gnu-gcov-dump" \
        "ln -sf aarch64-linux-gnu-gcov-tool-12 /usr/bin/aarch64-linux-gnu-gcov-tool"
    do
        if ! $cmd; then
            echo "Error: Failed to execute command: $cmd" >&2
            exit 1
        fi
    done

    echo "Dependencies installed and symbolic links created successfully."
    exit 0
}

clone_git_repo() {
    repo_url=$1
    repo_dir=$2
    branch=$3

    if [ -d "$repo_dir" ]; then
        echo "Repository $repo_url already cloned in $repo_dir."
    else
        echo "Cloning $repo_url into $repo_dir..."
        if [ -n "$branch" ]; then
            git clone --branch "$branch" "$repo_url" "$repo_dir"
        else
            git clone "$repo_url" "$repo_dir"
        fi
    fi
}

install_deps=false
use_defconfig=false
use_customconfig=false
use_dotconfig=true

for arg in "$@"; do
    case $arg in
        --install-deps)
            install_deps=true
            ;;
        --defconfig)
            use_defconfig=true
            use_dotconfig=false
            ;;
        --customconfig)
            use_customconfig=true
            use_dotconfig=false
            ;;
        --help)
            help
            ;;
        *)
            echo "Error: Invalid argument '$arg'. Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

if [ "$install_deps" = true ]; then
    install_dependencies
fi

clone_git_repo "$REPO_RKBIN" "$ROOTPATH/rkbin"
clone_git_repo "$REPO_UBOOT" "$ROOTPATH/u-boot-rockchip" "$REPO_UBOOT_BRANCH"

# Configure DDR initialisation bin
DDRBIN=$(confget -f "$ROOTPATH"/rkbin/RKBOOT/"$VARIANT"MINIALL.ini -s LOADER_OPTION FlashData)
# Set SOC
SOC=$(echo "$VARIANT" | tr '[:upper:]' '[:lower:]')

# backup ddrbin_param.txt
if ! cp "$ROOTPATH"/rkbin/tools/ddrbin_param.txt "$ROOTPATH"/rkbin/tools/ddrbin_param.ori; then
      echo "Error: Failed to backup ddrbin_param.txt" >&2
      exit 1
fi

# Set baud rate
sed -i "s/uart baudrate=/uart baudrate=$BAUDRATE/" "$ROOTPATH/rkbin/tools/ddrbin_param.txt"
# Disable printing of training results
sed -i 's/dis_train_print=/dis_train_print=1/' "$ROOTPATH/rkbin/tools/ddrbin_param.txt"

"$PYTHON" "$ROOTPATH/rkbin/tools/ddrbin_tool.py" "$SOC" "$ROOTPATH/rkbin/tools/ddrbin_param.txt" "$ROOTPATH/rkbin/$DDRBIN"

# restore ddrbin_param.txt
if ! cp "$ROOTPATH"/rkbin/tools/ddrbin_param.ori "$ROOTPATH"/rkbin/tools/ddrbin_param.txt; then
      echo "Error: Failed to restore ddrbin_param.txt" >&2
      exit 1
fi

ROCKCHIP_TPL="$ROOTPATH/rkbin/$DDRBIN"
BL31="$ROOTPATH/rkbin/$(confget -f "$ROOTPATH/rkbin/RKTRUST/RK3568TRUST.ini" -s BL31_OPTION PATH)"

# This may or may not be needed for TPM, OP-TEE (Truested Execution Environment), UKI and stuff..

# SEC_FIRMWARE_LOAD="$(confget -f "$ROOTPATH/rkbin/RKTRUST/RK3568TRUST.ini" -s BL31_OPTION ADDR)"
# BL32=$ROOTPATH/rkbin/"$(confget -f $ROOTPATH/rkbin/RKTRUST/RK3568TRUST.ini -s BL32_OPTION PATH)"
# export SEC_FIRMWARE_RET=0xa00000
# export BL32

export ARCH BL31 SEC_FIRMWARE_LOAD ROCKCHIP_TPL

cd "$ROOTPATH/u-boot-rockchip" || exit 1

if [ "$use_dotconfig" = true ]; then
    if ! cp .config /tmp/u-boot_dotconfig; then
      echo "Error: Failed to backup .config to /tmp" >&2
      exit 1
    fi
    make mrproper
    if ! mv /tmp/u-boot_dotconfig .config; then
      echo "Error: Failed restore .config from /tmp" >&2
      exit 1
    fi
    echo "Using existing .config in the U-Boot directory..."
elif [ "$use_defconfig" = true ]; then
    make mrproper
    echo "Running make $DEFCONFIG..."
    make "$DEFCONFIG"
elif [ "$use_customconfig" = true ]; then
    echo "Copying .config from $CUSTOM_CONFIG..."
    make mrproper
    # allow relative paths in CUSTOM_CONFIG → resolve against SCRIPT_DIR
    CONFIG_PATH="$CUSTOM_CONFIG"
    if [ ! -f "$CONFIG_PATH" ]; then
        CONFIG_PATH="$SCRIPT_DIR/$CUSTOM_CONFIG"
    fi
    if ! cp "$CONFIG_PATH" .config; then
        echo "Error: Failed to copy .config from $CUSTOM_CONFIG" >&2
        exit 1
    fi
fi

make KCFLAGS="-Werror" CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)"
./tools/mkimage -l u-boot.itb

cd - || exit 1
