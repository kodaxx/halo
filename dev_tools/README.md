# Halo Mesh Developer Guide

This guide explains how to build the base image for the Halo Mesh Node.
The workflow consists of three steps: **Build**, **Test**, and **Capture**.

## Registry
*   **Build Scripts**: `dev_tools/`
*   **Runtime Scripts**: `scripts/`
*   **Service Defs**: `services/`

---

## 1. Build The Master (On Raspberry Pi)
Use a fresh Raspberry Pi Zero 2 W (Bullseye) to create the master installation.

1.  Flash `Raspberry Pi OS Lite (32-bit)` to an SD Card.
2.  Run `prepare_pi.sh` to set hostname, wifi, and user.
3.  Boot the Pi, connect to internet, and SSH in.
## 1. Build THE MASTER (2-Step Process)

### Step 1: Bootstrap (Run on Pi)
SSH into your fresh Pi and run this. It will lock the kernel, clone the repo, and setup the overlay.
```bash
curl -sL https://raw.githubusercontent.com/kodaxx/halo/main/dev_tools/build_step_one.sh | bash
```
**Action**: The system will ask you to **REBOOT**. Do it (`sudo reboot`).

### Step 2: Finalize (Run on Pi after Reboot)
SSH back in and run:
```bash
sudo ~/halo/dev_tools/build_step_two.sh
```
**Action**: This compiles the driver, installs services, and prepares the system for capture.
**Result**: A base image ready for shutdown and capture.

## 2. Verify The Build (On Raspberry Pi)
Before shutting down, verify the build is healthy.

1.  Run the Verify Script:
    ```bash
    sudo ./dev_tools/test_build.sh
    ```
    *   **Checks**: Loads the driver manually, checks for `wlan1` interface, verifies services are installed but disabled, checks `dmesg` for errors.
2.  If Green/Pass, shutdown the Pi:
    ```bash
    sudo shutdown now
    ```

## 3. Capture The Image (On Mac)
Takes the physical SD card and turns it into a distributable `.img.gz` file.

1.  Insert the SD Card into your Mac.
2.  Run the Capture Tool:
    ```bash
    cd dev_tools
    sudo ./capture_image.sh
    ```
3.  **Process**:
    *   It will ask you to identify the SD card disk (e.g. `/dev/disk4`).
    *   It creates a raw `dd` image.
    *   It runs `pishrink` (via Docker) to shrink the filesystem to the minimum size and enable auto-expansion.
    *   It compresses the result to `halo_v1.img.gz`.

## Distribution
Share `halo_v1.img.gz`. This is the file users will flash.
