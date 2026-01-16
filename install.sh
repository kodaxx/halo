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
# Ensure we are running from the repo directory
cd "$(dirname "$0")"
REPO_DIR=$(pwd)

# Detect the Real User (Owner of the repo)
# When running via systemd (Phase 2), SUDO_USER is empty and USER is root.
# We want to install for the user who owns this directory (e.g., 'halo' or 'pi').
USER_NAME=$(stat -c '%U' "$REPO_DIR")
if [ "$USER_NAME" == "root" ]; then
    # Fallback to sudo user if repo is owned by root? Or just use root.
    USER_NAME="${SUDO_USER:-root}"
fi

# Detect Home Directory
USER_HOME=$(eval echo "~$USER_NAME")

if [ "$EUID" -ne 0 ]; then
    log "Please run as root (sudo ./install.sh)"
    exit 1
fi

log "Starting Installation... (User: $USER_NAME, Home: $USER_HOME)"

# Helper: Setup Access Point & Provisioning
setup_ap() {
    log "Configuring Access Point & Provisioning Credentials..."
    
    # 1. Hostapd Config
    if [ -f "assets/hostapd.conf" ]; then
        cp assets/hostapd.conf /etc/hostapd/hostapd.conf
        sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|g' /etc/default/hostapd
        systemctl unmask hostapd
        systemctl enable hostapd
    fi

    # 2. Dnsmasq Config
    if [ -f "assets/dnsmasq.conf" ]; then
        mkdir -p /etc/dnsmasq.d
        cp assets/dnsmasq.conf /etc/dnsmasq.d/halo-ap.conf
    fi

    # 3. run Provisioning
    if [ -f "assets/provision_wifi.sh" ]; then
        DEST_PROV="$USER_HOME/halo/provision_wifi.sh"
        cp assets/provision_wifi.sh "$DEST_PROV"
        chmod +x "$DEST_PROV"
        sed -i "s|/home/halo|$USER_HOME|g" /etc/systemd/system/halo-provision.service
        systemctl enable halo-provision.service
        
        # Run NOW to generate credentials
        bash "$DEST_PROV"
        
        # DISPLAY CREDENTIALS
        if [ -f /boot/wifi_credentials.txt ]; then
            echo ""
            echo "========================================================"
            echo "   HALO APPLIANCE CREDENTIALS (SAVE THESE!)"
            echo "========================================================"
            cat /boot/wifi_credentials.txt
            echo "========================================================"
            echo ""
            echo "NOTE: The system will REBOOT to install the kernel overlay."
            echo "      Installation will continue in the background."
            echo "      Please wait ~5 minutes for the WiFi network to appear."
            echo ""
        fi
    fi
}

# --- PHASE 1: OVERLAY CHECK ---
# Check if overlay is loaded in config.txt
if ! grep -q "dtoverlay=nrc-rpi" /boot/config.txt; then
    log "Phase 1: Installing Device Tree Overlay..."
    
    # 0. Fix Hostname Resolution (Silence sudo warnings)
    if ! grep -q "127.0.1.1" /etc/hosts; then
        echo "127.0.1.1 $(hostname)" >> /etc/hosts
    fi
    
    # 1. Update & Dependencies
    log "Updating Package Lists..."
    if ! apt-get update --allow-releaseinfo-change; then
        log "APT Update failed. Clearing lists and retrying..."
        rm -rf /var/lib/apt/lists/*
        apt-get update --allow-releaseinfo-change -o Acquire::http::Pipeline-Depth=0 -o Acquire::http::No-Cache=True -o Acquire::BrokenProxy=true || log "Update finished with errors. Proceeding..."
    fi
    apt-get install -y git device-tree-compiler raspberrypi-kernel-headers build-essential hostapd dnsmasq python3-flask python3-pip iptables bridge-utils batctl
    
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
    
    # 4. PRE-PROVISION WIFI (So user sees creds before reboot)
    setup_ap
    
    # 5. Setup Bootstrap Service for Post-Reboot
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
    
    log "Phase 1 Complete. Rebooting in 30 seconds to apply overlay..."
    log "Please SAVE YOUR CREDENTIALS above."
    sleep 30
    reboot
    exit 0
fi

# --- PHASE 2: DRIVER & APPLIANCE SETUP ---
log "Phase 2: Overlay detected. Proceeding with Driver & Software Setup..."
# 0. Fix Hostname Resolution (Again, just in case)
if ! grep -q "127.0.1.1" /etc/hosts; then
    echo "127.0.1.1 $(hostname)" >> /etc/hosts
fi

# ... (Rest of Phase 2 Logic) ...

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
# 1. Local Package Scripts
find "$LOCAL_PKG_DIR" -name "*.py" -exec chmod +x {} \;
find "$LOCAL_PKG_DIR" -name "*.sh" -exec chmod +x {} \;
chown -R "$USER_NAME:$USER_NAME" "$LOCAL_PKG_DIR"

# 2. Repo Scripts (Critical for systemd 203/EXEC error)
chmod +x "$REPO_DIR/start_mesh_safe.sh"
chmod +x "$REPO_DIR/gateway_monitor.sh"
chmod +x "$REPO_DIR/web_admin.py"
chown -R "$USER_NAME:$USER_NAME" "$REPO_DIR"

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
# Fix paths in services to match the actual REPO location
# Services use placeholder /home/halo/halo, we replace it with $REPO_DIR
sed -i "s|/home/halo/halo|$REPO_DIR|g" /etc/systemd/system/halo-*.service
# Fallback: just in case some used /home/halo without the double halo
sed -i "s|/home/halo|$REPO_DIR|g" /etc/systemd/system/halo-*.service

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

# 6a. Install Boot Config (Overlay, Gadget Mode, UART)
if [ -f "assets/config.txt" ]; then
    log "Installing optimized /boot/config.txt..."
    cp assets/config.txt /boot/config.txt
fi

# 6b. Setup AP Mode (Run again to ensure config consistency)
setup_ap

# 7. Cleanup & Final Security
log "Disabling bootstrap service..."
# Use || true so we don't crash if it doesn't exist (manual run case)
systemctl disable halo-bootstrap.service 2>/dev/null || true
if [ -f /etc/systemd/system/halo-bootstrap.service ]; then
    rm /etc/systemd/system/halo-bootstrap.service
fi
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
