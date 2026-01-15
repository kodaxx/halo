#!/bin/bash
# Apply patch and recompile driver

cd nrc7292_sw_pkg || exit 1

echo "Applying DT support patch..."
wget -q https://raw.githubusercontent.com/kodaxx/halo/main/add_dt_support.patch -O add_dt_support.patch
# Try to reverse first if already applied, to ensure clean state or skip
patch -R -p1 --dry-run < add_dt_support.patch > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Patch seems to be applied already."
else
    patch -p1 < add_dt_support.patch || echo "Patch failed or already applied"
fi

echo "Recompiling driver..."
cd package/src/nrc || exit 1
make clean
make || exit 1

echo "Installing driver..."
sudo cp nrc.ko /lib/modules/$(uname -r)/extra/nrc.ko
sudo depmod -a
sudo rmmod nrc
sudo modprobe nrc

echo "Checking dmesg..."
dmesg | grep -i nrc | tail -n 20

echo "Checking interface..."
ip link show
