import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omi_minimal_fork/models/recording.dart';

class RecordingService extends ChangeNotifier {
  static const String _recordingsKey = 'recordings_metadata';
  
  List<Recording> _recordings = [];
  List<Recording> get recordings => List.unmodifiable(_recordings);
  
  // Filtered views
  List<Recording> get quickNotes => _recordings.where((r) => r.type == RecordingType.quick && !r.isArchived).toList();
  List<Recording> get conversations => _recordings.where((r) => r.type == RecordingType.conversation && !r.isArchived).toList();
  List<Recording> get journalEntries => _recordings.where((r) => r.type == RecordingType.journal && !r.isArchived).toList();
  List<Recording> get favorites => _recordings.where((r) => r.isFavorite && !r.isArchived).toList();
  List<Recording> get archived => _recordings.where((r) => r.isArchived).toList();
  
  // Current recording type (set by button taps)
  RecordingType _currentRecordingType = RecordingType.quick;
  RecordingType get currentRecordingType => _currentRecordingType;
  
  // Search/filter
  String _searchQuery = '';
  set searchQuery(String query) {
    _searchQuery = query.toLowerCase();
    notifyListeners();
  }
  
  List<Recording> get filteredRecordings {
    if (_searchQuery.isEmpty) return recordings;
    
    return _recordings.where((recording) {
      // Search in transcription
      if (recording.transcription != null && 
          recording.transcription!.toLowerCase().contains(_searchQuery)) {
        return true;
      }
      
      // Search in keywords
      if (recording.keywords.any((k) => k.toLowerCase().contains(_searchQuery))) {
        return true;
      }
      
      // Search in title
      if (recording.displayTitle.toLowerCase().contains(_searchQuery)) {
        return true;
      }
      
      return false;
    }).toList();
  }
  
  RecordingService() {
    _loadRecordings();
  }
  
  // Set recording type based on button taps
  void setRecordingTypeFromTaps(int tapCount) {
    _currentRecordingType = RecordingType.fromTapCount(tapCount);
    debugPrint('[RecordingService] Recording type set to ${_currentRecordingType.displayName} from $tapCount taps');
    notifyListeners();
  }
  
  // Add a new recording
  Future<void> addRecording(String audioPath, {RecordingType? type}) async {
    final recording = Recording.fromFile(
      audioPath, 
      type ?? _currentRecordingType
    );
    
    _recordings.insert(0, recording); // Add to beginning
    await _saveRecordings();
    notifyListeners();
    
    // TODO: Trigger transcription job
    _scheduleTranscription(recording);
  }
  
  // Add a recording object directly (used by AI and knowledge capture)
  Future<void> addRecordingObject(Recording recording) async {
    _recordings.insert(0, recording); // Add to beginning
    await _saveRecordings();
    notifyListeners();
  }
  
  // Update recording (e.g., after transcription)
  Future<void> updateRecording(Recording recording) async {
    final index = _recordings.indexWhere((r) => r.id == recording.id);
    if (index != -1) {
      _recordings[index] = recording;
      await _saveRecordings();
      notifyListeners();
    }
  }
  
  // Toggle favorite
  Future<void> toggleFavorite(String recordingId) async {
    final index = _recordings.indexWhere((r) => r.id == recordingId);
    if (index != -1) {
      final recording = _recordings[index];
      _recordings[index] = recording.copyWith(isFavorite: !recording.isFavorite);
      await _saveRecordings();
      notifyListeners();
    }
  }
  
  // Archive/unarchive
  Future<void> toggleArchive(String recordingId) async {
    final index = _recordings.indexWhere((r) => r.id == recordingId);
    if (index != -1) {
      final recording = _recordings[index];
      _recordings[index] = recording.copyWith(isArchived: !recording.isArchived);
      await _saveRecordings();
      notifyListeners();
    }
  }
  
  // Delete recording
  Future<void> deleteRecording(String recordingId) async {
    final index = _recordings.indexWhere((r) => r.id == recordingId);
    if (index != -1) {
      final recording = _recordings[index];
      
      // Delete audio file
      try {
        final file = File(recording.audioPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('[RecordingService] Error deleting audio file: $e');
      }
      
      _recordings.removeAt(index);
      await _saveRecordings();
      notifyListeners();
    }
  }
  
  // Load recordings from storage
  Future<void> _loadRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordingsJson = prefs.getString(_recordingsKey);
      
      if (recordingsJson != null) {
        final List<dynamic> decodedList = json.decode(recordingsJson);
        _recordings = decodedList
            .map((json) => Recording.fromJson(json))
            .toList();
        
        // Sort by timestamp, newest first
        _recordings.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[RecordingService] Error loading recordings: $e');
    }
  }
  
  // Save recordings to storage
  Future<void> _saveRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordingsJson = json.encode(
        _recordings.map((r) => r.toJson()).toList()
      );
      await prefs.setString(_recordingsKey, recordingsJson);
    } catch (e) {
      debugPrint('[RecordingService] Error saving recordings: $e');
    }
  }
  
  // Schedule transcription (placeholder for now)
  void _scheduleTranscription(Recording recording) {
    // TODO: Implement transcription service
    // For now, just simulate with a delay
    Future.delayed(const Duration(seconds: 2), () {
      final mockTranscription = _getMockTranscription(recording.type);
      final updatedRecording = recording.copyWith(
        transcription: mockTranscription,
        keywords: _extractKeywords(mockTranscription),
        duration: const Duration(seconds: 45), // Mock duration
      );
      updateRecording(updatedRecording);
    });
  }
  
  String _getMockTranscription(RecordingType type) {
    switch (type) {
      case RecordingType.quick:
        return "Remember to send the quarterly report to Sarah by Friday. Also need to review the new design mockups.";
      case RecordingType.conversation:
        return "Team standup meeting. John mentioned the API integration is complete. Sarah is working on the UI updates. We agreed to push the release to next Tuesday.";
      case RecordingType.journal:
        return "Feeling productive today. The new feature implementation went smoothly. I'm grateful for the team's support during the challenging migration last week.";
    }
  }
  
  List<String> _extractKeywords(String text) {
    // Simple keyword extraction - in real app would use NLP
    final commonWords = {'the', 'to', 'is', 'a', 'and', 'of', 'in', 'on', 'for', 'with', 'by'};
    final words = text.toLowerCase().split(RegExp(r'\W+'));
    final keywords = words
        .where((w) => w.length > 3 && !commonWords.contains(w))
        .toSet()
        .take(5)
        .toList();
    return keywords;
  }
  
  // Get recordings by date range
  List<Recording> getRecordingsByDateRange(DateTime start, DateTime end) {
    return _recordings.where((r) => 
      r.timestamp.isAfter(start) && r.timestamp.isBefore(end)
    ).toList();
  }
  
  // Get today's recordings
  List<Recording> getTodaysRecordings() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return getRecordingsByDateRange(today, tomorrow);
  }
}