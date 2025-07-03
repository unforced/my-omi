import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

enum TranscriptionProvider {
  openaiWhisper('OpenAI Whisper', 'https://api.openai.com/v1/audio/transcriptions'),
  googleSpeech('Google Speech-to-Text', 'https://speech.googleapis.com/v1/speech:recognize'),
  local('Local Whisper', 'http://localhost:8080/transcribe'); // For self-hosted

  final String displayName;
  final String endpoint;
  
  const TranscriptionProvider(this.displayName, this.endpoint);
}

class TranscriptionResult {
  final String text;
  final String? language;
  final double? confidence;
  final Duration? duration;
  final Map<String, dynamic>? metadata;
  
  TranscriptionResult({
    required this.text,
    this.language,
    this.confidence,
    this.duration,
    this.metadata,
  });
}

abstract class TranscriptionService {
  Future<TranscriptionResult> transcribe(String audioPath, {String? language});
  Future<void> configure(Map<String, dynamic> settings);
  bool get requiresApiKey;
  String get serviceName;
}

// OpenAI Whisper Implementation
class WhisperService extends TranscriptionService {
  String? _apiKey;
  String _model = 'whisper-1';
  
  @override
  String get serviceName => 'OpenAI Whisper';
  
  @override
  bool get requiresApiKey => true;
  
  @override
  Future<void> configure(Map<String, dynamic> settings) async {
    _apiKey = settings['apiKey'];
    _model = settings['model'] ?? _model;
  }
  
  @override
  Future<TranscriptionResult> transcribe(String audioPath, {String? language}) async {
    if (_apiKey == null) {
      throw Exception('OpenAI API key not configured');
    }
    
    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $audioPath');
    }
    
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(TranscriptionProvider.openaiWhisper.endpoint),
      );
      
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.fields['model'] = _model;
      if (language != null) {
        request.fields['language'] = language;
      }
      request.fields['response_format'] = 'verbose_json'; // Get more metadata
      
      request.files.add(
        await http.MultipartFile.fromPath('file', audioPath),
      );
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        return TranscriptionResult(
          text: data['text'],
          language: data['language'],
          duration: data['duration'] != null 
            ? Duration(milliseconds: (data['duration'] * 1000).round())
            : null,
          metadata: {
            'segments': data['segments'],
            'task': data['task'],
          },
        );
      } else {
        throw Exception('Whisper API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Whisper transcription error: $e');
      rethrow;
    }
  }
}

// Local Whisper Implementation (for privacy-conscious users)
class LocalWhisperService extends TranscriptionService {
  String _endpoint = 'http://localhost:8080/transcribe';
  
  @override
  String get serviceName => 'Local Whisper';
  
  @override
  bool get requiresApiKey => false;
  
  @override
  Future<void> configure(Map<String, dynamic> settings) async {
    _endpoint = settings['endpoint'] ?? _endpoint;
  }
  
  @override
  Future<TranscriptionResult> transcribe(String audioPath, {String? language}) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $audioPath');
    }
    
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_endpoint),
      );
      
      if (language != null) {
        request.fields['language'] = language;
      }
      
      request.files.add(
        await http.MultipartFile.fromPath('audio', audioPath),
      );
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        return TranscriptionResult(
          text: data['text'] ?? data['transcription'],
          language: data['language'],
          confidence: data['confidence']?.toDouble(),
        );
      } else {
        throw Exception('Local Whisper error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Local Whisper error: $e');
      rethrow;
    }
  }
}

// Transcription Service Manager
class TranscriptionServiceManager extends ChangeNotifier {
  static const String _prefsKeyProvider = 'transcription_provider';
  static const String _prefsKeySettings = 'transcription_settings';
  
  final Map<TranscriptionProvider, TranscriptionService> _services = {
    TranscriptionProvider.openaiWhisper: WhisperService(),
    TranscriptionProvider.local: LocalWhisperService(),
  };
  
  TranscriptionProvider _activeProvider = TranscriptionProvider.openaiWhisper;
  TranscriptionService? _activeService;
  Map<String, dynamic> _currentSettings = {};
  bool _isTranscribing = false;
  
  TranscriptionProvider get activeProvider => _activeProvider;
  TranscriptionService? get activeService => _activeService;
  bool get isConfigured => _activeService != null && 
    (!_activeService!.requiresApiKey || _currentSettings.containsKey('apiKey'));
  bool get isTranscribing => _isTranscribing;
  
  TranscriptionServiceManager() {
    _loadConfiguration();
  }
  
  Future<void> _loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load provider
    final providerIndex = prefs.getInt(_prefsKeyProvider);
    if (providerIndex != null && providerIndex < TranscriptionProvider.values.length) {
      _activeProvider = TranscriptionProvider.values[providerIndex];
    }
    
    // Load settings
    final settingsJson = prefs.getString(_prefsKeySettings);
    if (settingsJson != null) {
      _currentSettings = json.decode(settingsJson);
      await setActiveProvider(_activeProvider, _currentSettings);
    }
    
    notifyListeners();
  }
  
  Future<void> setActiveProvider(TranscriptionProvider provider, Map<String, dynamic> settings) async {
    _activeProvider = provider;
    _activeService = _services[provider];
    _currentSettings = settings;
    
    if (_activeService != null) {
      await _activeService!.configure(settings);
    }
    
    // Save configuration
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyProvider, provider.index);
    await prefs.setString(_prefsKeySettings, json.encode(settings));
    
    notifyListeners();
  }
  
  Future<TranscriptionResult> transcribeAudio(String audioPath, {String? language}) async {
    if (_activeService == null) {
      throw Exception('No transcription service configured');
    }
    
    _isTranscribing = true;
    notifyListeners();
    
    try {
      final result = await _activeService!.transcribe(audioPath, language: language);
      
      _isTranscribing = false;
      notifyListeners();
      
      return result;
    } catch (e) {
      _isTranscribing = false;
      notifyListeners();
      
      debugPrint('Transcription failed: $e');
      rethrow;
    }
  }
  
  // Helper method to extract key phrases from transcription
  List<String> extractKeyPhrases(String text) {
    // Simple implementation - in production would use NLP
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'been', 'be',
      'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
      'should', 'may', 'might', 'must', 'can', 'this', 'that', 'these', 'those'
    };
    
    final phrases = <String>[];
    final wordCounts = <String, int>{};
    
    // Count word frequency
    for (final word in words) {
      if (word.length > 3 && !stopWords.contains(word)) {
        wordCounts[word] = (wordCounts[word] ?? 0) + 1;
      }
    }
    
    // Get top phrases
    final sorted = wordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    phrases.addAll(sorted.take(5).map((e) => e.key));
    
    return phrases;
  }
  
  // Helper to detect action items in transcription
  List<String> extractActionItems(String text) {
    final actionItems = <String>[];
    final lines = text.split(RegExp(r'[.!?]'));
    
    final actionPatterns = [
      RegExp(r'(need to|have to|should|must|will)\s+(.+)', caseSensitive: false),
      RegExp(r"(remember to|don't forget to)\s+(.+)", caseSensitive: false),
      RegExp(r'(todo|task):\s*(.+)', caseSensitive: false),
    ];
    
    for (final line in lines) {
      for (final pattern in actionPatterns) {
        final match = pattern.firstMatch(line.trim());
        if (match != null) {
          actionItems.add(match.group(2)?.trim() ?? line.trim());
          break;
        }
      }
    }
    
    return actionItems;
  }
}