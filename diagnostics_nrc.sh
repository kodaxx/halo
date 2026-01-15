#!/bin/bash
# Quick NRC7292 Hardware Diagnostics

echo "=== NRC7292 Hardware Diagnostics ==="
echo ""

echo "1. Firmware file check:"
if [ -f "/lib/firmware/uni.bin" ]; then
    SIZE=$(stat -c%s "/lib/firmware/uni.bin" 2>/dev/null || stat -f%z "/lib/firmware/uni.bin" 2>/dev/null)
    echo "   ✓ /lib/firmware/uni.bin exists (size: $SIZE bytes)"
else
    echo "   ✗ /lib/firmware/uni.bin NOT FOUND"
    echo "     This is required for the driver to probe the device!"
    echo ""
    echo "   Creating link from /lib/firmware/uni.bin..."
    DRIVER_DIR="/home/halo/nrc7292_sw_pkg"
    FW_SOURCE="$DRIVER_DIR/package/evk/sw_pkg/nrc_pkg/sw/firmware/nrc7292_cspi.bin"
    if [ -f "$FW_SOURCE" ]; then
        echo "   Found source at: $FW_SOURCE"
        sudo mkdir -p /lib/firmware
        sudo cp "$FW_SOURCE" /lib/firmware/uni.bin
        echo "   ✓ Firmware copied to /lib/firmware/uni.bin"
    else
        echo "   Cannot find firmware source!"
    fi
fi

echo ""
echo "2. Device Tree Overlay check:"
if [ -f "/boot/overlays/nrc-rpi.dtbo" ]; then
    echo "   ✓ /boot/overlays/nrc-rpi.dtbo exists"
else
    echo "   ✗ /boot/overlays/nrc-rpi.dtbo NOT FOUND"
fi

echo ""
echo "3. Config.txt check:"
if grep -q "dtoverlay=nrc-rpi" /boot/config.txt 2>/dev/null; then
    echo "   ✓ dtoverlay=nrc-rpi found in /boot/config.txt"
elif grep -q "dtoverlay=nrc-rpi" /boot/firmware/config.txt 2>/dev/null; then
    echo "   ✓ dtoverlay=nrc-rpi found in /boot/firmware/config.txt"
else
    echo "   ✗ dtoverlay=nrc-rpi NOT in config.txt"
    echo "     Adding to /boot/config.txt..."
    CONFIG_FILE="/boot/config.txt"
    if [ ! -f "$CONFIG_FILE" ] && [ -f "/boot/firmware/config.txt" ]; then
        CONFIG_FILE="/boot/firmware/config.txt"
    fi
    if ! grep -q "dtoverlay=nrc-rpi" "$CONFIG_FILE"; then
        echo "" | sudo tee -a "$CONFIG_FILE" > /dev/null
        echo "dtoverlay=nrc-rpi" | sudo tee -a "$CONFIG_FILE" > /dev/null
        echo "   ✓ Added dtoverlay=nrc-rpi to $CONFIG_FILE"
        echo "   ⚠ REBOOT REQUIRED for overlay to load"
    fi
fi

echo ""
echo "4. NRC Device in Device Tree:"
if dtc -I fs /sys/firmware/devicetree/base -O dts 2>/dev/null | grep -q "nrc"; then
    echo "   ✓ NRC device found in device tree"
    echo ""
    echo "   Device node details:"
    dtc -I fs /sys/firmware/devicetree/base -O dts 2>/dev/null | grep -A 8 "nrc-cspi\|compatible.*nrc80211"
else
    echo "   ✗ NRC device NOT found in device tree"
fi

echo ""
echo "5. SPI Bus Devices:"
ls -la /sys/bus/spi/devices/ 2>/dev/null | grep -E "spi0\.[0-9]" || echo "   No SPI devices found"

echo ""
echo "6. Driver Module Status:"
if lsmod | grep -q "^nrc "; then
    echo "   ✓ nrc module is loaded"
else
    echo "   ✗ nrc module is NOT loaded"
fi

echo ""
echo "7. Wireless Interfaces:"
ip link show 2>/dev/null | grep -E "^[0-9]+: wlan" | awk '{print "   " $2}'

echo ""
echo "=== Summary ==="
echo "If firmware is missing, you need to run:"
echo "  sudo cp /home/halo/nrc7292_sw_pkg/package/evk/sw_pkg/nrc_pkg/sw/firmware/nrc7292_cspi.bin /lib/firmware/uni.bin"
echo ""
echo "If overlay didn't load, you need to:"
echo "  1. Add 'dtoverlay=nrc-rpi' to /boot/config.txt"
echo "  2. Reboot the device"
echo ""
