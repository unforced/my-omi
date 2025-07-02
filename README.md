# Omi Minimal Fork

A streamlined implementation of the Omi wearable AI device, focusing on core audio capture and BLE connectivity features.

## Overview

This is a minimal fork of the [Omi project](https://github.com/BasedHardware/omi) that provides:
- 🎙️ Real-time audio streaming from Omi hardware to mobile app
- 📱 Cross-platform Flutter application (iOS, Android, Desktop)
- 🔊 Offline audio recording with device storage
- 🔄 Over-the-air (OTA) firmware updates
- 🎯 Simplified, focused feature set for audio capture

## Key Features

### Mobile Application
- **BLE Device Discovery**: Automatic scanning and connection to Omi devices
- **Audio Streaming**: Real-time audio capture with Opus codec support
- **Recording Management**: Save, play, share, and delete audio recordings
- **Firmware Updates**: Built-in OTA/DFU support for keeping device up-to-date
- **Cross-Platform**: Runs on iOS, Android, macOS, Windows, and Linux

### Firmware
- **Zephyr RTOS**: Built on robust real-time operating system
- **Audio Codecs**: PCM8/16, Opus, and μLaw support
- **Offline Recording**: Continue recording when disconnected from app
- **Button Controls**: Configurable button gestures for device control
- **Low Power**: Optimized for extended battery life

## Quick Start

### Prerequisites
- Flutter SDK (latest stable)
- For firmware development: Docker or nRF Connect SDK v2.7.0
- Omi hardware device or compatible nRF52840 development board

### Running the App

```bash
# Clone the repository
git clone https://github.com/yourusername/my-omi.git
cd my-omi

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Building Firmware

```bash
# Using Docker (recommended)
cd firmware
./scripts/build-docker.sh

# The firmware package will be at:
# firmware/build/docker_build/zephyr.zip
```

## Documentation

Comprehensive documentation is available in the [`docs/`](docs/) directory:

- [Documentation Index](docs/README.md) - Start here for navigation
- [Getting Started Guide](docs/user/getting-started.md) - First-time setup
- [Architecture Overview](docs/developer/architecture/) - Technical deep-dives
- [Build Instructions](docs/developer/setup/firmware-build.md) - Detailed build guides

## Current Status

This minimal fork implements core functionality while removing complex features from the original Omi project. See [progress tracking](docs/project/progress.md) for implementation status.

### What's Working
- ✅ BLE connection and device discovery
- ✅ Audio streaming and recording
- ✅ File management (save/play/share/delete)
- ✅ Firmware OTA updates
- ✅ Basic UI for all core features

### Recent Updates (December 2024)
- ✅ Button controls implemented (single tap = record toggle)
- ✅ Visual button event indicators in app
- ✅ Automatic firmware updates (v2.0.10 bundled)
- ✅ Improved firmware version detection

## Contributing

We welcome contributions! Please see our [contributing guidelines](docs/developer/guides/contributing.md) for details on:
- Code style and standards
- Testing requirements
- Pull request process
- Issue reporting

## Hardware

This project is designed for Omi hardware devices based on the nRF52840 chip. Compatible boards include:
- Omi v1/v2 devices
- Seeed XIAO nRF52840 Sense (for development)
- Custom boards following Omi specifications

## License

This project inherits the license from the original Omi project. See [LICENSE](LICENSE) for details.

## Acknowledgments

This minimal fork is based on the excellent work of the [Based Hardware](https://github.com/BasedHardware) team and the Omi community. We've focused on simplifying the codebase while maintaining core functionality for audio capture use cases.