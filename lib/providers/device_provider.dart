import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart';
import 'package:omi_minimal_fork/main.dart';
import 'package:omi_minimal_fork/providers/capture_provider.dart';
import 'package:omi_minimal_fork/services/device_connection.dart';
import 'package:omi_minimal_fork/services/devices.dart';
import 'package:omi_minimal_fork/services/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:omi_minimal_fork/utils/audio/wav_bytes.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

const String _lastConnectedDeviceIdKey = 'last_connected_omi_id';

// UUIDs for Legacy DFU Trigger
final fbp.Guid _legacyDfuServiceGuid = fbp.Guid("00001530-1212-EFDE-1523-785FEABCD123");
final fbp.Guid _legacyDfuControlPointGuid = fbp.Guid("00001531-1212-EFDE-1523-785FEABCD123");

class MinimalDeviceProvider extends ChangeNotifier implements IDeviceServiceSubsciption {
  final IDeviceService _deviceService = ServiceManager.instance().device;
  List<BtDevice> discoveredDevices = [];
  DeviceConnectionState connectionState = DeviceConnectionState.disconnected;
  BtDevice? connectedDevice;
  DeviceConnection? activeConnection;
  bool isScanning = false;
  bool isConnecting = false;
  String? _lastConnectedDeviceId;

  // State for recording
  bool isRecording = false;
  List<String> savedRecordings = [];

  // --- Offline Recording Transfer Logic ---
  bool _isTransferring = false; // Flag to prevent simultaneous transfers

  WavBytesUtil? _wavBytesUtil;

  MinimalDeviceProvider() {
    _deviceService.subscribe(this, this);
    _loadLastDeviceAndAttemptConnect();
  }

  Future<void> _loadLastDeviceAndAttemptConnect() async {
    final prefs = await SharedPreferences.getInstance();
    _lastConnectedDeviceId = prefs.getString(_lastConnectedDeviceIdKey);
    if (_lastConnectedDeviceId != null) {
      debugPrint("[DeviceProvider] Found last connected device ID: $_lastConnectedDeviceId. Starting targeted scan...");
      await startScan(); 
    } else {
      debugPrint("[DeviceProvider] No last connected device ID found.");
    }
  }

