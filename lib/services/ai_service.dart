import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AIServiceType {
  perplexity('Perplexity', 'https://api.perplexity.ai'),
  openai('OpenAI', 'https://api.openai.com/v1'),
  anthropic('Claude', 'https://api.anthropic.com/v1'),
  google('Gemini', 'https://generativelanguage.googleapis.com/v1'),
  local('Local LLM', 'http://localhost:8080'); // For Ollama or similar

  final String displayName;
  final String baseUrl;
  
  const AIServiceType(this.displayName, this.baseUrl);
}

abstract class AIService {
  Future<AIResponse> query(String transcript, {Map<String, dynamic>? context});
  Future<void> configure(Map<String, dynamic> settings);
  bool get requiresApiKey;
  String get serviceName;
  
  // Helper to build context-aware prompts
  String buildContextualPrompt(String query, Map<String, dynamic>? context) {
    final buffer = StringBuffer(query);
    
    if (context != null) {
      if (context['location'] != null) {
        buffer.write('\n\nCurrent location: ${context['location']}');
      }
      if (context['time'] != null) {
        buffer.write('\n\nCurrent time: ${context['time']}');
      }
      if (context['previousQueries'] != null) {
        buffer.write('\n\nPrevious context: ${context['previousQueries']}');
      }
    }
    
    return buffer.toString();
  }
}

class AIResponse {
  final String text;
  final Map<String, dynamic>? metadata;
  final List<String>? sources;
  final DateTime timestamp;
  
