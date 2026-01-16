#!/bin/bash
# setup_evk_clean.sh
# Complete EVK Setup with LOCAL COMPILATION and ROBUST PATH FIXING.
# Handles: Driver Compilation, PATH patching, Start.py patching.

set -e # Exit on error

REPO_ROOT=$(pwd)
# Robust root detection
if [ -d "nrc7292_sw_pkg" ]; then
    REPO_ROOT=$(pwd)
elif [ -d "$HOME/halo/nrc7292_sw_pkg" ]; then
    REPO_ROOT="$HOME/halo"
    echo "Found existing repository at $REPO_ROOT"
else
    echo "Repo not found locally. Cloning kodaxx/halo to temp_repo..."
    git clone https://github.com/kodaxx/halo.git temp_repo
    if [ -d "temp_repo/nrc7292_sw_pkg" ]; then
        REPO_ROOT="$(pwd)/temp_repo"
    else
        echo "Error: Failed to clone repository."
        exit 1
    fi
fi

SRC_EVK="$REPO_ROOT/nrc7292_sw_pkg/package/evk/sw_pkg/nrc_pkg"
BINARY_DIR="$REPO_ROOT/nrc7292_sw_pkg/package/evk/binary"
DRIVER_SRC="$REPO_ROOT/nrc7292_sw_pkg/package/src/nrc"
LOCAL_PKG_DIR="$HOME/nrc_pkg"
CURRENT_USER=$(whoami)

echo "===  Setting up Clean EVK Environment in $LOCAL_PKG_DIR for user $CURRENT_USER ==="

# Install Kernel Headers (Required for compilation) and hostapd
echo "Installing Kernel Headers and Hostapd..."
sudo apt-get install -y raspberrypi-kernel-headers build-essential hostapd

# Unmask hostapd (it is often masked by default on RPi)
sudo systemctl unmask hostapd
sudo systemctl disable hostapd # We run it manually via script


# 1. Copy Generic EVK Package
if [ -d "$LOCAL_PKG_DIR" ]; then
    echo "Backing up existing nrc_pkg..."
    mv "$LOCAL_PKG_DIR" "$LOCAL_PKG_DIR.bak_$(date +%s)"
fi
cp -r "$SRC_EVK" "$LOCAL_PKG_DIR"

# 2. INSTALL DRIVER (Prebuilt or Compile)
echo "Checking for driver..."
if [ -f "$BINARY_DIR/nrc.ko" ]; then
    echo "Found prebuilt driver at $BINARY_DIR/nrc.ko. Using it..."
    mkdir -p "$LOCAL_PKG_DIR/sw/driver"
    cp "$BINARY_DIR/nrc.ko" "$LOCAL_PKG_DIR/sw/driver/nrc.ko"
    # Ensure it's also in evk/binary in the local pkg
    mkdir -p "$LOCAL_PKG_DIR/evk/binary"
    cp "$BINARY_DIR/nrc.ko" "$LOCAL_PKG_DIR/evk/binary/nrc.ko"
else
    echo "Prebuilt driver not found. Compiling Driver Locally..."
    if [ ! -d "$DRIVER_SRC" ]; then
        echo "ERROR: Driver source not found at $DRIVER_SRC"
        exit 1
    fi
    cd "$DRIVER_SRC"
    echo "Current Directory: $(pwd)"
    make clean
    if make; then
        echo "Driver Compiled Successfully."
        cp "nrc.ko" "$LOCAL_PKG_DIR/sw/driver/nrc.ko"
        # Also copy to evk/binary for consistency
        mkdir -p "$LOCAL_PKG_DIR/evk/binary"
        cp "nrc.ko" "$LOCAL_PKG_DIR/evk/binary/nrc.ko"
    else
        echo "ERROR: Driver compilation failed!"
        exit 1
    fi
fi

# 3. Install Firmware
echo "Installing Firmware..."
if [ -f "$BINARY_DIR/nrc7292_cspi.bin" ]; then
    # Ensure destination exists
    mkdir -p "$LOCAL_PKG_DIR/sw/firmware"
    
    # Copy firmware and BD data to where 'copy' script expects them
    cp "$BINARY_DIR/nrc7292_cspi.bin" "$LOCAL_PKG_DIR/sw/firmware/nrc7292_cspi.bin"
    cp "$BINARY_DIR/nrc7292_bd.dat" "$LOCAL_PKG_DIR/sw/firmware/nrc7292_bd.dat"
    # Create the default link just in case
    cp "$BINARY_DIR/nrc7292_cspi.bin" "$LOCAL_PKG_DIR/sw/firmware/uni_s1g.bin"
    
    # CRITICAL: Install to system /lib/firmware for loading
    echo "Installing to /lib/firmware..."
    sudo cp "$LOCAL_PKG_DIR/sw/firmware/"* /lib/firmware/
    # Driver looks for 'bd.dat' specifically in some versions
    sudo cp "$LOCAL_PKG_DIR/sw/firmware/nrc7292_bd.dat" /lib/firmware/bd.dat
    
    echo "Firmware installed to $LOCAL_PKG_DIR/sw/firmware and /lib/firmware"
else
    echo "Error: Firmware not found at $BINARY_DIR!"
    exit 1
fi

# 4. AGGRESSIVE PATH FIXING (Fix for /home/pi/ persistence)
echo "Patching ALL paths from /home/pi/ to $HOME/ ..."
# Use gre, find, and sed to replace /home/pi in ALL text files in the package
grep -rl "/home/pi/" "$LOCAL_PKG_DIR" | xargs sed -i "s|/home/pi/|$HOME/|g"

