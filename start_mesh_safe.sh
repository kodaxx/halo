#!/bin/bash
# start_mesh_safe.sh
# Halo Mesh Startup (Safe Mode - Preserves wlan0/SSH)

set -e  # Exit on error

# Configuration
CONFIG_FILE="/boot/halo.json"
# Correct runtime path for our setup
DRIVER_DIR="$HOME/nrc_pkg"
SCRIPT_PATH="$DRIVER_DIR/script/start.py"

# Logging helper
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Error handler
error_exit() {
    log "ERROR: $*" >&2
    exit 1
}

# Create bridge using ip command
create_bridge() {
    local br_name=$1
    log "Creating bridge $br_name"
    # Check if bridge exists first
    if ip link show "$br_name" >/dev/null 2>&1; then
        log "Bridge $br_name already exists"
        sudo ip link set "$br_name" up
    else
        sudo ip link add "$br_name" type bridge || error_exit "Failed to create bridge $br_name"
        sudo ip link set "$br_name" up || error_exit "Failed to bring up bridge $br_name"
    fi
}

# Add interface to bridge
bridge_add_if() {
    local br_name=$1
    local if_name=$2
    log "Adding $if_name to bridge $br_name"
    sudo ip link set "$if_name" master "$br_name" || error_exit "Failed to add $if_name to $br_name"
}

# Bring interface up
interface_up() {
    local if_name=$1
    log "Bringing up interface $if_name"
    sudo ip link set "$if_name" up || error_exit "Failed to bring up $if_name"
}

log "=== Halo Mesh Startup (Safe Mode) ==="

# 1. Load Settings
if [ -f "$CONFIG_FILE" ]; then
    log "Loading configuration from $CONFIG_FILE"
    MESH_ID=$(grep -o '"mesh_id": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "HaloNet")
    FREQ=$(grep -o '"freq": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "915")
    COUNTRY=$(grep -o '"country": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "US")
else
    log "Config file not found, using defaults"
    MESH_ID="HaloNet"
    FREQ="915"
    COUNTRY="US"
fi

log "Configuration: MESH_ID=$MESH_ID, FREQ=$FREQ, COUNTRY=$COUNTRY"

# 2. Setup Bridge (br0)
log "Setting up br0 bridge..."
create_bridge "br0"
# CRITICAL: Do NOT add wlan0 to bridge, or we lose SSH
# bridge_add_if "br0" "wlan0"

# 3. Initialize HaLow Radio
if [ ! -f "$SCRIPT_PATH" ]; then
    error_exit "NRC startup script not found: $SCRIPT_PATH"
fi

# Ensure previous instances are killed
sudo killall -9 wpa_supplicant 2>/dev/null || true
# Do NOT kill dhcpcd, we need it for wlan0

# Check if wlan1 is already up
if ip link show wlan1 >/dev/null 2>&1; then
    log "wlan1 already exists, assuming driver loaded."
else
    log "Initializing HaLow radio..."
    cd "$DRIVER_DIR/script"
    # Arg 1: 4 = Mesh AP (check this mapping?) 
    # Based on start.py analysis:
    # We used '1' for AP before.
    # User assets used '4'. Let's trust assets for Mesh mode.
    # Args: Mode(4=MeshAP?), ???(0), Country, Freq, MeshID
    sudo python3 "$SCRIPT_PATH" 4 0 "$COUNTRY" "$FREQ" "$MESH_ID" || error_exit "HaLow initialization failed"
fi

# 4. Configure wlan1 IP (since we removed start.py auto-ip)
log "Configuring wlan1..."
# We don't need IP on wlan1 if it's bridged, usually?
# But if it's batman-adv, we add wlan1 to bat0.

# 5. Start Batman-adv
log "Loading batman-adv module..."
sudo modprobe batman-adv || true

log "Adding wlan1 interface to batman-adv..."
# Wait for wlan1 to appear
sleep 2
sudo batctl if add wlan1 || log "WARNING: Failed to add wlan1 to batman-adv"

log "Bringing up bat0 interface..."
interface_up "bat0"

log "Adding bat0 to br0 bridge..."
bridge_add_if "br0" "bat0"

# 6. Configure Bridge IP
# Since we unbridged wlan0, br0 needs its own IP for the mesh network
log "Setting IP for br0 (10.0.0.1)..."
sudo ip addr add 10.0.0.1/24 dev br0 2>/dev/null || true
sudo ip link set br0 up

# 7. Disable Multicast Snooping
log "Disabling multicast snooping on br0..."
echo 0 | sudo tee /sys/devices/virtual/net/br0/bridge/multicast_snooping > /dev/null

log "=== Halo Mesh Startup Complete ==="
log "Mesh Interface: bat0 (inside br0)"
log "Management Interface: wlan0 (Keep Alive!)"
