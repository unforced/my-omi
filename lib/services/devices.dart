import 'dart:async';
import 'dart:io'; // Added for Platform check

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart';
import 'package:omi_minimal_fork/services/device_connection.dart';
import 'package:omi_minimal_fork/services/models.dart';

abstract class IDeviceService {
  void start();
  void stop();
  Future<void> discover({String? desirableDeviceId, int timeout = 5});

  Future<DeviceConnection?> ensureConnection(String deviceId, {bool force = false});

  // Add getter for the active connection
  DeviceConnection? get activeConnection;

  void subscribe(IDeviceServiceSubsciption subscription, Object context);
  void unsubscribe(Object context);

  DateTime? getFirstConnectedAt();
}

enum DeviceServiceStatus {
  init,
  ready,
  scanning,
  stop,
}

enum DeviceConnectionState {
  connected,
  disconnected,
}

abstract class IDeviceServiceSubsciption {
  void onDevices(List<BtDevice> devices);
  void onStatusChanged(DeviceServiceStatus status);
  void onDeviceConnectionStateChanged(String deviceId, DeviceConnectionState state);
}

class DeviceService implements IDeviceService {
  DeviceServiceStatus _status = DeviceServiceStatus.init;
  List<BtDevice> _devices = [];
  List<ScanResult> _bleDevices = [];

  final Map<Object, IDeviceServiceSubsciption> _subscriptions = {};

  DeviceConnection? _connection;

  // Implement the getter
  @override
  DeviceConnection? get activeConnection => _connection;

  // Store subscription for connection state changes
  StreamSubscription<OnConnectionStateChangedEvent>? _connectionStateSubscription;
  String? _currentlyConnectingDeviceId;

  List<BtDevice> get devices => _devices;

  DeviceServiceStatus get status => _status;

  DateTime? _firstConnectedAt;

  @override
  Future<void> discover({
    String? desirableDeviceId,
    int timeout = 5,
  }) async {
    debugPrint("Device discovering...");
    if (_status != DeviceServiceStatus.ready) {
      throw Exception("Device service is not ready, may busying or stop");
    }

    if (!(await FlutterBluePlus.isSupported)) {
      throw Exception("Bluetooth is not supported");
    }

    if (FlutterBluePlus.isScanningNow) {
      debugPrint("Device service is scanning...");
      return;
    }

    // Listen to scan results, always re-emits previous results
    var discoverSubscription = FlutterBluePlus.scanResults.listen(
      (results) async {
        await _onBleDiscovered(results, desirableDeviceId);
      },
      onError: (e) {
        debugPrint('bleFindDevices error: $e');
      },
    );
    FlutterBluePlus.cancelWhenScanComplete(discoverSubscription);

    // Only look for devices that implement Omi or Frame main service
    _status = DeviceServiceStatus.scanning;
    await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
    await FlutterBluePlus.startScan(
      timeout: Duration(seconds: timeout),
      withServices: [Guid(omiServiceUuid), Guid(frameServiceUuid)],
    );
    _status = DeviceServiceStatus.ready;
  }

  Future<void> _onBleDiscovered(List<ScanResult> results, String? desirableDeviceId) async {
    _bleDevices = results.where((r) => r.device.platformName.isNotEmpty).toList();
    _bleDevices.sort((a, b) => b.rssi.compareTo(a.rssi));
    _devices = _bleDevices.map<BtDevice>((e) => BtDevice.fromScanResult(e)).toList();
    onDevices(devices);

    // Check desirable device
    if (desirableDeviceId != null && desirableDeviceId.isNotEmpty) {
      await ensureConnection(desirableDeviceId, force: true);
    }
  }

