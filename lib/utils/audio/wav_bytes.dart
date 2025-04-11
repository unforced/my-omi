import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:omi_minimal_fork/backend/schema/bt_device/bt_device.dart';
import 'package:intl/intl.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tuple/tuple.dart';

/// A class to handle WAV file format conversion
class WavBytes {
  final Uint8List _pcmData;
  final int _sampleRate;
  final int _numChannels;
  final int _bitsPerSample = 16; // PCM is typically 16-bit

  WavBytes._(this._pcmData, this._sampleRate, this._numChannels);

  /// Create a WAV bytes object from PCM data
  factory WavBytes.fromPcm(
    Uint8List pcmData, {
    required int sampleRate,
    required int numChannels,
  }) {
    return WavBytes._(pcmData, sampleRate, numChannels);
  }

  /// Convert to WAV format bytes
  Uint8List asBytes() {
    // Calculate sizes
    final int byteRate = _sampleRate * _numChannels * _bitsPerSample ~/ 8;
    final int blockAlign = _numChannels * _bitsPerSample ~/ 8;
    final int subchunk2Size = _pcmData.length;
    final int chunkSize = 36 + subchunk2Size;

    // Create a buffer for the WAV header (44 bytes) + PCM data
    final ByteData wavData = ByteData(44 + _pcmData.length);

    // Write WAV header
    // "RIFF" chunk descriptor
    wavData.setUint8(0, 0x52); // 'R'
    wavData.setUint8(1, 0x49); // 'I'
    wavData.setUint8(2, 0x46); // 'F'
    wavData.setUint8(3, 0x46); // 'F'
    wavData.setUint32(4, chunkSize, Endian.little); // Chunk size
    wavData.setUint8(8, 0x57); // 'W'
    wavData.setUint8(9, 0x41); // 'A'
    wavData.setUint8(10, 0x56); // 'V'
    wavData.setUint8(11, 0x45); // 'E'

    // "fmt " sub-chunk
    wavData.setUint8(12, 0x66); // 'f'
    wavData.setUint8(13, 0x6D); // 'm'
    wavData.setUint8(14, 0x74); // 't'
    wavData.setUint8(15, 0x20); // ' '
    wavData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    wavData.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    wavData.setUint16(22, _numChannels, Endian.little); // NumChannels
    wavData.setUint32(24, _sampleRate, Endian.little); // SampleRate
    wavData.setUint32(28, byteRate, Endian.little); // ByteRate
    wavData.setUint16(32, blockAlign, Endian.little); // BlockAlign
    wavData.setUint16(34, _bitsPerSample, Endian.little); // BitsPerSample

    // "data" sub-chunk
    wavData.setUint8(36, 0x64); // 'd'
    wavData.setUint8(37, 0x61); // 'a'
    wavData.setUint8(38, 0x74); // 't'
    wavData.setUint8(39, 0x61); // 'a'
    wavData.setUint32(40, subchunk2Size, Endian.little); // Subchunk2Size

    // Copy PCM data
    for (int i = 0; i < _pcmData.length; i++) {
      wavData.setUint8(44 + i, _pcmData[i]);
    }

    return wavData.buffer.asUint8List();
  }
}

class WavBytesUtil {
  // Store the codec determined during initialization
  BleAudioCodec codec;
  List<List<int>> frames = [];
  List<List<int>> rawPackets = [];
  
  // Initialize OpusDecoder lazily or based on codec
  SimpleOpusDecoder? _opusDecoder; 

