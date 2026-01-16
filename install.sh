#!/bin/bash
# install.sh
# One-Click Installer for Halo HaLow Mesh
# auto-reboots and continues installation.

set -e
LOG_FILE="/var/log/halo-install.log"

log() {
    echo "[Halo Installer] $(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE"
    echo "$1"
}

# Ensure we are running from the repo directory
cd "$(dirname "$0")"
REPO_DIR=$(pwd)
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
USER_NAME="${SUDO_USER:-$USER}"

if [ "$EUID" -ne 0 ]; then
    log "Please run as root (sudo ./install.sh)"
    exit 1
fi

log "Starting Installation... (User: $USER_NAME, Home: $USER_HOME)"

# --- PHASE 1: OVERLAY CHECK ---
# Check if overlay is loaded in config.txt
if ! grep -q "dtoverlay=nrc-rpi" /boot/config.txt; then
    log "Phase 1: Installing Device Tree Overlay..."
    
    # 1. Update & Dependencies
    apt-get update
    apt-get install -y git device-tree-compiler raspberrypi-kernel-headers build-essential hostapd python3-flask python3-pip iptables bridge-utils batctl
    
    # 2. Compile & Install Overlay
    DTS_FILE="nrc7292_sw_pkg/dts/newracom_for_5.16_or_later.dts"
    if [ ! -f "$DTS_FILE" ]; then
        log "Error: DTS file not found at $DTS_FILE"
        exit 1
    fi
    dtc -I dts -O dtb -o nrc-rpi.dtbo "$DTS_FILE"
    cp nrc-rpi.dtbo /boot/overlays/
    
    # 3. Enable in config.txt
    echo "dtoverlay=nrc-rpi" >> /boot/config.txt
    
    # 4. Setup Bootstrap Service for Post-Reboot
    log "Setting up bootstrap service for post-reboot continuation..."
    cat > /etc/systemd/system/halo-bootstrap.service <<EOF
[Unit]
Description=Halo Installer Bootstrap
After=network.target

[Service]
Type=oneshot
ExecStart=$REPO_DIR/install.sh
WorkingDirectory=$REPO_DIR
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable halo-bootstrap.service
    
    log "Phase 1 Complete. Rebooting in 5 seconds..."
    sleep 5
    reboot
    exit 0
fi

# --- PHASE 2: DRIVER & APPLIANCE SETUP ---
log "Phase 2: Overlay detected. Proceeding with Driver & Software Setup..."

# 1. Setup Local EVK Directory
LOCAL_PKG_DIR="$USER_HOME/nrc_pkg"
if [ ! -d "$LOCAL_PKG_DIR" ]; then
    log "Creating local package directory at $LOCAL_PKG_DIR..."
    cp -r "nrc7292_sw_pkg/package/evk/sw_pkg/nrc_pkg" "$LOCAL_PKG_DIR"
    chown -R "$USER_NAME:$USER_NAME" "$LOCAL_PKG_DIR"
fi

# 2. Compile Driver (Idempotent check)
if [ ! -f "$LOCAL_PKG_DIR/sw/driver/nrc.ko" ]; then
    log "Compiling Driver..."
    cd "nrc7292_sw_pkg/package/src/nrc"
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
else
    log "Driver already compiled."
fi

# 3. Install Firmware
mkdir -p /lib/firmware
cp "nrc7292_sw_pkg/package/evk/binary/nrc7292_cspi.bin" /lib/firmware/
cp "nrc7292_sw_pkg/package/evk/binary/nrc7292_bd.dat" /lib/firmware/bd.dat
log "Firmware installed."

# 4. Patch Scripts (start.py, mesh.py) - calling existing logic or rewriting inline? 
# Rewriting minimal necessary logic to ensure robustness
log "Patching Scripts..."

# Fix Permissions
find "$LOCAL_PKG_DIR" -name "*.py" -exec chmod +x {} \;
find "$LOCAL_PKG_DIR" -name "*.sh" -exec chmod +x {} \;
chown -R "$USER_NAME:$USER_NAME" "$LOCAL_PKG_DIR" # Ensure user owns it all

