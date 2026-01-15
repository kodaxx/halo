#!/bin/bash
# Force NRC7292 driver binding to SPI device

echo "=== Forcing NRC7292 Driver Binding ==="
echo ""

# Check which SPI device is the NRC7292
echo "Checking SPI devices for NRC7292..."

for spi_dev in /sys/bus/spi/devices/spi0.*; do
    if [ -d "$spi_dev" ]; then
        DEV_NAME=$(basename "$spi_dev")
        DRIVER=$([ -L "$spi_dev/driver" ] && readlink -f "$spi_dev/driver" | xargs basename || echo "none")
        echo "  $DEV_NAME: driver=$DRIVER"
        
        # Check the device tree name
        if [ -f "$spi_dev/of_node/compatible" ]; then
            COMPAT=$(cat "$spi_dev/of_node/compatible" 2>/dev/null | head -c 30)
            echo "    compatible: $COMPAT"
            
            # If this is the NRC device and not bound, bind it
            if grep -q "nrc80211" "$spi_dev/of_node/compatible" 2>/dev/null; then
                echo "    ✓ Found NRC7292 at $DEV_NAME"
                if [ "$DRIVER" = "none" ]; then
                    echo "    Binding nrc80211 driver..."
                    echo "nrc80211" | sudo tee "$spi_dev/driver_override" > /dev/null 2>&1
                    echo "$DEV_NAME" | sudo tee /sys/bus/spi/drivers/nrc80211/bind > /dev/null 2>&1 || echo "    (bind attempt completed)"
                else
                    echo "    Already bound to: $DRIVER"
                fi
            fi
        fi
    fi
done

echo ""
echo "Checking if NRC interface now appears..."
sleep 2

# Check for wireless interfaces
if command -v ip &>/dev/null; then
    echo "Wireless interfaces:"
    ip link show 2>/dev/null | grep -E "^[0-9]+: wlan" | while read line; do
        echo "  $line"
    done
fi

echo ""
echo "Full SPI device status:"
ls -la /sys/bus/spi/devices/ | grep spi0

echo ""
echo "Driver module check:"
lsmod | grep nrc

echo ""
echo "Done!"
