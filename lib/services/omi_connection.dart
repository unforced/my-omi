import 'dart:async';
import 'dart:io';
import 'dart:math';

// import 'package:awesome_notifications/awesome_notifications.dart'; // Removed
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart'; // Updated
import 'package:omi_minimal_fork/services/devices.dart'; // Updated
import 'package:omi_minimal_fork/services/device_connection.dart'; // Updated
import 'package:omi_minimal_fork/services/errors.dart'; // Updated
import 'package:omi_minimal_fork/services/models.dart'; // Updated
// import 'package:omi/utils/logger.dart'; // Removed logger - replace with debugPrint or basic logging

// Helper functions replacing logger
void logServiceNotFoundError(String serviceName, String deviceId) {
  debugPrint('Error: $serviceName service not found for device $deviceId');
}

void logCharacteristicNotFoundError(String charName, String deviceId) {
  debugPrint('Error: $charName characteristic not found for device $deviceId');
}

void logSubscribeError(String streamName, String deviceId, Object e, StackTrace stackTrace) {
  debugPrint('Error subscribing to $streamName for device $deviceId: $e\n$stackTrace');
}

void logErrorMessage(String message, String deviceId) {
  debugPrint('Error for device $deviceId: $message');
}

// Custom logger replacement for PlatformException
void logPlatformException(String context, String deviceId, PlatformException e) {
   debugPrint('PlatformException in $context for device $deviceId: ${e.code} - ${e.message}');
}

// Custom logger replacement for generic Exception
void logException(String context, String deviceId, Exception e, StackTrace stackTrace) {
   debugPrint('Exception in $context for device $deviceId: $e\n$stackTrace');
}

class OmiDeviceConnection extends DeviceConnection {
  BluetoothService? _batteryService;
  BluetoothService? _omiService;
  BluetoothService? _storageService;
  BluetoothService? _accelService;
  BluetoothService? _buttonService;
  BluetoothService? _speakerService;
  // TODO: Remove if image capture not needed
  // BluetoothService? _imageService; 

  OmiDeviceConnection({required super.device, required super.bleDevice});

  get deviceId => device.id;

  @override
  Future<void> connect({Function(String deviceId, DeviceConnectionState state)? onConnectionStateChanged}) async {
    await super.connect(onConnectionStateChanged: onConnectionStateChanged);

    // Services
    _omiService = await getService(omiServiceUuid);
    if (_omiService == null) {
      logServiceNotFoundError('Omi', deviceId);
      throw DeviceConnectionException("Omi ble service is not found");
    }

    _batteryService = await getService(batteryServiceUuid);
    if (_batteryService == null) {
      logServiceNotFoundError('Battery', deviceId);
    }

    _storageService = await getService(storageDataStreamServiceUuid);
    if (_storageService == null) {
      logServiceNotFoundError('Storage', deviceId);
    }

    _speakerService = await getService(speakerDataStreamServiceUuid);
    if (_speakerService == null) {
      logServiceNotFoundError('Speaker', deviceId);
    }

    _accelService = await getService(accelDataStreamServiceUuid);
    if (_accelService == null) {
      logServiceNotFoundError('Accelerometer', deviceId);
    }

    _buttonService = await getService(buttonServiceUuid);
    if (_buttonService == null) {
      logServiceNotFoundError('Button', deviceId);
    }

    // TODO: Remove if image capture not needed
    // _imageService = await getService(imageServiceUuid); 
    // if (_imageService == null) {
    //     logServiceNotFoundError('Image Capture', deviceId);
    // }
  }

  // Mimic @app/lib/utils/ble/friend_communication.dart
  @override
  Future<bool> isConnected() async {
    return bleDevice.isConnected;
  }

