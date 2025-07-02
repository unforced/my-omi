# Firmware Build and OTA Package Generation

This document outlines the steps to build the firmware within this `omi-minimal-fork` project and generate the necessary Over-the-Air (OTA) Device Firmware Update (DFU) package (`.zip` file) required by the Flutter application.

## Prerequisites

*   **Omi Hardware:** You are targeting the Omi DevKit (adjust board/config names if targeting other hardware).
*   **Build Environment:** You need either:
    *   **nRF Connect SDK:** Version `2.7.0` installed and configured with VS Code and the nRF Connect extension (see [Omi Compile Firmware Docs](https://docs.omi.me/docs/developer/firmware/Compile_firmware) for setup).
    *   **Docker:** Docker installed and running.
*   **`adafruit-nrfutil`:** If *not* using the Docker build method, you need this Python tool installed globally or in your environment:
    ```bash
    pip install adafruit-nrfutil
    ```

## Target Firmware Directory

All build commands should be configured to build the **DevKit firmware** located at:
`omi-minimal-fork/firmware/devkit`

## Build Method 1: Using nRF Connect for VS Code

1.  **Open Project:** Open the `omi-minimal-fork/firmware/devkit` folder in VS Code.
2.  **Select Application:** Ensure the nRF Connect extension recognizes this folder as the application.
3.  **Add Build Configuration:**
    *   Click "Add Build Configuration" in the nRF Connect panel.
    *   Choose the correct CMake preset for your DevKit hardware (e.g., `xiao_ble_sense_devkitv1` or `xiao_ble_sense_devkitv2-adafruit`). The board target should be `xiao_ble/nrf52840/sense`.
    *   Ensure the Toolchain version selected corresponds to NCS SDK v2.7.0.
4.  **Build Firmware:** Click the "Build" icon for the created configuration.
5.  **Locate Output:** The compiled firmware (`zephyr.hex`, `zephyr.bin`, `zephyr.uf2`) will be in the build output directory, typically:
    `omi-minimal-fork/firmware/devkit/build/build_xiao_ble_sense_devkitv.../zephyr/`
6.  **Generate OTA Package:**
    *   Open a terminal.
    *   Navigate (`cd`) into the specific build output directory found in the previous step (the one containing `zephyr.hex`).
    *   Run the `adafruit-nrfutil` command:
        ```bash
        # Example command - creates firmware_update.zip
        adafruit-nrfutil dfu genpkg --dev-type 0x0052 --dev-revision 0xCE68 --application zephyr.hex firmware_update.zip
        ```
        *   *(Note: Add `--sd-req 0x0` if you encounter DFU errors related to SoftDevice requirements.)*
    *   This creates the `firmware_update.zip` file in the current directory.

## Build Method 2: Using Docker

1.  **Navigate:** Open a terminal in the `omi-minimal-fork/firmware` directory.
2.  **Run Script:** Execute the Docker build script:
    ```bash
    sh ./scripts/build-firmware-in-docker.sh
    ```
    *(Note: The script is configured to build the DevKit firmware using SDK v2.7.0)*
3.  **Locate Output:** The script automatically performs the build and generates the OTA package.
    *   The compiled firmware (`.hex`, `.bin`, `.uf2`) and the OTA package (`zephyr.zip`) will be placed in:
        `omi-minimal-fork/firmware/build/docker_build/`

## Using the OTA Package (`.zip`)

The generated `.zip` file (e.g., `firmware_update.zip` or `zephyr.zip`) is the package required by the `omi-minimal-fork` Flutter application.

1.  Transfer the `.zip` file to the device running the app (e.g., via USB, cloud storage, etc.).
2.  In the app, use the "Select Firmware File (.zip)" button to locate and select this file.
3.  Use the "Start Update" button to initiate the OTA DFU process.

Refer to `OTA_DFU_REPORT.md` for details on how the app handles this process internally. 