import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart';
import 'package:omi_minimal_fork/providers/device_provider.dart';
import 'package:omi_minimal_fork/services/device_connection.dart';
import 'package:omi_minimal_fork/utils/audio/wav_bytes.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart'; // Added
import 'package:intl/intl.dart'; // Added for timestamp filenames
import 'package:omi_minimal_fork/main.dart'; // Import MyApp for navigatorKey

class MinimalCaptureProvider extends ChangeNotifier {
  DeviceConnection? _activeConnection;
  StreamSubscription? _audioBytesSubscription;
  StreamSubscription? _buttonSubscription; // Optional button handling

  WavBytesUtil? _wavBytesUtil;
  bool _loggedFirstBytes = false;
  bool _isRecording = false; // Added recording state flag
  int _frameCount = 0; // Added frame counter for logging

  // Method called by MinimalDeviceProvider when connection state changes
  void setActiveConnection(DeviceConnection? connection) {
    _activeConnection = connection;
    _loggedFirstBytes = false;
    _audioBytesSubscription?.cancel();
    _buttonSubscription?.cancel();
    _audioBytesSubscription = null;
    _buttonSubscription = null;

    if (_activeConnection != null) {
      _wavBytesUtil = null; // Reset WAV util only when starting a new connection setup
      debugPrint("[CaptureProvider] Received active connection: ${_activeConnection!.bleDevice.remoteId}");
      _initializeForConnection(_activeConnection!); 
    } else {
      debugPrint("[CaptureProvider] Received null connection (disconnected). Checking recording state...");
      bool wasRecording = _isRecording;
      debugPrint("[CaptureProvider] _isRecording state on disconnect: $wasRecording");
      if (wasRecording) {
        debugPrint("[CaptureProvider] Was recording, calling stopRecordingAndSave().");
        stopRecordingAndSave();
      } else {
         debugPrint("[CaptureProvider] Was NOT recording, doing nothing.");
      }
    }
  }

  // Initialize based on the specific connection's properties
  Future<void> _initializeForConnection(DeviceConnection connection) async {
    debugPrint("[CaptureProvider] Initializing for connection...");
    try {
      // Determine the codec from the device
      final codec = await connection.performGetAudioCodec();
      debugPrint("[CaptureProvider] Determined Codec: $codec");

      // Initialize WavBytesUtil with the determined codec
      // Assumes WavBytesUtil constructor accepts a codec parameter
      _wavBytesUtil = WavBytesUtil(codec: codec); 
      debugPrint("[CaptureProvider] Initialized WavBytesUtil with codec $codec.");

      // Start listening to audio bytes only after initialization
      _startAudioStream(connection);

      // Optional: Start listening to button presses
      // _startButtonStream(connection);
    } catch (e, stackTrace) {
        debugPrint("[CaptureProvider] Error during initialization: $e\n$stackTrace");
        // Handle initialization failure (e.g., notify UI, disconnect)
        setActiveConnection(null); // Trigger disconnect flow
    }
  }

  void _startAudioStream(DeviceConnection connection) async {
    debugPrint("[CaptureProvider] Attempting to start audio stream...");
    _audioBytesSubscription?.cancel(); // Cancel previous subscription
    try {
      // Get the subscription first
      _audioBytesSubscription = await connection.performGetBleAudioBytesListener(
        onAudioBytesReceived: (bytes) {
          // Log first few bytes received ONCE
          if (_wavBytesUtil != null && !_loggedFirstBytes) { 
            debugPrint("[CaptureProvider] Received first audio bytes chunk (len=${bytes.length}): ${bytes.take(10).toList()}...");
            _loggedFirstBytes = true; 
          }

          // Check recording state BEFORE processing/storing
          final context = MyApp.navigatorKey.currentContext;
          bool currentlyRecording = false;
          if (context != null && context.mounted) {
              final provider = Provider.of<MinimalDeviceProvider>(context, listen: false);
              currentlyRecording = provider.isRecording; // Check state via provider
          }

          // Only store packet and increment count if actually recording
          if (currentlyRecording && _wavBytesUtil != null) {
             _wavBytesUtil!.storeFramePacket(bytes); // Store raw packet data
             _frameCount++; // Increment counter based on packets processed while recording
             
             // Log only occasionally
             if (_frameCount % 100 == 0) {
                 debugPrint("[CaptureProvider] Processed packet #${_frameCount} while recording."); 
             }
          } 
        },
      ); // End of performGetBleAudioBytesListener call

      // Handle errors and completion on the subscription itself
      _audioBytesSubscription?.onError((error) {
        print("Audio Stream Error: $error");
        // Attempt to clean up and notify UI or DeviceProvider
        setActiveConnection(null); // Indicate disconnection on error
      });

      _audioBytesSubscription?.onDone(() {
        print("Audio Stream Closed (onDone).");
        // Optionally handle stream closure, though setActiveConnection(null) usually covers this
      });

      if (_audioBytesSubscription == null) {
          print("Error: Failed to get audio stream subscription.");
          setActiveConnection(null);
      }

    } catch (e, stackTrace) {
      print("Error setting up audio stream subscription: $e\n$stackTrace");
      setActiveConnection(null);
    }
  }

