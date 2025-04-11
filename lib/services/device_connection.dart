import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart';
import 'package:omi_minimal_fork/services/devices.dart';
import 'package:omi_minimal_fork/services/frame_connection.dart';
import 'package:omi_minimal_fork/services/omi_connection.dart';

class DeviceConnectionFactory {
  static DeviceConnection? create(
    BtDevice device,
    BluetoothDevice bleDevice,
  ) {
    if (device.type == null) {
      return null;
    }
    switch (device.type!) {
      case DeviceType.omi:
        return OmiDeviceConnection(device: device, bleDevice: bleDevice);
      case DeviceType.openglass:
        return OmiDeviceConnection(device: device, bleDevice: bleDevice);
      case DeviceType.frame:
        return FrameDeviceConnection(device: device, bleDevice: bleDevice);
      default:
        return null;
    }
  }
}

class DeviceConnectionException implements Exception {
  String cause;
  DeviceConnectionException(this.cause);
}

abstract class DeviceConnection {
  final BtDevice device;
  final BluetoothDevice bleDevice;
  DateTime? lastActivityAt = DateTime.now();
  DeviceConnectionState status = DeviceConnectionState.disconnected;
  DateTime? pongAt;

  List<BluetoothService> _services = [];

  DeviceConnectionState get connectionState => status;

  Function(String deviceId, DeviceConnectionState state)? _connectionStateChangedCallback;

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;

  DeviceConnection({
    required this.device,
    required this.bleDevice,
  });

  Future<void> connect({
    Function(String deviceId, DeviceConnectionState state)? onConnectionStateChanged,
  }) async {
    if (status == DeviceConnectionState.connected) {
      throw DeviceConnectionException("Connection already established, please disconnect before start new connection");
    }

    // Connect
    _connectionStateChangedCallback = onConnectionStateChanged;
    _connectionStateSubscription = bleDevice.connectionState.listen((BluetoothConnectionState state) async {
      _onBleConnectionStateChanged(state);
    });

    try {
      await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
      await bleDevice.connect();
      await bleDevice.connectionState.where((val) => val == BluetoothConnectionState.connected).first;
    } on FlutterBluePlusException catch (e) {
      throw DeviceConnectionException("FlutterBluePlusException: ${e.toString()}");
    }

    // Mtu
    if (Platform.isAndroid && bleDevice.mtuNow < 512) {
      await bleDevice.requestMtu(512); // This might fix the code 133 error
    }

    // Check connection
    await ping();

    // Discover services
    _services = await bleDevice.discoverServices();
  }

  void _onBleConnectionStateChanged(BluetoothConnectionState state) async {
    if (state == BluetoothConnectionState.disconnected && status == DeviceConnectionState.connected) {
      status = DeviceConnectionState.disconnected;
      await disconnect();
      return;
    }

    if (state == BluetoothConnectionState.connected && status == DeviceConnectionState.disconnected) {
      status = DeviceConnectionState.connected;
      if (_connectionStateChangedCallback != null) {
        _connectionStateChangedCallback!(device.id, status);
      }
    }
  }

  Future<void> disconnect() async {
    status = DeviceConnectionState.disconnected;
    if (_connectionStateChangedCallback != null) {
      _connectionStateChangedCallback!(device.id, status);
      _connectionStateChangedCallback = null;
    }
    await bleDevice.disconnect();
    _connectionStateSubscription.cancel();
    _services.clear();
  }

  Future<bool> ping() async {
    try {
      int rssi = await bleDevice.readRssi();
      device.rssi = rssi;
      pongAt = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('Error reading RSSI: $e');
    }

    return false;
  }

  void read() {}

  void write() {}

  Future<BluetoothService?> getService(String uuid) async {
    return _services.firstWhereOrNull((service) => service.uuid.str128.toLowerCase() == uuid);
  }

  BluetoothCharacteristic? getCharacteristic(BluetoothService service, String uuid) {
    return service.characteristics.firstWhereOrNull(
      (characteristic) => characteristic.uuid.str128.toLowerCase() == uuid.toLowerCase(),
    );
  }

  // Mimic @app/lib/utils/device_base.dart
  Future<bool> isConnected();

  Future<int> retrieveBatteryLevel() async {
    if (await isConnected()) {
      return await performRetrieveBatteryLevel();
    }
    return -1;
  }

  Future<int> performRetrieveBatteryLevel();

  Future<StreamSubscription<List<int>>?> getBleBatteryLevelListener({
    void Function(int)? onBatteryLevelChange,
  }) async {
    if (await isConnected()) {
      return await performGetBleBatteryLevelListener(onBatteryLevelChange: onBatteryLevelChange);
    }
    return null;
  }

  Future<StreamSubscription<List<int>>?> performGetBleBatteryLevelListener({
    void Function(int)? onBatteryLevelChange,
  });

  Future<StreamSubscription?> getBleAudioBytesListener({
    required void Function(List<int>) onAudioBytesReceived,
  }) async {
    if (await isConnected()) {
      return await performGetBleAudioBytesListener(onAudioBytesReceived: onAudioBytesReceived);
    }
    return null;
  }

  Future<List<int>> getBleButtonState() async {
    if (await isConnected()) {
      debugPrint('button state called');
      return await performGetButtonState();
    }
    debugPrint('button state error');
    return Future.value(<int>[]);
  }

  Future<List<int>> performGetButtonState();

  Future<StreamSubscription?> getBleButtonListener({
    required void Function(List<int>) onButtonReceived,
  }) async {
    if (await isConnected()) {
      return await performGetBleButtonListener(onButtonReceived: onButtonReceived);
    }
    return null;
  }

  Future<StreamSubscription?> performGetBleAudioBytesListener({
    required void Function(List<int>) onAudioBytesReceived,
  });

  Future<StreamSubscription?> performGetBleButtonListener({
    required void Function(List<int>) onButtonReceived,
  });

  Future<BleAudioCodec> getAudioCodec() async {
    if (await isConnected()) {
      return await performGetAudioCodec();
    }
    return BleAudioCodec.pcm8;
  }

  Future<BleAudioCodec> performGetAudioCodec();

  Future<bool> performPlayToSpeakerHaptic(int mode);

  // storage here

  Future<bool> writeToStorage(int numFile, int command, int offset) async {
    if (await isConnected()) {
      return await performWriteToStorage(numFile, command, offset);
    }
    return Future.value(false);
  }

  Future<StreamSubscription?> getBleStorageBytesListener({
    required void Function(List<int>) onStorageBytesReceived,
  }) async {
    if (await isConnected()) {
      return await performGetBleStorageBytesListener(onStorageBytesReceived: onStorageBytesReceived);
    }
    return null;
  }

  // Abstract methods to be implemented by subclasses
  Future<List<int>> performGetStorageList();
  Future<bool> performWriteToStorage(int numFile, int command, int offset);
  Future<StreamSubscription?> performGetBleStorageBytesListener({
    required void Function(List<int>) onStorageBytesReceived,
  });

  void _showDeviceDisconnectedNotification() {
    debugPrint("Device disconnected notification was suppressed.");
  }
}