# 5. Fix Permissions
echo "Fixing permissions..."
find "$LOCAL_PKG_DIR" -type f \( -name "*.py" -o -name "*.sh" -o -name "copy" -o -name "cli_app" \) -exec chmod +x {} \;

# 6. Patch start.py (Network Safety & wlan1 usage)
START_PY="$LOCAL_PKG_DIR/script/start.py"
echo "Patching start.py for wlan1, network safety, and dependencies..."

# Inject modprobe mac80211 at the top of run_common or main
sed -i '/import sys/a import subprocess; subprocess.call(["sudo", "modprobe", "mac80211"])' "$START_PY"

# Disable wlan0 interference
sed -i '/wpa_cli disable wlan0/s/^/#/' "$START_PY"
# Disable killing wpa_supplicant
sed -i '/killall.*wpa_supplicant/s/^/#/' "$START_PY"
# Disable stopping DHCPCD
sed -i '/stopDHCPCD()/s/^/#/' "$START_PY"
# Disable stopping NAT
sed -i '/stopNAT()/s/^/#/' "$START_PY"

# NUCLEAR OPTION: Disable STARTING DHCPCD, NAT, and DNSMASQ
# Fix: Do not comment out function definitions (def ...), only calls
sed -i '/def /! s/startDHCPCD()/#startDHCPCD()/g' "$START_PY"
sed -i '/def /! s/startDNSMASQ()/#startDNSMASQ()/g' "$START_PY"
sed -i '/def /! s/startNAT()/#startNAT()/g' "$START_PY"

# Switch to wlan1
sed -i "s/run_ap('wlan0')/run_ap('wlan1')/g" "$START_PY"
sed -i "s/run_sta('wlan0')/run_sta('wlan1')/g" "$START_PY"
# Fix Mesh calls also defaulting to wlan0
sed -i "s/run_mpp('wlan0'/run_mpp('wlan1'/g" "$START_PY"
sed -i "s/run_mp('wlan0'/run_mp('wlan1'/g" "$START_PY"
sed -i "s/run_map('wlan0'/run_map('wlan1'/g" "$START_PY"

# CRITICAL FIX: Patch mesh.py (imported by start.py) which ALSO kills wpa_supplicant
# AND deletes our bridge (br0)
MESH_PY="$LOCAL_PKG_DIR/script/mesh.py"
echo "Patching mesh.py..."
sed -i '/killall.*wpa_supplicant/s/^/#/' "$MESH_PY"
# Prevent destroying br0
sed -i '/removeBridgeMeshAP/s/^/#/' "$MESH_PY"
# Also prevent it from messing with bat0/wlan0 blindly if we are using manual setup
sed -i '/batctl if del wlan0/s/^/#/' "$MESH_PY"

# Update: Manually set IP for wlan1 since we disabled dhcpcd service restart
sed -i 's/subprocess.call(\["sudo", "ifconfig", "wlan0", "up"\])/subprocess.call(["sudo", "ifconfig", "wlan1", "192.168.200.1", "up"])/g' "$START_PY"

# Fix hostapd configuration files

find "$LOCAL_PKG_DIR/script/conf" -name "*.conf" -print0 | xargs -0 sed -i "s/interface=wlan0/interface=wlan1/g"

# CRITICAL: Patch ip_config.sh to prevent it from hijacking wlan0
# ip_config.sh writes to dhcpcd.conf. We must ensure it writes 'interface wlan1'
IP_CONFIG="$LOCAL_PKG_DIR/script/conf/etc/ip_config.sh"
echo "Patching ip_config.sh to use wlan1..."
sed -i 's/interface wlan0/interface wlan1/g' "$IP_CONFIG"
sed -i 's/AP INTERFACE     : wlan0/AP INTERFACE     : wlan1/g' "$IP_CONFIG"
sed -i 's/STA INTERFACE    : wlan0/STA INTERFACE    : wlan1/g' "$IP_CONFIG"

# CRITICAL FIX: Prevent ip_config.sh from overwriting system dhcpcd.conf (which kills wlan0)
# We comment out the copy command
sed -i 's/sudo cp $DHCPCD_CONF_FILE \/etc\/dhcpcd.conf/#sudo cp $DHCPCD_CONF_FILE \/etc\/dhcpcd.conf/g' "$IP_CONFIG"

# Instead, we safely APPEND the wlan1 config to /etc/dhcpcd.conf if not present
echo "Safely configuring /etc/dhcpcd.conf for wlan1..."
if ! grep -q "interface wlan1" /etc/dhcpcd.conf; then
    echo "Appending wlan1 config to /etc/dhcpcd.conf"
    echo "" | sudo tee -a /etc/dhcpcd.conf
    echo "interface wlan1" | sudo tee -a /etc/dhcpcd.conf
    echo "static ip_address=192.168.200.1/24" | sudo tee -a /etc/dhcpcd.conf
    echo "nohook wpa_supplicant" | sudo tee -a /etc/dhcpcd.conf
fi

# 7. Fix hostname resolution

if ! grep -q "127.0.0.1 $(hostname)" /etc/hosts; then
    echo "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts
fi

echo "=== Setup Complete ==="
echo "Driver compiled and installed."
echo "Firmware copied to /lib/firmware/bd.dat."
echo "To run AP mode: sudo $LOCAL_PKG_DIR/script/start.py 1 0 US"
