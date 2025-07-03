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

enum RecordingMode {
  standard,   // Single tap - normal recording
  aiQuery,    // Double tap - AI query
  knowledge,  // Triple tap - knowledge capture
}

class MinimalCaptureProvider extends ChangeNotifier {
  DeviceConnection? _activeConnection;
  StreamSubscription? _audioBytesSubscription;
  StreamSubscription? _buttonSubscription; // Optional button handling

  WavBytesUtil? _wavBytesUtil;
  bool _loggedFirstBytes = false;
  bool _isRecording = false; // Added recording state flag
  int _frameCount = 0; // Added frame counter for logging
  RecordingMode _currentMode = RecordingMode.standard;
  
  // Button event callback
  void Function(String)? onButtonEvent;

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

      // Start listening to button presses
      _startButtonStream(connection);
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

  void _startButtonStream(DeviceConnection connection) async {
    debugPrint("[CaptureProvider] Setting up button stream...");
    _buttonSubscription?.cancel();
    try {
      _buttonSubscription = await connection.performGetBleButtonListener(
        onButtonReceived: (bytes) {
          if (bytes.length >= 2) {
            int buttonEvent = bytes[0];
            debugPrint("[CaptureProvider] Button event received: $buttonEvent");
            
            String eventName = "";
            RecordingMode mode = RecordingMode.standard;
            
            switch (buttonEvent) {
              case 1: // SINGLE_TAP - Standard recording
                eventName = "Single Tap";
                mode = RecordingMode.standard;
                debugPrint("[CaptureProvider] Single tap detected - standard recording");
                if (_isRecording) {
                  stopRecordingAndSave(mode: mode);
                } else {
                  startRecording(mode: mode);
                }
                break;
              case 2: // DOUBLE_TAP - AI Query
                eventName = "Double Tap - AI Query";
                mode = RecordingMode.aiQuery;
                debugPrint("[CaptureProvider] Double tap detected - AI query mode");
                if (_isRecording) {
                  stopRecordingAndSave(mode: mode);
                } else {
                  startRecording(mode: mode);
                }
                break;
              case 3: // TRIPLE_TAP - Knowledge Capture
                eventName = "Triple Tap - Knowledge";
                mode = RecordingMode.knowledge;
                debugPrint("[CaptureProvider] Triple tap detected - knowledge capture mode");
                if (_isRecording) {
                  stopRecordingAndSave(mode: mode);
                } else {
                  startRecording(mode: mode);
                }
                break;
              case 4: // LONG_TAP (Long press)
                eventName = "Long Press";
                debugPrint("[CaptureProvider] Long press detected - device will power off");
                // Device handles power off in firmware
                break;
              case 5: // BUTTON_PRESS
                eventName = "Button Down";
                debugPrint("[CaptureProvider] Button pressed down");
                break;
              case 6: // BUTTON_RELEASE
                eventName = "Button Up";
                debugPrint("[CaptureProvider] Button released");
                break;
            }
            
            // Notify UI about button event
            if (eventName.isNotEmpty && onButtonEvent != null) {
              onButtonEvent!(eventName);
            }
          }
        },
      );
      debugPrint("[CaptureProvider] Button stream subscription established");
    } catch (e) {
      debugPrint("[CaptureProvider] Error setting up button stream: $e");
    }
  }

  // --- Recording Control --- 

  void startRecording({RecordingMode mode = RecordingMode.standard}) {
    if (_activeConnection == null || _isRecording) return;
    debugPrint("[CaptureProvider] Starting recording in mode: $mode"); 
    _isRecording = true;
    _currentMode = mode;
    _frameCount = 0; 
    // Notify DeviceProvider to update its state
    _notifyDeviceProviderRecordingState(true);
    notifyListeners(); // Notify local listeners if any
  }

  Future<void> stopRecordingAndSave({RecordingMode? mode}) async {
    if (!_isRecording) return;
    mode ??= _currentMode;
    debugPrint("[CaptureProvider] Stopping recording. Mode: $mode, Total packets: $_frameCount"); 
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
          
          // Handle based on mode
          switch (mode) {
            case RecordingMode.aiQuery:
              await _handleAIQuery(filePath);
              break;
            case RecordingMode.knowledge:
              await _handleKnowledgeCapture(filePath);
              break;
            case RecordingMode.standard:
            default:
              // Standard recording - just save to list
              _notifyDeviceProviderAddRecording(filePath);
              break;
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
  
  void _notifyDeviceProviderAddRecording(String filePath) {
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
  
  // Handle AI Query recording
  Future<void> _handleAIQuery(String audioPath) async {
    debugPrint("[CaptureProvider] Processing AI query from: $audioPath");
    
    // TODO: Implement AI query processing
    // 1. Transcribe audio
    // 2. Send to AI service
    // 3. Show response to user
    // 4. Save query/response pair
    
    // For now, just save as normal recording
    _notifyDeviceProviderAddRecording(audioPath);
  }
  
  // Handle Knowledge Capture recording
  Future<void> _handleKnowledgeCapture(String audioPath) async {
    debugPrint("[CaptureProvider] Processing knowledge capture from: $audioPath");
    
    // TODO: Implement knowledge capture
    // 1. Transcribe audio
    // 2. Extract entities and concepts
    // 3. Add to knowledge graph
    // 4. Sync with external services (Obsidian, etc.)
    
    // For now, just save as normal recording
    _notifyDeviceProviderAddRecording(audioPath);
  }

  @override
  void dispose() {
    _audioBytesSubscription?.cancel();
    _buttonSubscription?.cancel();
    super.dispose();
  }
} 