  // Constructor now requires the codec
  WavBytesUtil({required this.codec}) {
     // Initialize decoder only if codec is Opus
     if (codec == BleAudioCodec.opus) {
       // Assuming 16kHz, 1 channel based on Omi spec
       _opusDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);
     }
  }

  // needed variables for `storeFramePacket`
  int lastPacketIndex = -1;
  int lastFrameId = -1;
  List<int> pending = [];
  int lost = 0;

  void storeFramePacket(value) {
    rawPackets.add(value);
    int index = value[0] + (value[1] << 8);
    int internal = value[2];
    List<int> content = value.sublist(3);

    // Start of a new frame
    if (lastPacketIndex == -1 && internal == 0) {
      lastPacketIndex = index;
      lastFrameId = internal;
      pending = content;
      return;
    }

    if (lastPacketIndex == -1) return;

    // Lost frame - reset state
    if (index != lastPacketIndex + 1 || (internal != 0 && internal != lastFrameId + 1)) {
      debugPrint('Lost frame');
      lastPacketIndex = -1;
      pending = [];
      lost += 1;
      return;
    }

    // Start of a new frame
    if (internal == 0) {
      frames.add(pending); // Save frame
      pending = content; // Start new frame
      lastFrameId = internal; // Update internal frame id
      lastPacketIndex = index; // Update packet id
      return;
    }

    // Continue frame
    pending.addAll(content);
    lastFrameId = internal; // Update internal frame id
    lastPacketIndex = index; // Update packet id
  }

  // Call this potentially before getting frames to ensure the last pending frame is added
  void finalizeCurrentFrame() {
      if (pending.isNotEmpty) {
          debugPrint("[WavBytesUtil] Finalizing pending frame (size=${pending.length}).");
          frames.add(List<int>.from(pending)); // Add a copy
          pending.clear();
          lastPacketIndex = -1; // Reset state
          lastFrameId = -1;
      }
  }

  void removeFramesRange({
    int fromSecond = 0, // unused
    int toSecond = 0,
  }) {
    debugPrint('removing frames from ${fromSecond}s to ${toSecond}s');
    frames.removeRange(fromSecond * 100, min(toSecond * 100, frames.length));
    debugPrint('frames length: ${frames.length}');
  }

  void insertAudioBytes(List<List<int>> bytes) => frames.insertAll(0, bytes);

  void clearAudioBytes() => {frames.clear(), rawPackets.clear()};

  bool hasFrames() => frames.isNotEmpty;

  // Standardize directory
  static Future<Directory> getDir() => getApplicationDocumentsDirectory();

  Future<Tuple2<File, List<List<int>>>> createWavFile({String? filename, int removeLastNSeconds = 0}) async {
    debugPrint('createWavFile $filename');
    List<List<int>> framesCopy;
    if (removeLastNSeconds > 0) {
      removeFramesRange(fromSecond: (frames.length ~/ 100) - removeLastNSeconds, toSecond: frames.length ~/ 100);
      framesCopy = List<List<int>>.from(frames);
    } else {
      framesCopy = List<List<int>>.from(frames);
      clearAudioBytes();
    }
    File file = await createWavByCodec(framesCopy, filename: filename);
    return Tuple2(file, framesCopy);
  }

  Future<File> createWavByCodec(List<List<int>> frames, {String? filename}) async {
    Uint8List wavBytes;
    int sampleRate = 16000; // Default/Opus sample rate

    if (codec == BleAudioCodec.pcm8) {
      sampleRate = 8000;
      // Assuming frames contain raw PCM8 data 
      List<int> pcmData = frames.expand((f) => f).toList(); 
      wavBytes = getUInt8ListBytes(pcmData, sampleRate);
    } else if (codec == BleAudioCodec.pcm16) {
       sampleRate = 16000;
      // Assuming frames contain raw PCM16 data
      List<int> pcmData = frames.expand((f) => f).toList(); 
      wavBytes = getUInt8ListBytes(pcmData, sampleRate);
    } else if (codec == BleAudioCodec.mulaw8 || codec == BleAudioCodec.mulaw16) {
      // CrashReporting.reportHandledCrash(...) // Keep error handling concept
      throw UnimplementedError('mulaw codec not implemented');
    } else if (codec == BleAudioCodec.opus) {
       sampleRate = 16000;
       if (_opusDecoder == null) {
         throw StateError('Opus codec specified but decoder not initialized.');
       }
      List<int> decodedSamples = [];
      try {
        for (var frame in frames) {
          // Ensure frame is Uint8List for decoder
          decodedSamples.addAll(_opusDecoder!.decode(input: Uint8List.fromList(frame)));
        }
      } catch (e, stackTrace) {
        debugPrint('Error decoding audio: $e\n$stackTrace');
        throw Exception('Opus decoding failed: $e');
      }
      wavBytes = getUInt8ListBytes(decodedSamples, sampleRate);
    } else {
      // CrashReporting.reportHandledCrash(...)
      throw UnimplementedError('unknown codec: $codec');
    }
    // Pass the determined sample rate to createWav
    return createWav(wavBytes, filename: filename, sampleRate: sampleRate);
  }

  Future<File> createWav(Uint8List wavData, {String? filename, int sampleRate = 16000}) async {
    final directory = await getDir();
    filename ??= 'recording-${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.wav';
    final file = File('${directory.path}/$filename');

    // Generate header with correct sample rate BEFORE writing
    Uint8List header = getWavHeader(wavData.length, sampleRate); 
    // Combine header and data
    Uint8List fullWavBytes = Uint8List.fromList(header + wavData);

    await file.writeAsBytes(fullWavBytes); // Write combined data
    debugPrint('WAV file created: ${file.path}');
    return file;
  }

  // Update getUInt8ListBytes to return ONLY PCM data bytes
  Uint8List getUInt8ListBytes(List<int> pcmSamples, int sampleRate) {
    // This function should just convert PCM samples to bytes
    return WavBytesUtil.convertToLittleEndianBytes(pcmSamples);
  }

  // Utility to convert integer PCM samples to little-endian bytes
  static Uint8List convertToLittleEndianBytes(List<int> audioData) {
    final byteData = ByteData(2 * audioData.length);
    for (int i = 0; i < audioData.length; i++) {
      byteData.setInt16(i * 2, audioData[i], Endian.little); // Use setInt16 for PCM samples
    }
    return byteData.buffer.asUint8List();
  }

  // getWavHeader remains largely the same, ensures sampleWidth is correct
  static Uint8List getWavHeader(int dataLength, int sampleRate, {int bitsPerSample = 16, int channelCount = 1}) {
    final int sampleWidth = bitsPerSample ~/ 8; // Calculate sampleWidth
    final byteData = ByteData(44);
    final size = dataLength + 36;
    final byteRate = sampleRate * channelCount * sampleWidth;
    final blockAlign = channelCount * sampleWidth;

    // RIFF chunk
    byteData.setUint8(0, 0x52); byteData.setUint8(1, 0x49); byteData.setUint8(2, 0x46); byteData.setUint8(3, 0x46);
    byteData.setUint32(4, size, Endian.little);
    byteData.setUint8(8, 0x57); byteData.setUint8(9, 0x41); byteData.setUint8(10, 0x56); byteData.setUint8(11, 0x45);

    // fmt chunk
    byteData.setUint8(12, 0x66); byteData.setUint8(13, 0x6D); byteData.setUint8(14, 0x74); byteData.setUint8(15, 0x20);
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little); // Audio format (1 = PCM)
    byteData.setUint16(22, channelCount, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, byteRate, Endian.little); // ByteRate
    byteData.setUint16(32, blockAlign, Endian.little); // BlockAlign
    byteData.setUint16(34, bitsPerSample, Endian.little); // BitsPerSample

    // data chunk
    byteData.setUint8(36, 0x64); byteData.setUint8(37, 0x61); byteData.setUint8(38, 0x74); byteData.setUint8(39, 0x61);
    byteData.setUint32(40, dataLength, Endian.little); // Subchunk2Size

    return byteData.buffer.asUint8List();
  }
}