# Patch start.py to not kill wlan0
START_PY="$LOCAL_PKG_DIR/script/start.py"
sed -i '/wpa_cli disable wlan0/s/^/#/' "$START_PY"
sed -i '/killall.*wpa_supplicant/s/^/#/' "$START_PY"
sed -i "s|/home/pi/|$USER_HOME/|g" "$START_PY"
# Use wlan1
sed -i "s/run_mp('wlan0'/run_mp('wlan1'/g" "$START_PY"

# 5. Install Services
log "Installing Systemd Services..."
cp services/*.service /etc/systemd/system/
# Fix paths in services to match $USER_HOME if needed (assuming /home/halo for now based on previous work, but lets be safe)
sed -i "s|/home/halo|$USER_HOME|g" /etc/systemd/system/halo-*.service

systemctl daemon-reload
systemctl enable halo-web.service
systemctl enable halo-mesh.service
systemctl enable halo-monitor.service

# 5b. Configure Networking (dhcpcd)
log "Configuring DHCPCD (Preventing interference)..."
if ! grep -q "denyinterfaces.*wlan1" /etc/dhcpcd.conf; then
    log "Adding interfaces denial to /etc/dhcpcd.conf..."
    # Remove old verify lines to avoid duplicates
    sed -i '/denyinterfaces/d' /etc/dhcpcd.conf
    # Append new configuration
    echo "denyinterfaces wlan1 br0 bat0" >> /etc/dhcpcd.conf
    # Restart dhcpcd immediately as part of install process
    systemctl restart dhcpcd || log "Warning: dhcpcd restart failed (might not be running)"
fi

# 6. Install Default Config & Assets
if [ ! -f /boot/halo.json ]; then
    cp halo.json /boot/halo.json
    log "Default config installed to /boot/halo.json"
fi

# 6b. Setup AP Mode (wlan0)
log "Configuring Access Point (wlan0)..."
if [ -f "assets/hostapd.conf" ]; then
    cp assets/hostapd.conf /etc/hostapd/hostapd.conf
    # Point default to config
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|g' /etc/default/hostapd
    systemctl unmask hostapd
    systemctl enable hostapd
fi

if [ -f "assets/dnsmasq.conf" ]; then
    cp assets/dnsmasq.conf /etc/dnsmasq.d/halo-ap.conf
    # Note: We rely on gateway_monitor.sh for dnsmasq, but this file is good backup
fi

# 6c. Setup Provisioning Script (AND RUN IT NOW)
if [ -f "assets/provision_wifi.sh" ]; then
    DEST_PROV="$USER_HOME/halo/provision_wifi.sh"
    cp assets/provision_wifi.sh "$DEST_PROV"
    chmod +x "$DEST_PROV"
    # Ensure service file uses correct path
    sed -i "s|/home/halo|$USER_HOME|g" /etc/systemd/system/halo-provision.service
    systemctl enable halo-provision.service
    
    # Run NOW to generate credentials before reboot
    log "Generating Wi-Fi Credentials..."
    bash "$DEST_PROV"
    
    # DISPLAY CREDENTIALS
    if [ -f /boot/wifi_credentials.txt ]; then
        echo ""
        echo "========================================================"
        echo "   HALO APPLIANCE SETUP COMPLETE - SAVE THESE NOW!"
        echo "========================================================"
        cat /boot/wifi_credentials.txt
        echo "========================================================"
        echo ""
    fi
fi

# 7. Cleanup & Final Security
log "Disabling bootstrap service..."
systemctl disable halo-bootstrap.service
rm /etc/systemd/system/halo-bootstrap.service
systemctl daemon-reload

# 8. Final Network Lockdown
# We delayed denying wlan0 until now to keep your SSH alive during install
log "Locking down wlan0 for AP mode..."
sed -i '/denyinterfaces/d' /etc/dhcpcd.conf
echo "denyinterfaces wlan1 br0 bat0 wlan0" >> /etc/dhcpcd.conf

log "=== INSTALLATION SUCCESSFUL ==="
log "The system will REBOOT in 30 seconds."
log "Your current SSH connection will drop."
log "After reboot, connect to the Wi-Fi network shown above."
log "Access the Web Admin at: http://10.0.0.1"
log "Rebooting in 30s..."

sleep 30
reboot
