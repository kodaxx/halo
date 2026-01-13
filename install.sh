#!/bin/bash
# Halo Cloud Installer
# USAGE: bash <(curl -sL https://raw.githubusercontent.com/kodaxx/Halo/main/install.sh)

REPO_URL="https://github.com/kodaxx/Halo.git" # REPLACE THIS
INSTALL_DIR="/tmp/halo_install"
echo "=== Halo Installer ==="
sudo apt-get update
sudo apt-get install -y raspberrypi-kernel-headers git python3-flask batctl bridge-utils dnsmasq hostapd

rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR

cd /home/pi
if [ ! -d "nrc7292_sw_pkg" ]; then
    git clone https://github.com/newracom/nrc7292_sw_pkg.git
fi

grep -qxF "dwc2" /etc/modules || echo "dwc2" | sudo tee -a /etc/modules
grep -qxF "g_ether" /etc/modules || echo "g_ether" | sudo tee -a /etc/modules

cat $INSTALL_DIR/assets/config.txt | sudo tee -a /boot/config.txt

sudo cp $INSTALL_DIR/assets/hostapd.conf /etc/hostapd/hostapd.conf
sudo cp $INSTALL_DIR/assets/dnsmasq.conf /etc/dnsmasq.conf
sudo cp $INSTALL_DIR/assets/dhcpcd.conf /etc/dhcpcd.conf
sudo cp $INSTALL_DIR/assets/halo.json /boot/halo.json
sudo cp $INSTALL_DIR/assets/halo.service /etc/systemd/system/
sudo cp $INSTALL_DIR/assets/halo-firstboot.service /etc/systemd/system/
sudo cp $INSTALL_DIR/assets/start_mesh.sh /home/pi/
sudo cp $INSTALL_DIR/assets/gateway_monitor.sh /home/pi/
sudo cp $INSTALL_DIR/assets/web_admin.py /home/pi/
sudo cp $INSTALL_DIR/assets/provision_wifi.sh /home/pi/

sudo chmod +x /home/pi/start_mesh.sh
sudo chmod +x /home/pi/gateway_monitor.sh
sudo chmod +x /home/pi/provision_wifi.sh

sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl enable halo.service
sudo systemctl enable halo-firstboot
sudo systemctl unmask hostapd.service

echo "=== Running Initial Provisioning ==="
sudo /home/pi/provision_wifi.sh

echo "=== Installation Complete ==="
echo "Here are the device credentials:"
echo "--------------------------------"
if [ -f /boot/wifi_credentials.txt ]; then
    cat /boot/wifi_credentials.txt
else
    echo "Error: Credentials not generated."
fi
echo "--------------------------------"
echo "Please Reboot to start the First Boot Compilation."