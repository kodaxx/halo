#!/bin/bash
# Compile and install fixed overlay

echo "Downloading nrc_fixed.dts..."
wget -q https://raw.githubusercontent.com/kodaxx/halo/main/nrc_fixed.dts -O nrc_fixed.dts || exit 1

echo "Compiling nrc_fixed.dts..."
dtc -@ -I dts -O dtb -o nrc-fixed.dtbo nrc_fixed.dts || exit 1

echo "Installing to /boot/overlays..."
sudo cp nrc-fixed.dtbo /boot/overlays/
sudo cp nrc-fixed.dtbo /boot/firmware/overlays/ 2>/dev/null

echo "Updating config.txt..."
CONFIG="/boot/firmware/config.txt"
[ ! -f "$CONFIG" ] && CONFIG="/boot/config.txt"

# Remove old overlay
sudo sed -i '/dtoverlay=nrc-rpi/d' "$CONFIG"
# Remove any existing nrc-fixed
sudo sed -i '/dtoverlay=nrc-fixed/d' "$CONFIG"

# Add new overlay
echo "dtoverlay=nrc-fixed" | sudo tee -a "$CONFIG"

echo "Done. Rebooting..."
sudo reboot