  @override
  Future<int> performRetrieveBatteryLevel() async {
    if (_batteryService == null) {
      logServiceNotFoundError('Battery', deviceId);
      return -1;
    }

    var batteryLevelCharacteristic = getCharacteristic(_batteryService!, batteryLevelCharacteristicUuid);
    if (batteryLevelCharacteristic == null) {
      logCharacteristicNotFoundError('Battery level', deviceId);
      return -1;
    }

    try {
      var currValue = await batteryLevelCharacteristic.read();
      if (currValue.isNotEmpty) return currValue[0];
    } on PlatformException catch (e) {
      logPlatformException('performRetrieveBatteryLevel', deviceId, e);
    } catch (e, stackTrace) {
      logException('performRetrieveBatteryLevel', deviceId, e as Exception, stackTrace);
    }
    return -1;
  }

  @override
  Future<StreamSubscription<List<int>>?> performGetBleBatteryLevelListener({
    void Function(int)? onBatteryLevelChange,
  }) async {
    if (_batteryService == null) {
      logServiceNotFoundError('Battery', deviceId);
      return null;
    }

    var batteryLevelCharacteristic = getCharacteristic(_batteryService!, batteryLevelCharacteristicUuid);
    if (batteryLevelCharacteristic == null) {
      logCharacteristicNotFoundError('Battery level', deviceId);
      return null;
    }

    try {
      var currValue = await batteryLevelCharacteristic.read();
      if (currValue.isNotEmpty) {
        debugPrint('Battery level: ${currValue[0]}');
        if (onBatteryLevelChange != null) onBatteryLevelChange(currValue[0]);
      }

      await batteryLevelCharacteristic.setNotifyValue(true);

      var listener = batteryLevelCharacteristic.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          // Commented out noisy log
          // debugPrint('Battery level changed: ${value[0]}');
          if (onBatteryLevelChange != null) onBatteryLevelChange(value[0]);
        }
      });

      final device = bleDevice;
      device.cancelWhenDisconnected(listener);
      return listener;
    } on PlatformException catch (e) {
      logPlatformException('performGetBleBatteryLevelListener', deviceId, e);
    } catch (e, stackTrace) {
      logSubscribeError('Battery level', deviceId, e, stackTrace);
    }
    return null;
  }

  @override
  Future<List<int>> performGetButtonState() async {
    debugPrint('perform button state called');
    if (_buttonService == null) {
      return Future.value(<int>[]);
    }

    var buttonStateCharacteristic = getCharacteristic(_buttonService!, buttonTriggerCharacteristicUuid);
    if (buttonStateCharacteristic == null) {
      logCharacteristicNotFoundError('Button state', deviceId);
      return Future.value(<int>[]);
    }
    try {
      var value = await buttonStateCharacteristic.read();
      return value;
    } on PlatformException catch (e) {
      logPlatformException('performGetButtonState', deviceId, e);
    } catch (e, stackTrace) {
      logException('performGetButtonState', deviceId, e as Exception, stackTrace);
    }
    return Future.value(<int>[]);
  }

  @override
  Future<StreamSubscription?> performGetBleButtonListener({
    required void Function(List<int>) onButtonReceived,
  }) async {
    debugPrint("[OmiConn] performGetBleButtonListener called.");
    if (_buttonService == null) {
      logServiceNotFoundError('Button', deviceId);
      return null;
    }

    var buttonDataStreamCharacteristic = getCharacteristic(_buttonService!, buttonTriggerCharacteristicUuid);
    if (buttonDataStreamCharacteristic == null) {
      logCharacteristicNotFoundError('Button data stream', deviceId);
      return null;
    }
    debugPrint("[OmiConn] Button characteristic found. Properties: ${buttonDataStreamCharacteristic.properties}");

    if (!buttonDataStreamCharacteristic.properties.notify && !buttonDataStreamCharacteristic.properties.indicate) {
        debugPrint("[OmiConn] Error: Button characteristic does not support notifications or indications.");
        return null;
    }

    try {
      final device = bleDevice;
      // Ensure device is connected before proceeding
      if (!device.isConnected) {
          logErrorMessage('Device not connected for button stream setup', deviceId);
          return null;
      }
      
      // Commented out MTU request here
      // if (Platform.isAndroid && device.mtuNow < 512) {
      //   await device.requestMtu(512);
      // }

      // Check connection again after potential MTU request
      if (!device.isConnected) {
          logErrorMessage('Device disconnected before setting notify value for button stream', deviceId);
          return null;
      }

      debugPrint("[OmiConn] Setting notify value for button characteristic...");
      await buttonDataStreamCharacteristic.setNotifyValue(true);
      debugPrint("[OmiConn] Set notify value successful for button. Subscribing...");

      var listener = buttonDataStreamCharacteristic.lastValueStream.listen((value) {
        // Commented out spammy log
        // debugPrint("new button value ${value}");
        if (value.isNotEmpty) onButtonReceived(value);
      });

      device.cancelWhenDisconnected(listener);
      debugPrint("[OmiConn] Button listener setup complete.");
      return listener;

    } on PlatformException catch (e) {
        logPlatformException('performGetBleButtonListener', deviceId, e);
        debugPrint("[OmiConn] PlatformException during button subscription setup: $e");
    } catch (e, stackTrace) {
      logSubscribeError('Button data stream', deviceId, e, stackTrace);
      debugPrint("[OmiConn] Generic Exception during button subscription setup: $e");
    }
    debugPrint("[OmiConn] Button listener setup failed, returning null.");
    return null;
  }

  @override
  Future<StreamSubscription?> performGetBleAudioBytesListener({
    required void Function(List<int>) onAudioBytesReceived,
  }) async {
    debugPrint("[OmiConn] performGetBleAudioBytesListener called."); 
    if (_omiService == null) {
      logServiceNotFoundError('Omi', deviceId);
      return null;
    }

    var audioCharacteristic = getCharacteristic(_omiService!, audioDataStreamCharacteristicUuid);
    if (audioCharacteristic == null) {
      logCharacteristicNotFoundError('Audio data stream', deviceId);
      return null;
    }

    if (!audioCharacteristic.properties.notify) {
        debugPrint("[OmiConn] Error: Audio characteristic does not support notifications."); 
        return null;
    }

    try {
      // Ensure device is connected
      final device = bleDevice;
      if (!device.isConnected) {
          logErrorMessage('Device not connected for audio stream setup', deviceId);
          return null;
      }

      // Commented out MTU Request (if any was planned here)

      // Check connection again
      if (!device.isConnected) {
          logErrorMessage('Device disconnected before setting notify value for audio stream', deviceId);
          return null;
      }

      await audioCharacteristic.setNotifyValue(true);

      var listener = audioCharacteristic.lastValueStream.listen((value) {
        if (value.isNotEmpty) onAudioBytesReceived(value);
      });

      device.cancelWhenDisconnected(listener);
      debugPrint("[OmiConn] Subscription setup complete, returning listener."); 
      return listener;

    } on PlatformException catch (e) {
      logPlatformException('performGetBleAudioBytesListener', deviceId, e);
      debugPrint("[OmiConn] PlatformException during audio subscription setup: $e"); 
    } catch (e, stackTrace) {
      logSubscribeError('Audio data stream', deviceId, e, stackTrace);
      debugPrint("[OmiConn] Generic Exception during audio subscription setup: $e"); 
    }

    debugPrint("[OmiConn] Audio subscription setup failed, returning null."); 
    return null;
  }

  @override
  Future<BleAudioCodec> performGetAudioCodec() async {
    debugPrint("[OmiConn] performGetAudioCodec called.");
    if (_omiService == null) {
      logServiceNotFoundError('Omi', deviceId);
      return BleAudioCodec.unknown;
    }

    var codecCharacteristic = getCharacteristic(_omiService!, audioCodecCharacteristicUuid);
    if (codecCharacteristic == null) {
      logCharacteristicNotFoundError('Audio codec', deviceId);
      return BleAudioCodec.unknown;
    }

    try {
      final value = await codecCharacteristic.read();
      if (value.isNotEmpty) {
         int codecId = value[0];
         BleAudioCodec codec = BleAudioCodec.unknown;
         // Manually map ID to Enum based on known values
         switch (codecId) {
           case 1: 
             codec = BleAudioCodec.pcm8;
             break;
           case 10: // Assuming 10 for pcm16 based on common patterns
             codec = BleAudioCodec.pcm16;
             break;
           case 20:
             codec = BleAudioCodec.opus;
             break;
           // Add cases for mulaw8, mulaw16 if needed
           default:
             logErrorMessage('Unknown codec id received: $codecId', deviceId);
             codec = BleAudioCodec.unknown;
         }
         debugPrint("[OmiConn] Read codec value: $codecId, Parsed as: $codec");
         return codec;
      } else {
          debugPrint("[OmiConn] Read empty value from codec characteristic.");
          return BleAudioCodec.unknown;
      }
    } on PlatformException catch (e) {
      logPlatformException('performGetAudioCodec', deviceId, e);
    } catch (e, stackTrace) {
      logException('performGetAudioCodec', deviceId, e as Exception, stackTrace);
    }
    return BleAudioCodec.unknown;
  }

  @override
  Future<List<int>> performGetStorageList() async {
    debugPrint("[OmiConn] performGetStorageList called.");
    if (_storageService == null) {
      logServiceNotFoundError('Storage', deviceId);
      return [];
    }
    var controlChar = getCharacteristic(_storageService!, storageReadControlCharacteristicUuid);
    if (controlChar == null) {
      logCharacteristicNotFoundError('Storage Control', deviceId);
      return [];
    }

    // Check if characteristic supports READ
    if (!controlChar.properties.read) {
        debugPrint("[OmiConn] Error: Storage control characteristic does not support read.");
        return [];
    }

    try {
      // Attempt to READ the characteristic directly
      debugPrint("[OmiConn] Attempting to read storage list characteristic...");
      List<int> value = await controlChar.read();
      debugPrint("[OmiConn] Storage list read response: $value");
      // TODO: Parse the response `value` to extract file identifiers/list
      return value; // Return raw bytes read
    } catch (e, stackTrace) {
       logException("performGetStorageList", deviceId, e is Exception ? e : Exception(e.toString()), stackTrace);
       return [];
    }
  }

  @override
  Future<bool> performWriteToStorage(int numFile, int command, int offset) async {
     // Use Command Codes from firmware/storage.c
     const int READ_COMMAND = 0;
     const int DELETE_COMMAND = 1;
     const int NUKE_COMMAND = 2; // If needed
     const int STOP_COMMAND = 3; // If needed
     const int HEARTBEAT_COMMAND = 50; // If needed
     
     String commandName = "UNKNOWN ($command)";
     if (command == READ_COMMAND) commandName = "READ";
     if (command == DELETE_COMMAND) commandName = "DELETE";

     debugPrint("[OmiConn] performWriteToStorage called. File: $numFile, Cmd: $commandName, Offset: $offset");
     if (_storageService == null) {
      logServiceNotFoundError('Storage', deviceId);
      return false;
    }
    var dataChar = getCharacteristic(_storageService!, storageDataStreamCharacteristicUuid); 
    if (dataChar == null) {
      logCharacteristicNotFoundError('Storage Data Stream', deviceId);
      return false;
    }
    if (!dataChar.properties.write && !dataChar.properties.writeWithoutResponse) {
        debugPrint("[OmiConn] Error: Storage data characteristic does not support write.");
        return false;
    }

    try {
        // Format based on original omi_connection.dart performWriteToStorage
        // Byte 0: Command (0=Read, 1=Delete)
        // Byte 1: File Number (ID)
        // Bytes 2-5: Offset (Big Endian)
        var offsetBytes = [
          (offset >> 24) & 0xFF,
          (offset >> 16) & 0xFF,
          (offset >> 8) & 0xFF,
          offset & 0xFF,
        ];
        Uint8List commandData = Uint8List.fromList([
            command & 0xFF, 
            numFile & 0xFF, 
            offsetBytes[0], 
            offsetBytes[1], 
            offsetBytes[2], 
            offsetBytes[3]
        ]);

        bool withoutResponse = dataChar.properties.writeWithoutResponse;
        debugPrint("[OmiConn] Writing command $commandName ($commandData) to DATA characteristic (withoutResponse: $withoutResponse)...");
        await dataChar.write(commandData, withoutResponse: withoutResponse);
        debugPrint("[OmiConn] Storage command $commandName sent successfully via DATA characteristic.");
        return true;
    } catch (e, stackTrace) {
       logException("performWriteToStorage", deviceId, e is Exception ? e : Exception(e.toString()), stackTrace);
       return false;
    }
  }

  @override
  Future<StreamSubscription?> performGetBleStorageBytesListener({
    required void Function(List<int>) onStorageBytesReceived,
  }) async {
     debugPrint("[OmiConn] performGetBleStorageBytesListener called.");
     if (_storageService == null) {
      logServiceNotFoundError('Storage', deviceId);
      return null;
    }
    var dataChar = getCharacteristic(_storageService!, storageDataStreamCharacteristicUuid);
     if (dataChar == null) {
      logCharacteristicNotFoundError('Storage Data Stream', deviceId);
      return null;
    }
     if (!dataChar.properties.notify) {
        debugPrint("[OmiConn] Error: Storage data characteristic does not support notifications."); 
        return null;
    }

    try {
      await dataChar.setNotifyValue(true);
      var listener = dataChar.lastValueStream.listen(onStorageBytesReceived);
      bleDevice.cancelWhenDisconnected(listener);
      debugPrint("[OmiConn] Storage data listener setup complete.");
      return listener;
    } catch (e, stackTrace) {
      logSubscribeError('Storage data stream', deviceId, e, stackTrace);
      return null;
    }
  }

  // level
  //   1 - play 20ms
  //   2 - play 50ms
  //   3 - play 500ms
  @override
  Future<bool> performPlayToSpeakerHaptic(int level) async {
    if (_speakerService == null) {
      logServiceNotFoundError('Speaker Write', deviceId);
      return false;
    }

    var speakerDataStreamCharacteristic = getCharacteristic(_speakerService!, speakerDataStreamCharacteristicUuid);
    if (speakerDataStreamCharacteristic == null) {
      logCharacteristicNotFoundError('Speaker data stream', deviceId);
      return false;
    }
    try {
      debugPrint('About to play to speaker haptic');
      await speakerDataStreamCharacteristic.write([level & 0xFF]);
      return true;
    } on PlatformException catch (e) {
      logPlatformException('performPlayToSpeakerHaptic', deviceId, e);
    } catch (e, stackTrace) {
      logException('performPlayToSpeakerHaptic', deviceId, e as Exception, stackTrace);
    }
    return false;
  }

  // TODO: Remove image capture related methods if not needed
  // @override
  // Future performCameraStartPhotoController() async {
  //   // ... removed implementation ...
  // }

  // @override
  // Future performCameraStopPhotoController() async {
  //   // ... removed implementation ...
  // }

  // @override
  // Future<bool> performHasPhotoStreamingCharacteristic() async {
  //   // ... removed implementation ...
  //   return false;
  // }

  // Future<StreamSubscription?> _getBleImageBytesListener({
  //   required void Function(List<int>) onImageBytesReceived,
  // }) async {
  //  // ... removed implementation ...
  //  return null;
  // }

  // @override
  // Future<StreamSubscription?> performGetImageListener({
  //   required void Function(Uint8List base64JpgData) onImageReceived,
  // }) async {
  //  // ... removed implementation ...
  //  return null;
  // }

  // TODO: Implement or remove accel listener based on requirements
  // @override
  // Future<StreamSubscription<List<int>>?> performGetAccelListener({
  //   void Function(int)? onAccelChange,
  // }) async {
  //   // Implementation needed
  //   return null;
  // }

  @override
  Future<bool> performPing() async {
    debugPrint("[OmiConn] performPing called.");
    try {
      var batteryLevel = await performRetrieveBatteryLevel();
      bool success = batteryLevel != -1;
      if (success) {
        pongAt = DateTime.now();
      } else {
          debugPrint("[OmiConn] Ping failed (could not read battery level).");
      }
      return success;
    } catch (e) {
       debugPrint("[OmiConn] Exception during ping: $e");
      return false;
    }
  }
}
