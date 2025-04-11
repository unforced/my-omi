import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart';
import 'package:omi_minimal_fork/services/devices.dart';
import 'package:omi_minimal_fork/services/device_connection.dart';

class FrameDeviceConnection extends DeviceConnection {
  FrameDeviceConnection({required super.device, required super.bleDevice});

  get deviceId => device.id;

  @override
  Future<void> connect({Function(String deviceId, DeviceConnectionState state)? onConnectionStateChanged}) async {
    debugPrint("FrameDeviceConnection connect - Not implemented");
    await super.connect(onConnectionStateChanged: onConnectionStateChanged);
  }

  Future<void> init() async {
    debugPrint("FrameDeviceConnection init - Not implemented");
  }

  String get firmwareRevision => 'Unknown';
  String get hardwareRevision => 'Unknown';
  String get manufacturerName => "Brilliant Labs (Not Implemented)";
  String get modelNumber => 'Frame (Not Implemented)';

  @override
  Future<bool> isConnected() async {
    return super.connectionState == DeviceConnectionState.connected;
  }

  @override
  Future<int> performRetrieveBatteryLevel() async {
    debugPrint("FrameDeviceConnection performRetrieveBatteryLevel - Not implemented");
    return -1;
  }

  @override
  Future<StreamSubscription<List<int>>?> performGetBleBatteryLevelListener({
    void Function(int)? onBatteryLevelChange,
  }) async {
    debugPrint("FrameDeviceConnection performGetBleBatteryLevelListener - Not implemented");
    return null;
  }

  @override
  Future<List<int>> performGetButtonState() async {
    debugPrint("FrameDeviceConnection performGetButtonState - Not implemented");
    return [];
  }

  @override
  Future<StreamSubscription?> performGetBleButtonListener({
    required void Function(List<int>) onButtonReceived,
  }) async {
    debugPrint("FrameDeviceConnection performGetBleButtonListener - Not implemented");
    return null;
  }

  @override
  Future<StreamSubscription?> performGetBleAudioBytesListener({
    required void Function(List<int>) onAudioBytesReceived,
  }) async {
    debugPrint("FrameDeviceConnection performGetBleAudioBytesListener - Not implemented");
    return null;
  }

  @override
  Future<BleAudioCodec> performGetAudioCodec() async {
    debugPrint("FrameDeviceConnection performGetAudioCodec - Not implemented");
    return BleAudioCodec.pcm8;
  }

  @override
  Future<bool> performPlayToSpeakerHaptic(int mode) async {
    debugPrint("FrameDeviceConnection performPlayToSpeakerHaptic - Not implemented");
    return false;
  }

  @override
  Future<List<int>> performGetStorageList() async {
    debugPrint("FrameDeviceConnection performGetStorageList - Not implemented");
    return [];
  }

  @override
  Future<bool> performWriteToStorage(int numFile, int command, int offset) async {
    debugPrint("FrameDeviceConnection performWriteToStorage - Not implemented");
    return false;
  }

  @override
  Future<StreamSubscription?> performGetBleStorageBytesListener({
    required void Function(List<int>) onStorageBytesReceived,
  }) async {
    debugPrint("FrameDeviceConnection performGetBleStorageBytesListener - Not implemented");
    return null;
  }

  @override
  Future performCameraStartPhotoController() async {
    debugPrint("FrameDeviceConnection performCameraStartPhotoController - Not implemented");
  }

  @override
  Future performCameraStopPhotoController() async {
    debugPrint("FrameDeviceConnection performCameraStopPhotoController - Not implemented");
  }

  @override
  Future<bool> performHasPhotoStreamingCharacteristic() async {
    debugPrint("FrameDeviceConnection performHasPhotoStreamingCharacteristic - Not implemented");
    return false;
  }

  @override
  Future<StreamSubscription?> performGetImageListener({
    required void Function(Uint8List base64JpgData) onImageReceived,
  }) async {
    debugPrint("FrameDeviceConnection performGetImageListener - Not implemented");
    return null;
  }
}
