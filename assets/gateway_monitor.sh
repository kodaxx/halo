#!/bin/bash
# Halo Universal Gateway Monitor (Linux 6.12+ optimized)
# 
# Automatically detects Internet on usb0 (Laptop) or eth0 (Dongle) and shares it.
# 
# Requires:
# - Linux 6.12+
# - iproute2 (ip command)
# - batman-adv kernel module (batctl)
# - dnsmasq, dhclient, iptables-nft
# - avahi-daemon (optional, for zeroconf)

set -e

CONFIG_FILE="/boot/halo.json"
CURRENT_WAN=""
LOG_TAG="[GatewayMonitor]"

# Logging helper
log() {
    echo "$LOG_TAG $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Get IP address from interface using ip command (modern, Linux 6.12+)
get_interface_ip() {
    local if_name=$1
    ip -o -4 addr show "$if_name" 2>/dev/null | awk '{print $4; exit}' | cut -d'/' -f1
}

# Set IP address on interface using ip command (modern, Linux 6.12+)
set_interface_ip() {
    local if_name=$1
    local ip_addr=$2
    
    log "Setting IP $ip_addr on $if_name using ip command"
    sudo ip addr add "$ip_addr/24" dev "$if_name" 2>/dev/null || true
    sudo ip link set "$if_name" up
}

# Check if interface has an IP address
interface_has_ip() {
    local if_name=$1
    local ip=$(get_interface_ip "$if_name")
    [ -n "$ip" ]
}

# Get list of active network interfaces matching pattern
get_active_interfaces() {
    local pattern=$1
    ip -o link show up | awk -F': ' '{print $2}' | grep -E "$pattern" || true
}

# Enable gateway mode (Linux 6.12+ with iptables-nft)
enable_gateway() {
    local WAN_IFACE=$1
    
    if [ "$CURRENT_WAN" == "$WAN_IFACE" ]; then
        return  # Already a gateway on this interface
    fi

    log "Internet detected on $WAN_IFACE! Promoting to gateway mode..."
    
    # Set batman mode to server
    sudo batctl gw_mode server 100mbit/100mbit || log "WARNING: Failed to set batman server mode"
    
    # Enable IP forwarding
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    
    # Setup NAT using iptables-nft (Linux 6.12+ standard)
    log "Configuring firewall rules with iptables-nft..."
    sudo iptables-nft -t nat -F || true
    sudo iptables-nft -F || true
    sudo iptables-nft -t nat -A POSTROUTING -o "$WAN_IFACE" -j MASQUERADE || log "WARNING: MASQUERADE rule failed"
    sudo iptables-nft -A FORWARD -i br0 -o "$WAN_IFACE" -j ACCEPT || true
    sudo iptables-nft -A FORWARD -i "$WAN_IFACE" -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT || true
    
    # Setup DHCP on br0
    if ! get_interface_ip br0 | grep -q "^10.0.0"; then
        log "Configuring DHCP on br0 (10.0.0.1)..."
        set_interface_ip br0 "10.0.0.1"
    fi
    
    # Start dnsmasq if not already running
    if ! pgrep -f "dnsmasq.*--interface=br0" > /dev/null; then
        log "Starting dnsmasq on br0..."
        sudo dnsmasq --interface=br0 --dhcp-range=10.0.0.50,10.0.0.200,12h --dhcp-option=3,10.0.0.1 || log "WARNING: Failed to start dnsmasq"
    else
        log "dnsmasq already running on br0"
    fi
    
    CURRENT_WAN=$WAN_IFACE
    log "Gateway mode enabled on $WAN_IFACE"
}

# Disable gateway mode (Linux 6.12+ with iptables-nft)
disable_gateway() {
    if [ -z "$CURRENT_WAN" ]; then
        return  # Not currently a gateway
    fi

    log "Internet lost on $CURRENT_WAN. Demoting to client mode..."
    
    # Set batman mode to client
    sudo batctl gw_mode client || log "WARNING: Failed to set batman client mode"
    
    # Stop dnsmasq
    sudo pkill -f "dnsmasq.*--interface=br0" || log "dnsmasq not running"
    
    # Clear firewall rules using iptables-nft
    sudo iptables-nft -t nat -F || true
    sudo iptables-nft -F || true
    
    # Clear avahi autoip
    if command -v avahi-autoipd &>/dev/null; then
        sudo avahi-autoipd -D br0 || log "avahi-autoipd not running"
    fi
    
    CURRENT_WAN=""
    log "Client mode enabled"
}

log "=== Starting Universal Hot-Swap Monitor ==="

# Initial Fallback: Client Mode + Random IP
log "Setting initial client mode..."
sudo batctl gw_mode client || log "WARNING: Failed to set initial batman mode"

if command -v avahi-autoipd &>/dev/null; then
    sudo avahi-autoipd -D br0 || log "avahi-autoipd not available"
fi

# Main monitoring loop
while true; do
    GATEWAY_SETTING=$(grep -o '"gateway": "[^"]*' "$CONFIG_FILE" 2>/dev/null | grep -o '[^"]*$' || echo "auto")
    
    # Get list of potential WAN interfaces
    CANDIDATES=$(get_active_interfaces '^(eth|usb|enx)')
    FOUND_INTERNET=false

    if [ "$GATEWAY_SETTING" != "off" ]; then
        for IFACE in $CANDIDATES; do
            log "Checking for internet on $IFACE..."
            
            # Try to get DHCP if interface doesn't have IP
            if ! interface_has_ip "$IFACE"; then
                log "No IP on $IFACE, attempting DHCP..."
                sudo dhclient "$IFACE" > /dev/null 2>&1 || log "dhclient failed for $IFACE"
                sleep 2  # Wait for DHCP
            fi
            
            # Verify actual internet connectivity
            if ping -I "$IFACE" -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; then
                log "Internet confirmed on $IFACE!"
                enable_gateway "$IFACE"
                FOUND_INTERNET=true
                break
            fi
        done
    else
        log "Gateway mode disabled in config (gateway=off)"
    fi

    if [ "$FOUND_INTERNET" = false ]; then
        # If we were a gateway, stop. If not, ensure we're in client mode.
        if [ -n "$CURRENT_WAN" ]; then
            disable_gateway
        fi
        # Optional: Enable client-side DHCP to pull IP from another gateway
        # log "Attempting to get DHCP from mesh gateway..."
        # sudo dhclient br0 > /dev/null 2>&1 || log "Could not get DHCP from mesh"
    fi
    
    sleep 10
done
