#!/bin/bash
# HALO BUILD STEP ONE
# Entry Point: curl -sL https://raw.githubusercontent.com/kodaxx/halo/main/dev_tools/build_step_one.sh | bash
# Actions:
# 1. Lock Kernel (Crucial)
# 2. Update System & Install Git/DTC
# 3. Clone/Update Repo
# 4. Install Overlay

set -e

echo "=== Halo Build: Step 1/2 ==="

# 1. Update & Sync Kernel/Headers (CRITICAL)
echo "[1/4] syncing system kernel and headers..."
sudo apt-get update
# Force full upgrade first to get latest kernel
sudo apt-get full-upgrade -y

# Install headers NOW to ensure they match the kernel we just installed
sudo apt-get install -y raspberrypi-kernel-headers git device-tree-compiler

# 2. Lock Kernel (Now that we are synced)
echo "[2/4] Locking kernel version..."
# We lock BOTH to ensure they stay in sync
sudo apt-mark hold raspberrypi-kernel raspberrypi-bootloader raspberrypi-kernel-headers
echo "Kernel and Headers synced and pinned."

# 3. Clone Repository
echo "[3/4] Ensuring Repository..."
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
DTS_FILE="$REPO_DIR/nrc7292/dts/newracom_for_5.16_or_later.dts"
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
if ! grep -q "dtoverlay=$DTBO_NAME" /boot/config.txt; then
    echo "dtoverlay=$DTBO_NAME" | sudo tee -a /boot/config.txt
fi

# Enable USB Gadget Mode (Safety Net)
if ! grep -q "dtoverlay=dwc2" /boot/config.txt; then
    echo "dtoverlay=dwc2" | sudo tee -a /boot/config.txt
    
    # Add modules-load for gadget
    if ! grep -q "g_ether" /etc/modules; then
         echo "dwc2" | sudo tee -a /etc/modules
         echo "g_ether" | sudo tee -a /etc/modules
    fi
    echo "USB Gadget mode enabled (dwc2)"
fi

# Disable Bluetooth (Save power/interference)
if ! grep -q "dtoverlay=disable-bt" /boot/config.txt; then
    echo "dtoverlay=disable-bt" | sudo tee -a /boot/config.txt
    echo "Bluetooth disabled (disable-bt)"
fi

echo "=== Step One Complete ==="
echo "Please REBOOT now: 'sudo reboot'"
echo "After reboot, run: 'sudo ~/halo/dev_tools/build_step_two.sh'"