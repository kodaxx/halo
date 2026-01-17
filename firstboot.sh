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

# 2. Generate & Display Credentials
# We do this now so you see them even if the network cuts out later.

# Ensure qrencode is installed
if ! command -v qrencode &> /dev/null; then
    log "Installing qrencode..."
    apt-get install -y qrencode || log "WARNING: Failed to install qrencode. QR code will not be displayed."
fi

log "Generating Security Credentials..."

# MAC Address Suffix for SSID (Unique to device)
MAC_SUFFIX=$(cat /sys/class/net/wlan0/address | awk -F: '{print $5$6}' | tr '[:lower:]' '[:upper:]')
NEW_SSID="Halo_$MAC_SUFFIX"

# Generate Random Password (8-13 chars)
# 8 chars minimum + random 0-5 chars extra
EXTRA_LEN=$((RANDOM % 6))
PASS_LEN=$((8 + EXTRA_LEN))
# Use openssl for secure random string, filter for alphanumeric (readability)
NEW_PASS=$(openssl rand -base64 20 | tr -dc 'a-zA-Z0-9' | head -c $PASS_LEN)

# Fallback if openssl fails
if [ -z "$NEW_PASS" ] || [ ${#NEW_PASS} -lt 8 ]; then
     log "WARNING: Random generation failed. Using fallback."
     NEW_PASS="halo_default_$MAC_SUFFIX"
fi

echo ""
echo "========================================================"
echo "   HALO CREDENTIALS"
echo "========================================================"
echo "SSID: $NEW_SSID"
echo "PASS: $NEW_PASS"
echo "ADMIN: http://10.0.0.1 or http://gw.halo.local"
#echo "QR_STRING: WIFI:S:$NEW_SSID;T:WPA;P:$NEW_PASS;H:true;;"
echo "========================================================"
echo "Scan this QR Code once the system reboots to Connect:"
qrencode -t ANSIUTF8 "WIFI:S:$NEW_SSID;T:WPA;P:$NEW_PASS;H:true;;"
echo "========================================================"
echo "Make sure to SAVE these credentials now!"
echo "========================================================"
echo ""
log "System will REBOOT in about 60 seconds."
log "After reboot, the device will be in Mesh/AP mode."
log "You will see your Halo AP on your phone or computer."
log "Connect to the WiFi shown above"
log "Rebooting in 60s..."
sleep 2

# 3. Install Access Point Configuration (Might drop SSH here)
log "Installing Access Point Configurations..."
log "SSH may drop connection while this happens..."
if [ -f "configs/hostapd.conf" ]; then
    # This overwrites /etc/hostapd/hostapd.conf with the DEFAULT (Halo_SETUP)
    cp configs/hostapd.conf /etc/hostapd/hostapd.conf
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|g' /etc/default/hostapd
    systemctl unmask hostapd
fi

if [ -f "configs/dnsmasq.conf" ]; then
    mkdir -p /etc/dnsmasq.d
    cp configs/dnsmasq.conf /etc/dnsmasq.d/halo-ap.conf
fi

# 4. Apply Credentials (Provisioning)
log "Applying Credentials to System..."
if [ -f "scripts/provision_wifi.sh" ]; then
    chmod +x "scripts/provision_wifi.sh"
    # Pass our pre-calculated credentials to the script
    bash "scripts/provision_wifi.sh" "$NEW_SSID" "$NEW_PASS"
else
    log "ERROR: scripts/provision_wifi.sh not found!"
    exit 1
fi

# 5. Enable Services
log "Enabling Systemd AP Services..."
# hostapd and dnsmasq are needed for AP
systemctl enable hostapd
systemctl enable dnsmasq

# We enable the core services (mesh/web/monitor) assuming they were installed
# but maybe not enabled by build_step_two (or we are re-enabling them to be sure)
systemctl enable halo-mesh.service
systemctl enable halo-web.service
systemctl enable halo-monitor.service

# 6. Network Lockdown
log "Locking down network interfaces..."
if ! grep -q "denyinterfaces.*wlan1" /etc/dhcpcd.conf; then
    # Remove old verify lines to avoid duplicates
    sed -i '/denyinterfaces/d' /etc/dhcpcd.conf
    # Append new configuration (Deny EVERYTHING except eth0 effectively)
    echo "denyinterfaces wlan1 br0 bat0 wlan0" >> /etc/dhcpcd.conf
    log "Network locked down."
fi

# 7. Handover
log "=== ACTIVATION COMPLETE ==="
log "System will REBOOT in 30 seconds."
log "After reboot, the device will be in Mesh/AP mode."
log "Connect to the WiFi shown above and visit http://gw.halo.local or http://10.0.0.1"
log "Rebooting in 30s..."

sleep 30
reboot