  AIResponse({
    required this.text,
    this.metadata,
    this.sources,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'text': text,
    'metadata': metadata,
    'sources': sources,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory AIResponse.fromJson(Map<String, dynamic> json) => AIResponse(
    text: json['text'],
    metadata: json['metadata'],
    sources: json['sources'] != null ? List<String>.from(json['sources']) : null,
    timestamp: DateTime.parse(json['timestamp']),
  );
}

// Perplexity Implementation
class PerplexityService extends AIService {
  String? _apiKey;
  String _model = 'sonar-medium-online'; // Good for real-time info
  
  @override
  String get serviceName => 'Perplexity';
  
  @override
  bool get requiresApiKey => true;
  
  @override
  Future<void> configure(Map<String, dynamic> settings) async {
    _apiKey = settings['apiKey'];
    _model = settings['model'] ?? _model;
  }
  
  @override
  Future<AIResponse> query(String transcript, {Map<String, dynamic>? context}) async {
    if (_apiKey == null) {
      throw Exception('Perplexity API key not configured');
    }
    
    final prompt = buildContextualPrompt(transcript, context);
    
    try {
      final response = await http.post(
        Uri.parse('${AIServiceType.perplexity.baseUrl}/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': _model,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'return_citations': true, // Perplexity feature
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final message = data['choices'][0]['message']['content'];
        final citations = data['citations'] as List?;
        
        return AIResponse(
          text: message,
          sources: citations?.map((c) => c.toString()).toList(),
          metadata: {'model': _model},
        );
      } else {
        throw Exception('Perplexity API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Perplexity query error: $e');
      rethrow;
    }
  }
}

// OpenAI Implementation
class OpenAIService extends AIService {
  String? _apiKey;
  String _model = 'gpt-4-turbo-preview';
  
  @override
  String get serviceName => 'OpenAI';
  
  @override
  bool get requiresApiKey => true;
  
  @override
  Future<void> configure(Map<String, dynamic> settings) async {
    _apiKey = settings['apiKey'];
    _model = settings['model'] ?? _model;
  }
  
  @override
  Future<AIResponse> query(String transcript, {Map<String, dynamic>? context}) async {
    if (_apiKey == null) {
      throw Exception('OpenAI API key not configured');
    }
    
    final prompt = buildContextualPrompt(transcript, context);
    
    try {
      final response = await http.post(
        Uri.parse('${AIServiceType.openai.baseUrl}/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': 'You are a helpful AI assistant accessed through a wearable device. Be concise but informative.'},
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final message = data['choices'][0]['message']['content'];
        
        return AIResponse(
          text: message,
          metadata: {'model': _model, 'usage': data['usage']},
        );
      } else {
        throw Exception('OpenAI API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('OpenAI query error: $e');
      rethrow;
    }
  }
}

// AI Service Manager
class AIServiceManager extends ChangeNotifier {
  static const String _prefsKeyService = 'ai_service_type';
  static const String _prefsKeySettings = 'ai_service_settings';
  
  final Map<AIServiceType, AIService> _services = {
    AIServiceType.perplexity: PerplexityService(),
    AIServiceType.openai: OpenAIService(),
    // Add more services as needed
  };
  
  AIServiceType _activeServiceType = AIServiceType.openai;
  AIService? _activeService;
  Map<String, dynamic> _currentSettings = {};
  
  // Query history for context
  final List<AIQueryRecord> _queryHistory = [];
  List<AIQueryRecord> get queryHistory => List.unmodifiable(_queryHistory);
  
  AIServiceType get activeServiceType => _activeServiceType;
  AIService? get activeService => _activeService;
  Map<String, dynamic> get currentSettings => Map.unmodifiable(_currentSettings);
  bool get isConfigured => _activeService != null && _currentSettings.containsKey('apiKey') && _currentSettings['apiKey']?.isNotEmpty == true;
  
  AIServiceManager() {
    _loadConfiguration();
  }
  
  Future<void> _loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load service type
    final serviceTypeIndex = prefs.getInt(_prefsKeyService);
    if (serviceTypeIndex != null && serviceTypeIndex < AIServiceType.values.length) {
      _activeServiceType = AIServiceType.values[serviceTypeIndex];
    }
    
    // Load settings
    final settingsJson = prefs.getString(_prefsKeySettings);
    if (settingsJson != null) {
      _currentSettings = json.decode(settingsJson);
      await setActiveService(_activeServiceType, _currentSettings);
    }
    
    notifyListeners();
  }
  
  Future<void> setActiveService(AIServiceType type, Map<String, dynamic> settings) async {
    _activeServiceType = type;
    _activeService = _services[type];
    _currentSettings = settings;
    
    if (_activeService != null) {
      await _activeService!.configure(settings);
    }
    
    // Save configuration
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyService, type.index);
    await prefs.setString(_prefsKeySettings, json.encode(settings));
    
    notifyListeners();
  }
  
  Future<AIResponse> query(String transcript) async {
    if (_activeService == null) {
      throw Exception('No AI service configured');
    }
    
    // Build context from recent queries
    final context = {
      'time': DateTime.now().toString(),
      if (_queryHistory.isNotEmpty)
        'previousQueries': _queryHistory.take(3).map((q) => q.query).join('; '),
    };
    
    try {
      final response = await _activeService!.query(transcript, context: context);
      
      // Save to history
      final record = AIQueryRecord(
        query: transcript,
        response: response,
        service: _activeServiceType,
        timestamp: DateTime.now(),
      );
      
      _queryHistory.insert(0, record);
      
      // Keep only last 50 queries
      if (_queryHistory.length > 50) {
        _queryHistory.removeRange(50, _queryHistory.length);
      }
      
      notifyListeners();
      
      return response;
    } catch (e) {
      debugPrint('AI query failed: $e');
      rethrow;
    }
  }
  
  void clearHistory() {
    _queryHistory.clear();
    notifyListeners();
  }
}

// Query record for history
class AIQueryRecord {
  final String query;
  final AIResponse response;
  final AIServiceType service;
  final DateTime timestamp;
  
  AIQueryRecord({
    required this.query,
    required this.response,
    required this.service,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'query': query,
    'response': response.toJson(),
    'service': service.index,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory AIQueryRecord.fromJson(Map<String, dynamic> json) => AIQueryRecord(
    query: json['query'],
    response: AIResponse.fromJson(json['response']),
    service: AIServiceType.values[json['service']],
    timestamp: DateTime.parse(json['timestamp']),
  );
}