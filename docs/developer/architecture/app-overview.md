# Omi App Analysis Report

## Overview

The Omi app is a Flutter-based mobile application that interfaces with the Omi hardware device, a wearable audio capture device that enables real-time conversation recording, transcription, and AI-powered processing. The app serves as the bridge between the hardware device and various backend services.

## Hardware Interface

### Device Communication

The Omi device communicates with the mobile app via Bluetooth Low Energy (BLE) with the following key characteristics:

1. **Core Service UUID**: `19b10000-e8f2-537e-4f6c-d104768a1214`
2. **Key Characteristics**:
   - Audio Data Stream: `19b10001-e8f2-537e-4f6c-d104768a1214`
   - Audio Codec: `19b10002-e8f2-537e-4f6c-d104768a1214`
   - Battery Service: `0000180f-0000-1000-8000-00805f9b34fb`
   - Battery Level: `00002a19-0000-1000-8000-00805f9b34fb`
   - Button Service: `23ba7924-0000-1000-7450-346eac492e92`
   - Button Trigger: `23ba7925-0000-1000-7450-346eac492e92`

### Audio Capabilities

The device supports multiple audio codecs:
1. PCM8 (8kHz sampling rate)
2. PCM16 (16kHz sampling rate)
3. Opus (16kHz sampling rate) - Primary codec used for better compression
4. μLaw8 and μLaw16 (supported but not commonly used)

### Device Features

1. **Audio Streaming**: Real-time audio capture and streaming via BLE
2. **Battery Monitoring**: Real-time battery level reporting
3. **Button Interface**: Hardware button for user interaction
4. **Storage**: On-device storage capabilities for offline recording
5. **Accelerometer**: Motion detection capabilities

## Essential Components for a Minimal Implementation

### Core Files Required

1. **Device Connection** (`app/lib/services/devices/omi_connection.dart`):
   - Handles BLE device discovery and connection
   - Manages device services and characteristics
   - Essential for any hardware interaction

2. **Audio Processing** (`app/lib/utils/audio/wav_bytes.dart`):
   - Handles audio codec conversion
   - Manages audio frame processing
   - Required for audio capture

3. **Device Models** (`app/lib/backend/schema/bt_device/bt_device.dart`):
   - Defines device types and capabilities
   - Handles device information management

### App Initialization and Service Management (`app/lib/main.dart`)

- **Entry Point**: The `main` function serves as the app's entry point.
- **Core Initialization (`_init` function)**:
    - `ServiceManager.init()`: Initializes the central service manager.
    - `ServiceManager.instance().start()`: **Crucially, this starts the underlying services**, including the `DeviceService` which handles BLE operations. A minimal fork *must* ensure this service management pattern is replicated or replaced appropriately.
    - `initOpus`: Initializes the Opus codec library, required if handling Opus audio streams from the device.
- **State Management (`MultiProvider`)**:
    - The app uses the `provider` package extensively.
    - `DeviceProvider`: Central provider managing device state and likely interacting with `DeviceService`. Depends on `CaptureProvider`.
    - `CaptureProvider`: Likely handles the incoming audio stream data.
    - A minimal fork needs to replicate the setup for essential providers (`DeviceProvider`, potentially `CaptureProvider` depending on how audio is handled) or implement an alternative state management solution for the device connection and audio data.
- **Lifecycle**: The `ServiceManager` handles service shutdown via `_deinit` in `_MyAppState`.

### Device Discovery and Connection (`app/lib/services/devices.dart`)

- **Central Hub (`DeviceService`)**: This class orchestrates BLE interactions.
- **Discovery (`discover` method)**:
    - Uses `FlutterBluePlus.startScan` to find nearby devices advertising the Omi service UUID.
    - Listens to `FlutterBluePlus.scanResults`.
    - `_onBleDiscovered`: Processes results, converts `ScanResult` to `BtDevice` model, notifies subscribers.
- **Connection (`ensureConnection` method)**:
    - Primary method for requesting a connection to a specific `deviceId`.
    - Checks existing connection status and device responsiveness (ping).
    - Calls `_connectToDevice` if a new connection is required.
- **Connection Handling (`_connectToDevice` method)**:
    - Uses `DeviceConnectionFactory.create` to get an instance of `OmiDeviceConnection` (for Omi hardware).
    - Calls the `connect()` method on the `OmiDeviceConnection` instance, establishing the actual BLE connection and service discovery.
- **State Updates (Subscription Pattern)**:
    - `subscribe`/`unsubscribe`: Allows other components (like `DeviceProvider`) to react to changes in the discovered device list (`onDevices`) and connection status (`onDeviceConnectionStateChanged`).
