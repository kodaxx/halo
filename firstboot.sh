#!/bin/bash
# firstboot.sh
# Run this ONCE after flashing the base Image.

set -e
LOG_FILE="/var/log/halo-firstboot.log"

log() {
    echo "[Halo Firstboot] $(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE"
    echo "$1"
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./firstboot.sh)"
    exit 1
fi

cd "$(dirname "$0")"
REPO_DIR=$(pwd)
USER_NAME=$(stat -c '%U' "$REPO_DIR")
if [ "$USER_NAME" == "root" ]; then
    USER_NAME="${SUDO_USER:-root}"
fi
USER_HOME=$(eval echo "~$USER_NAME")

log "Starting Activation... (User: $USER_NAME)"

# 1. Hardware Check
log "Checking hardware..."
if ! ip link show wlan1 >/dev/null 2>&1; then
    log "WARNING: wlan1 interface not found! Is the WiFi HaLow Hat connected?"
    log "Proceeding anyway, but mesh services may fail."
fi

# 2. Install AP Configuration
log "Installing Access Point Configurations..."
if [ -f "configs/hostapd.conf" ]; then
    cp configs/hostapd.conf /etc/hostapd/hostapd.conf
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|g' /etc/default/hostapd
    systemctl unmask hostapd
    # Note: We enable it later
fi

if [ -f "configs/dnsmasq.conf" ]; then
    mkdir -p /etc/dnsmasq.d
    cp configs/dnsmasq.conf /etc/dnsmasq.d/halo-ap.conf
fi

# 3. Provision Security (Generate Passwords)
log "Generating Security Credentials..."
if [ -f "scripts/provision_wifi.sh" ]; then
    chmod +x "scripts/provision_wifi.sh"
    bash "scripts/provision_wifi.sh"
else
    log "ERROR: scripts/provision_wifi.sh not found!"
    exit 1
fi

# 4. Enable Services
log "Enabling Systemd AP Services..."
# hostapd and dnsmasq are needed for AP
systemctl enable hostapd
systemctl enable dnsmasq

# 5. Network Lockdown
log "Locking down network interfaces..."
if ! grep -q "denyinterfaces.*wlan1" /etc/dhcpcd.conf; then
    # Remove old verify lines to avoid duplicates
    sed -i '/denyinterfaces/d' /etc/dhcpcd.conf
    # Append new configuration (Deny EVERYTHING except eth0 effectively)
    # wlan0 is handled by hostapd/bridge
    # wlan1 is handled by nrc driver/batman
    # br0 is handled by bridge-utils/static IP
    echo "denyinterfaces wlan1 br0 bat0 wlan0" >> /etc/dhcpcd.conf
fi

# 6. Handover
log "=== ACTIVATION COMPLETE ==="

if [ -f /boot/wifi_credentials.txt ]; then
    echo ""
    echo "========================================================"
    echo "   HALO APPLIANCE CREDENTIALS (SAVE THESE!)"
    echo "========================================================"
    cat /boot/wifi_credentials.txt
    echo "========================================================"
    echo ""
fi

log "System will REBOOT in 30 seconds."
log "After reboot, the device will be in Mesh/AP mode."
log "Connect to the WiFi shown above and visit http://10.0.0.1"
log "Rebooting in 30s..."

sleep 30
reboot
