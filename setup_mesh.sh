#!/bin/bash
# setup_mesh.sh
# Installs dependencies for Halo Mesh (batman-adv, etc)

echo "Installing Mesh Dependencies..."
sudo sudo apt-get update
sudo sudo apt-get install -y batctl dnsmasq iptables bridge-utils python3-flask

echo "Dependencies Installed."
