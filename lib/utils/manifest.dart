import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:path_provider/path_provider.dart';

class McuMgrImage {
  final int image;
  final String version;
  final String hash;
  final Uint8List data; // Added field to hold image data after extraction

  McuMgrImage({
    required this.image,
    required this.version,
    required this.hash,
    required this.data, // Added parameter
  });
}

// Utility function adapted from firmware_mixin.dart (original location unknown)
Future<List<McuMgrImage>> processZipFile(Uint8List zipData) async {
  final tempDir = await getTemporaryDirectory();
  final zipFile = File('${tempDir.path}/firmware_temp.zip');
  await zipFile.writeAsBytes(zipData);

  final destinationDir = Directory('${tempDir.path}/firmware_unzipped');
  if (await destinationDir.exists()) {
    await destinationDir.delete(recursive: true);
  }
  await destinationDir.create();

  try {
    await ZipFile.extractToDirectory(
        zipFile: zipFile, destinationDir: destinationDir);
  } catch (e) {
    print('Error extracting zip file: $e');
    rethrow;
  } finally {
    await zipFile.delete();
  }

  final manifestFile = File('${destinationDir.path}/manifest.json');
  if (!await manifestFile.exists()) {
    throw Exception('manifest.json not found in the zip file');
  }

  final manifestContent = await manifestFile.readAsString();
  final manifestJson = jsonDecode(manifestContent);

  // Assuming manifest structure like: { "files": [ { "image": 0, "file": "app_update.bin", ... }, ... ] }
  if (manifestJson['files'] == null || manifestJson['files'] is! List) {
    throw Exception('Invalid manifest format: missing or invalid "files" list');
  }

  final List<McuMgrImage> images = [];
  for (var fileInfo in manifestJson['files']) {
    final imageName = fileInfo['file'];
    final imageFile = File('${destinationDir.path}/$imageName');
    if (!await imageFile.exists()) {
      throw Exception('Image file $imageName listed in manifest not found');
    }
    final imageData = await imageFile.readAsBytes();

    images.add(McuMgrImage(
      // Use null-aware operators and provide defaults
      image: fileInfo['image'] as int? ?? 0, 
      version: fileInfo['version'] as String? ?? '0.0.0',
      hash: fileInfo['hash'] as String? ?? '', 
      data: imageData,
    ));
  }

  await destinationDir.delete(recursive: true);
  return images;
}
