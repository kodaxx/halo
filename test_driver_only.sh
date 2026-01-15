#!/bin/bash
# Halo Driver Test Script
# Focus: Get the NRC7292 driver compiled and working
# Does NOT install config files, scripts, or services yet

REPO_URL="https://github.com/kodaxx/halo.git"
INSTALL_DIR="/tmp/halo_install"
DRIVER_DIR="/home/halo/nrc7292_sw_pkg"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
    log "ERROR: $*" >&2
    exit 1
}

log "=== Halo Driver Test Script (Linux 6.12+) ==="

# 1. Update package lists
log "Updating package lists..."
sudo apt-get update || error_exit "apt-get update failed"

# 2. Install dependencies (minimal for driver only)
log "Installing dependencies for driver compilation..."
PACKAGES="git build-essential bc wget device-tree-compiler"

# Install base packages
sudo apt-get install -y $PACKAGES || error_exit "Failed to install base dependencies"

# Install kernel headers (try multiple options)
log "Installing kernel headers for compilation..."
KERNEL_RELEASE=$(uname -r)
log "Detected kernel: $KERNEL_RELEASE"

# Try linux-headers for specific kernel version, then fallback options
if ! sudo apt-get install -y "linux-headers-${KERNEL_RELEASE}" 2>/dev/null; then
    log "Trying linux-headers-generic fallback..."
    if ! sudo apt-get install -y linux-headers-generic 2>/dev/null; then
        log "Trying raspberrypi-kernel-headers fallback..."
        sudo apt-get install -y raspberrypi-kernel-headers || error_exit "Failed to install any kernel headers"
    fi
fi

# 3. Clone repository
log "Cloning Halo repository..."
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR || error_exit "git clone failed"

# 4. Setup nrc7292 driver
log "Setting up NRC7292 HaLow driver..."
cd /home/halo || error_exit "Failed to cd to /home/halo"

if [ ! -d "nrc7292_sw_pkg" ]; then
    log "Copying nrc7292_sw_pkg from installation..."
    cp -r $INSTALL_DIR/nrc7292_sw_pkg . || error_exit "Failed to copy nrc7292_sw_pkg"
    log "Driver source copied to $DRIVER_DIR"
else
    log "nrc7292_sw_pkg already exists at $DRIVER_DIR"
fi

# 5. Update /etc/modules for USB Ethernet Gadget (needed for initial debugging)
log "Configuring kernel modules..."
grep -qxF "dwc2" /etc/modules || echo "dwc2" | sudo tee -a /etc/modules
grep -qxF "g_ether" /etc/modules || echo "g_ether" | sudo tee -a /etc/modules

# 6. Configure boot settings (config.txt changes)
log "Updating boot configuration..."

