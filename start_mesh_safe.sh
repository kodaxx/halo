#!/bin/bash
# start_mesh_safe.sh
# Halo Mesh Startup (Safe Mode - Preserves wlan0/SSH)

set -e  # Exit on error

# Configuration
CONFIG_FILE="/boot/halo.json"
DRIVER_DIR="$HOME/nrc_pkg"
SCRIPT_PATH="$DRIVER_DIR/script/start.py"
CONF_DIR="$DRIVER_DIR/script/conf"

# Logging helper
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Error handler
error_exit() {
    log "ERROR: $*" >&2
    exit 1
}

# 0. CRITICAL PRE-CHECK: Protect networking from dhcpcd
log "Checking dhcpcd configuration..."
# We need to ensure dhcpcd does NOT try to manage wlan1, br0 or bat0.
# managing wlan1 manually means dhcpcd will fight us if we don't deny it.
if ! grep -q "denyinterfaces.*wlan1" /etc/dhcpcd.conf; then
    log "WARNING: wlan1/br0/bat0 must be unmanaged by dhcpcd!"
    log "Updating /etc/dhcpcd.conf..."
    # Remove old deny lines to avoid duplicates
    sudo sed -i '/denyinterfaces/d' /etc/dhcpcd.conf
    echo "denyinterfaces wlan1 br0 bat0" | sudo tee -a /etc/dhcpcd.conf >/dev/null
    log "--------------------------------------------------------"
    log "Configuration updated. You MUST restart networking to apply."
    log "Please run this command (your connection will drop briefly):"
    log "   sudo systemctl restart dhcpcd"
    log "Then connect again and run this script."
    log "--------------------------------------------------------"
    exit 1
fi