  @override
  Future<void> _connectToDevice(String id) async {
    _connection = null;

    var bleDevice = _bleDevices.firstWhereOrNull((f) => f.device.remoteId.toString() == id);
    var device = _devices.firstWhereOrNull((f) => f.id == id);
    if (bleDevice == null || device == null) {
      debugPrint("Device not found in discovered list: $id");
      // Notify potential listeners about the failure
      onDeviceConnectionStateChanged(id, DeviceConnectionState.disconnected);
      return;
    }

    // Track which device we are attempting to connect to
    _currentlyConnectingDeviceId = id;

    // Important: Let flutter_blue_plus manage the connection state via its stream.
    // We initiate the connection, but the state callback will handle the result.
    try {
        debugPrint("[DeviceService] Attempting connect(autoConnect: true, mtu: null) for $id");
        await bleDevice.device.connect(autoConnect: true, mtu: null);
        // The _connectionStateSubscription listener will handle the connected state WHEN the OS sees the device.
    } catch (e) {
        debugPrint("Error during bleDevice.connect(autoConnect: true, mtu: null): $e");
        _currentlyConnectingDeviceId = null;
        onDeviceConnectionStateChanged(id, DeviceConnectionState.disconnected); // Notify failure
    }
    // Removed: await _connection?.connect(onConnectionStateChanged: onDeviceConnectionStateChanged);
    return;
  }

  @override
  void subscribe(IDeviceServiceSubsciption subscription, Object context) {
    _subscriptions.remove(context.hashCode);
    _subscriptions.putIfAbsent(context.hashCode, () => subscription);

    // Retains
    subscription.onDevices(_devices);
    subscription.onStatusChanged(_status);

    // Also provide current connection status if available
    if (_connection != null) {
       subscription.onDeviceConnectionStateChanged(_connection!.device.id, _connection!.status);
    }
  }

  @override
  void unsubscribe(Object context) {
    _subscriptions.remove(context.hashCode);
  }