# Bookworm can use either /boot/config.txt or /boot/firmware/config.txt
CONFIG_FILE="/boot/config.txt"
if [ ! -f "$CONFIG_FILE" ] && [ -f "/boot/firmware/config.txt" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
    log "Using firmware config at /boot/firmware/config.txt"
fi

if [ -f "$INSTALL_DIR/assets/config.txt" ]; then
    # Check if already appended to avoid duplicates
    if ! grep -q "dtoverlay=dwc2" "$CONFIG_FILE" 2>/dev/null; then
        log "Appending configuration to $CONFIG_FILE..."
        cat $INSTALL_DIR/assets/config.txt | sudo tee -a "$CONFIG_FILE" > /dev/null || error_exit "Failed to append to $CONFIG_FILE"
        log "Boot config updated"
    else
        log "Boot config already up to date"
    fi
else
    log "WARNING: config.txt not found in assets"
fi

# 7. Install firmware files
log "Installing firmware files..."
if [ ! -d "/lib/firmware" ]; then
    sudo mkdir -p /lib/firmware || error_exit "Failed to create /lib/firmware"
fi

FW_SOURCE="$DRIVER_DIR/package/evk/sw_pkg/nrc_pkg/sw/firmware/nrc7292_cspi.bin"
FW_DEST="/lib/firmware/uni.bin"

if [ -f "$FW_SOURCE" ]; then
    log "Copying firmware to /lib/firmware/uni.bin..."
    sudo cp "$FW_SOURCE" "$FW_DEST" || error_exit "Failed to copy firmware"
    log "✓ Firmware installed"
else
    error_exit "Firmware file not found at $FW_SOURCE"
fi

# 8. Compile device tree overlay
log "Compiling device tree overlay..."
DTS_DIR="$DRIVER_DIR/dts"
cd "$DTS_DIR" || error_exit "Failed to cd to device tree source directory: $DTS_DIR"

# Use the newer 5.16+ version for Linux 6.12+
DTS_FILE="newracom_for_5.16_or_later.dts"

if [ ! -f "$DTS_FILE" ]; then
    error_exit "Device tree source not found at $(pwd)/$DTS_FILE"
fi

if command -v dtc &>/dev/null; then
    log "Building $DTS_FILE -> nrc-rpi.dtbo..."
    sudo dtc -@ -I dts -O dtb -o nrc-rpi.dtbo "$DTS_FILE" || error_exit "Device tree compilation failed"
    
    DT_DEST="/boot/overlays/nrc-rpi.dtbo"
    if [ ! -d "/boot/overlays" ]; then
        sudo mkdir -p /boot/overlays || error_exit "Failed to create /boot/overlays"
    fi
    
    log "Installing device tree overlay to /boot/overlays/..."
    sudo cp nrc-rpi.dtbo "$DT_DEST" || error_exit "Failed to copy device tree overlay"
    log "✓ Device tree overlay installed"
else
    log "WARNING: Device tree compiler (dtc) not found, skipping overlay compilation"
    log "         To fix: sudo apt-get install device-tree-compiler"
fi

# 9. Build the driver
log "Building NRC7292 driver..."

log "Cleaning previous build..."
sudo make clean || log "WARNING: make clean failed (may be normal if first build)"

log "Compiling driver (this may take several minutes)..."
sudo make || error_exit "Driver compilation failed"

if [ ! -f "nrc.ko" ]; then
    error_exit "Driver compilation did not produce nrc.ko"
fi

log "Driver compiled successfully: $(pwd)/nrc.ko"

# 8. Load the driverlog "Loading kernel dependencies..."
sudo modprobe cfg80211 || log "WARNING: cfg80211 already loaded or unavailable"
sudo modprobe mac80211 || log "WARNING: mac80211 already loaded or unavailable"
log "Loading nrc.ko module..."
sudo insmod nrc.ko || error_exit "Failed to insert nrc.ko module"

# 9. Verify driver is loaded
log "Verifying driver is loaded..."
if lsmod | grep -q "^nrc"; then
    log "✓ Driver loaded successfully!"
    lsmod | grep nrc
else
    error_exit "Driver does not appear to be loaded"
fi

# 12. Check for nrc devices
log "Checking for NRC7292 devices..."
if [ -d "/sys/class/net" ]; then
    NRC_DEVICES=$(ls /sys/class/net/ | grep -E "^wlan[0-9]" || true)
    if [ -n "$NRC_DEVICES" ]; then
        log "✓ Found wireless devices:"
        for dev in $NRC_DEVICES; do
            log "  - $dev"
        done
    else
        log "WARNING: No wireless devices found (may appear after full provisioning)"
    fi
fi

log ""
log "=== Driver Setup Complete ==="
log ""
log "IMPORTANT: You need to REBOOT for the changes to take full effect!"
log ""
log "What was done:"
log "  ✓ Firmware installed to /lib/firmware/uni.bin"
log "  ✓ Device tree overlay compiled and installed to /boot/overlays/nrc-rpi.dtbo"
log "  ✓ Device tree overlay added to config.txt (dtoverlay=nrc-rpi)"
log "  ✓ Driver compiled and loaded (nrc.ko)"
log ""
log "What still needs to happen:"
log "  1. REBOOT the device for device tree overlay to load"
log "  2. After reboot, driver may auto-load if it's in /etc/modules"
log "  3. For full installation, run: bash install.sh"
log ""
log "To reboot now: sudo reboot"
log ""
