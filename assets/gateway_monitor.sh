#!/bin/bash
# Halo Universal Gateway Monitor
# Automatically detects Internet on usb0 (Laptop) or eth0 (Dongle) and shares it.

CONFIG_FILE="/boot/halo.json"
CURRENT_WAN=""

enable_gateway() {
    WAN_IFACE=$1
    if [ "$CURRENT_WAN" == "$WAN_IFACE" ]; then return; fi

    echo "[Monitor] Internet Detected on $WAN_IFACE! Promoting to Gateway..."
    batctl gw_mode server 100mbit/100mbit
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    iptables -t nat -F
    iptables -F
    iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE
    iptables -A FORWARD -i br0 -o $WAN_IFACE -j ACCEPT
    iptables -A FORWARD -i $WAN_IFACE -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    if ! ifconfig br0 | grep -q "10.0.0.1"; then
        ifconfig br0 10.0.0.1 netmask 255.255.255.0 up
    fi
    
    if ! pgrep -f "dnsmasq --interface=br0" > /dev/null; then
        dnsmasq --interface=br0 --dhcp-range=10.0.0.50,10.0.0.200,12h --dhcp-option=3,10.0.0.1
    fi
    CURRENT_WAN=$WAN_IFACE
}

disable_gateway() {
    if [ -n "$CURRENT_WAN" ]; then
        echo "[Monitor] Internet Lost. Demoting to Client..."
        batctl gw_mode client
        pkill -f "dnsmasq --interface=br0"
        iptables -t nat -F
        iptables -F
        avahi-autoipd -D br0
        CURRENT_WAN=""
    fi
}

echo "[Monitor] Starting Universal Hot-Swap Monitor..."

# Initial Fallback: Client Mode + Random IP
batctl gw_mode client
avahi-autoipd -D br0

while true; do
    GATEWAY_SETTING=$(grep -o '"gateway": "[^"]*' $CONFIG_FILE | grep -o '[^"]*$')
    CANDIDATES=$(ip -o link show up | awk -F': ' '{print $2}' | grep -E '^(eth|usb|enx)')
    FOUND_INTERNET=false

    if [ "$GATEWAY_SETTING" != "off" ]; then
        for IFACE in $CANDIDATES; do
            if ! ifconfig $IFACE | grep -q "inet "; then
                dhclient -v $IFACE > /dev/null 2>&1
            fi
            # Ping Google to verify actual internet
            if ping -I $IFACE -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; then
                enable_gateway $IFACE
                FOUND_INTERNET=true
                break
            fi
        done
    fi

    if [ "$FOUND_INTERNET" = false ]; then
        # If we were a gateway, stop. If we weren't, verify we are in client mode.
        disable_gateway
        # Optional: Add logic here to enable Client-Side DHCP (dhclient br0)
        # if you want to pull an IP from ANOTHER gateway in the mesh.
    fi
    sleep 10
done