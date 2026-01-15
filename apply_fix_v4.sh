#!/bin/bash
# apply_fix_v4.sh
# Fixes compilation on Kernel 6.12 by:
# 1. Disabling incompatible "NEW_MAC_TX" (3-arg) signature.
# 2. Removing non-existent .mgmt_tx callback.
# 3. Applying standard segfault fixes.

DRIVER_DIR="$HOME/nrc7292_sw_pkg/package/src/nrc"
CONFIG_FILE="$DRIVER_DIR/nrc-build-config.h"
HEADER_FILE="$DRIVER_DIR/nrc-mac80211.h"
MAC_FILE="$DRIVER_DIR/nrc-mac80211.c"
CSPI_FILE="$DRIVER_DIR/nrc-hif-cspi.c"

# Ensure repo exists
if [ ! -d "$DRIVER_DIR" ]; then
    echo "Error: Driver directory not found at $DRIVER_DIR"
    # Try to find it if we are in the repo
    if [ -d "./nrc7292_sw_pkg/package/src/nrc" ]; then
        DRIVER_DIR="./nrc7292_sw_pkg/package/src/nrc"
        CONFIG_FILE="$DRIVER_DIR/nrc-build-config.h"
        HEADER_FILE="$DRIVER_DIR/nrc-mac80211.h"
        MAC_FILE="$DRIVER_DIR/nrc-mac80211.c"
        CSPI_FILE="$DRIVER_DIR/nrc-hif-cspi.c"
    else
        exit 1
    fi
fi

echo " Applying Fixes to $DRIVER_DIR..."

# --- Step 1: Disable NEW_MAC_TX for Kernel >= 6.0 in config ---
# We append the undef logic to the end of the config block, just before #endif
if ! grep -q "undef CONFIG_SUPPORT_NEW_MAC_TX" "$CONFIG_FILE"; then
    echo "Patching nrc-build-config.h to disable 3-arg TX..."
    # Insert before the last #endif
    sed -i '/#endif/i \
#if KERNEL_VERSION(6, 0, 0) <= NRC_TARGET_KERNEL_VERSION\
#undef CONFIG_SUPPORT_NEW_MAC_TX\
#undef CONFIG_SUPPORT_TX_CONTROL\
#endif\
' "$CONFIG_FILE"
fi

# --- Step 2: Update Header to respect NEW_MAC_TX macro ---
# Change the guard from AFTER_KERNEL_3_0_36 to CONFIG_SUPPORT_NEW_MAC_TX
echo "Patching nrc-mac80211.h to check CONFIG_SUPPORT_NEW_MAC_TX..."
sed -i 's/#ifdef CONFIG_SUPPORT_AFTER_KERNEL_3_0_36/#ifdef CONFIG_SUPPORT_NEW_MAC_TX/' "$HEADER_FILE"

# --- Step 3: Remove .mgmt_tx from OPS (It doesn't exist in 6.12) ---
echo "Removing .mgmt_tx from nrc-mac80211.c..."
sed -i '/.mgmt_tx = nrc_mac_mgmt_tx,/d' "$MAC_FILE"
# Also remove the wrapper function if it exists
sed -i '/static int nrc_mac_mgmt_tx/,/}/d' "$MAC_FILE"

# --- Step 4: Fix Segfault (IS_ERR logic) - Re-applying just in case ---
echo "Ensuring IS_ERR fixes are applied..."
sed -i 's/IS_ERR(priv)/!priv/g' "$CSPI_FILE"
sed -i 's/IS_ERR(nw)/!nw/g' "$CSPI_FILE"
sed -i 's/IS_ERR(hdev)/!hdev/g' "$CSPI_FILE"

# --- Step 5: Clean and Recompile ---
echo "Compiling..."
cd "$DRIVER_DIR" || exit 1
make clean
if make; then
    echo "SUCCESS: Driver compiled!"
else
    echo "FAIL: Compilation failed."
    exit 1
fi
