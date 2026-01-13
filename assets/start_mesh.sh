#!/bin/bash
# Halo Main Startup Script

CONFIG_FILE="/boot/halo.json"
DRIVER_DIR="/home/pi/nrc7292_sw_pkg"

# 0. Run Security Provisioning First
/home/pi/provision_wifi.sh

# 1. Load Settings
MESH_ID=$(grep -o '"mesh_id": "[^"]*' $CONFIG_FILE | grep -o '[^"]*$')
FREQ=$(grep -o '"freq": "[^"]*' $CONFIG_FILE | grep -o '[^"]*$')
COUNTRY=$(grep -o '"country": "[^"]*' $CONFIG_FILE | grep -o '[^"]*$')
STATIC_IP=$(grep -o '"static_ip": "[^"]*' $CONFIG_FILE | grep -o '[^"]*$')

echo "Starting Halo..."

# 2. Setup Bridge (br0)
# We create a bridge connecting the Phone (wlan0) to the Mesh (bat0)
brctl addbr br0
ifconfig br0 up
brctl addif br0 wlan0

# 3. Initialize HaLow Radio
cd $DRIVER_DIR
sudo python3 script/start.py 4 0 $COUNTRY $FREQ $MESH_ID

# 4. Start Batman-adv
modprobe batman-adv
batctl if add wlan1 
ifconfig bat0 up
brctl addif br0 bat0

# 5. Disable Multicast Snooping (Fixes Chat Apps)
echo 0 > /sys/devices/virtual/net/br0/bridge/multicast_snooping

echo "MagPuck Mesh Online. Starting Gateway Monitor..."

# 6. Start the Universal Gateway Monitor in Background
# This handles IP assignment and Internet Sharing dynamically
/home/pi/gateway_monitor.sh &
