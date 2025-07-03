#!/usr/bin/env bash
# generate_image.sh - create a sparse, size-optimized backup image of an Odroid M1S eMMC or SD card

set -euo pipefail

# Function: print usage message
usage() {
  cat <<EOF
Usage: $0 <device>

  <device>  The block device to image, e.g. /dev/sdb

This script will:
  1) Zero-fill free space in BOOT and rootfs partitions to improve sparsity
  2) Compute the size of BOOT and used space in rootfs
  3) Create a sparse image of just those MiB + 100 MiB buffer
  4) Compress the resulting image with gzip
EOF
  exit 1
}

# Check arguments
if [[ $# -ne 1 ]]; then
  usage
fi

DEVICE=$1

# Ensure running as root
if (( EUID != 0 )); then
  echo "This script must be run as root or via sudo."
  exit 1
fi

# Confirm device exists
if [[ ! -b "$DEVICE" ]]; then
  echo "Error: Device $DEVICE not found or is not a block device."
  exit 1
fi

# Define partitions
BOOT_PART="${DEVICE}1"
ROOT_PART="${DEVICE}2"

# Step 1: Zero-fill free space on partitions for better sparsity
echo "[1/4] Zero-filling free space on partitions..."
for part in "$BOOT_PART" "$ROOT_PART"; do
  echo "  Zero-filling $part ..."
  mkdir -p /mnt/tmp
  mount "$part" /mnt/tmp
  dd if=/dev/zero of=/mnt/tmp/zero.tmp bs=1M status=progress || true
  sync
  rm -f /mnt/tmp/zero.tmp
  umount /mnt/tmp
  rmdir /mnt/tmp

done

# Step 2: Calculate image size in MiB
echo "[2/4] Calculating required image size..."
BOOT_START_MB=$(parted "$DEVICE" unit MiB print --script \  | awk -F: '/^  1:/ { sub(/MiB$/, "", $2); print int($2) }')

mount "$ROOT_PART" /mnt/tmp
USED_MB=$(df --output=used -B1M /mnt/tmp | tail -n1 | tr -dc '0-9')
umount /mnt/tmp
rmdir /mnt/tmp

COUNT=$(( BOOT_START_MB + USED_MB + 100 ))
echo "  BOOT starts at ${BOOT_START_MB} MiB"
echo "  Rootfs uses ${USED_MB} MiB"
echo "  Total image size = ${COUNT} MiB (incl. 100 MiB buffer)"

# Step 3: Create sparse image
IMG_NAME="$(basename "$DEVICE").img"
echo "[3/4] Creating sparse image $IMG_NAME (count=${COUNT} MiB)..."

dd if="${DEVICE}" of="$IMG_NAME" bs=1M count="$COUNT" conv=sparse status=progress
sync

# Step 4: Compress
echo "[4/4] Compressing $IMG_NAME to ${IMG_NAME}.gz..."
gzip -1 "$IMG_NAME"

echo "Done: ${IMG_NAME}.gz created."
