#!/bin/bash
# Halo Main Startup Script (Linux 6.12+ optimized)
# 
# Requires:
# - Linux 6.12+
# - iproute2 (ip, bridge commands)
# - batman-adv kernel module
# - hostapd, dnsmasq
# - NRC7292 driver (nrc.ko)

set -e  # Exit on error

CONFIG_FILE="/boot/halo.json"
DRIVER_DIR="/home/pi/nrc7292_sw_pkg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging helper
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Error handler
error_exit() {
    log "ERROR: $*" >&2
    exit 1
}

# Create bridge using ip command (modern, Linux 6.12+)
create_bridge() {
    local br_name=$1
    log "Creating bridge $br_name"
    sudo ip link add "$br_name" type bridge || error_exit "Failed to create bridge $br_name"
    sudo ip link set "$br_name" up || error_exit "Failed to bring up bridge $br_name"
}

# Add interface to bridge using ip command (modern, Linux 6.12+)
bridge_add_if() {
    local br_name=$1
    local if_name=$2
    log "Adding $if_name to bridge $br_name"
    sudo ip link set "$if_name" master "$br_name" || error_exit "Failed to add $if_name to $br_name"
}

# Bring interface up using ip command (modern, Linux 6.12+)
interface_up() {
    local if_name=$1
    log "Bringing up interface $if_name"
    sudo ip link set "$if_name" up || error_exit "Failed to bring up $if_name"
}

log "=== Halo Mesh Startup (Kernel 6.12+) ==="

# 0. Run Security Provisioning First
if [ -x "$SCRIPT_DIR/provision_wifi.sh" ]; then
    log "Running WiFi provisioning..."
    "$SCRIPT_DIR/provision_wifi.sh" || error_exit "Provisioning failed"
else
    error_exit "Provisioning script not found at $SCRIPT_DIR/provision_wifi.sh"
fi

# 1. Load Settings from config file
if [ ! -f "$CONFIG_FILE" ]; then
    error_exit "Config file not found: $CONFIG_FILE"
fi

log "Loading configuration from $CONFIG_FILE"
MESH_ID=$(grep -o '"mesh_id": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "HaloNet")
FREQ=$(grep -o '"freq": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "915")
COUNTRY=$(grep -o '"country": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "US")
STATIC_IP=$(grep -o '"static_ip": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "10.0.0.1")

log "Configuration: MESH_ID=$MESH_ID, FREQ=$FREQ, COUNTRY=$COUNTRY, STATIC_IP=$STATIC_IP"

# 2. Setup Bridge (br0)
log "Setting up br0 bridge..."
create_bridge "br0" || error_exit "Bridge setup failed"
bridge_add_if "br0" "wlan0" || error_exit "Failed to add wlan0 to bridge"

# 3. Initialize HaLow Radio
if [ -d "$DRIVER_DIR/package/evk/sw_pkg/nrc_pkg" ]; then
    SCRIPT_PATH="$DRIVER_DIR/package/evk/sw_pkg/nrc_pkg/script/start.py"
else
    SCRIPT_PATH="$DRIVER_DIR/script/start.py"
fi

if [ ! -f "$SCRIPT_PATH" ]; then
    error_exit "NRC startup script not found: $SCRIPT_PATH"
fi

log "Initializing HaLow radio with Country=$COUNTRY, Freq=$FREQ, Mesh=$MESH_ID"
cd "$DRIVER_DIR"
sudo python3 "$SCRIPT_PATH" 4 0 "$COUNTRY" "$FREQ" "$MESH_ID" || error_exit "HaLow initialization failed"

# 4. Start Batman-adv
log "Loading batman-adv module..."
sudo modprobe batman-adv || log "WARNING: batman-adv module may already be loaded"

log "Adding wlan1 interface to batman-adv..."
sudo batctl if add wlan1 || log "WARNING: Failed to add wlan1, it may already be configured"

log "Bringing up bat0 interface..."
interface_up "bat0"

log "Adding bat0 to br0 bridge..."
bridge_add_if "br0" "bat0"

# 5. Disable Multicast Snooping (Fixes Chat Apps)
log "Disabling multicast snooping on br0..."
echo 0 | sudo tee /sys/devices/virtual/net/br0/bridge/multicast_snooping > /dev/null

log "=== Halo Mesh Startup Complete ==="

# 6. Start the Universal Gateway Monitor in Background
log "Starting gateway monitor..."
if [ -x "$SCRIPT_DIR/gateway_monitor.sh" ]; then
    "$SCRIPT_DIR/gateway_monitor.sh" &
    MONITOR_PID=$!
    log "Gateway monitor started (PID: $MONITOR_PID)"
else
    error_exit "Gateway monitor script not found"
fi

log "Halo mesh is online. Check syslog for details."
