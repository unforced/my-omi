# Omi App OTA DFU Integration Report

## Overview

This report details the findings from analyzing the Over-the-Air (OTA) Device Firmware Update (DFU) implementation in the original Omi application and outlines the plan to integrate this functionality into the `omi-minimal-fork` Flutter app.

## Original Implementation Analysis

The original Omi app (`omi/app`) utilizes a combination of standard libraries and protocols for handling OTA DFU:

1.  **Firmware Support:** The Omi firmware (both consumer and DevKit versions) is built with support for the MCUBoot bootloader and the MCUmgr management protocol over BLE. It advertises a specific "Legacy DFU" service (`00001530-...`) which allows the app to trigger a reset into the MCUBoot DFU mode by writing to a control point characteristic (`00001531-...`).
2.  **App Libraries:** The Flutter app uses two key libraries (found in `omi/app/pubspec.yaml`):
    *   `nordic_dfu`: Handles the low-level BLE communication for the Nordic Secure DFU protocol, likely used by MCUmgr for the actual firmware image transfer.
    *   `mcumgr_flutter`: Implements the higher-level MCUmgr protocol used to manage the update process (check device state, upload image data, confirm update, reset device).
3.  **Core App Logic:** The file `omi/app/lib/pages/home/firmware_mixin.dart` contains the primary UI logic and state management for the DFU process.
    *   It fetches information about the latest available firmware.
    *   It likely handles downloading the firmware package (`.zip` file containing the `.hex` firmware image and manifest).
    *   It uses `mcumgr_flutter`'s `FirmwareUpdateManager` to orchestrate the update.
    *   It interacts with the `DeviceProvider` (via `prepareDFU()`) to trigger the device reset into DFU mode (likely by writing to the Legacy DFU control point).
    *   It tracks the download and installation progress and state (`isDownloading`, `isInstalling`, `downloadProgress`, `installProgress`, etc.).

## Integration Plan for `omi-minimal-fork`

The goal is to add the necessary components to the minimal fork to enable OTA DFU triggered from the app UI.

**Steps:**

1.  **Add Dependencies:**
    *   Modify `omi-minimal-fork/pubspec.yaml`.
    *   Add `nordic_dfu`, `mcumgr_flutter`, `flutter_archive` (needed by `firmware_mixin.dart` to process the zip), `path_provider`, and potentially `http` (if firmware needs downloading) to the `dependencies` section, using versions similar to the original `pubspec.yaml`. Run `flutter pub get`.

2.  **Copy Core Logic Files:**
    *   Copy `omi/app/lib/pages/home/firmware_mixin.dart` to `omi-minimal-fork/lib/utils/firmware_mixin.dart` (or a similar appropriate location).
    *   **Identify and copy** any utility functions or classes that `firmware_mixin.dart` depends on (e.g., functions for downloading the firmware zip, potentially API service files if it checks a server for updates, manifest parsing logic (`omi/utils/manifest/manifest.dart` seems likely)). This requires careful inspection of `firmware_mixin.dart` imports. *Self-correction: Search results showed `omi/http/api/device.dart` and `omi/utils/manifest/manifest.dart` as relevant.*
    *   Copy `omi/app/lib/http/api/device.dart` to `omi-minimal-fork/lib/http/api/device.dart`.
    *   Copy `omi/app/lib/utils/manifest/manifest.dart` to `omi-minimal-fork/lib/utils/manifest/manifest.dart`.
    *   Copy any related model/schema files if needed by the API or manifest logic.

3.  **Integrate DFU Triggering:**
    *   Modify `omi-minimal-fork/lib/providers/device_provider.dart` (or the equivalent minimal state manager).
    *   Add a method similar to `prepareDFU()` from the original `DeviceProvider`. This method needs to:
        *   Find the Legacy DFU service (`00001530-...`).
        *   Find the DFU control point characteristic (`00001531-...`).
        *   Write the specific byte sequence (`[0x01]` or `[0x06]`) to the characteristic to trigger the reset into DFU mode. This requires using `flutter_blue_plus` methods.

4.  **Integrate UI:**
    *   Modify the main UI page (`omi-minimal-fork/lib/main.dart` or `home_page.dart`).
    *   Add UI elements (e.g., a button "Check for Updates" or "Install Firmware").
    *   Use the `FirmwareMixin` logic:
        *   Connect button actions to call functions within the mixin (e.g., check for updates, download firmware, `startMCUDfu`).
        *   Display progress (`downloadProgress`, `installProgress`) and state (`isDownloading`, `isInstalling`, `isInstalled`).
    *   Ensure the necessary `Provider` setup is in place if the mixin relies on `context.read` or `context.watch` for providers like `DeviceProvider`.

5.  **Adaptation and Refinement:**
    *   Resolve any import errors in the copied files.
    *   Adapt the copied code to fit the structure and state management patterns of the minimal fork. Remove dependencies on non-existent providers or services.
    *   Simplify the UI integration as needed for the minimal app. For instance, instead of checking a server, it might initially just allow selecting a pre-downloaded `.zip` file.

6.  **Testing:**
    *   Thoroughly test the entire flow: triggering DFU mode, transferring the firmware, device resetting, and verifying the new version.

## Conclusion

Integrating OTA DFU is feasible but involves adding several dependencies and careful integration of service logic, UI components, and state management interactions. The primary files to copy and adapt are `firmware_mixin.dart` and its dependencies, along with adding the DFU trigger logic to the device connection handling. 