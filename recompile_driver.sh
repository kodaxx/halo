#!/bin/bash
# Apply patch and recompile driver

cd nrc7292_sw_pkg || exit 1

echo "Applying DT support patch..."
# Download patch if local file specific fails or push via git
wget -q https://raw.githubusercontent.com/kodaxx/halo/main/add_dt_support.patch -O add_dt_support.patch
patch -p1 < add_dt_support.patch || echo "Patch already applied or failed"

echo "Recompiling driver..."
make clean
make || exit 1

echo "Installing driver..."
sudo cp package/src/nrc/nrc.ko /lib/modules/$(uname -r)/extra/nrc.ko
sudo depmod -a
sudo rmmod nrc
sudo modprobe nrc

echo "Checking dmesg..."
dmesg | grep -i nrc | tail -n 20

echo "Checking interface..."
ip link show
