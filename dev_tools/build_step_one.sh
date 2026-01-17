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

# 1. Install Matching Headers & Lock (CRITICAL)
# We must compile against the EXACT kernel version we are running.
# Since we DO NOT want to upgrade the kernel, we fetch headers matching the CURRENT installed kernel pkg.

echo "[1/4] Checking kernel version..."
CURRENT_KERNEL_VER=$(dpkg-query -W -f='${Version}' raspberrypi-kernel)
echo "Current Kernel Package: $CURRENT_KERNEL_VER"

echo "[1/4] Installing matching headers..."
# Try to install the headers that match this specific version
if sudo apt-get install -y raspberrypi-kernel-headers="$CURRENT_KERNEL_VER"; then
    echo "Success: Installed matching headers."
else
    echo "ERROR: Could not find headers for kernel $CURRENT_KERNEL_VER."
    echo "The repository may have rotated them out. You might need to allow a kernel upgrade."
    echo "Retry with the 'Upgrade Kernel' strategy if this fails."
    exit 1
fi

# 2. Lock Kernel & Headers
echo "[2/4] Locking kernel/headers version..."
sudo apt-mark hold raspberrypi-kernel raspberrypi-bootloader raspberrypi-kernel-headers
echo "Kernel and Headers pinned at $CURRENT_KERNEL_VER"

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