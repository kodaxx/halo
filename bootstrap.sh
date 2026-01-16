#!/bin/bash
# Halo Bootstrap Loader
# USAGE: curl -sL https://raw.githubusercontent.com/kodaxx/halo/main/bootstrap.sh | bash

set -e

echo "========================================"
echo "   Halo Mesh - One-Line Installer"
echo "========================================"

# 1. Install Git if missing
if ! command -v git &> /dev/null; then
    echo "Installing Git..."
    # Robust APT Update Logic
    # 1. Allow release info changes (bullseye stable -> oldstable etc)
    # 2. If update fails (hash mismatch), clear lists and retry
    if ! sudo apt-get update --allow-releaseinfo-change; then
        echo "APT Update failed. Clearing lists and retrying..."
        sudo rm -rf /var/lib/apt/lists/*
        sudo apt-get update --allow-releaseinfo-change
    fi
    sudo apt-get install -y git
fi

# 2. Setup Repository
TARGET_DIR="$HOME/halo"

if [ -d "$TARGET_DIR" ]; then
    echo "Updating existing repository at $TARGET_DIR..."
    cd "$TARGET_DIR"
    # Stash local changes just in case, to ensure clean pull
    git stash 2>/dev/null || true
    git pull origin main
else
    echo "Cloning repository to $TARGET_DIR..."
    git clone https://github.com/kodaxx/halo.git "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

# 3. Handover to Main Installer
echo "Launching Install Script..."
chmod +x install.sh
sudo ./install.sh
