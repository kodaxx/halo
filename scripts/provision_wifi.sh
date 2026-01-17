#!/bin/bash
# Halo Security Provisioning
# Generates unique, deterministic Wi-Fi credentials based on Hardware ID.

HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
# Check if we have already provisioned (Look for factory default)
if grep -q "Halo_SETUP" "$HOSTAPD_CONF"; then
    echo "Provisioning new Wi-Fi Credentials..."

    # 1. Get Unique Hardware IDs or Use Provided Args
    if [ -n "$1" ] && [ -n "$2" ]; then
        echo "Using provided credentials..."
        NEW_SSID="$1"
        NEW_PASS="$2"
    else
        echo "Generating unique credentials..."
        # Safer parsing for Serial (handles tabs/spaces correctly)
        CPU_SERIAL=$(grep "Serial" /proc/cpuinfo | awk -F': ' '{print $2}' | tr -d ' ' | tr -d '\t')
        
        # MAC Address (Unique to Wi-Fi Chip) - Used for SSID Suffix
        MAC_SUFFIX=$(cat /sys/class/net/wlan0/address | awk -F: '{print $5$6}' | tr '[:lower:]' '[:upper:]')
        
        # Ensure Serial is valid.
        if [ -z "$CPU_SERIAL" ] || [ ${#CPU_SERIAL} -lt 8 ]; then
             echo "WARNING: Failed to extract valid CPU Serial. Using fallback."
             CPU_SERIAL="halo_default_$MAC_SUFFIX"
        fi

        # 2. Define Credentials
        NEW_SSID="Halo_$MAC_SUFFIX"
        NEW_PASS="$CPU_SERIAL"
    fi

    # 3. Apply to Hostapd Config
    sed -i "s/ssid=Halo_SETUP/ssid=$NEW_SSID/" $HOSTAPD_CONF
    sed -i "s/wpa_passphrase=halo_default/wpa_passphrase=$NEW_PASS/" $HOSTAPD_CONF
    
    # Sync filesystem to ensure writes persist before reboot
    sync
    
    # 4. Save credentials to a text file
    echo "SSID: $NEW_SSID" > /boot/wifi_credentials.txt
    echo "PASS: $NEW_PASS" >> /boot/wifi_credentials.txt
    echo "QR_STRING: WIFI:S:$NEW_SSID;T:WPA;P:$NEW_PASS;H:true;;" >> /boot/wifi_credentials.txt
    echo "ADMIN: http://10.0.0.1" >> /boot/wifi_credentials.txt

    echo "Provisioning Complete. SSID: $NEW_SSID"
fi