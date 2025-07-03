import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:omi_minimal_fork/services/transcription_service.dart';

class TranscriptionSettingsScreen extends StatefulWidget {
  const TranscriptionSettingsScreen({super.key});

  @override
  State<TranscriptionSettingsScreen> createState() => _TranscriptionSettingsScreenState();
}

class _TranscriptionSettingsScreenState extends State<TranscriptionSettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _endpointController = TextEditingController();
  bool _obscureApiKey = true;
  
  @override
  void dispose() {
    _apiKeyController.dispose();
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcription Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<TranscriptionServiceManager>(
        builder: (context, transcriptionManager, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Info Card
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.mic, 
                            color: Theme.of(context).colorScheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Text('Speech-to-Text', 
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Transcription converts your voice recordings to text, '
                        'enabling search, AI queries, and text export.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Provider Selection
              Text('Transcription Provider', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...TranscriptionProvider.values.map((provider) => 
                RadioListTile<TranscriptionProvider>(
                  title: Text(provider.displayName),
                  subtitle: Text(_getProviderDescription(provider)),
                  value: provider,
                  groupValue: transcriptionManager.activeProvider,
                  onChanged: (value) {
                    if (value != null) {
                      _selectProvider(value);
                    }
                  },
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Configuration based on provider
              if (transcriptionManager.activeProvider == TranscriptionProvider.openaiWhisper) ...[
                Text('OpenAI Configuration', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  decoration: InputDecoration(
                    labelText: 'OpenAI API Key',
                    hintText: 'sk-...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureApiKey ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          _obscureApiKey = !_obscureApiKey;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Get your API key from platform.openai.com/api-keys',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (transcriptionManager.activeProvider == TranscriptionProvider.local) ...[
                Text('Local Server Configuration', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _endpointController,
                  decoration: const InputDecoration(
                    labelText: 'Server Endpoint',
                    hintText: 'http://localhost:8080/transcribe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Run a local Whisper server for privacy. See docs for setup.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Save Button
              if (transcriptionManager.activeService?.requiresApiKey ?? false) ...[
                ElevatedButton.icon(
                  onPressed: _canSave() ? _saveConfiguration : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Configuration'),
                ),
              ] else if (transcriptionManager.activeProvider == TranscriptionProvider.local) ...[
                ElevatedButton.icon(
                  onPressed: _endpointController.text.isNotEmpty ? _saveConfiguration : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Configuration'),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Test Section
              if (transcriptionManager.isConfigured) ...[
                const Divider(),
                const SizedBox(height: 16),
                Text('Test Transcription', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: transcriptionManager.isTranscribing ? null : _testTranscription,
                        icon: transcriptionManager.isTranscribing 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mic),
                        label: Text(transcriptionManager.isTranscribing 
                          ? 'Transcribing...' 
                          : 'Test with Sample Audio'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'This will test transcription with a sample audio file',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              
              // Status
              if (transcriptionManager.isConfigured) ...[
                const SizedBox(height: 24),
                Card(
                  color: Colors.green.withOpacity(0.1),
                  child: const ListTile(
                    leading: Icon(Icons.check_circle, color: Colors.green),
                    title: Text('Transcription Configured'),
                    subtitle: Text('Ready to transcribe recordings'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 24),
                Card(
                  color: Colors.orange.withOpacity(0.1),
                  child: const ListTile(
                    leading: Icon(Icons.warning, color: Colors.orange),
                    title: Text('Configuration Required'),
                    subtitle: Text('Please configure transcription service'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
  
  String _getProviderDescription(TranscriptionProvider provider) {
    switch (provider) {
      case TranscriptionProvider.openaiWhisper:
        return 'Cloud-based, high accuracy, requires API key';
      case TranscriptionProvider.googleSpeech:
        return 'Google\'s speech recognition (coming soon)';
      case TranscriptionProvider.local:
        return 'Privacy-focused, runs on your local server';
    }
  }
  
  void _selectProvider(TranscriptionProvider provider) {
    setState(() {
      _apiKeyController.clear();
      _endpointController.clear();
    });
  }
  
  bool _canSave() {
    final transcriptionManager = Provider.of<TranscriptionServiceManager>(context, listen: false);
    if (transcriptionManager.activeProvider == TranscriptionProvider.openaiWhisper) {
      return _apiKeyController.text.isNotEmpty;
    }
    return false;
  }
  
  void _saveConfiguration() async {
    final transcriptionManager = Provider.of<TranscriptionServiceManager>(context, listen: false);
    
    Map<String, dynamic> settings = {};
    
    switch (transcriptionManager.activeProvider) {
      case TranscriptionProvider.openaiWhisper:
        settings = {'apiKey': _apiKeyController.text.trim()};
        break;
      case TranscriptionProvider.local:
        settings = {'endpoint': _endpointController.text.trim()};
        break;
      default:
        break;
    }
    
    await transcriptionManager.setActiveProvider(
      transcriptionManager.activeProvider,
      settings,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved successfully')),
      );
    }
  }
  
  void _testTranscription() async {
    // TODO: Implement test with a sample audio file
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test transcription coming soon')),
    );
  }
}