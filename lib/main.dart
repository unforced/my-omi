import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:omi_minimal_fork/services/services.dart'; // Import ServiceManager
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter; // Import Opus
import 'package:opus_dart/opus_dart.dart'; // Import Opus
import 'package:provider/provider.dart'; // Import Provider
import 'package:omi_minimal_fork/providers/device_provider.dart'; // Import MinimalDeviceProvider
import 'package:omi_minimal_fork/providers/capture_provider.dart'; // Import MinimalCaptureProvider
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart'; // Import BtDevice
import 'package:omi_minimal_fork/services/devices.dart'; // Import DeviceConnectionState
import 'package:just_audio/just_audio.dart'; // Import just_audio
import 'package:share_plus/share_plus.dart'; // Import share_plus
import 'package:device_info_plus/device_info_plus.dart'; // Import device_info_plus
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // Import FlutterBluePlus
import 'package:omi_minimal_fork/utils/audio/wav_bytes.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:omi_minimal_fork/utils/firmware_mixin.dart';
import 'package:file_picker/file_picker.dart';

// TODO: Add imports for State Management (Provider)

Future<void> _requestPermissions() async {
  Map<Permission, PermissionStatus> permissionsToRequest = {};
  bool permissionsGranted = true;

  if (Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt <= 30) { // Android 11 (API 30) or lower
      permissionsToRequest = {
        Permission.bluetooth: await Permission.bluetooth.status,
        Permission.locationWhenInUse: await Permission.locationWhenInUse.status, // Needed for scanning
        Permission.storage: await Permission.storage.status, // For saving files
      };
    } else { // Android 12 (API 31) or higher
      permissionsToRequest = {
        Permission.bluetoothScan: await Permission.bluetoothScan.status,
        Permission.bluetoothConnect: await Permission.bluetoothConnect.status,
        Permission.locationWhenInUse: await Permission.locationWhenInUse.status, // Still often needed
        Permission.storage: await Permission.storage.status, // Needs review for Android 13+ scoped storage
      };
    }
  } else if (Platform.isIOS) {
    // iOS permissions (unchanged for now)
    permissionsToRequest = {
      Permission.bluetooth: await Permission.bluetooth.status,
      // Permission.photos: await Permission.photos.status, // Uncomment if saving to gallery
      // Permission.microphone: await Permission.microphone.status, // Uncomment if local mic used
    };
  }

  // Filter out permissions that are already granted
  Map<Permission, PermissionStatus> permissionsToActuallyRequest = {};
  permissionsToRequest.forEach((permission, status) {
    if (!status.isGranted) {
      permissionsToActuallyRequest[permission] = status;
    }
  });

  // Request only the permissions that are not granted
  if (permissionsToActuallyRequest.isNotEmpty) {
    Map<Permission, PermissionStatus> finalStatuses = await permissionsToActuallyRequest.keys.toList().request();
    
    finalStatuses.forEach((permission, status) {
      if (!status.isGranted) {
        permissionsGranted = false;
        print('Permission denied: $permission');
        // TODO: Show a user-friendly message explaining why the permission is needed
        // and potentially guide them to settings if permanently denied.
      }
    });
  } else {
     print("All required permissions already granted.");
  }

  if (!permissionsGranted) {
      // Handle the case where essential permissions were denied
      print("Warning: Not all required permissions were granted. App functionality may be limited.");
      // Optionally, show a dialog and maybe exit the app if critical permissions are missing.
  }
}

void main() async { // Make main async
  WidgetsFlutterBinding.ensureInitialized(); // Ensure bindings are initialized

  // Set FBP log level to Warning
  FlutterBluePlus.setLogLevel(LogLevel.warning, color: true);
  debugPrint("Set FlutterBluePlus log level to warning.");

  await _requestPermissions(); // Request permissions early

  // Initialize ServiceManager
  ServiceManager.init();
  await ServiceManager.instance().start();
  try {
    initOpus(await opus_flutter.load());
    print("Opus initialized successfully.");
  } catch (e) {
    print("Error initializing Opus: $e");
  }

  // Initialize State Management (Providers)
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MinimalDeviceProvider()),
        ChangeNotifierProvider(create: (_) => MinimalCaptureProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // Add the navigator key
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Call deinit here - might need to be async depending on implementation
    ServiceManager.instance().deinit(); 
    print("ServiceManager deinited.");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Optional: Handle background/foreground transitions if needed
    if (state == AppLifecycleState.detached) {
        // Might also call deinit here for robustness
        ServiceManager.instance().deinit();
        print("ServiceManager deinited on detached.");
    }
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Providers are now above MyApp in the widget tree
    return MaterialApp(
      navigatorKey: MyApp.navigatorKey, // Access static key via class name
      title: 'Omi Minimal Fork', // Updated title
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.dark),
        useMaterial3: true,
        brightness: Brightness.dark, // Use dark theme
      ),
      home: const HomePage(), // Use new HomePage
    );
  }
}