  void _startButtonStream(DeviceConnection connection) {
      // Optional: Implement button listener similar to audio stream
      // Use connection.performGetBleButtonListener
  }

  // --- Recording Control --- 

  void startRecording() {
    if (_activeConnection == null || _isRecording) return;
    debugPrint("[CaptureProvider] Starting recording..."); 
    _isRecording = true;
    _frameCount = 0; 
    // Notify DeviceProvider to update its state
    _notifyDeviceProviderRecordingState(true);
    notifyListeners(); // Notify local listeners if any
  }

  Future<void> stopRecordingAndSave() async {
    if (!_isRecording) return;
    debugPrint("[CaptureProvider] Stopping recording. Total packets processed while recording: $_frameCount"); 
    _isRecording = false;
    _notifyDeviceProviderRecordingState(false);

    // Check frameCount collected during recording
    if (_frameCount <= 0) {
      debugPrint("[CaptureProvider] No packets processed during recording, nothing to save.");
      _wavBytesUtil?.clearAudioBytes(); // Clear any potential residual data
      notifyListeners();
      return;
    }

    if (_wavBytesUtil == null) {
        debugPrint("[CaptureProvider] Error: WavBytesUtil is null, cannot save.");
        notifyListeners(); 
        return;
    }

    // Finalize any pending frame data in WavBytesUtil
    _wavBytesUtil!.finalizeCurrentFrame();

    // Get the assembled frames directly from WavBytesUtil
    if (_wavBytesUtil!.frames.isEmpty) {
         debugPrint("[CaptureProvider] Frame count was > 0, but WavBytesUtil.frames is empty after finalize. Frame assembly likely failed.");
         _wavBytesUtil!.clearAudioBytes(); 
         notifyListeners();
         return;
    }
    List<List<int>> framesToSave = List<List<int>>.from(_wavBytesUtil!.frames);
    _wavBytesUtil!.clearAudioBytes(); 
    
    try {
      debugPrint("[CaptureProvider] Processing ${framesToSave.length} assembled frames and saving WAV file...");
      // Use createWavByCodec assuming it handles Opus decoding and file writing
      // It likely needs a filename stem, not a full path
      final directory = await getApplicationDocumentsDirectory(); // Get dir just for context
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filenameStem = 'recording-$timestamp'; // Just the name part

      File wavFile = await _wavBytesUtil!.createWavByCodec(framesToSave, filename: filenameStem); 
      final filePath = wavFile.path;
      
      if (filePath.isEmpty) {
         debugPrint("[CaptureProvider] Error: createWavByCodec failed or returned empty path.");
      } else {
          debugPrint("[CaptureProvider] Recording saved successfully: $filePath");
          // Notify DeviceProvider to update the UI list
          final context = MyApp.navigatorKey.currentContext;
          if (context != null && context.mounted) {
              try {
                  Provider.of<MinimalDeviceProvider>(context, listen: false).addRecording(filePath);
                  debugPrint("[CaptureProvider] Notified DeviceProvider to add recording.");
              } catch (e) {
                  debugPrint("[CaptureProvider] Error notifying DeviceProvider: $e");
              }
          } else {
              debugPrint("[CaptureProvider] Could not notify DeviceProvider: Context not available.");
          }
      }
    } catch (e, stackTrace) {
      debugPrint("[CaptureProvider] Error saving recording: $e\n$stackTrace");
    } finally {
      notifyListeners(); // Update UI state (e.g., recording button)
    }
  }

  // Helper to notify DeviceProvider about recording state changes
  void _notifyDeviceProviderRecordingState(bool isRecording) {
      final context = MyApp.navigatorKey.currentContext;
      if (context != null && context.mounted) {
          try {
              Provider.of<MinimalDeviceProvider>(context, listen: false).setRecordingState(isRecording);
              debugPrint("[CaptureProvider] Notified DeviceProvider setRecordingState($isRecording).");
          } catch (e) {
              debugPrint("[CaptureProvider] Error notifying DeviceProvider setRecordingState: $e");
          }
      } else {
          debugPrint("[CaptureProvider] Could not notify DeviceProvider setRecordingState: Context not available.");
      }
  }

  @override
  void dispose() {
    _audioBytesSubscription?.cancel();
    _buttonSubscription?.cancel();
    super.dispose();
  }
} 