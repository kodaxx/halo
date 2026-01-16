#!/bin/bash
# prepare_sd.sh
# Developer Tool: Configures a fresh SD card for Headless Boot.
# Copies cmdline.txt, userconf.txt, ssh, and generates wpa_supplicant.conf.

set -e

# Default Mac boot volume
BOOT_VOL="/Volumes/bootfs"

echo "========================================="
echo "   Halo SD Card Prep Tool"
echo "========================================="

# 1. Locate Boot Volume
if [ ! -d "$BOOT_VOL" ]; then
    echo "Default boot volume ($BOOT_VOL) not found."
    read -p "Enter path to SD Card boot volume: " BOOT_VOL
    if [ ! -d "$BOOT_VOL" ]; then
        echo "Error: Directory $BOOT_VOL does not exist."
        exit 1
    fi
fi
echo "Target: $BOOT_VOL"

# 2. Copy Base Configs (SSH, User, Cmdline)
SRC_DIR="$(dirname "$0")/pi_files"
echo "Copying base configs from $SRC_DIR..."
cp "$SRC_DIR/ssh" "$BOOT_VOL/"
cp "$SRC_DIR/userconf.txt" "$BOOT_VOL/"
# Optional: cmdline.txt usually needs to be handled carefully to not break boot, 
# but if we have a known good one:
if [ -f "$SRC_DIR/cmdline.txt" ]; then
   cp "$SRC_DIR/cmdline.txt" "$BOOT_VOL/"
fi

# 3. Interactive WiFi Setup
echo ""
echo "--- WiFi Setup ---"
read -p "Enter WiFi SSID: " SSID
read -s -p "Enter WiFi Password: " PASS
echo ""
read -p "Country Code (default US): " COUNTRY
COUNTRY=${COUNTRY:-US}

echo "Generating wpa_supplicant.conf..."
cat > "$BOOT_VOL/wpa_supplicant.conf" <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$COUNTRY

network={
    ssid="$SSID"
    psk="$PASS"
    key_mgmt=WPA-PSK
}
EOF

echo "========================================="
echo "   Success! SD Card is ready."
echo "   1. Eject SD Card."
echo "   2. Insert into Pi and power on."
echo "   3. Wait for it to connect to '$SSID'."
echo "========================================="
