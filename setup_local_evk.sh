#!/bin/bash
# setup_local_evk.sh
# Sets up the EVK software locally, patching it to run as current user and keep wlan0 alive.

# 1. Define Paths
REPO_ROOT=$(pwd)
SRC_EVK="$REPO_ROOT/nrc7292_sw_pkg/package/evk/sw_pkg/nrc_pkg"
COMPILED_DRIVER="$REPO_ROOT/nrc7292_sw_pkg/package/src/nrc/nrc.ko"
LOCAL_PKG_DIR="$HOME/nrc_pkg"

echo "Setting up Local EVK Environment..."
echo "Repo Root: $REPO_ROOT"
echo "Target Dir: $LOCAL_PKG_DIR"

# 2. Compilation (Auto-detect if needed)
echo "Checking for compiled driver..."
if [ ! -f "$COMPILED_DRIVER" ]; then
    echo "Driver not found. Attempting to compile..."
    SRC_DIR="$REPO_ROOT/nrc7292_sw_pkg/package/src/nrc"
    
    if [ -d "$SRC_DIR" ]; then
        cd "$SRC_DIR" || exit 1
        echo "Compiling in $SRC_DIR..."
        make clean
        if make; then
            echo "Compilation successful!"
        else
            echo "Error: Compilation failed."
            echo "Ensure you are on Raspberry Pi OS Legacy (Bullseye) and have kernel headers installed."
            exit 1
        fi
        cd "$REPO_ROOT" || exit 1
    else
        echo "Error: Source directory not found at $SRC_DIR"
        exit 1
    fi
else
    echo "Found existing compiled driver."
fi

# 3. Create Local Workspace
echo "Creating local workspace..."
rm -rf "$LOCAL_PKG_DIR"
mkdir -p "$LOCAL_PKG_DIR"
cp -r "$SRC_EVK/"* "$LOCAL_PKG_DIR/"

# 4. Copy Compiled Driver to EVK location
# EVK expects driver in sw/driver/nrc.ko
mkdir -p "$LOCAL_PKG_DIR/sw/driver"
cp "$COMPILED_DRIVER" "$LOCAL_PKG_DIR/sw/driver/nrc.ko"
echo "Copied compiled driver to $LOCAL_PKG_DIR/sw/driver/nrc.ko"

# 5. Patch start.py
START_SCRIPT="$LOCAL_PKG_DIR/script/start.py"
echo "Patching $START_SCRIPT..."

# A. Replace /home/pi/nrc_pkg with actual LOCAL_PKG_DIR
# We use | as delimiter to avoid slashes collision
sed -i "s|/home/pi/nrc_pkg|$LOCAL_PKG_DIR|g" "$START_SCRIPT"

# B. Prevent disabling of wlan0/wlan1 (Allow concurrent usage)
echo "Disabling wlan0 kill-switch..."
sed -i 's/os.system("sudo wpa_cli disable wlan0 2>\/dev\/null ")/# os.system("sudo wpa_cli disable wlan0")/' "$START_SCRIPT"
sed -i 's/os.system("sudo wpa_cli disable wlan1 2>\/dev\/null")/# os.system("sudo wpa_cli disable wlan1")/' "$START_SCRIPT"

# C. Prevent Killing wpa_supplicant (might affect wlan0 if shared)
# If wlan0 uses wpa_supplicant, killing it will drop the connection.
# We'll comment it out, but this might prevent wlan1 from starting if it NEEDS it.
# For now, let's try keeping it alive.
sed -i 's/os.system("sudo killall -9 wpa_supplicant 2>\/dev\/null")/# os.system("sudo killall -9 wpa_supplicant")/' "$START_SCRIPT"

# 6. Patch Conf Scripts (ip_config.sh etc)
# These might also have hardcoded paths
find "$LOCAL_PKG_DIR" -type f -name "*.sh" -print0 | xargs -0 sed -i "s|/home/pi/nrc_pkg|$LOCAL_PKG_DIR|g"

echo "------------------------------------------------"
echo "Setup Complete!"
echo "To start the driver (STA mode, US country, Open security):"
echo "  cd $LOCAL_PKG_DIR/script"
echo "  sudo ./start.py 0 0 US"
echo "------------------------------------------------"
