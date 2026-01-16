#!/bin/bash
# bootstrap_build.sh
# Quickstart wrapper for developers.
# Installs Git, clones the repo, and runs the main build script.
# Usage: curl -sL https://raw.githubusercontent.com/kodaxx/halo/main/dev_tools/bootstrap_build.sh | bash

set -e

echo "=== Halo Build Bootstrap ==="

# 1. Install Git
if ! command -v git &> /dev/null; then
    echo "Git not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y git
fi

# 2. Clone/Update Repo
cd ~
if [ -d "halo" ]; then
    echo "Directory 'halo' already exists."
    read -p "Overwrite (delete and re-clone)? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm -rf halo
        git clone https://github.com/kodaxx/halo.git
    else
        echo "Updating existing repo..."
        cd halo
        git pull
    fi
else
    echo "Cloning repository..."
    git clone https://github.com/kodaxx/halo.git
fi

# 3. Handover to Build Script
cd ~/halo
echo "Launching Build Script..."
chmod +x dev_tools/build_image.sh
sudo ./dev_tools/build_image.sh