- **Minimal Fork Considerations**:
    - A minimal fork needs a similar service to manage scanning (`FlutterBluePlus.startScan`) and connection initiation (`OmiDeviceConnection.connect`).
    - The subscription pattern (or an alternative event/stream mechanism) is crucial for notifying other parts of the app about connection state changes.

### Connection State Management (`app/lib/providers/device_provider.dart`)

- **Role**: Acts as the primary state holder for the connected device, bridging `DeviceService` with the UI and other providers.
- **Subscription**: Implements `IDeviceServiceSubsciption` and subscribes to `DeviceService` to receive connection updates.
- **State Handling (`onDeviceConnectionStateChanged`)**:
    - **On Connect**: Updates `isConnected` state, stores the `BtDevice`, fetches device info, starts battery monitoring (`initiateBleBatteryListener`), cancels reconnection attempts, and notifies listeners. **Crucially, it passes the active `DeviceConnection` object to `CaptureProvider` via `captureProvider?.updateRecordingDevice(conn)`**. This is the likely trigger for audio streaming to begin.
    - **On Disconnect**: Updates state, clears device info, notifies `CaptureProvider`, and restarts the periodic reconnection logic (`periodicConnect`).
- **Connection Maintenance**: Uses `scanAndConnectToDevice` and `periodicConnect` to automatically find and reconnect to the last known device (stored in `SharedPreferencesUtil`).
- **Minimal Fork Considerations**:
    - A state management solution (like a simplified Provider or another pattern) is needed to hold the current `BtDevice` and `isConnected` status.
    - Logic is required to react to connection events from the underlying BLE service.
    - The handoff mechanism to start audio streaming upon connection (passing the active connection object) needs to be replicated.
    - Reconnection logic might be desirable but isn't strictly essential for a minimal version.

### Audio Stream Handling (`app/lib/providers/capture_provider.dart`)

- **Role**: Manages the active audio capture session, receiving audio data from the connected device and forwarding it.
- **Receiving Connection**: The `updateRecordingDevice` method receives the active `DeviceConnection` object from `DeviceProvider` when a connection is established.
- **Starting Audio Stream (`streamAudioToWs` method)**:
    - This method (or similar logic triggered by `updateRecordingDevice`) initiates the audio stream.
    - It calls `_getBleAudioBytesListener` (which wraps `OmiDeviceConnection.performGetBleAudioBytesListener`).
    - **The `onAudioBytesReceived` callback within this call is the core of the audio pipeline**: It receives raw byte lists (`List<int>`) directly from the BLE characteristic.
    - In the original app, these bytes are forwarded to a WebSocket (`_socket?.send(value)`) for real-time transcription.
- **WebSocket Management**: Manages the connection (`_initiateWebsocket`) to the backend transcription service, configuring it based on the device's audio codec.
- **Minimal Fork Considerations**:
    - A component (like a simplified `CaptureProvider`) is needed to:
        - Receive the active `DeviceConnection` upon successful connection.
        - Call `performGetBleAudioBytesListener` on the connection.
        - **Implement the `onAudioBytesReceived` callback.** This is where the minimal fork diverges: instead of sending to a WebSocket, this callback would:
            - Pass the raw bytes (potentially after Opus decoding if applicable) to your custom processing function/service.
            - Handle frame assembly/buffering as needed (potentially leveraging parts of `WavBytesUtil`).
    - The original app's WebSocket logic (`TranscriptSegmentSocketService`) can likely be removed entirely in a minimal fork.
    - Handling button presses (`streamButton`) is optional depending on requirements.

### Audio Packet Assembly & Decoding (`app/lib/utils/audio/wav_bytes.dart`)

- **Role**: Handles reassembly of potentially fragmented BLE packets into complete audio frames and performs codec-specific operations.
- **Packet Assembly (`storeFramePacket`)**:
    - Receives raw `List<int>` from the BLE callback.
    - Uses packet index and internal frame ID bytes within the list to detect lost packets and group bytes belonging to the same audio frame.
    - Stores completed frames in the `frames` list.
- **Opus Decoding (`createWavByCodec`)**:
    - Iterates through assembled `frames`.
    - Uses `SimpleOpusDecoder.decode` to convert each Opus frame (`List<int>`) into PCM samples.
- **WAV Conversion**: Provides utilities (`getUInt8ListBytes`, `getWavHeader`) to format PCM samples into a standard WAV byte structure.
- **Minimal Fork Considerations**:
    - **Crucial**: If dealing with Opus or needing guaranteed complete audio frames, the logic from `storeFramePacket` *must* be replicated or adapted to correctly reassemble data from the BLE characteristic callback.
    - Opus decoding logic is required if the device sends Opus and the target service needs PCM.
    - WAV conversion utilities can be reused if WAV output is desired.
    - If simply forwarding raw BLE packets is sufficient, this component might be simplified, but packet fragmentation must be considered.

