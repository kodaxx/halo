#!/bin/bash
# Complete Bootstrap Script for Clean EVK Setup
# 1. Locks Kernel (to prevent breaking upgrades)
# 2. Updates Packages
# 3. Clones 'halo' repository
# 4. Installs Device Tree Overlay

set -e # Exit on error

echo "=== Starting Pi Bootstrap ==="

# 1. Lock Kernel Version (Prevent upgrade to incompatible 6.x)
echo "[1/4] Locking kernel version..."
if ! apt-mark showhold | grep -q "raspberrypi-kernel"; then
    sudo apt-mark hold raspberrypi-kernel raspberrypi-bootloader
    echo "Kernel pinned."
else
    echo "Kernel already pinned."
fi

# 2. System Update
echo "[2/4] Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y
# Install git and dtc if missing
sudo apt-get install -y git device-tree-compiler

# 3. Clone Repository
echo "[3/4] Cloning repository..."
REPO_DIR="$HOME/halo"
if [ -d "$REPO_DIR" ]; then
    echo "Repo exists at $REPO_DIR. Pulling latest..."
    cd "$REPO_DIR" && git pull origin main
else
    git clone https://github.com/kodaxx/halo.git "$REPO_DIR"
    echo "Cloned to $REPO_DIR"
fi

# 4. Install Overlay
echo "[4/4] Installing Device Tree Overlay..."
DTS_FILE="$REPO_DIR/nrc7292_sw_pkg/dts/newracom_for_5.16_or_later.dts"
DTBO_NAME="nrc-rpi"
TARGET_DTBO="/boot/overlays/$DTBO_NAME.dtbo"

if [ ! -f "$DTS_FILE" ]; then
    echo "Error: DTS file not found at $DTS_FILE"
    exit 1
fi

# Compile
dtc -I dts -O dtb -o "$DTBO_NAME.dtbo" "$DTS_FILE"
sudo cp "$DTBO_NAME.dtbo" "$TARGET_DTBO"

# Enable in config.txt
grep -q "dtoverlay=$DTBO_NAME" /boot/config.txt || echo "dtoverlay=$DTBO_NAME" | sudo tee -a /boot/config.txt

# Enable USB Gadget Mode (Safety Net)
if ! grep -q "dtoverlay=dwc2" /boot/config.txt; then
    echo "dtoverlay=dwc2" >> /boot/config.txt
    log "USB Gadget mode enabled (dwc2)"
fi
# Add modules-load for gadget
if ! grep -q "g_ether" /etc/modules; then
     echo "dwc2" >> /etc/modules
     echo "g_ether" >> /etc/modules
fi

# Disable Bluetooth (Save power/interference)
if ! grep -q "dtoverlay=disable-bt" /boot/config.txt; then
    echo "dtoverlay=disable-bt" >> /boot/config.txt
    log "Bluetooth disabled (disable-bt)"
fi

echo "=== Step One Complete ==="
echo "The system is updated, repo is cloned at ~/halo, and overlay is installed."
echo "After reboot run step two: 'sudo ./build_step_two.sh'"
echo "Please REBOOT now: 'sudo reboot'"