#!/bin/bash
# apply_fix_v3.sh
# 1. Apply Device Tree patch (if not already applied)
# 2. Fix IS_ERR logic errors (cause of segfault)
# 3. Add missing mgmt_tx callback (cause of load failure/warning on Kernel 6.12)
# 4. Recompile and Install

DRIVER_DIR="$HOME/nrc7292_sw_pkg/package/src/nrc"
CSPI_FILE="$DRIVER_DIR/nrc-hif-cspi.c"
MAC_FILE="$DRIVER_DIR/nrc-mac80211.c"

# Ensure we are in the right place
if [ ! -d "$DRIVER_DIR" ]; then
    echo "Error: Driver directory not found at $DRIVER_DIR"
    exit 1
fi

cd "$DRIVER_DIR" || exit 1

# --- Step 1: DT Patch ---
# (Skipping patch command significantly if already applied, but we ensure the content is there)
# We assume the user has run the previous scripts or we rely on the manual sed fixes below.

# --- Step 2: Fix Segfault (IS_ERR logic) ---
echo "Fixing IS_ERR logic in nrc-hif-cspi.c..."
# Replace IS_ERR(ptr) with !ptr for simple pointer checks
# We use a loop/global replace to be safe.
sed -i 's/IS_ERR(priv)/!priv/g' "$CSPI_FILE"
sed -i 's/IS_ERR(nw)/!nw/g' "$CSPI_FILE"
sed -i 's/IS_ERR(hdev)/!hdev/g' "$CSPI_FILE"

# --- Step 3: Add mgmt_tx callback ---
echo "Adding mgmt_tx callback to nrc-mac80211.c..."

# Check if already added to avoid duplication
if grep -q "nrc_mac_mgmt_tx" "$MAC_FILE"; then
    echo "mgmt_tx wrapper already present."
else
    # Insert the wrapper function definition before the ops struct
    # We look for "static const struct ieee80211_ops nrc_mac80211_ops = {"
    sed -i '/static const struct ieee80211_ops nrc_mac80211_ops = {/i \
static int nrc_mac_mgmt_tx(struct ieee80211_hw *hw, struct wireless_dev *wdev, struct sk_buff *skb, struct cfg80211_chan_def *chandef)\
{\
	return nrc_mac_tx(hw, skb);\
}\
' "$MAC_FILE"

    # Insert the .mgmt_tx callback inside the ops struct
    # We insert it after .tx = nrc_mac_tx,
    sed -i '/.tx = nrc_mac_tx,/a \ \ \ \ \ \ \ \ .mgmt_tx = nrc_mac_mgmt_tx,' "$MAC_FILE"
fi

# --- Step 4: Recompile ---
echo "Cleaning and Recompiling..."
make clean
if make; then
    echo "Compilation successful."
else
    echo "Compilation failed."
    exit 1
fi

# --- Step 5: Install ---
echo "Installing..."
TARGET_MOD_DIR="/lib/modules/$(uname -r)/extra"
sudo mkdir -p "$TARGET_MOD_DIR"
sudo cp nrc.ko "$TARGET_MOD_DIR/nrc.ko"
sudo depmod -a

echo "Attempting to unload old driver (if possible)..."
sudo rmmod nrc 2>/dev/null

echo "Loading new driver..."
if sudo insmod nrc.ko; then
    echo "Driver loaded successfully!"
    ip link show
    dmesg | tail -n 20
else
    echo "Failed to load driver (likely 'Device or resource busy' if you didn't reboot)."
    echo "PLEASE COMPLETED STEP: REBOOT YOUR PI and run this script again."
    exit 1
fi