### Connection Trigger UI (`app/lib/pages/onboarding/device_selection.dart`, `app/lib/pages/onboarding/wrapper.dart`)

- **Flow**: The connection process is typically user-initiated:
    1.  User presses a button (e.g., "Connect omi" in `DeviceSelectionPage`).
    2.  App navigates to a screen/component responsible for scanning/connection (e.g., `OnboardingWrapper`).
    3.  This component likely triggers `DeviceService.discover()` and displays found devices.
    4.  User selects a device, triggering `DeviceService.ensureConnection(selectedDeviceId)`.
- **Minimal Fork Considerations**:
    - A minimal UI needs:
        - A button/action to start scanning (`DeviceService.discover`).
        - A way to display discovered devices (listening to `DeviceService` updates).
        - A way to select a device and trigger connection (`DeviceService.ensureConnection`).
        - Basic status indication (Scanning, Connecting, Connected, Error).

## Plan of Action for Minimal Fork

This plan outlines the steps to create a minimal Flutter application that connects to the Omi hardware, streams audio data, saves it as playable/shareable files, and optionally transcribes it locally.

1.  **Project Setup**:
    *   Create a new Flutter project.
    *   Add necessary dependencies from the original `pubspec.yaml`, including:
        *   `flutter_blue_plus` (for BLE)
        *   `provider` (or alternative state management)
        *   `opus_dart` / `opus_flutter` (likely needed for decoding)
        *   `permission_handler` (for permissions)
        *   `path_provider` (to find storage directories)
        *   `share_plus` (for sharing files)
        *   `just_audio` (or similar for playback)
        *   (Optional) `whisper_flutter` (or similar Whisper package)
        *   Core Dart/Flutter packages.
    *   Copy essential files identified in this report:
        *   `app/lib/services/devices/` (all files)
        *   `app/lib/backend/schema/bt_device/bt_device.dart`
        *   `app/lib/utils/audio/wav_bytes.dart` (especially `storeFramePacket`, `createWavByCodec`, `createWav`, `getWavHeader`, `convertToLittleEndianBytes`)
        *   `app/lib/services/services.dart` (adapted for minimal needs)
        *   Related constants/UUIDs.

2.  **Permissions Handling**:
    *   Implement logic (e.g., using `permission_handler`) to request necessary permissions (Bluetooth Scan, Bluetooth Connect, Location, potentially Storage/Media Library access depending on saving/sharing implementation) at app startup or before scanning.

3.  **Core Service Initialization (`main.dart`)**:
    *   Adapt the `main` and `_init` logic.
    *   Initialize `WidgetsFlutterBinding`.
    *   Initialize and start a minimal `ServiceManager` (including `DeviceService`).
    *   Initialize Opus codec (`initOpus`).
    *   Set up minimal state management (`MinimalDeviceProvider`).

4.  **Minimal UI Implementation**:
    *   Create a simple screen (`HomePage` or similar).
    *   Add a button to trigger `DeviceService.discover()`.
    *   Display a list of discovered devices.
    *   Allow selection of a device to trigger `DeviceService.ensureConnection(selectedDeviceId)`.
    *   Show basic connection status (Scanning, Connecting, Connected, Disconnected, Error).
    *   **Add Start/Stop Recording buttons** (enabled when connected).
    *   **Display a list of saved recordings** (file paths/names retrieved from state).
    *   **For each recording, provide buttons for Play, Share, Delete, and (Optional) Transcribe.**

5.  **State Management (`MinimalDeviceProvider`)**:
    *   Create a simplified provider/state manager.
    *   Subscribe to `DeviceService`.
    *   Hold `discoveredDevices` list, `connectionState`, and the active `DeviceConnection`.
    *   Implement `onDevices` and `onDeviceConnectionStateChanged`.
    *   **Add state for `isRecording` (bool).**
    *   **Add state for `savedRecordings` (List<String> of file paths).** Manage adding/removing paths here.

