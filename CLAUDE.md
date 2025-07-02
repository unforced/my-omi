# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a minimal fork of the Omi project - a wearable AI device for capturing audio conversations. The repository contains:
- Flutter mobile application for iOS/Android/Desktop
- Firmware for nRF5340-based hardware (Zephyr RTOS)
- BLE communication protocol between app and device

## Common Development Commands

### Flutter App Development

```bash
# Install dependencies
flutter pub get

# Run app in development
flutter run

# Build for production
flutter build ios
flutter build android
flutter build macos

# Run tests
flutter test
```

### Firmware Development

```bash
# Build firmware using Docker (recommended)
cd firmware
./scripts/build-docker.sh
# Note: May encounter SDK compatibility issues with picolibc
# See FIRMWARE_BUILD_STATUS.md for details

# Clean build
./scripts/build-docker.sh --clean

# Flash firmware (device in bootloader mode)
cd firmware/devkit
./flash.sh

# Monitor device serial output
cd firmware/scripts
./monitor_device.sh
```

**Known Issue**: The Docker build may fail due to picolibc type conflicts between Zephyr SDK v0.17.2 and nRF Connect SDK v2.7.0. Consider using VS Code with nRF Connect extension for local builds.

## Architecture Overview

### Mobile App Architecture

The Flutter app uses a service-based architecture with Provider for state management:

**Core Services (lib/services/)**
- `ServiceManager`: Singleton managing all services initialization
- `DeviceService`: BLE device discovery and connection management
- `MinimalOmiService`: Main service coordinating device operations

**State Management (lib/providers/)**
- `MinimalDeviceProvider`: Device connection state and BLE operations
- `MinimalCaptureProvider`: Audio capture state and file management

**Connection Layer (lib/connections/)**
- `OmiConnection`: High-level Omi device interface
- `FrameConnection`: Low-level BLE frame protocol implementation
- `FrameTypes`: Protocol frame definitions

**Key BLE UUIDs**
- Service: `19b10000-e8f2-537e-4f6c-d104768a1214`
- Audio Stream: `19b10001-e8f2-537e-4f6c-d104768a1214`
- Audio Codec: `19b10002-e8f2-537e-4f6c-d104768a1214`

### Firmware Architecture

Built on Zephyr RTOS with custom board support:

**Directory Structure**
- `firmware/omi/`: Main application firmware
- `firmware/devkit/`: Development kit variants
- `firmware/boards/`: Custom board definitions
- `firmware/bootloader/`: MCUboot bootloader

**Key Components**
- BLE GATT services for audio streaming
- Opus audio codec integration
- OTA/DFU firmware update support
- Button and LED control

## Key Implementation Notes

### Audio Processing
- Supports PCM8/16, Opus, and μLaw codecs
- Real-time streaming over BLE
- Offline recording capability on device
- Audio data stored as WAV files with proper headers

### Firmware Updates
- Uses Nordic Legacy DFU protocol (not MCUmgr)
- OTA package bundled in app at `assets/firmware/devkit-v2-firmware.zip`
- Automatic firmware version detection and update prompts
- Current bundled version: v2.0.10

### Button Event System
- Button events sent via BLE characteristic (UUID: 30295781-4301-EABD-2904-2849ADFEAE43)
- Event types: SINGLE_TAP(1), DOUBLE_TAP(2), TRIPLE_TAP(3), LONG_TAP(4)
- Visual feedback in app shows button press events
- Button state integrated with recording functionality

### Current Firmware Button Functionality
**WARNING**: Current firmware has single tap = power off, which needs fixing
- Single tap: Powers off device (problematic - needs to be changed)
- Double tap: Detected but no action assigned
- Long press (≥1s): Detected but no action assigned
- Triple tap: Not implemented yet

**Proposed Button Changes (from FIRMWARE_REPORT.md)**:
- Single tap: Start/stop recording
- Double tap: Trigger custom action
- Triple tap: Special mode activation
- Long press: Power off device

### State Flow
1. Device discovery via BLE scanning
2. Connection establishment with GATT service discovery
3. Audio stream negotiation (codec selection)
4. Real-time audio capture and streaming
5. Local file storage as WAV format

### Error Handling
- Connection failures handled in `MinimalDeviceProvider`
- Audio capture errors managed by `MinimalCaptureProvider`
- BLE permission errors checked on startup

## Development Guidelines

When modifying the codebase:
1. Follow existing Provider pattern for state management
2. Use ServiceManager for service initialization
3. Handle BLE permissions appropriately for each platform
4. Test on both iOS and Android due to BLE differences
5. Ensure firmware changes are compatible with existing protocol

## Documentation Structure

### Key Documentation Files
- `REPORT.md`: Original Omi app architecture analysis
- `FIRMWARE_REPORT.md`: Firmware analysis with button implementation details
- `OTA_DFU_REPORT.md`: OTA/DFU implementation guide
- `FIRMWARE_BUILD_AND_OTA.md`: Step-by-step build instructions
- `tracking.md`: Implementation progress tracker

### Recommended Documentation Improvements
When working with documentation:
1. Consider moving technical reports to a `docs/` directory
2. Update README.md to replace generic Flutter template
3. Create user-facing documentation for the minimal fork
4. Consolidate scattered firmware documentation
5. Add clear navigation between related documents