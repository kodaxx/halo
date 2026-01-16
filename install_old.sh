#!/bin/bash
# Halo Cloud Installer
# USAGE: bash <(curl -sL https://raw.githubusercontent.com/kodaxx/Halo/main/install.sh)
# Requires: Linux 6.12+, Raspberry Pi OS (Bookworm)

REPO_URL="https://github.com/kodaxx/Halo.git" # REPLACE THIS
INSTALL_DIR="/tmp/halo_install"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
    log "ERROR: $*" >&2
    exit 1
}

log "=== Halo Installer (Linux 6.12+) ==="

# 1. Update package lists
log "Updating package lists..."
sudo apt-get update || error_exit "apt-get update failed"

# 2. Install dependencies
log "Installing dependencies..."
PACKAGES="raspberrypi-kernel-headers git python3-flask batctl dnsmasq hostapd build-essential bc wget iproute2 iptables-nft"

sudo apt-get install -y $PACKAGES || error_exit "apt-get install failed"

# 3. Clone repository
log "Cloning Halo repository..."
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR || error_exit "git clone failed"

# 4. Setup nrc7292 driver
log "Setting up NRC7292 HaLow driver..."
cd /home/pi
if [ ! -d "nrc7292_sw_pkg" ]; then
    log "Copying nrc7292_sw_pkg from installation..."
    cp -r $INSTALL_DIR/nrc7292_sw_pkg . || error_exit "Failed to copy nrc7292_sw_pkg"
else
    log "nrc7292_sw_pkg already exists, skipping copy"
fi

# 5. Update /etc/modules for USB Ethernet Gadget
log "Configuring kernel modules..."
grep -qxF "dwc2" /etc/modules || echo "dwc2" | sudo tee -a /etc/modules
grep -qxF "g_ether" /etc/modules || echo "g_ether" | sudo tee -a /etc/modules

# 6. Configure boot settings
log "Configuring boot settings..."
if [ -f "$INSTALL_DIR/assets/config.txt" ]; then
    cat $INSTALL_DIR/assets/config.txt | sudo tee -a /boot/config.txt || log "WARNING: Failed to append to /boot/config.txt"
else
    log "WARNING: config.txt not found in assets"
fi

# 7. Copy configuration files
log "Installing configuration files..."
sudo cp $INSTALL_DIR/assets/hostapd.conf /etc/hostapd/hostapd.conf || error_exit "Failed to copy hostapd.conf"
sudo cp $INSTALL_DIR/assets/dnsmasq.conf /etc/dnsmasq.conf || error_exit "Failed to copy dnsmasq.conf"
sudo cp $INSTALL_DIR/assets/dhcpcd.conf /etc/dhcpcd.conf || error_exit "Failed to copy dhcpcd.conf"
sudo cp $INSTALL_DIR/assets/halo.json /boot/halo.json || error_exit "Failed to copy halo.json"

# 8. Install scripts and systemd units
log "Installing scripts..."
if [ "$MODERN" -eq 1 ]; then
    log "Using modernized scripts (Linux 6.12+ optimized)"
    SCRIPT_SUFFIX=".modern"
else
    log "Using legacy scripts"
    SCRIPT_SUFFIX=""
fi

# Copy scripts (prefer modern versions if available)
for script in start_mesh.sh gateway_monitor.sh provision_wifi.sh; do
    if [ -f "$INSTALL_DIR/assets/${script}${SCRIPT_SUFFIX}" ]; then
        sudo cp "$IN
log "Installing scripts..."
for script in start_mesh.sh gateway_monitor.sh provision_wifi.sh web_admin.py; do
    sudo cp "$INSTALL_DIR/assets/$script" "/home/pi/$script" || error_exit "Failed to copy $script"
    sudo chmod +x "/home/pi/$script"
    log "Installed $script"  log "Installed $unit (legacy)"
    fi
done

# Always install web_admin.service (if it exists)
if [ -f "$INSTALL_DIR/assets/web_admin.service" ]; then
    sudo cp "$INSTALL_DIR/assets/web_admin.service" "/etc/systemd/system/web_admin.service" || log "WARNING: Failed to copy web_admin.service"
fi

# 10. Reload systemd and enable services
log "Configuring systemd services..."
sudo systemctl daemon-reload
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl enable halo.service
sudo systemctl enable halo-firstboot
sudo systemctl enable web_admin.service 2>/dev/null || log "web_admin.service not available"

# 11. Run initial provisioning
for unit in halo.service halo-firstboot.service; do
    sudo cp "$INSTALL_DIR/assets/$unit" "/etc/systemd/system/$unit" || error_exit "Failed to copy $unit"
    log "Installed $unit"t /boot/wifi_credentials.txt
else
    echo "ERROR: Credentials not generated."
fi
echo "================================"
echo ""
echo "Next steps:"
echo "  1. Review /boot/halo.json for configuration"
echo "  2. Reboot the device: sudo reboot"
echo "  3. After reboot, driver will compile (first boot only)"
echo "  4. Access web admin at: http://gw.halo.local or http://10.0.0.1"
echo ""
