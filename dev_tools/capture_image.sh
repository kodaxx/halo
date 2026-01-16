#!/bin/bash
# capture_image.sh
# Developer Tool (Mac): Captures SD Card to a distributable Image
# Usage: sudo ./capture_image.sh

set -e
IMAGE_NAME="halo_v1.img"

echo "==========================================="
echo "   Halo Image Capture Tool (Mac OS)"
echo "==========================================="

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./capture_image.sh)"
    exit 1
fi

echo "Scanning for external disks..."
diskutil list external

echo ""
echo "Enter the disk identifier for the SD Card (e.g., /dev/disk2):"
read -r DISK_ID

if [ -z "$DISK_ID" ]; then
    echo "Error: No disk selected."
    exit 1
fi

echo "Unmounting disk $DISK_ID..."
diskutil unmountDisk "$DISK_ID"

echo "Capturing image from $DISK_ID to $IMAGE_NAME..."
echo "This will take some time (reading 32GB+)..."
# Use /dev/rdiskN for faster raw access
RDISK_ID=$(echo "$DISK_ID" | sed 's/disk/rdisk/')
dd if="$RDISK_ID" of="$IMAGE_NAME" bs=4m status=progress

echo "Capture Complete."

# PiShrink Step (Requires Docker)
if command -v docker &> /dev/null; then
    echo "Docker detected. Running PiShrink..."
    echo "Shrinking image and enabling auto-expand..."
    
    # Run PiShrink via Docker
    # -s: Script to auto-expand on boot
    # Volume mount current dir to /workdir
    docker run --privileged=true --rm \
        -v "$(pwd):/workdir" \
        drewsif/pishrink \
        pishrink -s "/workdir/$IMAGE_NAME"
        
    echo "PiShrink Complete."
else
    echo "WARNING: Docker not found. Skipping PiShrink."
    echo "The image will be the full size of the SD card ($DISK_ID)."
    echo "Install Docker Desktop to enable automatic shrinking."
fi

echo "Compressing image..."
gzip -f "$IMAGE_NAME"

echo "==========================================="
echo "   SUCCESS: $IMAGE_NAME.gz created!"
echo "==========================================="
