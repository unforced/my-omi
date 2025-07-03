import 'package:flutter/foundation.dart';

enum RecordingType {
  quick('Quick Note', '🔴', Duration(minutes: 2)),
  conversation('Conversation', '🔵', Duration(hours: 2)), 
  journal('Journal Entry', '🟣', Duration(minutes: 30));

  final String displayName;
  final String emoji;
  final Duration defaultMaxDuration;
  
  const RecordingType(this.displayName, this.emoji, this.defaultMaxDuration);
  
  static RecordingType fromTapCount(int taps) {
    switch (taps) {
      case 1:
        return RecordingType.quick;
      case 2:
        return RecordingType.conversation;
      case 3:
        return RecordingType.journal;
      default:
        return RecordingType.quick;
    }
  }
}

class Recording {
  final String id;
  final DateTime timestamp;
  final RecordingType type;
  final String audioPath;
  final Duration duration;
  final String? transcription;
  final List<String> keywords;
  final Map<String, dynamic> metadata;
  final bool isFavorite;
  final bool isArchived;

  Recording({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.audioPath,
    required this.duration,
    this.transcription,
    List<String>? keywords,
    Map<String, dynamic>? metadata,
    this.isFavorite = false,
    this.isArchived = false,
  }) : keywords = keywords ?? [],
       metadata = metadata ?? {};

  // Create a recording from a file path with type
  factory Recording.fromFile(String filePath, RecordingType type) {
    final fileName = filePath.split('/').last;
    final timestamp = DateTime.now(); // Could parse from filename
    
    return Recording(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: timestamp,
      type: type,
      audioPath: filePath,
      duration: Duration.zero, // Will be updated when audio is analyzed
    );
  }

  // Convert to/from JSON for storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'type': type.index,
    'audioPath': audioPath,
    'duration': duration.inSeconds,
    'transcription': transcription,
    'keywords': keywords,
    'metadata': metadata,
    'isFavorite': isFavorite,
    'isArchived': isArchived,
  };

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
    id: json['id'],
    timestamp: DateTime.parse(json['timestamp']),
    type: RecordingType.values[json['type']],
    audioPath: json['audioPath'],
    duration: Duration(seconds: json['duration']),
    transcription: json['transcription'],
    keywords: List<String>.from(json['keywords'] ?? []),
    metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    isFavorite: json['isFavorite'] ?? false,
    isArchived: json['isArchived'] ?? false,
  );

  // Helper methods
  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get displayTitle {
    if (transcription != null && transcription!.isNotEmpty) {
      // Return first line or first 50 chars of transcription
      final firstLine = transcription!.split('\n').first;
      return firstLine.length > 50 
        ? '${firstLine.substring(0, 47)}...' 
        : firstLine;
    }
    return '${type.displayName} - ${_formatTimestamp()}';
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordingDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    if (recordingDate == today) {
      return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (recordingDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  Recording copyWith({
    String? transcription,
    List<String>? keywords,
    Map<String, dynamic>? metadata,
    bool? isFavorite,
    bool? isArchived,
    Duration? duration,
  }) {
    return Recording(
      id: id,
      timestamp: timestamp,
      type: type,
      audioPath: audioPath,
      duration: duration ?? this.duration,
      transcription: transcription ?? this.transcription,
      keywords: keywords ?? this.keywords,
      metadata: metadata ?? this.metadata,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}