// Updated HomePage Widget
class HomePage extends StatefulWidget { // Change to StatefulWidget
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Apply FirmwareMixin and add state for selected file
class _HomePageState extends State<HomePage> with FirmwareMixin<HomePage> { // Create State and add Mixin
  final AudioPlayer _audioPlayer = AudioPlayer(); // Audio player instance
  String? _selectedFirmwarePath;

  @override
  void dispose() {
    _audioPlayer.dispose(); // Dispose player
    super.dispose();
  }

  // --- Button Action Handlers --- 
  Future<void> _playAudio(String filePath) async {
    try {
       if (_audioPlayer.playing) {
           await _audioPlayer.stop();
       }
       await _audioPlayer.setFilePath(filePath);
       await _audioPlayer.play();
    } catch (e) {
        print("Error playing audio: $e");
        // Show snackbar or dialog
        ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Error playing audio: $e"))
        );
    }
  }

  Future<void> _shareAudio(String filePath) async {
    try {
        final result = await Share.shareXFiles([XFile(filePath)], text: 'Omi Recording');
        if (result.status == ShareResultStatus.success) {
            print('Thank you for sharing the picture!');
        } 
    } catch (e) {
        print("Error sharing audio: $e");
         ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Error sharing audio: $e"))
        );
    }
  }

  Future<void> _deleteAudio(BuildContext context, String filePath) async {
    // Confirmation dialog
    bool confirmDelete = await showDialog(
        context: context,
        builder: (BuildContext ctx) {
            return AlertDialog(
                title: const Text('Confirm Delete'),
                content: const Text('Are you sure you want to delete this recording?'),
                actions: <Widget>[
                    TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(ctx).pop(false)),
                    TextButton(child: const Text('Delete'), onPressed: () => Navigator.of(ctx).pop(true)),
                ],
            );
        },
    ) ?? false;

    if (confirmDelete) {
        try {
            final file = File(filePath);
            if (await file.exists()) {
                await file.delete();
                print("Deleted file: $filePath");
                // Update state via provider
                Provider.of<MinimalDeviceProvider>(context, listen: false).removeRecording(filePath);
            } else {
                 print("File not found for deletion: $filePath");
                 // Might still remove from list if state is inconsistent
                 Provider.of<MinimalDeviceProvider>(context, listen: false).removeRecording(filePath);
            }
        } catch (e) {
            print("Error deleting audio: $e");
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Error deleting audio: $e"))
            );
        }
    }
  }

  // TODO: Implement _transcribeAudio(String filePath) if Whisper is added

  @override
  Widget build(BuildContext context) {
    // Access providers within build method
    final deviceProvider = Provider.of<MinimalDeviceProvider>(context);
    final captureProvider = Provider.of<MinimalCaptureProvider>(context, listen: false); // Typically don't listen for actions

    return Scaffold(
      appBar: AppBar(
        title: const Text('Omi Minimal Fork'),
        actions: [
          // Scan Button
          IconButton(
            icon: Icon(deviceProvider.isScanning ? Icons.stop : Icons.search),
            tooltip: deviceProvider.isScanning ? 'Stop Scan' : 'Scan for Devices',
            onPressed: deviceProvider.isScanning
                ? null 
                : () => deviceProvider.startScan(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Connection Section ---
            Consumer<MinimalDeviceProvider>(
              builder: (context, provider, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          provider.connectionState == DeviceConnectionState.connected && provider.connectedDevice != null
                              ? 'Connected to: ${provider.connectedDevice!.name}'
                              : provider.isConnecting
                                ? 'Connecting...'
                                : provider.isScanning
                                  ? 'Scanning...'
                                  : 'Disconnected',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        // Scan Button
                        IconButton(
                          icon: Icon(provider.isScanning ? Icons.bluetooth_searching : Icons.bluetooth),
                          tooltip: 'Scan for Devices',
                          onPressed: provider.isScanning || provider.isConnecting
                              ? null // Disable if scanning or connecting
                              : () => provider.startScan(),
                        ),
                      ],
                    ),
                    if (provider.connectionState == DeviceConnectionState.connected && provider.connectedDevice != null)
                      ElevatedButton.icon(
                         icon: const Icon(Icons.link_off),
                         label: const Text('Disconnect'),
                         onPressed: () => provider.disconnect(),
                         style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                      ),
                    const SizedBox(height: 10),
                    if (provider.discoveredDevices.isNotEmpty && provider.connectionState != DeviceConnectionState.connected)
                      const Text('Found Devices:', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (provider.connectionState != DeviceConnectionState.connected)
                       SizedBox(
                          height: 100, // Limit height for discovered devices list
                          child: ListView.builder(
                              itemCount: provider.discoveredDevices.length,
                              itemBuilder: (context, index) {
                                  final device = provider.discoveredDevices[index];
                                  return ListTile(
                                      title: Text(device.name.isEmpty ? "(Unknown Device)" : device.name),
                                      subtitle: Text(device.id),
                                      trailing: ElevatedButton(
                                           child: const Text('Connect'),
                                           onPressed: provider.isConnecting ? null : () => provider.connectToDevice(device.id),
                                      ),
                                  );
                              },
                          ),
                       ),
                  ],
                );
              },
            ),
            const Divider(height: 30),

            // --- Recording Section ---
            Consumer<MinimalCaptureProvider>(
               builder: (context, captureProvider, child) {
                   // Accessing DeviceProvider to check connection state
                   final deviceProvider = context.watch<MinimalDeviceProvider>();
                   return Row(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                            ElevatedButton.icon(
                               // Use placeholder icons/text or fetch state differently
                               icon: Icon(deviceProvider.isRecording ? Icons.stop : Icons.mic),
                               label: Text(deviceProvider.isRecording ? 'Stop Recording' : 'Start Recording'),
                               onPressed: deviceProvider.connectionState == DeviceConnectionState.connected
                                    ? () {
                                        // We need to call methods on CaptureProvider
                                        // but the state is on DeviceProvider now
                                        if (deviceProvider.isRecording) {
                                            // Need a way to stop, maybe move stop logic to DeviceProvider
                                            // Or have CaptureProvider expose stop method directly
                                            captureProvider.stopRecordingAndSave(); // Assumes this method exists
                                            deviceProvider.setRecordingState(false); // Sync state
                                        } else {
                                            captureProvider.startRecording(); // Assumes this method exists
                                            deviceProvider.setRecordingState(true); // Sync state
                                        }
                                      }
                                    : null, // Disable if not connected
                               style: ElevatedButton.styleFrom(
                                  // Use state from DeviceProvider
                                  backgroundColor: deviceProvider.isRecording ? Colors.red : Colors.green,
                               ),
                           ),
                       ],
                   );
               }
            ),
            const SizedBox(height: 20),
            const Text('Saved Recordings:', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Consumer<MinimalDeviceProvider>(
                builder: (context, provider, child) {
                  if (provider.savedRecordings.isEmpty) {
                    return const Center(child: Text('No recordings saved yet.'));
                  }
                  return ListView.builder(
                    itemCount: provider.savedRecordings.length,
                    itemBuilder: (context, index) {
                      final filePath = provider.savedRecordings[index];
                      final fileName = filePath.split('/').last;
                      return Card(
                        child: ListTile(
                          title: Text(fileName),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Play', onPressed: () => _playAudio(filePath)),
                              IconButton(icon: const Icon(Icons.share), tooltip: 'Share', onPressed: () => _shareAudio(filePath)),
                              IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: () => _deleteAudio(context, filePath)),
                              // Optional Transcribe Button
                              // IconButton(icon: Icon(Icons.transcribe), tooltip: 'Transcribe', onPressed: () => _transcribeAudio(filePath)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 30),
            // --- Firmware Update Section ---
            const Text('Firmware Update', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
               icon: const Icon(Icons.file_open),
               label: const Text('Select Firmware File (.zip)'),
               onPressed: () async {
                 FilePickerResult? result = await FilePicker.platform.pickFiles(
                   type: FileType.custom,
                   allowedExtensions: ['zip'],
                 );
                 if (result != null && result.files.single.path != null) {
                   setState(() {
                     _selectedFirmwarePath = result.files.single.path!;
                   });
                   print('Selected firmware file: $_selectedFirmwarePath');
                 } else {
                   // User canceled the picker
                 }
               },
            ),
            if (_selectedFirmwarePath != null)
               Padding(
                 padding: const EdgeInsets.symmetric(vertical: 8.0),
                 child: Text('Selected: ${_selectedFirmwarePath!.split('/').last}'),
               ),
            const SizedBox(height: 10),
            Consumer<MinimalDeviceProvider>(
               builder: (context, provider, child) {
                  return ElevatedButton.icon(
                     icon: const Icon(Icons.system_update_alt),
                     label: const Text('Start Update'),
                     // Enable only if connected and file selected and not already installing
                     onPressed: provider.connectionState == DeviceConnectionState.connected && _selectedFirmwarePath != null && !isInstalling
                       ? () async {
                           if (provider.connectedDevice == null) return;
                           try {
                              // Use MCUmgr flow by default for robustness
                              await startMCUDfu(provider.connectedDevice!, zipFilePath: _selectedFirmwarePath!);
                           } catch (e) {
                             print("Error starting DFU: $e");
                             ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("DFU Error: $e"), backgroundColor: Colors.red)
                             );
                             // Reset installing state on error
                             if (mounted) { // Check if widget is still in tree
                               setState(() { isInstalling = false; });
                             }
                           }
                       } : null,
                  );
               }
            ),
            // DFU Status Display
            const SizedBox(height: 10),
            if (isDownloading) // Although downloadFirmware isn't called here, keep for potential future use
               Text('Downloading: $downloadProgress%'),
            if (isInstalling)
               Column(
                  children: [
                     Text('Installing Firmware: $installProgress%'),
                     const SizedBox(height: 5),
                     LinearProgressIndicator(value: installProgress / 100),
                  ],
               ),
            if (isInstalled)
               const Text('Firmware Update Successful!', style: TextStyle(color: Colors.green)),

          ],
        ),
      ),
    );
  }
}
