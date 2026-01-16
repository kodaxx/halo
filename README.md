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

### 2. Initial Boot
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
    sudo ./finalize_appliance.sh
    ```
3.  **Done!**
    *   The script will generate unique WiFi credentials for this device.
    *   It will enable the Mesh AP and lock down the networking.
    *   The system will reboot into Appliance Mode.

## Usage
*   **Connect**: Look for WiFi SSID `Halo_XXXX` (password presented during activation).
*   **Admin**: Visit `http://10.0.0.1` to monitor the mesh and configure settings.