# Create bridge using ip command
create_bridge() {
    local br_name=$1
    log "Creating bridge $br_name"
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
    FREQ=$(grep -o '"freq": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "924") # Default to 924MHz (approx Ch 40?)
    COUNTRY=$(grep -o '"country": "[^"]*' "$CONFIG_FILE" | grep -o '[^"]*$' || echo "US")
else
    log "Config file not found, using defaults"
    MESH_ID="HaloNet"
    FREQ="924"
    COUNTRY="US"
fi

log "Configuration: MESH_ID=$MESH_ID, FREQ=$FREQ, COUNTRY=$COUNTRY"
# Convert FREQ to MHz if it's small? 
# If FREQ < 1000, assume it is MHz. If < 200, assume channel? 
# Start.py usage says "channel". wpa_supplicant needs "frequency" (MHz).
# NRC7292 usually treats 902-928MHz. 
# Let's assume FREQ is in MHz.

# 2. Setup Bridge (br0)
log "Setting up br0 bridge..."
create_bridge "br0"

# 3. Initialize HaLow Radio
if [ ! -f "$SCRIPT_PATH" ]; then
    error_exit "NRC startup script not found: $SCRIPT_PATH"
fi

# Pre-configure the wpa_supplicant conf file with SSID and Freq
# Target: mp_halow_open.conf (assuming Open security for internal mesh)
TARGET_CONF="$CONF_DIR/$COUNTRY/mp_halow_open.conf"
if [ -f "$TARGET_CONF" ]; then
    log "Patching config: $TARGET_CONF"
    sudo sed -i "s/ssid=\".*\"/ssid=\"$MESH_ID\"/g" "$TARGET_CONF"
    # Replace all frequency lines
    sudo sed -i "s/frequency=.*/frequency=$FREQ/g" "$TARGET_CONF"
    sudo sed -i "s/freq_list=.*/freq_list=$FREQ/g" "$TARGET_CONF"
    sudo sed -i "s/scan_freq=.*/scan_freq=$FREQ/g" "$TARGET_CONF"

    # CRITICAL: Sanitize config for standard wpa_supplicant
    # The NRC driver includes custom parameters that standard wpa_supplicant rejects
    sudo sed -i '/dot11MeshRetryTimeout/d' "$TARGET_CONF"
    sudo sed -i '/dot11MeshHoldingTimeout/d' "$TARGET_CONF"
    sudo sed -i '/dot11MeshMaxRetries/d' "$TARGET_CONF"
    sudo sed -i '/mesh_rssi_threshold/d' "$TARGET_CONF"
    sudo sed -i '/mesh_basic_rates/d' "$TARGET_CONF"
    sudo sed -i '/mesh_max_inactivity/d' "$TARGET_CONF"
    sudo sed -i '/ignore_old_scan_res/d' "$TARGET_CONF"
else
    log "WARNING: Config file not found at $TARGET_CONF"
fi

# Ensure previous instances are killed - BE GENTLE
if lsmod | grep -q "nrc"; then
    log "Driver already loaded."
else
    log "Initializing HaLow radio..."
    cd "$DRIVER_DIR/script"
    # Args: Type(4=Mesh), Security(0=Open), Country(US), MeshMode(1=MeshPoint)
    # Note: Freq and ID are now in the .conf file
    sudo python3 "$SCRIPT_PATH" 4 0 "$COUNTRY" 1 || error_exit "HaLow initialization failed"
fi

# 3b. Verify wlan1 state and Fallback to Manual Join if wpa_supplicant failed
log "Verifying wlan1 state..."
sleep 5
# Check if wlan1 is UP (RUNNING or carrier)
if ip link show wlan1 | grep -q "NO-CARRIER"; then
    log "WARNING: wlan1 is down (wpa_supplicant likely failed). Attempting manual 'iw' fallback..."
    
    # DO NOT killall wpa_supplicant, it kills wlan0 (SSH) too!
    # Only kill specific instance if it exists?
    # sudo pkill -f "wpa_supplicant.*wlan1" || true  <-- Even this is risky if the pattern matches generic.
    # Better to just proceed. The driver will error if busy, which is better than losing SSH.
    
    # 1. Set Mode (Try 'mesh', then 'mp', then 'ibss')
    log "Setting wlan1 to mesh mode..."
    sudo ip link set wlan1 down
    
    if sudo iw dev wlan1 set type mesh 2>/dev/null; then
        log "Mode set to 'mesh'"
    elif sudo iw dev wlan1 set type mp 2>/dev/null; then
        log "Mode set to 'mp'"
    elif sudo iw dev wlan1 set type ibss 2>/dev/null; then
        log "Mode set to 'ibss' (Ad-Hoc Fallback)"
    else
        log "ERROR: Failed to set mesh/mp/ibss mode. Driver capabilities might be limited."
    fi
    
    sudo ip link set wlan1 up
    
    # 2. Join Mesh
    log "Joining mesh $MESH_ID on freq $FREQ MHz..."
    if ip link show wlan1 | grep -q "ibss"; then
        sudo iw dev wlan1 ibss join "$MESH_ID" "$FREQ"
    else
        sudo iw dev wlan1 mesh join "$MESH_ID" freq "$FREQ"
    fi
    
    sleep 2
    if ip link show wlan1 | grep -q "NO-CARRIER"; then
         log "ERROR: Manual join also failed. Please check driver logs."
         # We continue anyway to see if batman can pick it up
    else
         log "Manual join successful!"
    fi
else
    log "wlan1 is up and running!"
fi

# 4. Start Batman-adv
log "Loading batman-adv module..."
sudo modprobe batman-adv || true

log "Adding wlan1 interface to batman-adv..."
# Wait for wlan1 to appear
sleep 2
if ! ip link show wlan1 >/dev/null 2>&1; then
    error_exit "wlan1 interface not found!"
fi

# CRITICAL: Disable HW Mesh Forwarding so Batman can take over
log "Disabling HW Mesh Forwarding..."
sudo iw dev wlan1 set mesh_param mesh_fwding 0 || log "WARNING: Failed to set mesh_fwding (might be already 0)"

sudo batctl if add wlan1 || log "WARNING: Failed to add wlan1 to batman-adv (already added?)"

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
log "You can now test connectivity on 10.0.0.1"
