# Halo - WiFi HaLow Mesh Node

Turn your Raspberry Pi into a secure, long-range HaLow Mesh node in minutes.

## Prerequisites
*   Raspberry Pi Zero 2 W.
*   Alfa Network AHPI7292S WiFi HaLow Pi Hat (Newracom 7292).
*   Micro SD Card (16GB+ recommended).

## Installation

### 1. Flash the Image
1.  Download the latest Halo release image `halo_[release].img.gz`.
2.  Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or [Balena Etcher](https://etcher.balena.io/) to flash the image to your SD Card.

### 2. Configure WiFi & SSH
**Crucial Step**: You need to get the Pi on your network to access it.

**Option A: Raspberry Pi Imager**
*   When flashing, use these custom **Settings**.
*   Enable **SSH**.
*   Set **username and password**. MUST be `halo`/`halo`.
*   Configure **Wireless LAN** with your home WiFi details.
*   *Then* click **Write**.

**Option B: Manual Method (Recommended)**
*   After flashing, re-insert the SD card into your computer.
*   Create a file named `ssh` (no extension) in the `bootfs` volume.
*   Create a file named `wpa_supplicant.conf` in the `bootfs` volume with your WiFi details.

### 3. Initial Boot
1.  Insert SD Card into the Pi.
2.  Connect the Alfa Network AHPI7292S Pi Hat to the Pi.
3.  Power on.
4.  **Wait 2-3 minutes**: The system will automatically expand the filesystem and boot up.

### 3. Activation
1.  SSH into the Pi (or use a keyboard/monitor).
    *   Default Hostname: `halo-setup` (or whatever the base image used).
    *   Default User/Pass: As configured in the base image (usually `halo`/`halo` or user created).
2.  Run the First Boot Script:
    ```bash
    cd halo
    sudo ./firstboot.sh
    ```
3.  **Done!**
    *   The script will generate unique WiFi credentials for this device.
    *   It will enable the Mesh AP and lock down the networking.
    *   The system will reboot and you will no longer be able to SSH into the device.

## Usage
*   **Connect**: Look for WiFi SSID `Halo_XXXX` (password presented during activation).
*   **Admin**: Visit `http://gw.halo.local` or `http://10.0.0.1` to monitor the mesh and configure settings.