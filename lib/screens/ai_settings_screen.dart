import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:omi_minimal_fork/services/ai_service.dart';

class AISettingsScreen extends StatefulWidget {
  const AISettingsScreen({super.key});

  @override
  State<AISettingsScreen> createState() => _AISettingsScreenState();
}

class _AISettingsScreenState extends State<AISettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  
  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Configuration'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<AIServiceManager>(
        builder: (context, aiManager, child) {
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
                          Icon(Icons.info_outline, 
                            color: Theme.of(context).colorScheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Text('AI Query Mode', 
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Double-tap your Omi device to ask questions. '
                        'Your voice will be sent to the selected AI service for processing.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Service Selection
              Text('AI Service', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...AIServiceType.values.map((service) => 
                RadioListTile<AIServiceType>(
                  title: Text(service.displayName),
                  subtitle: Text(_getServiceDescription(service)),
                  value: service,
                  groupValue: aiManager.activeServiceType,
                  onChanged: (value) {
                    if (value != null) {
                      _selectService(value);
                    }
                  },
                ),
              ),
              
              const SizedBox(height: 24),
              
              // API Key Configuration
              if (aiManager.activeService?.requiresApiKey ?? false) ...[
                Text('API Configuration', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'Enter your ${aiManager.activeServiceType.displayName} API key',
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
                  _getApiKeyInstructions(aiManager.activeServiceType),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _apiKeyController.text.isNotEmpty ? _saveApiKey : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save API Key'),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Test Section
              if (aiManager.isConfigured) ...[
                const Divider(),
                const SizedBox(height: 16),
                Text('Test Configuration', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testConfiguration,
                  icon: const Icon(Icons.send),
                  label: const Text('Send Test Query'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              
              // Query History
              if (aiManager.queryHistory.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Queries', style: Theme.of(context).textTheme.titleMedium),
                    TextButton(
                      onPressed: () {
                        aiManager.clearHistory();
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...aiManager.queryHistory.take(5).map((record) => 
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(record.query, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        record.response.text, 
                        maxLines: 2, 
                        overflow: TextOverflow.ellipsis
                      ),
                      trailing: Text(
                        _formatTime(record.timestamp),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
  
  String _getServiceDescription(AIServiceType service) {
    switch (service) {
      case AIServiceType.perplexity:
        return 'AI-powered search with real-time information';
      case AIServiceType.openai:
        return 'ChatGPT - General purpose AI assistant';
      case AIServiceType.anthropic:
        return 'Claude - Thoughtful AI assistant';
      case AIServiceType.google:
        return 'Gemini - Google\'s AI assistant';
      case AIServiceType.local:
        return 'Privacy-focused local processing';
    }
  }
  
  String _getApiKeyInstructions(AIServiceType service) {
    switch (service) {
      case AIServiceType.perplexity:
        return 'Get your API key from perplexity.ai/settings/api';
      case AIServiceType.openai:
        return 'Get your API key from platform.openai.com/api-keys';
      case AIServiceType.anthropic:
        return 'Get your API key from console.anthropic.com';
      case AIServiceType.google:
        return 'Get your API key from makersuite.google.com/app/apikey';
      case AIServiceType.local:
        return 'No API key needed for local processing';
    }
  }
  
  void _selectService(AIServiceType service) {
    setState(() {
      _apiKeyController.clear();
    });
    // Don't save yet - wait for API key
  }
  
  void _saveApiKey() async {
    final aiManager = Provider.of<AIServiceManager>(context, listen: false);
    await aiManager.setActiveService(
      aiManager.activeServiceType,
      {'apiKey': _apiKeyController.text.trim()},
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved successfully')),
      );
    }
  }
  
  void _testConfiguration() async {
    final aiManager = Provider.of<AIServiceManager>(context, listen: false);
    
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      final response = await aiManager.query('What is the weather like today?');
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Test Successful'),
            content: Text(response.text),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}