#!/bin/bash
# Fix conflicting overlays and missing parameters in config.txt

CONFIG_FILE="/boot/firmware/config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/boot/config.txt"
fi

echo "Fixing config file: $CONFIG_FILE"

# Backup first
sudo cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"

# 1. Remove old/conflicting overlay entries
sudo sed -i '/dtoverlay=nrc7292/d' "$CONFIG_FILE"

# 2. Ensure disable-spidev is present (crucial for SPI driver)
if ! grep -q "dtoverlay=disable-spidev" "$CONFIG_FILE"; then
    echo "Adding dtoverlay=disable-spidev..."
    # Insert it before nrc-rpi if possible, or just append
    if grep -q "dtoverlay=nrc-rpi" "$CONFIG_FILE"; then
        sudo sed -i '/dtoverlay=nrc-rpi/i dtoverlay=disable-spidev' "$CONFIG_FILE"
    else
        echo "dtoverlay=disable-spidev" | sudo tee -a "$CONFIG_FILE"
    fi
fi

# 3. Ensure dtparam=spi=on is ON (uncommented)
if grep -q "#dtparam=spi=on" "$CONFIG_FILE"; then
    echo "Enabling SPI bus..."
    sudo sed -i 's/#dtparam=spi=on/dtparam=spi=on/' "$CONFIG_FILE"
elif ! grep -q "dtparam=spi=on" "$CONFIG_FILE"; then
    echo "dtparam=spi=on" | sudo tee -a "$CONFIG_FILE"
fi

echo "Done. Please reboot."
