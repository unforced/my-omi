# Documentation Index

Welcome to the Omi Minimal Fork documentation. This index provides navigation to all available documentation.

## 📚 Documentation Categories

### For Users

- **[Getting Started Guide](user/getting-started.md)** - First-time setup and basic usage
- **[Features Overview](user/features.md)** - Detailed feature descriptions
- **[Troubleshooting](user/troubleshooting.md)** - Common issues and solutions

### For Developers

#### Architecture
- **[App Architecture Overview](developer/architecture/app-overview.md)** - Flutter app structure and design patterns
- **[Firmware Architecture Overview](developer/architecture/firmware-overview.md)** - Firmware components and button implementation
- **[OTA Implementation](developer/architecture/ota-implementation.md)** - Over-the-air update system details

#### Setup Guides
- **[Flutter Development Setup](developer/setup/flutter-setup.md)** - Setting up the Flutter development environment
- **[Firmware Build Guide](developer/setup/firmware-build.md)** - Building firmware with Docker or nRF SDK
- **[Docker Build Guide](developer/setup/docker-build.md)** - Detailed Docker build instructions

#### Development Guides
- **[Contributing Guidelines](developer/guides/contributing.md)** - How to contribute to the project
- **[Firmware Update Implementation](developer/guides/firmware-update-implementation.md)** - Implementing OTA updates

#### Technical Reference
- **[Firmware Build Status](developer/reference/firmware-build-status.md)** - Build issues and solutions
- **[Firmware Build Success](developer/reference/firmware-build-success.md)** - Working build configurations
- **[Firmware Update Summary](developer/reference/firmware-update-summary.md)** - Update implementation details

### Project Information

- **[Progress Tracking](project/progress.md)** - Current implementation status
- **[Roadmap](project/roadmap.md)** - Future development plans
- **[Changelog](project/changelog.md)** - Version history and changes

## 🚀 Quick Links

### Essential Documents
1. **[Main README](../README.md)** - Project overview and quick start
2. **[CLAUDE.md](../CLAUDE.md)** - AI assistant guidance for development
3. **[Firmware Build Guide](developer/setup/firmware-build.md)** - Step-by-step firmware building

### Common Tasks
- [Run the Flutter app](user/getting-started.md#running-the-app)
- [Build firmware with Docker](developer/setup/firmware-build.md#docker-build)
- [Update device firmware](user/features.md#firmware-updates)
- [Debug BLE connections](user/troubleshooting.md#bluetooth-issues)

## 📋 Documentation Status

| Document | Status | Last Updated |
|----------|--------|--------------|
| Getting Started | ✅ Complete | December 2024 |
| App Architecture | ✅ Complete | Migrated from REPORT.md |
| Firmware Architecture | ✅ Complete | Migrated from FIRMWARE_REPORT.md |
| OTA Implementation | ✅ Complete | Migrated from OTA_DFU_REPORT.md |
| Firmware Build Guide | ✅ Complete | Migrated from FIRMWARE_BUILD_AND_OTA.md |
| Contributing Guide | ✅ Complete | December 2024 |
| Progress Tracking | ✅ Complete | Migrated from tracking.md |

## 🔍 Finding Information

### By Topic
- **Hardware/Firmware**: Start with [Firmware Architecture](developer/architecture/firmware-overview.md)
- **Mobile App**: Start with [App Architecture](developer/architecture/app-overview.md)
- **Building/Compiling**: See [Setup Guides](developer/setup/)
- **Bluetooth/BLE**: Check [BLE Protocol Reference](developer/reference/ble-protocol.md)

### By Task
- **"I want to build the firmware"** → [Firmware Build Guide](developer/setup/firmware-build.md)
- **"I want to understand the button behavior"** → [Firmware Architecture](developer/architecture/firmware-overview.md#button-handling)
- **"I want to add a new feature"** → [Contributing Guidelines](developer/guides/contributing.md)
- **"I'm having connection issues"** → [Troubleshooting](user/troubleshooting.md)

## 📝 Contributing to Documentation

When adding or updating documentation:
1. Follow the existing structure and naming conventions
2. Update this index when adding new documents
3. Mark document status in the table above
4. Cross-reference related documents
5. Keep technical details in developer docs, user-friendly content in user docs