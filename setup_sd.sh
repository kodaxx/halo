#!/bin/bash
# setup_sd.sh
# Runs on Mac. Injects WiFi credentials and SSH enable into a mounted Raspberry Pi SD card.

BOOT_VOL="/Volumes/bootfs"

# Check if volume exists (sometimes it's just /Volumes/boot)
if [ ! -d "$BOOT_VOL" ]; then
    BOOT_VOL="/Volumes/boot"
fi

if [ ! -d "$BOOT_VOL" ]; then
    echo "Error: SD Card boot volume not found at /Volumes/bootfs or /Volumes/boot."
    echo "Please insert the SD card or check the name."
    exit 1
fi

echo "Found Boot Volume at: $BOOT_VOL"

# 1. Enable SSH
echo "Enabling SSH..."
touch "$BOOT_VOL/ssh"

# 2. Inject WiFi Credentials
echo ""
echo "Enter your HOME WiFi Credentials (to connect to internet for install):"
read -p "SSID: " WIFI_SSID
read -s -p "Password: " WIFI_PASS
echo ""

echo "Creating wpa_supplicant.conf..."
cat > "$BOOT_VOL/wpa_supplicant.conf" <<EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PASS"
    key_mgmt=WPA-PSK
}
EOF

# 3. Inject Other Files (pi_files) if they exist
PI_FILES_DIR="./pi_files"
if [ -d "$PI_FILES_DIR" ]; then
    echo "Copying contents of pi_files to SD card (excluding images)..."
    # Use rsync to exclude huge image files and system junk
    rsync -av --exclude="*.img" --exclude="*.xz" --exclude=".DS_Store" "$PI_FILES_DIR/" "$BOOT_VOL/"
else
    echo "No pi_files directory found, skipping file injection."
fi

# 4. Optional: Enable USB Gadget Mode (Safety Net)
read -p "Enable USB Gadget Mode (Ethernet over USB) as backup? [y/N] " ENABLE_GADGET
if [[ "$ENABLE_GADGET" =~ ^[Yy]$ ]]; then
    echo "Enabling USB Gadget Mode..."
    
    # Edit config.txt
    if ! grep -q "dtoverlay=dwc2" "$BOOT_VOL/config.txt"; then
        echo "dtoverlay=dwc2" >> "$BOOT_VOL/config.txt"
    fi
    
    # Edit cmdline.txt (Must be single line)
    # Sed on mac is tricky, reading into variable first
    CMDLINE=$(cat "$BOOT_VOL/cmdline.txt")
    if [[ "$CMDLINE" != *"modules-load=dwc2,g_ether"* ]]; then
        # Insert after rootwait
        NEW_CMDLINE="${CMDLINE/rootwait/rootwait modules-load=dwc2,g_ether}"
        echo "$NEW_CMDLINE" > "$BOOT_VOL/cmdline.txt"
        echo "Updated cmdline.txt"
    fi
fi

echo ""
echo "✅ Setup Complete. Please safely eject the SD card."
