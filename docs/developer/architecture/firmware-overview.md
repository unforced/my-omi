# Omi Firmware Analysis Report

## Overview

This report analyzes the firmware for the Omi device, focusing on the button handling logic and outlining the steps required to modify its behavior according to the minimal fork requirements. The firmware is based on the Zephyr RTOS and utilizes the nRF Connect SDK.

-   **Location:** The relevant firmware source code resides primarily within the `omi/omi/firmware/` directory in the original repository.
-   **Structure:** Contains subdirectories for the consumer version (`omi/`) and the development kit (`devkit/`). The consumer version appears to leverage components from `omi/src/lib/dk2/`.
-   **Build:** Requires the nRF Connect SDK toolchain (specific versions noted in docs) or Docker, as detailed in `omi/omi/firmware/readme.md` and the official documentation ([Compile Firmware](https://docs.omi.me/docs/developer/firmware/Compile_firmware)).

## Button Handling Mechanism

The firmware employs a combination of Zephyr's subsystems for button input:

1.  **Input Subsystem:** Detects raw button press and release events using device tree overlays (`usr_btn` alias) and the `input_event` system. The callback `buttons_input_cb` in `button.c` captures these events.
2.  **Workqueue:** A periodic, delayable work item (`button_work` executing `check_button_level`) runs every ~40ms. This function reads the latest button state (captured by the input subsystem) and implements a state machine to detect more complex gestures like taps and long presses based on timing thresholds.
3.  **BLE Service:** A custom Bluetooth Low Energy (BLE) GATT service (UUID `23BA7924...`) with a characteristic (UUID `23BA7925...`) is defined in `button.c`. This characteristic is used to send notifications to the connected mobile app when button events (press, release, single/double/long tap) are detected by the `check_button_level` function. The notification payload indicates the event type (e.g., `1` for single tap, `2` for double tap, `3` for long press).

**Key File:** The primary logic for button detection, state management, and event notification resides in:
`omi/omi/firmware/omi/src/lib/dk2/button.c`

## Current Button Functionality

Based on the analysis of `button.c`:

-   **Power On:** The device powers on when the **main button is pressed** while the device is in the System OFF state. This works because the `turnoff_all` function configures the button GPIO as a wake-up interrupt source before entering System OFF.
-   **Power Off:** Triggered by a **SINGLE TAP** (likely unintended/debug configuration). When a single tap is detected in `check_button_level`, it calls `bt_off()` and `turnoff_all()`. The `turnoff_all` function shuts down peripherals and puts the device into System OFF mode using `sys_poweroff()`.
-   **Single Tap:**
    -   Sends a BLE notification with value `1`.
    -   **Triggers device power-off.**
-   **Double Tap:**
    -   Sends a BLE notification with value `2`.
    -   No other hardware action is taken in the firmware.
-   **Long Press:**
    -   Detected based on `LONG_PRESS_TIME` (1000ms).
    -   Sends a BLE notification with value `3`.
    *   **Does NOT currently trigger power-off** or any other hardware action.

**Note:** For single and double taps, the firmware currently relies entirely on the connected mobile app to interpret the BLE notifications and perform corresponding actions.

## Proposed Changes & Implementation Strategy

**Goal:** Modify firmware for flexible button actions:
1.  Keep **button press to power on**.
2.  Change **long press to power off**.
3.  Implement distinct **hardware actions** for **single, double, and triple taps** (e.g., control local recording, trigger specific modes).

**Implementation Steps:**

1.  **Modify Power Off Trigger:**
    *   Open `omi/omi/firmware/omi/src/lib/dk2/button.c`.
    *   Locate the `check_button_level` function.
    *   Find the code block handling `BUTTON_EVENT_SINGLE_TAP` (around line 225).
    *   **Remove** the lines `is_off = true;`, `bt_off();`, and `turnoff_all();` from this block.
    *   Find the code block handling `BUTTON_EVENT_LONG_PRESS` (around line 241).
    *   **Add** the lines `is_off = true;`, `bt_off();`, and `turnoff_all();` to this block, likely after the `notify_long_tap();` call.

2.  **Implement Triple Tap Detection:**
    *   Within `check_button_level`, extend the state machine logic. This will likely involve:
        *   Adding a `BUTTON_EVENT_TRIPLE_TAP` enum value.
        *   Tracking the time of the *second* tap release.
        *   Checking if a *third* press-and-release cycle occurs within a suitable time window (e.g., `DOUBLE_TAP_WINDOW`) after the second tap.
        *   Resetting tap counters appropriately.

3.  **Implement Hardware Actions for Taps:**
    *   Define the specific hardware actions required for single, double, and triple taps (e.g., `start_sd_recording()`, `stop_sd_recording()`, `trigger_ai_mode()`). These might involve calling functions in other firmware modules like `storage.c`, `led.c`, or creating new functions.
    *   In the `check_button_level` function:
        *   In the block for `BUTTON_EVENT_SINGLE_TAP`, replace or augment `notify_tap()` with calls to the desired single-tap action function(s).
        *   In the block for `BUTTON_EVENT_DOUBLE_TAP`, replace or augment `notify_double_tap()` with calls to the desired double-tap action function(s).
        *   Add a new block to handle the detected `BUTTON_EVENT_TRIPLE_TAP`, calling the desired triple-tap action function(s) and potentially a `notify_triple_tap()` if app notification is still needed.

4.  **Build and Flash:**
    *   Follow the procedures in the Omi documentation ([Compile Firmware](https://docs.omi.me/docs/developer/firmware/Compile_firmware), [Flash Device](https://docs.omi.me/docs/get_started/Flash_device)) to build the modified firmware using the nRF Connect SDK (ensure correct SDK version for `omi/` firmware) or Docker.
    *   Flash the resulting `.uf2` file to the device.

## Conclusion

Modifying the Omi firmware button behavior is feasible. The core logic is centralized in `button.c`, and the proposed changes involve adjusting the existing state machine, moving the power-off trigger, and integrating calls to other firmware modules to execute hardware actions based on tap events. Careful implementation and testing will be required. 