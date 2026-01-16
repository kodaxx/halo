#!/bin/bash
# capture_image.sh
# Developer Tool (Mac): Captures SD Card to a distributable Image
# Usage: sudo ./capture_image.sh

set -e
# Resolve Repo Root (Assuming script is in dev_tools/ relative to root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$REPO_ROOT/release"

# Ensure release directory exists
if [ ! -d "$RELEASE_DIR" ]; then
    echo "Creating release directory: $RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"
fi

IMAGE_FILENAME="halo_v1.img"
IMAGE_PATH="$RELEASE_DIR/$IMAGE_FILENAME"

echo "==========================================="
echo "   Halo Image Capture Tool (Mac OS)"
echo "   Output: $IMAGE_PATH"
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

echo "Capturing image from $DISK_ID to $IMAGE_PATH..."
echo "This will take some time (reading 32GB+)..."
# Use /dev/rdiskN for faster raw access
RDISK_ID=$(echo "$DISK_ID" | sed 's/disk/rdisk/')
dd if="$RDISK_ID" of="$IMAGE_PATH" bs=4m status=progress

echo "Capture Complete."

# PiShrink Step (Requires Docker)
if command -v docker &> /dev/null; then
    echo "Docker detected. Running PiShrink..."
    echo "Shrinking image and enabling auto-expand..."
    
    # Run PiShrink via Docker with macOS Workaround
    # Workaround: Docker on Mac cannot loopback-mount files directly from the bind-mounted host FS.
    # Fix: We copy the image INTO the container, shrink it there, and copy it back.
    # We mount RELEASE_DIR to /workdir, so the file is at /workdir/$IMAGE_FILENAME
    if docker run --privileged=true --rm \
        --entrypoint "/bin/sh" \
        -v "$RELEASE_DIR:/workdir" \
        cheyne/pishrink \
        -c "echo 'Step 1/3: Copying image to container...' && cp /workdir/$IMAGE_FILENAME /tmp/working.img && echo 'Step 2/3: Running PiShrink...' && pishrink -s /tmp/working.img && echo 'Step 3/3: Copying image back to host...' && mv /tmp/working.img /workdir/$IMAGE_FILENAME"; then
        echo "PiShrink Complete."
    else
        echo "WARNING: PiShrink failed (Common on macOS Docker)."
        echo "Proceeding with standard gzip (Image size might be larger)..."
    fi
else
    echo "WARNING: Docker not found. Skipping PiShrink."
    echo "The image will be the full size of the SD card ($DISK_ID)."
    echo "Install Docker Desktop to enable automatic shrinking."
fi

echo "Compressing image..."
gzip -f "$IMAGE_PATH"

echo "==========================================="
echo "   SUCCESS: $IMAGE_PATH.gz created!"
echo "==========================================="