  @override
  void start() {
    _status = DeviceServiceStatus.ready;
    debugPrint("DeviceService started.");

    // ---- Listen to FlutterBluePlus connection state changes ----
    _connectionStateSubscription = FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
       // Access state via event.connectionState
       debugPrint("[FBP Listener] State changed: ${event.device.remoteId} -> ${event.connectionState}");
      
       // Map FBP state to our internal state
       final internalState = event.connectionState == BluetoothConnectionState.connected
           ? DeviceConnectionState.connected
           : DeviceConnectionState.disconnected;
       
       final deviceId = event.device.remoteId.toString();

       // If this is the device we were trying to connect, update internal state
       if (deviceId == _currentlyConnectingDeviceId) {
           if (internalState == DeviceConnectionState.connected) {
               var bleDevice = _bleDevices.firstWhereOrNull((f) => f.device.remoteId.toString() == deviceId);
               var btDevice = _devices.firstWhereOrNull((f) => f.id == deviceId);
               if (bleDevice != null && btDevice != null) {
                    // Create the connection object
                    _connection = DeviceConnectionFactory.create(btDevice, bleDevice.device);
                    _currentlyConnectingDeviceId = null; // Reset tracker before async connect call
                    debugPrint("[FBP Listener] Created DeviceConnection object for $deviceId. Connecting internally...");
                    try {
                       // **** ADDED: Call connect() on the connection object to discover services ****
                       await _connection?.connect(); 
                       debugPrint("[FBP Listener] Internal connect() completed for $deviceId.");
                       
                       // **** ADDED: Request MTU after successful internal connect ****
                       if (Platform.isAndroid && _connection != null) {
                           debugPrint("[FBP Listener] Requesting MTU 512 for $deviceId...");
                           try {
                             await _connection!.bleDevice.requestMtu(512);
                             debugPrint("[FBP Listener] MTU request successful for $deviceId.");
                           } catch (e) {
                             debugPrint("[FBP Listener] MTU request failed for $deviceId: $e");
                             // Continue even if MTU request fails, but log it.
                           }
                       }

                       debugPrint("[FBP Listener] Notifying subscribers of connection for $deviceId.");
                       onDeviceConnectionStateChanged(deviceId, internalState); 
                    } catch (e) {
                       debugPrint("[FBP Listener] Error during internal _connection.connect(): $e");
                       _connection = null; // Ensure connection is null on error
                       // Notify subscribers of failure
                       onDeviceConnectionStateChanged(deviceId, DeviceConnectionState.disconnected); 
                    }
               } else {
                   debugPrint("[FBP Listener] Error: Could not find devices to create connection object for $deviceId after connect event.");
                   _connection = null;
                   _currentlyConnectingDeviceId = null; 
                   // Notify subscribers of failure
                   onDeviceConnectionStateChanged(deviceId, DeviceConnectionState.disconnected); 
               }
           } else {
               // Connection failed or disconnected during attempt
                _connection = null;
               _currentlyConnectingDeviceId = null;
                debugPrint("[FBP Listener] Connection attempt failed/disconnected for $deviceId");
                // Notify subscribers of failure
                onDeviceConnectionStateChanged(deviceId, internalState); // Pass the disconnected state
           }
       } else if (_connection?.device.id == deviceId && internalState == DeviceConnectionState.disconnected) {
           // Handle disconnects for an existing connection
           _connection = null;
           debugPrint("[FBP Listener] Existing connection disconnected: $deviceId");
           // Notify subscribers of disconnection
           onDeviceConnectionStateChanged(deviceId, internalState);
       }
       // Removed: No longer notify here, notification happens after internal connect
       // onDeviceConnectionStateChanged(deviceId, internalState);
    });

    // TODO: Start watchdog if needed
  }

  @override
  void stop() {
    _status = DeviceServiceStatus.stop;
    onStatusChanged(_status);

    if (FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.stopScan();
    }
    // Cancel the connection state listener
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // Disconnect if connected
    _connection?.disconnect();
    _connection = null;

    _subscriptions.clear();
    _devices.clear();
    _bleDevices.clear();
     debugPrint("DeviceService stopped.");
  }

  void onStatusChanged(DeviceServiceStatus status) {
    for (var s in _subscriptions.values) {
      s.onStatusChanged(status);
    }
  }

  void onDeviceConnectionStateChanged(String deviceId, DeviceConnectionState state) {
    debugPrint("device connection state changed...${deviceId}...${state}");
    for (var s in _subscriptions.values) {
      s.onDeviceConnectionStateChanged(deviceId, state);
    }
  }

  void onDevices(List<BtDevice> devices) {
    for (var s in _subscriptions.values) {
      s.onDevices(devices);
    }
  }

  // Warn: Should use a better solution to prevent race conditions
  bool mutex = false;
  @override
  Future<DeviceConnection?> ensureConnection(String deviceId, {bool force = false}) async {
    while (mutex) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    mutex = true;

    debugPrint("ensureConnection: Requesting connection for $deviceId. Current: ${_connection?.device.id} State: ${_connection?.status} Force: ${force}");
    try {
      // If already connected to the right device, check ping and return
      if (_connection?.device.id == deviceId && _connection?.status == DeviceConnectionState.connected) {
          var pongAt = _connection?.pongAt;
          var shouldPing = (pongAt == null || pongAt.isBefore(DateTime.now().subtract(const Duration(seconds: 5))));
          if (shouldPing) {
              var ok = await _connection?.ping() ?? false;
              if (!ok) {
                  debugPrint("ensureConnection: Ping failed for $deviceId. Disconnecting.");
                  await _connection?.disconnect(); // Listener will set _connection to null
                  return null;
              } else {
                 debugPrint("ensureConnection: Ping successful for $deviceId.");
              }
          }
          debugPrint("ensureConnection: Already connected to $deviceId.");
          return _connection;
      }

      // If connected to a different device, or not connected, and force is true, disconnect old and connect new
      if (force) {
        if (_connection != null) {
           debugPrint("ensureConnection: Disconnecting previous connection (${_connection!.device.id}) due to force=true.");
           await _connection!.disconnect(); // Listener will set _connection to null
           await Future.delayed(const Duration(milliseconds: 100)); // Small delay after disconnect
        }
        debugPrint("ensureConnection: Force connecting to $deviceId...");
        await _connectToDevice(deviceId);
        // Wait briefly for the connection state listener to potentially update _connection
        await Future.delayed(const Duration(milliseconds: 200)); 
      } else {
         // If not forcing, and not connected to the right device, return null
         debugPrint("ensureConnection: Not connected to $deviceId and force=false. Returning null.");
         return null;
      }
      
      // At this point, connection attempt was made. Return the current _connection status.
      // The listener should have updated it if the connection was successful.
      _firstConnectedAt ??= (_connection?.status == DeviceConnectionState.connected) ? DateTime.now() : null;
      debugPrint("ensureConnection: Returning connection object for $deviceId (State: ${_connection?.status})");
      return _connection; // Return whatever state the listener set
    } finally {
      mutex = false;
    }
  }

  @override
  DateTime? getFirstConnectedAt() {
    return _firstConnectedAt;
  }
}
