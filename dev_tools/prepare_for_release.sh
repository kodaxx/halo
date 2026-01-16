#!/bin/bash
# Removes sensitive data (WiFi creds, SSH keys, logs) to prepare for Golden Image capture.
# Run this on the Raspberry Pi just before shutting down.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./prepare_for_release.sh)"
    exit 1
fi

echo "========================================================"
echo "   HALO BASE IMAGE CLEANUP"
echo "========================================================"

# 1. Remove WiFi Credentials
# This ensures your home WiFi password isn't in the distributed image.
if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    echo "Removing /etc/wpa_supplicant/wpa_supplicant.conf..."
    rm /etc/wpa_supplicant/wpa_supplicant.conf
    
    # recreate a dummy empty file to satisfy some services if needed, 
    # or let firstboot handle it. We'll create a generic fresh one.
    cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

# Credentials removed for release.
EOF
    chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
fi

# 2. Reset provisioning state
# If we ran tests, we might have generated specific credentials.
# We want the end-user to generate FRESH ones.
if [ -f /boot/wifi_credentials.txt ]; then
    echo "Removing generated credentials (/boot/wifi_credentials.txt)..."
    rm /boot/wifi_credentials.txt
fi

# Reset hostapd to default setup SSID
if [ -f /etc/hostapd/hostapd.conf ]; then
    echo "Resetting hostapd to 'Halo_SETUP'..."
    sed -i 's/ssid=Halo_.*/ssid=Halo_SETUP/' /etc/hostapd/hostapd.conf
    sed -i 's/wpa_passphrase=.*/wpa_passphrase=halo_default/' /etc/hostapd/hostapd.conf
fi

# 3. Clean Logs
echo "Cleaning /var/log/..."
find /var/log -type f -exec truncate -s 0 {} \;

# 4. Clean Bash History
echo "Clearing bash history..."
cat /dev/null > ~/.bash_history
if [ -n "$SUDO_USER" ]; then
    cat /dev/null > /home/$SUDO_USER/.bash_history
fi

# 5. Optional: Reset SSH Host Keys
# This forces the Pi to generate new unique keys on next boot.
# WARNING: This will cause a 'Remote Host Identification Changed' warning for you next time.
echo "Removing SSH Host Keys (will regenerate on next boot)..."
rm -f /etc/ssh/ssh_host_*
# Ensure regeneration service is enabled
systemctl enable regenerate_ssh_host_keys 2>/dev/null || true

echo "========================================================"
echo "   CLEANUP COMPLETE"
echo "========================================================"
echo "Action: Shutdown the Pi immediately and capture the image."
echo "Command: sudo shutdown -h now"
