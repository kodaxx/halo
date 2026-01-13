
# **Halo: Wi-Fi HaLow Mesh Node**

*Turn your Raspberry Pi Zero 2 W into a long-range, self-healing mesh network node.*

The Halo connects to your smartphone via standard Wi-Fi and bridges your communications over a 900MHz Wi-Fi HaLow link. This allows you to chat, send data, and communicate off-grid over kilometers of distance using standard IP-based apps.

Now with Universal Gateway support! Plug in a laptop (USB) or Starlink (Ethernet) to instantly share internet with the entire mesh.

#### **Hardware Requirements**
- Raspberry Pi Zero 2 W (Headers required)
- Alfa AHPI7292S (Wi-Fi HaLow HAT)
- Power Source: Geekworm X306 (18650) or PiSugar 2 (LiPo)
- MicroSD Card (8GB+)
- (Optional) Micro-USB Ethernet Adapter (For sharing wired internet)

#### **Installation Guide**

*Follow these steps to flash the software and provision your device.*

##### **Step 1: Flash the OS (Crucial Setup)**

- You do not need to download a custom image. We use the standard Raspberry Pi OS.
- Download and install the Raspberry Pi Imager.
- Choose OS: Select Raspberry Pi OS Lite (64-bit).
- Choose Storage: Select your SD card.
- Hostname: Set to halo-setup.
- Enable SSH: Select "Use password authentication".
- Set Username/Password: e.g., halo / halo.
- Configure Wireless LAN: Enter your HOME Wi-Fi credentials. This allows the Pi to connect to the internet on its first boot to download the Halo software.
- Click WRITE.

##### **Step 2: Connect via SSH**

- Insert the SD card into the Pi and power it on. Wait about 2 minutes for it to boot and connect to your home Wi-Fi.
- Open a terminal (Command Prompt on Windows, Terminal on Mac) and run:

    ```bash
	ssh halo@halo-setup.local
	```

##### **Step 3: Run the Cloud Installer**

Once logged into the Pi, run this single command to transform it into a Halo node. This will install drivers, configure the mesh, and set up the admin panel.

Bash
```bash
curl -sL https://raw.githubusercontent.com/kodaxx/Halo/main/install.sh
```

The installer will take 5-10 minutes.

##### ** ⚠️ Step 4: CRITICAL - Save Your Credentials ⚠️**

At the very end of the installation script, the terminal will display your unique device credentials. You must copy these down immediately. The output will look like this:

```plaintext
--------------------------------
SSID: Halo_A1B2
PASS: 10000000abcde
QR: WIFI:S:Halo_A1B2;T:WPA;P:10000000abcde;H:true;;
--------------------------------
```

**SSID:** The Wi-Fi network name your phone will connect to.
**PASS:** The password for that network (derived from your CPU Serial ID).
**QR:** A text string you can turn into a QR code for easy scanning.

##### **Step 5: Reboot & Compilation**

Run `sudo reboot`

The device will restart.

Wait 3-5 minutes: On this first boot, the device is compiling the radio drivers in the background. The LED may blink or stay solid.

Once finished, the Halo_XXXX Wi-Fi network will appear on your phone.

#### **Configuration & Web Admin**

- Connect your phone/laptop to the Halo_XXXX Wi-Fi network using the password from Step 4.
- Open a web browser and go to: http://192.168.10.1

##### **Settings Explained**

- **Mesh ID**: The "Group Password". All devices must have the exact same Mesh ID to talk to each other.
- **Frequency**: 915 MHz (US) or 920 MHz (Korea/Global). All devices must match.
- **IP Mode**:
	- **Smart (Auto-Detect)**: Recommended. Uses a random IP for P2P chat, but automatically grabs a Real IP if an Internet Gateway is detected in the mesh.
	- **Static**: Manually assign IPs (e.g., 10.1, 10.2).
- **Internet Gateway**:
	- **AUTO (Hot-Swap)**: Recommended. If you plug in an internet source (USB/Ethernet), this node automatically becomes the Server and shares internet with the mesh. If unplugged, it reverts to a Client.
	- **OFF**: Forces the node to always be a Client.

#### Internet Gateway (Sharing Internet)

*You can share an internet connection with the entire mesh.*

##### Method 1: Laptop Tethering (USB)
- Connect the Halo to your laptop using the USB Data Port (inner port).
- Ensure your laptop is sharing internet (or bridged) to the RNDIS/Ethernet Gadget adapter.
- Wait ~15 seconds. The Halo will detect the internet and broadcast it to the mesh.

##### Method 2: Ethernet Dongle

- Connect a Micro-USB to Ethernet Adapter to the Halo.
- Plug an Ethernet cable from a Router or Starlink into the adapter.
- Wait ~15 seconds. The Halo will detect the internet and broadcast it to the mesh.

*Note: Only one node in the mesh should be providing internet at a time to avoid IP conflicts.*