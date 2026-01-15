#!/bin/bash
# Apply driver DT support usage sed for robustness

# Target directory
TARGET_DIR="$HOME/nrc7292_sw_pkg/package/src/nrc"
TARGET_FILE="$TARGET_DIR/nrc-hif-cspi.c"

if [ ! -f "$TARGET_FILE" ]; then
    echo "Error: Cannot find $TARGET_FILE"
    exit 1
fi

cd "$TARGET_DIR" || exit 1
echo "Working in $(pwd)"

# 1. Add #include <linux/of.h> if missing
if ! grep -q "linux/of.h" "$TARGET_FILE"; then
    echo "Adding #include <linux/of.h>..."
    sed -i '/#include <linux\/gpio.h>/a #include <linux/of.h>' "$TARGET_FILE"
else
    echo "Header already present."
fi

# 2. Add nrc_of_match definition if missing
if ! grep -q "nrc_of_match" "$TARGET_FILE"; then
    echo "Adding nrc_of_match definition..."
    # Insert before 'static struct spi_driver nrc_cspi_driver'
    sed -i '/static struct spi_driver nrc_cspi_driver/i \
static const struct of_device_id nrc_of_match[] = {\
	{ .compatible = "newracom,nrc7292", },\
	{ .compatible = "nrc80211", },\
	{ }\
};\
MODULE_DEVICE_TABLE(of, nrc_of_match);\
' "$TARGET_FILE"
else
    echo "nrc_of_match already defined."
fi

# 3. Add .of_match_table to driver struct if missing
if ! grep -q ".of_match_table" "$TARGET_FILE"; then
    echo "Adding .of_match_table to driver struct..."
    sed -i '/.name = NRC_DRIVER_NAME,/a \ \ \ \ \ \ \ \ .of_match_table = nrc_of_match,' "$TARGET_FILE"
else
    echo ".of_match_table already present."
fi

# 4. Recompile
echo "Recompiling..."
if [ -f "Makefile" ]; then
    make clean
    make || exit 1
else
    echo "Error: Makefile not found in $TARGET_DIR"
    exit 1
fi

# 5. Install
echo "Installing driver..."
sudo cp nrc.ko /lib/modules/$(uname -r)/extra/nrc.ko
sudo depmod -a
sudo rmmod nrc
sudo modprobe nrc

echo "Checking dmesg..."
dmesg | grep -i nrc | tail -n 20

echo "Checking interface..."
ip link show
