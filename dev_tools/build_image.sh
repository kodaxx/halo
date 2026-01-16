#!/bin/bash
# build_image.sh
# Developer Tool: Prepares a Raspberry Pi as a "Golden Master" for the Halo Mesh.
# DOES NOT activate AP mode or lockdown networking.

set -e
LOG_FILE="/var/log/halo-build.log"

log() {
    echo "[Halo Build] $(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE"
    echo "$1"
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./build_image.sh)"
    exit 1
fi

# Locate Repo
cd "$(dirname "$0")/.."
REPO_DIR=$(pwd)
USER_NAME=$(stat -c '%U' "$REPO_DIR")
if [ "$USER_NAME" == "root" ]; then
    USER_NAME="${SUDO_USER:-root}"
fi
USER_HOME=$(eval echo "~$USER_NAME")

log "Starting Build Process... (User: $USER_NAME, Repo: $REPO_DIR)"

# 1. Update & Dependencies
log "Updating Package Lists & Installing Dependencies..."
# Helper: Robust APT Update
function update_apt() {
    local MAX_RETRIES=5
    local COUNT=0
    
    while [ $COUNT -lt $MAX_RETRIES ]; do
        log "Running apt-get update (Attempt $((COUNT+1))/$MAX_RETRIES)..."
        
        # 1. Try normal update
        # --allow-releaseinfo-change handles the "stable -> oldoldstable" suite change
        if apt-get update --allow-releaseinfo-change; then
            return 0
        fi
        
        log "APT Update failed (Hash mismatch?). Applying aggressive fixes..."
        
        # 2. Aggressive Cleaning
        rm -rf /var/lib/apt/lists/*
        rm -rf /var/lib/apt/lists/partial/*
        apt-get clean
        
        # 3. Wait slightly (Mirrors might be syncing)
        sleep 3
        
        # 4. Retry with robustness flags
        # Pipeline-Depth=0 fixes many HTTP 1.1 proxy issues
        # No-Cache forces fresh retrieval
        if apt-get update --allow-releaseinfo-change \
            -o Acquire::http::Pipeline-Depth=0 \
            -o Acquire::http::No-Cache=True \
            -o Acquire::BrokenProxy=true; then
            return 0
        fi
        
        COUNT=$((COUNT+1))
        log "Retry failed. Waiting 5s before next attempt..."
        sleep 5
    done
    
    return 1
}

if ! update_apt; then
    log "CRITICAL ERROR: Failed to update package lists after multiple attempts."
    log "Please check your internet connection or try a different mirror."
    log "If you are behind a firewall, ensure port 80/443 is open."
    exit 1
fi

# Install Dependencies (including those needed for building)
apt-get install -y git device-tree-compiler raspberrypi-kernel-headers build-essential hostapd dnsmasq python3-flask python3-pip iptables bridge-utils batctl dkms

# 2. Compile & Install Device Tree Overlay
log "Installing Device Tree Overlay..."
DTS_FILE="nrc7292/dts/newracom_for_5.16_or_later.dts"
if [ ! -f "$DTS_FILE" ]; then
    log "Error: DTS file not found at $DTS_FILE"
    exit 1
fi
dtc -I dts -O dtb -o nrc-rpi.dtbo "$DTS_FILE"
cp nrc-rpi.dtbo /boot/overlays/

# Enable in config.txt (if not already)
if ! grep -q "dtoverlay=nrc-rpi" /boot/config.txt; then
    echo "dtoverlay=nrc-rpi" >> /boot/config.txt
    log "Overlay enabled in /boot/config.txt"
fi

# 2b. Enable USB Gadget Mode (Safety Net)
if ! grep -q "dtoverlay=dwc2" /boot/config.txt; then
    echo "dtoverlay=dwc2" >> /boot/config.txt
    log "USB Gadget mode enabled (dwc2)"
fi
# Add modules-load for gadget
if ! grep -q "g_ether" /etc/modules; then
     echo "dwc2" >> /etc/modules
     echo "g_ether" >> /etc/modules
fi

# 3. Disable Bluetooth (Save power/interference)
if ! grep -q "dtoverlay=disable-bt" /boot/config.txt; then
    echo "dtoverlay=disable-bt" >> /boot/config.txt
    log "Bluetooth disabled (disable-bt)"
fi


# 3. Setup Local EVK Directory & Compile Driver
LOCAL_PKG_DIR="$USER_HOME/nrc_pkg"
if [ ! -d "$LOCAL_PKG_DIR" ]; then
    log "Creating local package directory at $LOCAL_PKG_DIR..."
    cp -r "nrc7292/package/evk/sw_pkg/nrc_pkg" "$LOCAL_PKG_DIR"
    chown -R "$USER_NAME:$USER_NAME" "$LOCAL_PKG_DIR"
fi

# Compile Driver
if [ ! -f "$LOCAL_PKG_DIR/sw/driver/nrc.ko" ]; then
    log "Compiling Driver..."
    cd "nrc7292/package/src/nrc"
    make clean
    if make; then
        mkdir -p "$LOCAL_PKG_DIR/sw/driver"
        cp nrc.ko "$LOCAL_PKG_DIR/sw/driver/"
        mkdir -p "$LOCAL_PKG_DIR/evk/binary"
        cp nrc.ko "$LOCAL_PKG_DIR/evk/binary/"
        log "Driver compiled successfully."
    else
        log "Error: Driver compilation failed."
        exit 1
    fi
    cd "$REPO_DIR"
fi

# 4. Install Firmware
log "Installing Firmware..."
mkdir -p /lib/firmware
cp "nrc7292/package/evk/binary/nrc7292_cspi.bin" /lib/firmware/
cp "nrc7292/package/evk/binary/nrc7292_bd.dat" /lib/firmware/bd.dat

# 5. Patch Scripts & Permissions
log "Patching Scripts & Permissions..."
# Local Package Scripts
find "$LOCAL_PKG_DIR" -name "*.py" -exec chmod +x {} \;
find "$LOCAL_PKG_DIR" -name "*.sh" -exec chmod +x {} \;
chown -R "$USER_NAME:$USER_NAME" "$LOCAL_PKG_DIR"

# Repo Scripts
chmod +x "$REPO_DIR/scripts/"*.sh
chmod +x "$REPO_DIR/dashboard/web_admin.py"
chown -R "$USER_NAME:$USER_NAME" "$REPO_DIR"

# Patch start.py (Standard fix)
START_PY="$LOCAL_PKG_DIR/script/start.py"
sed -i '/wpa_cli disable wlan0/s/^/#/' "$START_PY"
sed -i '/killall.*wpa_supplicant/s/^/#/' "$START_PY"
sed -i "s|/home/pi/|$USER_HOME/|g" "$START_PY"
sed -i "s/run_mp('wlan0'/run_mp('wlan1'/g" "$START_PY"

# 6. Install Systemd Services (BUT DO NOT ENABLE)
log "Installing Systemd Services (Disabled state)..."
cp services/*.service /etc/systemd/system/

# Fix paths in services to match $REPO_DIR
# Placeholder in repo is /home/halo/halo/
# We update it to the actual REPO_DIR
sed -i "s|/home/halo/halo|$REPO_DIR|g" /etc/systemd/system/halo-*.service

systemctl daemon-reload
# Note: We do NOT enable them. valid_appliance.sh will do that.

# 7. Install Default Configs
if [ ! -f /boot/halo.json ]; then
    cp configs/halo.json /boot/halo.json
fi

# Install optimized config.txt if available (careful not to overwrite if we just appended overlay?)
# Actually, better to append/check specific settings than overwrite the whole file to be safe.
# We already appended overlay above.

log "=== BUILD COMPLETE ==="
log "This system is now a 'Golden Master'."
log "NEXT STEPS:"
log "1. Shutdown this Pi."
log "2. Remove SD Card."
log "3. Run 'dev_tools/capture_image.sh' on your Mac."
