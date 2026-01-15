#!/bin/bash
# install_overlay.sh
# Compiles and installs the Device Tree Overlay for NRC7292

REPO_ROOT=$(pwd)
DTS_FILE="$REPO_ROOT/nrc7292_sw_pkg/dts/newracom_for_5.16_or_later.dts"
DTBO_NAME="nrc-rpi" # Standard name used in config.txt often
TARGET_DTBO="/boot/overlays/$DTBO_NAME.dtbo"

if [ ! -f "$DTS_FILE" ]; then
    echo "Error: DTS file not found at $DTS_FILE"
    exit 1
fi

echo "Compiling Device Tree Overlay..."
dtc -I dts -O dtb -o "$DTBO_NAME.dtbo" "$DTS_FILE"

if [ ! -f "$DTBO_NAME.dtbo" ]; then
    echo "Error: Compilation failed."
    exit 1
fi

echo "Installing to $TARGET_DTBO..."
sudo cp "$DTBO_NAME.dtbo" "$TARGET_DTBO"

echo "Adding to /boot/config.txt..."
# Check if already present
if ! grep -q "dtoverlay=$DTBO_NAME" /boot/config.txt; then
    echo "dtoverlay=$DTBO_NAME" | sudo tee -a /boot/config.txt
    echo "Overlay enabled."
else
    echo "Overlay already enabled in config.txt."
fi

echo "DT Overlay setup complete. Please reboot for changes to take effect."