6.  **Audio Capture & Saving Component (`MinimalCaptureProvider`)**:
    *   Create a component/provider to handle the audio stream and recording logic.
    *   Receive the active `DeviceConnection` from `MinimalDeviceProvider`.
    *   **Manage recording state**: Have methods like `startRecording()` and `stopRecordingAndSave()` triggered by UI buttons.
    *   **Implement Audio Streaming**: When connected, call `connection.performGetBleAudioBytesListener`.
    *   **Implement `onAudioBytesReceived`**: 
        *   Use the `storeFramePacket` logic from `WavBytesUtil` to reassemble complete audio frames (essential for saving usable audio).
        *   If `isRecording` is true, add the assembled frame to a temporary list (`currentRecordingFrames`).
    *   **Implement `stopRecordingAndSave()`**:
        *   Set `isRecording` to false.
        *   Check if `currentRecordingFrames` is not empty.
        *   Use `WavBytesUtil.createWavByCodec` to decode Opus frames in the list to PCM.
        *   Use `WavBytesUtil.createWav` to save the PCM data to a `.wav` file in a directory obtained via `path_provider` (e.g., `getApplicationDocumentsDirectory` or `getTemporaryDirectory`). Give it a unique name (e.g., timestamp-based).
        *   Add the resulting file path to the `savedRecordings` list in `MinimalDeviceProvider`.
        *   Clear `currentRecordingFrames`.

7.  **Post-Processing & Interaction Implementation**:
    *   **Playback**: Use `just_audio` (or similar) to play the WAV file when the Play button is pressed.
    *   **Sharing**: Use `share_plus` to share the WAV file when the Share button is pressed.
    *   **Deletion**: Delete the WAV file from storage and remove its path from the state when the Delete button is pressed.
    *   **(Optional) Transcription**: 
        *   If the Whisper package is included, implement the Transcribe button action.
        *   Pass the WAV file path to the Whisper transcription function.
        *   Display the resulting text (e.g., in a dialog, bottom sheet, or separate view).

8.  **Error Handling**:
    *   Add basic `try-catch` blocks around BLE operations, file operations, playback, sharing, and transcription.
    *   Update UI state to reflect errors.

9.  **Cleanup**: Ensure `ServiceManager.stop()` is called when the app closes.

10. **Testing and Refinement**: Test recording start/stop, file saving, playback, sharing, deletion, and optional transcription.

### Minimal Implementation Steps

1. **Basic Setup**:
   ```dart
   // Initialize BLE connection
   final connection = OmiDeviceConnection(device, bleDevice);
   await connection.connect();
   
   // Set up audio stream
   await connection.performGetBleAudioBytesListener(
     onAudioBytesReceived: (bytes) {
       // Process audio bytes
     }
   );
   ```

2. **Audio Processing**:
   - Implement audio codec detection and decoding
   - Handle audio frame reassembly
   - Convert to desired format (WAV/PCM)

3. **Custom Integration**:
   - Add your AI service configuration
   - Implement custom audio processing
   - Set up your data pipeline

4. **Ensure Proper Service Shutdown**:
   - Ensure proper service shutdown on app termination.

## Customization Points

1. **Audio Processing Pipeline**:
   - Replace the existing transcription service
   - Implement custom audio processing
   - Add real-time audio analysis

2. **Data Handling**:
   - Modify how audio data is stored
   - Change the format of processed data
   - Implement custom data transmission

3. **User Interface**:
   - Simplify the UI to basic device controls
   - Add custom visualization
   - Implement specific use case interfaces

## Technical Considerations

1. **BLE Connection**:
   - Handle MTU size (512 bytes recommended)
   - Manage connection state
   - Implement reconnection logic

2. **Audio Processing**:
   - Handle frame synchronization
   - Manage codec conversion
   - Consider buffer sizes and latency

3. **Resource Management**:
   - Monitor battery usage
   - Handle storage efficiently
   - Manage memory usage for audio processing

## Getting Started with a Fork

1. **Initial Setup**:
   ```bash
   # Clone the repository
   git clone https://github.com/BasedHardware/Omi.git
   cd Omi/app
   
   # Install dependencies
   flutter pub get
   ```

2. **Minimal Configuration**:
   - Remove unnecessary services and UI components
   - Keep core device communication
   - Implement basic audio handling

3. **Custom Integration**:
   - Add your AI service configuration
   - Implement custom audio processing
   - Set up your data pipeline

## Conclusion

The Omi app provides a robust foundation for BLE audio device communication. By focusing on the core device interface components, you can create a streamlined version that maintains essential functionality while adding your own custom features and integrations. The modular architecture makes it straightforward to remove unnecessary components while keeping the critical hardware interface intact. 

### Minimal `main.dart` Considerations

When forking, your `main.dart` or equivalent entry point must:

1.  Initialize necessary bindings (`WidgetsFlutterBinding.ensureInitialized()`).
2.  Initialize and start the `ServiceManager` (or a replacement mechanism) to activate the `DeviceService`.
3.  Initialize the Opus codec if needed (`initOpus`).
4.  Set up the required state management (e.g., `DeviceProvider`) to handle device state and interactions.
5.  Ensure proper service shutdown on app termination. 