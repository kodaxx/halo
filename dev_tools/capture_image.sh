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

# Inject Headless Config (userconf.txt + ssh)
# The OS deletes these on boot, so we must add them back to the captured image
# to ensure the *next* user can SSH in.
USERCONF_SRC="$REPO_ROOT/dev_tools/pi_files/userconf.txt"
if [ -f "$USERCONF_SRC" ]; then
    echo "Injecting Headless Config (ssh + userconf.txt)..."
    
    # 1. Mount the image
    # -nomount: Don't auto-mount, just attach
    # We parse the output to find the boot partition (usually 's1', DOS_FAT_32)
    ATTACH_OUT=$(hdiutil attach -nomount "$IMAGE_PATH")
    DEV_NODE=$(echo "$ATTACH_OUT" | head -n 1 | awk '{print $1}')
    
    if [ -z "$DEV_NODE" ]; then
        echo "Error: Failed to attach image for injection."
    else
        echo "Attached as $DEV_NODE. Mounting boot partition..."
        
        # Helper to create a temp mount point
        MOUNT_POINT="/tmp/halo_boot_mnt"
        mkdir -p "$MOUNT_POINT"
        
        # Try to mount the first partition (boot)
        # On Mac, usually /dev/diskXs1
        # We use 'mount -t msdos' for FAT32 boot partition
        if mount -t msdos "${DEV_NODE}s1" "$MOUNT_POINT"; then
             echo "Mounted at $MOUNT_POINT."
             
             # 2. Inject Files
             echo "Creating 'ssh' file..."
             touch "$MOUNT_POINT/ssh"
             
             echo "Copying userconf.txt..."
             cp "$USERCONF_SRC" "$MOUNT_POINT/userconf.txt"
             
             # 3. Cleanup
             echo "Unmounting..."
             umount "$MOUNT_POINT"
        else
             echo "Error: Failed to mount boot partition."
        fi
        
        echo "Detaching image..."
        hdiutil detach "$DEV_NODE"
    fi
else
    echo "WARNING: $USERCONF_SRC not found. Skipping headless injection."
fi

echo "Compressing image..."
gzip -f "$IMAGE_PATH"

echo "==========================================="
echo "   SUCCESS: $IMAGE_PATH.gz created!"
echo "==========================================="
