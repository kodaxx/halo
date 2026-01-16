# Halo Mesh Appliance

Turn your Raspberry Pi into a secure, long-range HaLow Mesh node in minutes.

## Prerequisites
*   Raspberry Pi 3B+ or 4 (or newer).
*   Halo HaLow USB Adapter (Newracom 7292).
*   Micro SD Card (16GB+ recommended).

## Installation

### 1. Flash the Image
1.  Download the latest `halo_v1.img.gz`.
2.  Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or [Balena Etcher](https://etcher.balena.io/) to flash the image to your SD Card.

### 2. Configure WiFi & SSH
**Crucial Step**: You need to get the Pi on your network to access it.

**Option A: Raspberry Pi Imager (Recommended)**
*   When flashing, click the **Settings (Gear) Icon**.
*   Enable **SSH**.
*   Set **username and password**.
*   Configure **Wireless LAN** with your home WiFi details.
*   *Then* click **Write**.

**Option B: Manual Method**
*   After flashing, re-insert the SD card into your computer.
*   Create a file named `ssh` (no extension) in the `boot` volume.
*   Create a file named `wpa_supplicant.conf` in the `boot` volume with your WiFi details.

### 3. Initial Boot
1.  Insert SD Card into the Pi.
2.  Connect the Halo USB Adapter.
3.  Power on.
4.  **Wait 2-3 minutes**: The system will automatically expand the filesystem and reboot once.

### 3. Activation
1.  SSH into the Pi (or use a keyboard/monitor).
    *   Default Hostname: `halo` (or whatever the base image used).
    *   Default User/Pass: As configured in the base image (usually `pi`/`raspberry` or user created).
2.  Run the Finalizer:
    ```bash
    cd halo
    sudo ./firstboot.sh
    ```
3.  **Done!**
    *   The script will generate unique WiFi credentials for this device.
    *   It will enable the Mesh AP and lock down the networking.
    *   The system will reboot into Appliance Mode.

## Usage
*   **Connect**: Look for WiFi SSID `Halo_XXXX` (password presented during activation).
*   **Admin**: Visit `http://10.0.0.1` to monitor the mesh and configure settings.