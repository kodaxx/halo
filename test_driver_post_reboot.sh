#!/bin/bash
# Halo Driver Post-Reboot Test Script
# Run this AFTER the Pi has rebooted from running test_driver_only.sh
# This script loads the compiled driver and verifies it works

DRIVER_DIR="/home/halo/nrc7292_sw_pkg"
DRIVER_KO="$DRIVER_DIR/package/src/nrc/nrc.ko"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
    log "ERROR: $*" >&2
    exit 1
}

log "=== Halo Driver Post-Reboot Test ==="
log ""

# 1. Check if device tree overlay was loaded
log "Checking device tree overlay..."
if dtc -I fs /sys/firmware/devicetree/base -O dts 2>/dev/null | grep -q "nrc"; then
    log "✓ Device tree overlay (nrc-rpi) appears to be loaded in device tree"
else
    log "⚠ Device tree overlay NOT found in loaded device tree"
    log "   This is the likely issue - overlay didn't load!"
    log "   Check: dtc -I fs /sys/firmware/devicetree/base -O dts | grep nrc"
fi

# Check firmware file
log "Checking firmware files..."
if [ -f "/lib/firmware/uni.bin" ]; then
    FW_SIZE=$(stat -f%z "/lib/firmware/uni.bin" 2>/dev/null || stat -c%s "/lib/firmware/uni.bin" 2>/dev/null || echo "unknown")
    log "✓ Firmware file found: /lib/firmware/uni.bin (size: $FW_SIZE bytes)"
else
    log "⚠ Firmware file NOT found at /lib/firmware/uni.bin"
    log "   Driver may fail to probe without firmware!"
fi

# Check device tree overlay file
log "Checking device tree overlay file..."
if [ -f "/boot/overlays/nrc-rpi.dtbo" ]; then
    log "✓ Device tree overlay file found: /boot/overlays/nrc-rpi.dtbo"
else
    log "⚠ Device tree overlay file NOT found at /boot/overlays/nrc-rpi.dtbo"
fi

# 2. Check if driver file exists
if [ ! -f "$DRIVER_KO" ]; then
    error_exit "Driver file not found at $DRIVER_KO"
fi
log "✓ Driver file found"

# 3. Load kernel dependencies (cfg80211 and mac80211)
log "Loading wireless kernel modules..."
sudo modprobe cfg80211 || log "WARNING: cfg80211 may already be loaded"
sudo modprobe mac80211 || log "WARNING: mac80211 may already be loaded"
log "✓ Wireless modules loaded"

# 4. Check if driver is already loaded (from previous reboot)
if lsmod | grep -q "^nrc "; then
    log "⚠ Driver already loaded, unloading first..."
    sudo rmmod nrc || log "WARNING: Could not unload driver"
    sleep 1
fi

# 5. Load the driver
log "Loading kernel dependencies (cfg80211, mac80211)..."
sudo modprobe cfg80211 || log "WARNING: cfg80211 already loaded or unavailable"
sudo modprobe mac80211 || log "WARNING: mac80211 already loaded or unavailable"

log "Loading nrc.ko driver..."
# Note: The overlay must be loaded for the driver to probe the device
# The overlay creates the SPI device node that the driver needs
sudo insmod "$DRIVER_KO" || error_exit "Failed to load driver"
sleep 2

log "✓ Driver loaded successfully"
log "Waiting for driver to probe NRC7292 device (3 seconds)..."
sleep 3

# 6. Verify driver is loaded
log "Verifying driver module..."
if lsmod | grep -q "^nrc "; then
    log "✓ Driver module confirmed loaded:"
    lsmod | grep nrc
else
    error_exit "Driver module not found in lsmod output"
fi

# 7. Check driver messages in dmesg
log ""
log "Driver and device tree messages from dmesg:"
dmesg | tail -30 | grep -E "nrc|NRC|nrc-rpi|dtb|overlay" || log "(No relevant messages found)"

# 8. Check for wireless devices
log ""
log "Checking for NRC7292 wireless devices..."
DEVICES=$(ip link show | grep -E "^[0-9]+: wlan" | awk '{print $2}' | sed 's/:$//')

if [ -n "$DEVICES" ]; then
    log "✓ Found wireless devices:"
    for dev in $DEVICES; do
        log "  - $dev"
        ip link show "$dev" 2>/dev/null | grep "state" || true
    done
else
    log "⚠ No wireless devices detected yet"
    log "  (May appear after more complete provisioning)"
fi

# 9. Check sysfs for NRC device
log ""
log "Checking /sys for NRC7292 driver and SPI device..."
if [ -d "/sys/class/net" ]; then
    NRC_SYS=$(ls /sys/class/net/ 2>/dev/null | grep -E "^wlan" || true)
    if [ -n "$NRC_SYS" ]; then
        log "✓ Wireless devices in /sys/class/net:"
        for dev in $NRC_SYS; do
            log "  - $dev"
        done
    else
        log "⚠ No wireless devices in /sys/class/net"
    fi
fi

# Check for SPI devices
log ""
log "Checking SPI devices..."
if [ -d "/sys/bus/spi/devices" ]; then
    SPI_DEVS=$(ls /sys/bus/spi/devices/ 2>/dev/null || echo "none")
    if [ "$SPI_DEVS" != "none" ]; then
        log "SPI devices found:"
        for dev in $SPI_DEVS; do
            log "  - $dev"
            if [ -f "/sys/bus/spi/devices/$dev/driver" ]; then
                DRIVER=$(readlink "/sys/bus/spi/devices/$dev/driver" | xargs basename)
                log "    Driver: $DRIVER"
            fi
        done
    else
        log "⚠ No SPI devices detected"
    fi
fi

# Check device tree
log ""
log "Detailed device tree check..."
if command -v dtc &>/dev/null; then
    log "Looking for nrc device node in device tree..."
    NRC_NODE=$(dtc -I fs /sys/firmware/devicetree/base -O dts 2>/dev/null | grep -A 10 "nrc-cspi\|nrc@")
    if [ -n "$NRC_NODE" ]; then
        log "✓ Found NRC device node:"
        echo "$NRC_NODE" | head -15
    else
        log "⚠ NRC device node NOT found in device tree"
        log "   The overlay may not have created the device node properly"
        log ""
        log "SPI0 node info:"
        dtc -I fs /sys/firmware/devicetree/base -O dts 2>/dev/null | grep -A 15 "spi@7e204000" | head -20
    fi
else
    log "Device tree compiler (dtc) not available"
fi

# 10. Check module parameters (if available)
log ""
log "Driver module information:"
if [ -f "/sys/module/nrc/parameters/fw_name" ]; then
    FW_NAME=$(cat /sys/module/nrc/parameters/fw_name 2>/dev/null || echo "unknown")
    log "  Firmware: $FW_NAME"
fi

if [ -f "/sys/module/nrc/parameters/hifport" ]; then
    HIF_PORT=$(cat /sys/module/nrc/parameters/hifport 2>/dev/null || echo "unknown")
    log "  HIF Port: $HIF_PORT"
fi

# 11. Summary
log ""
log "=== Post-Reboot Test Complete ==="
log ""
log "Status Summary:"
log "  ✓ Wireless modules loaded"
log "  ✓ Driver loaded and running"
log "  $([ -n "$DEVICES" ] && echo "✓" || echo "⚠") Wireless devices available"
log ""
log "Next steps:"
log "  1. Check full driver output: dmesg | grep -i nrc"
log "  2. Test wireless with: iw dev"
log "  3. For full installation: bash install.sh"
log "  4. To unload driver: sudo rmmod nrc"
log ""
