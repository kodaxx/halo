#!/bin/bash
# Force NRC7292 driver binding to SPI device

echo "=== Forcing NRC7292 Driver Binding ==="
echo ""

# Find the NRC7292 device
NRC_DEVICE=""
for spi_dev in /sys/bus/spi/devices/spi0.*; do
    if [ -d "$spi_dev" ]; then
        if grep -q "newracom,nrc7292" "$spi_dev/of_node/compatible" 2>/dev/null; then
            NRC_DEVICE=$(basename "$spi_dev")
            echo "✓ Found NRC7292 at: $NRC_DEVICE"
            break
        fi
    fi
done

if [ -z "$NRC_DEVICE" ]; then
    echo "✗ Could not find NRC7292 device!"
    exit 1
fi

# Check if already bound
if [ -L "/sys/bus/spi/devices/$NRC_DEVICE/driver" ]; then
    CURRENT_DRIVER=$(readlink -f "/sys/bus/spi/devices/$NRC_DEVICE/driver" | xargs basename)
    if [ "$CURRENT_DRIVER" = "nrc80211" ]; then
        echo "✓ Already bound to nrc80211 driver"
    else
        echo "⚠ Bound to different driver: $CURRENT_DRIVER"
        echo "Unbinding first..."
        echo "$NRC_DEVICE" | sudo tee /sys/bus/spi/drivers/$CURRENT_DRIVER/unbind > /dev/null 2>&1
        sleep 1
    fi
else
    echo "⚠ Not bound to any driver yet"
fi

# Bind to nrc80211 driver
echo ""
echo "Binding nrc80211 driver to $NRC_DEVICE..."

# Method 1: Try driver_override (Linux 4.14+)
echo "nrc80211" | sudo tee /sys/bus/spi/devices/$NRC_DEVICE/driver_override > /dev/null 2>&1

# Method 2: Direct bind to the driver
echo "$NRC_DEVICE" | sudo tee /sys/bus/spi/drivers/nrc80211/bind > /dev/null 2>&1

sleep 2

# Verify binding
echo ""
echo "Verifying binding..."
if [ -L "/sys/bus/spi/devices/$NRC_DEVICE/driver" ]; then
    DRIVER=$(readlink -f "/sys/bus/spi/devices/$NRC_DEVICE/driver" | xargs basename)
    echo "✓ $NRC_DEVICE bound to: $DRIVER"
else
    echo "✗ Still not bound!"
fi

echo ""
echo "Wireless interfaces:"
ip link show 2>/dev/null | grep -E "^[0-9]+: wlan" | awk '{print "  " $0}'

echo ""
echo "Check dmesg for driver probe messages:"
dmesg | tail -5 | grep -i nrc || echo "  (No recent NRC messages)"
