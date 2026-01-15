#!/bin/bash
# setup_evk_clean.sh
# Sets up the EVK environment using PREBUILT binaries on Bullseye.
# Patches start.py to run as current user and preserve wlan0.

REPO_ROOT=$(pwd)
# Robust root detection
# 1. Check if we are running from within the repo (standard behavior)
if [ -d "nrc7292_sw_pkg" ]; then
    REPO_ROOT=$(pwd)
# 2. Check if the bootstrap script already cloned it to ~/halo
elif [ -d "$HOME/halo/nrc7292_sw_pkg" ]; then
    REPO_ROOT="$HOME/halo"
    echo "Found existing repository at $REPO_ROOT"
else
    # 3. Fallback: Clone if necessary (rare if bootstrap was run)
    echo "Repo not found locally. Cloning kodaxx/halo to temp_repo..."
    git clone https://github.com/kodaxx/halo.git temp_repo
    if [ -d "temp_repo/nrc7292_sw_pkg" ]; then
        REPO_ROOT="$(pwd)/temp_repo"
    else
        echo "Error: Failed to clone repository."
        exit 1
    fi
fi

SRC_EVK="$REPO_ROOT/nrc7292_sw_pkg/package/evk/sw_pkg/nrc_pkg"
BINARY_DIR="$REPO_ROOT/nrc7292_sw_pkg/package/evk/binary"
LOCAL_PKG_DIR="$HOME/nrc_pkg"
CURRENT_USER=$(whoami)

echo "Setting up Clean EVK Environment in $LOCAL_PKG_DIR..."

# 1. Copy Generic EVK Package
if [ -d "$LOCAL_PKG_DIR" ]; then
    echo "Backing up existing nrc_pkg..."
    mv "$LOCAL_PKG_DIR" "$LOCAL_PKG_DIR.bak_$(date +%s)"
fi
cp -r "$SRC_EVK" "$LOCAL_PKG_DIR"

# 2. install Prebuilt Driver
echo "Installing prebuilt driver..."
if [ -f "$BINARY_DIR/nrc.ko" ]; then
    cp "$BINARY_DIR/nrc.ko" "$LOCAL_PKG_DIR/evk/binary/nrc.ko"
    # Also link it where script/start.py expects it? 
    # start.py looks in `evk/binary`? No, start.py is in `script/`.
    # Let's check start.py logic in a moment. Usually it expects module in same dir or specific path.
    # The default EVK structure has `evk` and `script` inside `nrc_pkg`.
    # nrc.ko usually goes to `nrc_pkg/evk/binary/nrc.ko`.
else
    echo "Error: Prebuilt nrc.ko not found!"
    exit 1
fi

# 3. Install Prebuilt Firmware
echo "Installing prebuilt firmware..."
# start.py defaults to loading 'uni_s1g.bin'
if [ -f "$BINARY_DIR/nrc7292_cspi.bin" ]; then
    cp "$BINARY_DIR/nrc7292_cspi.bin" "$LOCAL_PKG_DIR/evk/firmware/uni_s1g.bin"
    # Also keep original name just in case
    cp "$BINARY_DIR/nrc7292_cspi.bin" "$LOCAL_PKG_DIR/evk/firmware/nrc7292_cspi.bin"
else
    echo "Error: Prebuilt firmware not found!"
    exit 1
fi

# 4. Patch start.py
START_PY="$LOCAL_PKG_DIR/script/start.py"
echo "Patching $START_PY..."

# Remove hardcoded 'pi' user expectation
sed -i "s|/home/pi/|$HOME/|g" "$START_PY"

# Comment out wlan0 disabling
sed -i 's/os.system("wpa_cli disable wlan0")/#os.system("wpa_cli disable wlan0")/g' "$START_PY"
sed -i 's/os.system("sudo killall wpa_supplicant")/#os.system("sudo killall wpa_supplicant")/g' "$START_PY"

# 5. Patch files recursively
echo "Patching all scripts for user path..."
# Ensure scripts are executable
find "$LOCAL_PKG_DIR" -type f \( -name "*.py" -o -name "*.sh" \) -exec chmod +x {} \;

# Replace /home/pi path in all .py, .sh, and .conf files
find "$LOCAL_PKG_DIR" -type f \( -name "*.py" -o -name "*.sh" -o -name "*.conf" \) -print0 | xargs -0 sed -i "s|/home/pi/|$HOME/|g"

echo "Setup Complete."
echo "To run AP mode: sudo $LOCAL_PKG_DIR/script/start.py 1 0 US"
