import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:nordic_dfu/nordic_dfu.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart';
import 'package:omi_minimal_fork/http/api/device.dart';
import 'package:omi_minimal_fork/providers/device_provider.dart';
import 'package:omi_minimal_fork/utils/manifest.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

mixin FirmwareMixin<T extends StatefulWidget> on State<T> {
  Map latestFirmwareDetails = {};
  bool isDownloading = false;
  bool isDownloaded = false;
  int downloadProgress = 1;
  bool isInstalling = false;
  bool isInstalled = false;
  int installProgress = 1;
  bool isLegacySecureDFU = true; // Use Legacy DFU for current firmware format
  List<String> otaUpdateSteps = [];
  final mcumgr.FirmwareUpdateManagerFactory? managerFactory = mcumgr.FirmwareUpdateManagerFactory();

  Future<List<McuMgrImage>> _processZip(Uint8List zipData) async {
    return processZipFile(zipData);
  }

  Future<void> startDfu(BtDevice btDevice, {bool fileInAssets = false, String? zipFilePath, String? assetPath}) async {
    if (isLegacySecureDFU) {
      return startLegacyDfu(btDevice, fileInAssets: fileInAssets, assetPath: assetPath);
    }
    return startMCUDfu(btDevice, fileInAssets: fileInAssets, zipFilePath: zipFilePath, assetPath: assetPath);
  }

  Future<void> startMCUDfu(BtDevice btDevice, {bool fileInAssets = false, String? zipFilePath, String? assetPath}) async {
    setState(() {
      isInstalling = true;
    });
    await Provider.of<MinimalDeviceProvider>(context, listen: false).prepareDFU();
    await Future.delayed(const Duration(seconds: 2));

    Uint8List bytes;
    if (fileInAssets && assetPath != null) {
      // Load firmware from assets
      final ByteData data = await rootBundle.load(assetPath);
      bytes = data.buffer.asUint8List();
    } else if (zipFilePath != null) {
      // Load firmware from file path
      bytes = await File(zipFilePath).readAsBytes();
    } else {
      // Default to downloaded firmware
      String firmwareFile = '${(await getApplicationDocumentsDirectory()).path}/firmware.zip';
      bytes = await File(firmwareFile).readAsBytes();
    }
    const configuration = mcumgr.FirmwareUpgradeConfiguration(
      estimatedSwapTime: Duration(seconds: 0),
      eraseAppSettings: true,
      pipelineDepth: 1,
    );
    final updateManager = await managerFactory!.getUpdateManager(btDevice.id);
    final List<McuMgrImage> processedImages = await _processZip(bytes);
    final List<mcumgr.Image> imagesToUpdate = processedImages.map((img) => 
        mcumgr.Image(image: img.image, data: img.data, hash: Uint8List.fromList(utf8.encode(img.hash)))
    ).toList();

    final updateStream = updateManager.setup();

    updateStream.listen((state) {
      if (state == mcumgr.FirmwareUpgradeState.success) {
        debugPrint('update success');
        setState(() {
          isInstalling = false;
          isInstalled = true;
        });
      } else {
        debugPrint('update state: $state');
      }
    });

    updateManager.progressStream.listen((progress) {
      debugPrint('progress: $progress');
      setState(() {
        installProgress = (progress.bytesSent / progress.imageSize * 100).round();
      });
    });

    updateManager.logger.logMessageStream
        .where((log) => log.level.rawValue > 1)
        .listen((log) {
      debugPrint('dfu log: ${log.message}');
    });

    await updateManager.update(
      imagesToUpdate,
      configuration: configuration,
    );
  }

  Future<void> startLegacyDfu(BtDevice btDevice, {bool fileInAssets = false, String? assetPath}) async {
    setState(() {
      isInstalling = true;
    });
    await Provider.of<MinimalDeviceProvider>(context, listen: false).prepareDFU();
    await Future.delayed(const Duration(seconds: 2));
    
    String firmwareFile;
    if (fileInAssets && assetPath != null) {
      // For assets, we need to copy to a temporary file first for Nordic DFU
      final ByteData data = await rootBundle.load(assetPath);
      final Directory tempDir = await getTemporaryDirectory();
      firmwareFile = '${tempDir.path}/temp_firmware.zip';
      final File tempFile = File(firmwareFile);
      await tempFile.writeAsBytes(data.buffer.asUint8List());
      debugPrint('Created temporary firmware file: $firmwareFile');
      debugPrint('File exists: ${await tempFile.exists()}');
      debugPrint('File size: ${await tempFile.length()} bytes');
    } else {
      firmwareFile = '${(await getApplicationDocumentsDirectory()).path}/firmware.zip';
    }
    NordicDfu dfu = NordicDfu();
    await dfu.startDfu(
      btDevice.id,
      firmwareFile,
      fileInAsset: false, // Always false since we handle asset loading ourselves
      numberOfPackets: 8,
      enableUnsafeExperimentalButtonlessServiceInSecureDfu: true,
      iosSpecialParameter: const IosSpecialParameter(
        packetReceiptNotificationParameter: 8,
        forceScanningForNewAddressInLegacyDfu: true,
        connectionTimeout: 60,
      ),
      androidSpecialParameter: const AndroidSpecialParameter(
        packetReceiptNotificationsEnabled: true,
        rebootTime: 1000,
      ),
      onProgressChanged: (deviceAddress, percent, speed, avgSpeed, currentPart, partsTotal) {
        debugPrint('deviceAddress: $deviceAddress, percent: $percent');
        setState(() {
          installProgress = percent.toInt();
        });
      },
      onError: (deviceAddress, error, errorType, message) =>
          debugPrint('deviceAddress: $deviceAddress, error: $error, errorType: $errorType, message: $message'),
      onDeviceConnecting: (deviceAddress) => debugPrint('deviceAddress: $deviceAddress, onDeviceConnecting'),
      onDeviceConnected: (deviceAddress) => debugPrint('deviceAddress: $deviceAddress, onDeviceConnected'),
      onDfuProcessStarting: (deviceAddress) => debugPrint('deviceAddress: $deviceAddress, onDfuProcessStarting'),
      onDfuProcessStarted: (deviceAddress) => debugPrint('deviceAddress: $deviceAddress, onDfuProcessStarted'),
      onEnablingDfuMode: (deviceAddress) => debugPrint('deviceAddress: $deviceAddress, onEnablingDfuMode'),
      onFirmwareValidating: (deviceAddress) => debugPrint('address: $deviceAddress, onFirmwareValidating'),
      onDfuCompleted: (deviceAddress) {
        debugPrint('deviceAddress: $deviceAddress, onDfuCompleted');
        setState(() {
          isInstalling = false;
          isInstalled = true;
        });
      },
    );
  }

  Future getLatestVersion(
      {required String deviceModelNumber,
      required String firmwareRevision,
      required String hardwareRevision,
      required String manufacturerName}) async {
    var deviceId = context.read<MinimalDeviceProvider>().connectedDevice?.id ?? '';
    if (deviceId.isEmpty) {
        print("Cannot get latest version, no device connected.");
        return;
    }

    latestFirmwareDetails = await DeviceApi.getLatestFirmwareVersion(deviceId);

    if (latestFirmwareDetails['ota_update_steps'] != null && latestFirmwareDetails['ota_update_steps'] is List) {
      otaUpdateSteps = List<String>.from(latestFirmwareDetails['ota_update_steps']);
    }
    if (latestFirmwareDetails['is_legacy_secure_dfu'] != null && latestFirmwareDetails['is_legacy_secure_dfu'] is bool) {
      isLegacySecureDFU = latestFirmwareDetails['is_legacy_secure_dfu'];
    }
    setState(() {});
  }

  Future downloadFirmware() async {
    final zipUrl = latestFirmwareDetails['zip_url'] as String?;
    if (zipUrl == null || zipUrl.isEmpty) {
      debugPrint('Error: zip_url is null or empty in latestFirmwareDetails');
      throw Exception("Firmware download URL not found");
    }

    setState(() {
      isDownloading = true;
      isDownloaded = false;
      downloadProgress = 0;
    });

    try {
      final response = await DeviceApi.downloadFirmware(zipUrl);
      if (response.statusCode == 200) {
        String dir = (await getApplicationDocumentsDirectory()).path;
        File file = File('$dir/firmware.zip');
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          isDownloading = false;
          isDownloaded = true;
        });
      } else {
        throw Exception('Failed to download firmware: Status code ${response.statusCode}');
      }
    } catch (e) {
       setState(() {
          isDownloading = false;
          isDownloaded = false;
       });
       debugPrint("Error downloading firmware: $e");
       rethrow;
    }
  }
}