  Future<void> _saveLastConnectedDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastConnectedDeviceIdKey, deviceId);
    _lastConnectedDeviceId = deviceId;
    debugPrint("[DeviceProvider] Saved last connected device ID: $deviceId");
  }

  Future<void> _clearLastConnectedDevice() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastConnectedDeviceIdKey);
      _lastConnectedDeviceId = null;
      debugPrint("[DeviceProvider] Cleared last connected device ID.");
  }

  Future<void> startScan() async {
     if (isScanning) return;
     isScanning = true;
     discoveredDevices = [];
     notifyListeners();
     try {
       debugPrint("[DeviceProvider] Starting scan (mainly for discovery, autoConnect handles connection attempt)...");
       await _deviceService.discover(desirableDeviceId: _lastConnectedDeviceId, timeout: 5); 
       debugPrint("[DeviceProvider] Scan finished.");
     } catch (e) {
       print("Error during discovery: $e");
     } finally {
       isScanning = false;
       notifyListeners();
     }
  }

  Future<void> connectToDevice(String deviceId) async {
     if (isConnecting || (connectionState == DeviceConnectionState.connected && activeConnection?.bleDevice.remoteId.toString() == deviceId)) {
         debugPrint("[DeviceProvider] connectToDevice($deviceId) called but already connecting or connected.");
         return; 
     }
     isConnecting = true;
     notifyListeners();
     debugPrint("[DeviceProvider] Requesting auto-connection to $deviceId via ensureConnection...");
     try {
       await _deviceService.ensureConnection(deviceId, force: true);
       debugPrint("[DeviceProvider] ensureConnection request sent for $deviceId. OS will auto-connect when device is seen.");
     } catch (e) {
       print("Error during connectToDevice call for $deviceId: $e"); 
       isConnecting = false;
       connectionState = DeviceConnectionState.disconnected;
       activeConnection = null; 
       notifyListeners();
     } 
  }

  Future<void> disconnect() async {
     if (activeConnection != null) {
        String? deviceId = activeConnection?.bleDevice.remoteId.toString();
        debugPrint("[DeviceProvider] Manual disconnect initiated for $deviceId");
        await activeConnection!.disconnect();
     } else {
        debugPrint("[DeviceProvider] Manual disconnect called but no active connection.");
     }
     await _clearLastConnectedDevice(); 
  }

  // --- Add prepareDFU method ---
  Future<void> prepareDFU() async {
    if (activeConnection == null) {
      debugPrint("[DeviceProvider] Cannot prepare DFU: No active connection.");
      throw Exception("Device not connected");
    }

    final device = activeConnection!.bleDevice;
    final deviceId = device.remoteId.toString();
    debugPrint("[DeviceProvider] Preparing DFU for device: $deviceId");

    try {
      // Optional: Disconnect gracefully first? Original app did this.
      // await disconnect(); 
      // await Future.delayed(const Duration(milliseconds: 500)); // Small delay after disconnect

      // Ensure device is connected before service discovery (if not disconnected above)
      // Note: This might reconnect if disconnect() was called. Adjust logic as needed.
      // If disconnect() is used, remove this connect block.
      if (device.connectionState != fbp.BluetoothConnectionState.connected) {
         debugPrint("[DeviceProvider] Reconnecting for DFU trigger..."); 
         await device.connect(autoConnect: false, timeout: Duration(seconds: 10));
         debugPrint("[DeviceProvider] Reconnected for DFU trigger.");
      }
      
      debugPrint("[DeviceProvider] Discovering services for DFU...");
      List<fbp.BluetoothService> services = await device.discoverServices();
      debugPrint("[DeviceProvider] Found ${services.length} services.");

      fbp.BluetoothService? dfuService;
      for (var s in services) {
          if (s.uuid == _legacyDfuServiceGuid) {
              dfuService = s;
              debugPrint("[DeviceProvider] Found Legacy DFU Service: ${dfuService.uuid}");
              break;
          }
      }

      if (dfuService == null) {
        debugPrint("[DeviceProvider] Error: Legacy DFU Service not found.");
        throw Exception("Legacy DFU Service not found");
      }

      fbp.BluetoothCharacteristic? controlPoint;
      for (var c in dfuService.characteristics) {
          if (c.uuid == _legacyDfuControlPointGuid) {
              controlPoint = c;
              debugPrint("[DeviceProvider] Found DFU Control Point Characteristic: ${controlPoint.uuid}");
              break;
          }
      }

      if (controlPoint == null) {
        debugPrint("[DeviceProvider] Error: DFU Control Point Characteristic not found.");
        throw Exception("DFU Control Point Characteristic not found");
      }

      debugPrint("[DeviceProvider] Writing DFU trigger command [0x01]...");
      // Command [0x01] seems commonly used with nordic_dfu/mcumgr combo
      // The firmware code shows handling for [0x01] and [0x06]
      await controlPoint.write([0x01], withoutResponse: false); 
      debugPrint("[DeviceProvider] DFU trigger command sent. Device should reset to DFU mode.");

      // Device will likely disconnect automatically after the write triggers reset.
      // Manually update state if needed, or rely on onDeviceConnectionStateChanged.
      // connectionState = DeviceConnectionState.disconnected;
      // connectedDevice = null;
      // activeConnection = null;
      // notifyListeners();

    } on TimeoutException catch (e) {
       debugPrint("[DeviceProvider] Timeout during DFU preparation for $deviceId: $e");
       // Handle timeout (e.g., inform user)
       throw Exception("Timeout preparing device for update");
    } catch (e) {
      debugPrint("[DeviceProvider] Error preparing DFU for $deviceId: $e");
      // Handle other errors
      throw Exception("Failed to prepare device for update: $e");
    }
  }
  // --- End of prepareDFU method ---

  void setRecordingState(bool recording) {
      if (isRecording == recording) return;
      isRecording = recording;
      debugPrint("[DeviceProvider] Recording state set to: $isRecording");
      notifyListeners();
  }

  void addRecording(String filePath) {
      savedRecordings.add(filePath);
      notifyListeners();
  }

  void removeRecording(String filePath) {
      savedRecordings.remove(filePath);
      notifyListeners();
  }

  @override
  void onDevices(List<BtDevice> devices) {
    discoveredDevices = devices;
    notifyListeners();
  }

  @override
  void onDeviceConnectionStateChanged(String deviceId, DeviceConnectionState state) {
    debugPrint("[DeviceProvider] <<< onDeviceConnectionStateChanged CALLED >>> DeviceId: $deviceId, State: $state"); 

    DeviceConnectionState previousState = connectionState;
    connectionState = state;
    isConnecting = false;
    
    this.activeConnection = null;

    if (state == DeviceConnectionState.connected) {
       DeviceConnection? connectionFromService = _deviceService.activeConnection; 

       if (connectionFromService != null && connectionFromService.bleDevice.remoteId.toString() == deviceId) {
          this.activeConnection = connectionFromService; 
          connectedDevice = discoveredDevices.firstWhere((d) => d.id == deviceId, 
               orElse: () => this.activeConnection!.device); 
          debugPrint("[DeviceProvider] Connection successful: $deviceId. Notifying CaptureProvider.");
          _saveLastConnectedDevice(deviceId); 
          _notifyCaptureProviderOfConnection(this.activeConnection!); 
          // Start real-time recording AND check for offline files
          _startAutoRecording(); 
          _checkAndTransferOfflineRecordings();
       } else {
          print("Error: Connected state reported, but service.activeConnection is null or ID mismatch.");
          print("Reported ID: $deviceId, Service Connection ID: ${connectionFromService?.bleDevice.remoteId.toString()}");
          connectedDevice = null;
          connectionState = DeviceConnectionState.disconnected;
          _notifyCaptureProviderOfDisconnection();
       }
    } else {
      connectedDevice = null;
      if (previousState == DeviceConnectionState.connected) {
         debugPrint("[DeviceProvider] Device disconnected: $deviceId");
         _notifyCaptureProviderOfDisconnection();
      }
    }
    notifyListeners();
  }

  void _startAutoRecording() {
      final context = MyApp.navigatorKey.currentContext;
      if (context != null && context.mounted) {
          try {
              debugPrint("[DeviceProvider] Automatically starting recording...");
              Provider.of<MinimalCaptureProvider>(context, listen: false).startRecording();
          } catch (e) {
              debugPrint("[DeviceProvider] Error auto-starting recording: $e");
          }
      } else {
          debugPrint("[DeviceProvider] Cannot auto-start recording: Context not available.");
      }
  }

  void _notifyCaptureProviderOfConnection(DeviceConnection connection) {
    final context = MyApp.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        Provider.of<MinimalCaptureProvider>(context, listen: false)
            .setActiveConnection(connection);
        debugPrint("[DeviceProvider] Notified CaptureProvider of active connection: ${connection.bleDevice.remoteId}"); 
      } catch (e) {
        debugPrint("[DeviceProvider] Error notifying CaptureProvider of connection: $e"); 
      }
    }
  }

  void _notifyCaptureProviderOfDisconnection() {
    final context = MyApp.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        Provider.of<MinimalCaptureProvider>(context, listen: false)
            .setActiveConnection(null);
        debugPrint("[DeviceProvider] Notified CaptureProvider of disconnection."); 
      } catch (e) {
        debugPrint("[DeviceProvider] Error notifying CaptureProvider of disconnection: $e");
      }
    }
  }

  @override
  void onStatusChanged(DeviceServiceStatus status) {
    print("DeviceService status changed: $status");
  }

  @override
  void dispose() {
    _deviceService.unsubscribe(this);
    super.dispose();
  }

  // --- Offline Recording Transfer Logic ---
  Future<void> _checkAndTransferOfflineRecordings() async {
    if (_isTransferring || activeConnection == null) return; 

    _isTransferring = true;
    debugPrint("[DeviceProvider] Checking for offline recordings...");
    try {
        List<int> rawFileList = await activeConnection!.performGetStorageList();
        // TODO: Parse rawFileList based on actual device response format
        // Assuming for now it returns a list of numerical file IDs (e.g., [1, 2, 3])
        List<int> fileIds = _parseFileList(rawFileList);
        debugPrint("[DeviceProvider] Found offline file IDs: $fileIds");

        if (fileIds.isNotEmpty) {
            for (int fileId in fileIds) {
               bool success = await _transferRecording(fileId);
               if (!success) {
                  debugPrint("[DeviceProvider] Failed to transfer file ID: $fileId. Stopping transfer.");
                  // Optionally: Retry logic or notify user
                  break; // Stop processing further files on failure
               }
               // Add a small delay between transfers
               await Future.delayed(const Duration(milliseconds: 500)); 
            }
        } else {
            debugPrint("[DeviceProvider] No offline recordings found.");
        }
    } catch (e) {
        debugPrint("[DeviceProvider] Error checking/transferring offline recordings: $e");
    } finally {
        _isTransferring = false;
    }
  }

  // Placeholder parser - NEEDS ACTUAL IMPLEMENTATION based on device spec
  List<int> _parseFileList(List<int> rawData) {
     // Implementation based on original omi_connection.dart
     if (rawData.isEmpty || rawData.length % 4 != 0) {
        debugPrint("[DeviceProvider] _parseFileList: Received empty or invalid length data (${rawData.length}).");
        return [];
     }
     List<int> fileIds = [];
     int totalEntries = (rawData.length / 4).toInt();
     debugPrint("[DeviceProvider] Parsing $totalEntries potential file entries from ${rawData.length} bytes.");

     for (int i = 0; i < totalEntries; i++) {
       int baseIndex = i * 4;
       // Read 4 bytes as signed 32-bit little-endian integer for file size
       // Use ByteData for easier endian handling
       ByteData byteData = ByteData.sublistView(Uint8List.fromList(rawData), baseIndex, baseIndex + 4);
       int fileSize = byteData.getInt32(0, Endian.little); 

       int fileId = i; // File ID is the index

       if (fileSize > 0) {
         debugPrint("[DeviceProvider] File ID $fileId found with size: $fileSize bytes.");
         fileIds.add(fileId);
       } else {
         // Optional: Log files with size 0 or less if needed for debugging
         // debugPrint("[DeviceProvider] File ID $fileId has size <= 0 ($fileSize), skipping.");
       }
     }
     debugPrint("[DeviceProvider] _parseFileList: Parsed File IDs with size > 0: $fileIds");
     return fileIds;
  }

  Future<bool> _transferRecording(int fileId) async {
     debugPrint("[DeviceProvider] Starting transfer for file ID: $fileId");
     List<int> receivedBytes = [];
     Completer<bool> transferCompleter = Completer();
     StreamSubscription? dataSubscription;
     bool receivedDataPacket = false; // Flag to track if we got actual data

     try {
       // 1. Setup listener for data stream
       dataSubscription = await activeConnection!.performGetBleStorageBytesListener(
         onStorageBytesReceived: (dataChunk) {
           // Check for single-byte status codes first
           if (dataChunk.length == 1) {
              int statusCode = dataChunk[0];
              debugPrint("[DeviceProvider] Received status code: $statusCode for file $fileId");
              if (statusCode == 100) { // 100 = valid end command?
                 if (!transferCompleter.isCompleted) transferCompleter.complete(true);
              } else if (statusCode == 3) { // Invalid size?
                 debugPrint("[DeviceProvider] Received status code 3 (Invalid Size?). Completing with error.");
                 if (!transferCompleter.isCompleted) transferCompleter.complete(false);
              } else if (statusCode == 4) { // Zero size?
                  debugPrint("[DeviceProvider] Received status code 4 (Zero Size?). Completing with error.");
                 if (!transferCompleter.isCompleted) transferCompleter.complete(false);
              } else if (statusCode == 0) {
                 debugPrint("[DeviceProvider] Received status code 0 (Valid command ack?). Ignoring, waiting for data or end code.");
                 // Ignore, likely just an ack for the read command
              } else {
                 // Other potential error codes
                  debugPrint("[DeviceProvider] Received unknown status code $statusCode. Completing with error.");
                 if (!transferCompleter.isCompleted) transferCompleter.complete(false);
              }
              // Don't process status codes as data
              return; 
           }

           // If not a status code, assume it's data
           if (dataChunk.isNotEmpty) {
               receivedDataPacket = true; // Mark that we received actual data
               
               // TODO: Check for specific data format (e.g., 83 bytes with header?)
               // For now, just concatenate
               receivedBytes.addAll(dataChunk);
               // debugPrint("[DeviceProvider] Received chunk for file $fileId, total bytes: ${receivedBytes.length}"); 
           } else { 
               // Handle unexpected empty packet AFTER receiving data (should ideally not happen if status codes are used)
               if (receivedDataPacket && !transferCompleter.isCompleted) {
                   debugPrint("[DeviceProvider] Received unexpected empty data chunk AFTER data. Assuming EOF for file $fileId.");
                   transferCompleter.complete(true); 
               } else if (!receivedDataPacket) {
                   debugPrint("[DeviceProvider] Received initial/unexpected empty data chunk for file $fileId, ignoring.");
               }
           }
         }
       );

       if (dataSubscription == null) {
          debugPrint("[DeviceProvider] Failed to subscribe to storage data stream for file $fileId.");
          return false;
       }

       // Add error handling for the data stream itself
       dataSubscription.onError((error) {
            debugPrint("[DeviceProvider] Error on storage data stream for file $fileId: $error");
            if (!transferCompleter.isCompleted) transferCompleter.complete(false);
            dataSubscription?.cancel(); // Clean up listener
       });
       // Add done handling (might indicate end of transfer)
       dataSubscription.onDone(() {
            debugPrint("[DeviceProvider] Storage data stream 'onDone' called for file $fileId.");
            if (!transferCompleter.isCompleted) transferCompleter.complete(true); // Assume done means success
       });

       // 2. Send "read file" command (Command Code 0)
       bool commandSent = await activeConnection!.performWriteToStorage(fileId, 0, 0); // READ_COMMAND = 0
       if (!commandSent) {
         debugPrint("[DeviceProvider] Failed to send read command for file $fileId.");
         await dataSubscription.cancel();
         return false;
       }
       debugPrint("[DeviceProvider] Read command sent for file $fileId. Waiting for data...");

       // 3. Wait for transfer to complete (or timeout)
       // TODO: Implement a robust timeout mechanism
       bool success = await transferCompleter.future.timeout(const Duration(seconds: 30), onTimeout: () {
           debugPrint("[DeviceProvider] Transfer timed out for file $fileId.");
           return false;
       });
       await dataSubscription.cancel(); // Ensure listener is cleaned up

       if (success && receivedBytes.isNotEmpty) {
         debugPrint("[DeviceProvider] Transfer successful for file $fileId. Received ${receivedBytes.length} bytes. Processing & Saving...");
         
         try {
           // ** Assume receivedBytes is a sequence of Opus frames (like online stream) **
           // ** We need WavBytesUtil to decode it and create the WAV file **
           if (_wavBytesUtil == null) {
               // We need a WavBytesUtil instance. Re-initialize if needed.
               // This assumes the codec is the same as the online stream (likely Opus)
               final codec = await activeConnection?.performGetAudioCodec() ?? BleAudioCodec.opus; 
               _wavBytesUtil = WavBytesUtil(codec: codec); 
               debugPrint("[DeviceProvider] Re-initialized WavBytesUtil for offline save (Codec: $codec).");
           }

           // TODO: This assumes receivedBytes is directly usable by createWavByCodec.
           // If the storage stream format differs significantly from the audio stream 
           // (e.g., different framing/headers), more complex parsing/reassembly is needed here 
           // before passing to createWavByCodec.
           // For now, treat receivedBytes as a single large frame or sequence of frames.
           List<List<int>> framesToDecode = [receivedBytes]; // Treat as one chunk for now

           final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
           final filenameStem = 'offline-recording-$fileId-$timestamp'; 

           // Use createWavByCodec to handle decoding and saving
           File wavFile = await _wavBytesUtil!.createWavByCodec(framesToDecode, filename: filenameStem);
           final filePath = wavFile.path;

           if (filePath.isEmpty) {
              debugPrint("[DeviceProvider] Error: createWavByCodec failed for offline file $fileId.");
              return false; // Don't delete if save failed
           } else {
              debugPrint("[DeviceProvider] Saved offline recording via WavBytesUtil: $filePath");
              addRecording(filePath); 

              debugPrint("[DeviceProvider] Sending delete command for file $fileId.");
              await activeConnection!.performWriteToStorage(fileId, 1, 0); 
              return true;
           }
         } catch(e, stackTrace) {
            debugPrint("[DeviceProvider] Error processing/saving offline WAV file $fileId: $e\n$stackTrace");
            return false; // Don't delete if save failed
         }
       } else {
         debugPrint("[DeviceProvider] Transfer failed or received no data for file $fileId.");
         return false;
       }

     } catch (e) {
       debugPrint("[DeviceProvider] Error during _transferRecording for file $fileId: $e");
       await dataSubscription?.cancel(); // Ensure cleanup on error
       return false;
     }
  }
} 