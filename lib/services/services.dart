import 'dart:async';

// import 'package:flutter/material.dart'; // Removed unused import
import 'devices.dart'; // Using relative path
// import 'package:omi_minimal_fork/services/sockets.dart'; // Removed
// import 'package:omi_minimal_fork/services/wals.dart'; // Removed

class ServiceManager {
  // Removed MicRecorderService related fields
  late IDeviceService _device;
  // Removed SocketService related fields
  // Removed WalService related fields

  static ServiceManager? _instance;

  static ServiceManager _create() {
    ServiceManager sm = ServiceManager();
    // Removed MicRecorderService initialization
    sm._device = DeviceService();
    // Removed SocketService initialization
    // Removed WalService initialization

    return sm;
  }

  static ServiceManager instance() {
    if (_instance == null) {
      throw Exception("Service manager is not initiated");
    }

    return _instance!;
  }

  // Removed mic getter
  IDeviceService get device => _device;
  // Removed socket getter
  // Removed wal getter

  static void init() {
    if (_instance != null) {
      throw Exception("Service manager is initiated");
    }
    _instance = ServiceManager._create();
  }

  Future<void> start() async {
    _device.start();
    // Removed _wal.start();
  }

  void deinit() async {
    // Removed _wal.stop();
    // Removed _mic.stop();
    _device.stop(); // Keep device stop
  }
}

// Removed BackgroundService and related classes/enums/functions
// Removed IMicRecorderService and implementations
