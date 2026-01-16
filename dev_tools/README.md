# Halo Mesh Developer Guide

This guide explains how to build the "Golden Image" for the Halo Mesh Appliance.
The workflow consists of three steps: **Build**, **Test**, and **Capture**.

## Registry
*   **Build Scripts**: `dev_tools/`
*   **Runtime Scripts**: `scripts/`
*   **Service Defs**: `services/`

---

## 1. Build The Master (On Raspberry Pi)
Use a fresh Raspberry Pi (Bookworm or newer) to create the master installation.

1.  Flash `Raspberry Pi OS Lite (64-bit)` to an SD Card.
2.  Boot the Pi, connect to internet, and SSH in.
3.  Clone this repository:
    ```bash
    git clone https://github.com/kodaxx/halo.git
    cd halo
    ```
4.  Run the Builder:
    ```bash
    sudo ./dev_tools/build_image.sh
    ```
    *   **What it does**: Installs dependencies, compiles `nrc7292` driver, compiles Device Tree Overlay, and installs (but does not enable) systemd services.
    *   **Result**: A fully prepped system that behaves like a normal Pi (SSH works, WiFi is managed by standard OS).

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
