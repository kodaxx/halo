#!/bin/bash
# test_build.sh
# Developer Tool: Verifies the base image build state.
# Run this AFTER build_image.sh and BEFORE capture_image.sh.
# It manually loads the driver to verify hardware/software integration.

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[PASS] ${NC}$1"; }
fail() { echo -e "${RED}[FAIL] ${NC}$1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN] ${NC}$1"; }

echo "=== Halo Base Image Verification ==="

# 0. User/Path Detection
cd "$(dirname "$0")/.."
REPO_DIR=$(pwd)
USER_NAME=$(stat -c '%U' "$REPO_DIR")
if [ "$USER_NAME" == "root" ]; then
    USER_NAME="${SUDO_USER:-root}"
fi
USER_HOME=$(eval echo "~$USER_NAME")
LOCAL_PKG_DIR="$USER_HOME/nrc_pkg"
DRIVER_PATH="$LOCAL_PKG_DIR/sw/driver/nrc.ko"

echo "Detected User: $USER_NAME"
echo "Driver Path:   $DRIVER_PATH"

# 1. Start Active Services (Mesh, Web, Monitor) for Verification
echo "Enabling and Starting Core Services for Testing..."
systemctl enable --now halo-mesh.service
systemctl enable --now halo-web.service
systemctl enable --now halo-monitor.service

# 2. Check Overlay
if grep -q "dtoverlay=nrc-rpi" /boot/config.txt; then
    pass "Overlay configured in /boot/config.txt"
else
    fail "Overlay MISSING from /boot/config.txt"
fi

# 3. Check & Test Driver Load
if lsmod | grep -q "nrc"; then
    pass "nrc.ko module is already loaded"
else
    echo "Module not loaded (Expected for disabled services). Attempting manual load..."
    if [ -f "$DRIVER_PATH" ]; then
        # Try loading with default params (US, Mesh)
        if sudo insmod "$DRIVER_PATH"; then
             pass "nrc.ko loaded successfully via insmod"
             sleep 3 # Wait for interface initialization
        else
             fail "nrc.ko FAILED to load"
        fi
    else
        fail "Driver file not found at $DRIVER_PATH"
    fi
fi

# 4. Check Interface wlan1
if ip link show wlan1 >/dev/null 2>&1; then
    pass "Interface wlan1 exists and is visible"
else
    fail "Interface wlan1 NOT FOUND (Driver loaded but interface missing)"
fi

# 5. Check Services (Should be installed but DISABLED)
echo "Checking Service States..."
declare -a services=("halo-mesh" "halo-web" "halo-monitor")
for svc in "${services[@]}"; do
    if systemctl list-unit-files | grep -q "$svc.service"; then
        # Check if enabled
        STATUS=$(systemctl is-enabled "$svc.service" 2>/dev/null || echo "unknown")
        if [ "$STATUS" == "disabled" ]; then
            pass "Service $svc is installed and DISABLED (Correct)"
        else
            warn "Service $svc is installed but status is '$STATUS' (Should be disabled for image)"
        fi
    else
         fail "Service $svc is MISSING entirely"
    fi
done

# 6. Check Firmware
if [ -f /lib/firmware/nrc7292_cspi.bin ] && [ -f /lib/firmware/bd.dat ]; then
    pass "Firmware files present in /lib/firmware"
else
    fail "Firmware files MISSING in /lib/firmware/"
fi

# 7. Check Dmesg for obvious errors
echo "Checking dmesg for nrc errors..."
if dmesg | grep -i "nrc" | grep -E "error|fail|crash|trace"; then
    warn "Found possible ERRORS in dmesg:"
    dmesg | grep -i "nrc" | grep -E "error|fail|crash|trace" | tail -n 5
    echo "..."
else
    pass "No obvious driver errors found in dmesg"
fi

# 8. Services state
# CRITICAL: We NEED to disable these after testing.
# If we enable them, the device boots as an AP (Mesh), preventing the user
# from connecting via wpa_supplicant to their home WiFi to run firstboot.sh.
echo "Disabling Services and Staging for Distribution..."
systemctl disable halo-mesh.service
systemctl disable halo-web.service
systemctl disable halo-monitor.service

echo "=== Verification Complete ==="
echo "   wlan1 is UP and ready."
echo "   Services are staged."
echo "   System is ready for capture."
echo ""
echo "You may want to run the prepare_for_release.sh script to clean up the system."
echo "This will remove the WiFi credentials, logs, and Bash history."
echo "You can run it like this: ./prepare_for_release.sh"
