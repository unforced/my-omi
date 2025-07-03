# Omi AI Assistant Design

## Core Concept: Your Wearable AI Interface

The Omi device becomes your personal AI assistant that's always available. Each tap pattern serves a distinct AI-powered purpose:

### Tap Functions

#### 1. **Single Tap - Capture & Transcribe** 
- Traditional recording with automatic transcription
- Smart categorization based on content
- Automatic extraction of tasks, notes, ideas
- Example: "Remember to call Mom tomorrow at 3pm" → Creates reminder

#### 2. **Double Tap - AI Query Mode** 🤖
- Records your question/command
- Routes to configured AI service (Perplexity, ChatGPT, Claude, Gemini)
- Speaks response back through app (or Omi speaker if available)
- Saves Q&A pair for future reference
- Examples:
  - "What's the weather tomorrow?"
  - "Explain quantum computing in simple terms"
  - "What restaurants are nearby?"
  - "How do I fix a leaking faucet?"

#### 3. **Triple Tap - Smart Action Mode** ⚡
Purpose: Execute personalized workflows and automations

**Option A: Personal Knowledge Base**
- Save important information to your "second brain"
- Auto-categorizes into your knowledge graph
- Examples:
  - "Book recommendation from John: Atomic Habits"
  - "Startup idea: AI-powered plant care app"
  - "Learned that coffee grounds repel ants"

**Option B: Workflow Triggers**
- Execute pre-configured actions
- IFTTT-style automations
- Examples:
  - "Start my morning routine" → Turns on lights, reads calendar, starts coffee
  - "I'm heading home" → Sends ETA to family, sets thermostat
  - "Log expense: $45 lunch meeting with client"

**Option C: Context Commander**
- AI analyzes context (location, time, calendar) and suggests/executes relevant actions
- "Walking into office" → Triple tap → "Good morning! You have 3 meetings today. First one with Sarah in 30 minutes about the Q4 roadmap."
- "At grocery store" → Triple tap → "Your shopping list has 5 items: milk, eggs, bread, chicken, and broccoli"

## Technical Architecture

### AI Service Integration

```dart
abstract class AIService {
  Future<String> query(String audioPath, {Map<String, dynamic>? context});
  Future<void> configure(Map<String, dynamic> settings);
  bool get requiresApiKey;
  String get serviceName;
}

class PerplexityService extends AIService {
  @override
  Future<String> query(String audioPath, {Map<String, dynamic>? context}) async {
    // 1. Transcribe audio
    final transcription = await transcribeAudio(audioPath);
    
    // 2. Add context if available
    final prompt = _buildPrompt(transcription, context);
    
    // 3. Query Perplexity API
    final response = await _queryPerplexity(prompt);
    
    return response;
  }
}

class AIServiceManager {
  final Map<String, AIService> _services = {
    'perplexity': PerplexityService(),
    'openai': OpenAIService(),
    'anthropic': ClaudeService(),
    'google': GeminiService(),
    'local': LocalLLMService(), // For privacy-conscious users
  };
  
  AIService? _activeService;
  
  void setActiveService(String serviceName, Map<String, dynamic> config) {
    _activeService = _services[serviceName];
    _activeService?.configure(config);
  }
}
```

### Knowledge Graph Integration

```dart
class KnowledgeNode {
  final String id;
  final String content;
  final DateTime timestamp;
  final List<String> tags;
  final Map<String, dynamic> metadata;
  final List<String> connections; // IDs of related nodes
  
  // Auto-extracted entities
  final List<String> people;
  final List<String> places;
  final List<String> topics;
  final List<String> dates;
}

class KnowledgeGraphService {
  // Store nodes with relationships
  final Map<String, KnowledgeNode> _nodes = {};
  final Map<String, Set<String>> _tagIndex = {};
  
  Future<void> addKnowledge(String transcription) async {
    // 1. Extract entities using NLP
    final entities = await _extractEntities(transcription);
    
    // 2. Create node
    final node = KnowledgeNode(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: transcription,
      timestamp: DateTime.now(),
      tags: entities.topics,
      people: entities.people,
      places: entities.places,
      topics: entities.topics,
      dates: entities.dates,
      connections: _findRelatedNodes(entities),
    );
    
    // 3. Update graph
    _nodes[node.id] = node;
    _updateIndices(node);
    
    // 4. Optional: Sync to external service (Obsidian, Notion, etc.)
    await _syncToExternalService(node);
  }
  
  List<KnowledgeNode> query(String searchTerm) {
    // Smart search across content, tags, entities
    return _searchNodes(searchTerm);
  }
}
```

### Workflow Engine

```dart
class WorkflowAction {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Future<void> Function(Map<String, dynamic> context) execute;
}

class WorkflowEngine {
  final List<WorkflowAction> _actions = [
    WorkflowAction(
      id: 'smart_home',
      name: 'Control Smart Home',
      description: 'Execute home automation commands',
      icon: Icons.home,
      execute: (context) async {
        final command = context['transcription'];
        await SmartHomeService.execute(command);
      },
    ),
    WorkflowAction(
      id: 'expense_log',
      name: 'Log Expense',
      description: 'Quick expense tracking',
      icon: Icons.attach_money,
      execute: (context) async {
        final expense = ExpenseParser.parse(context['transcription']);
        await ExpenseService.log(expense);
      },
    ),
    // ... more actions
  ];
  
  Future<void> executeSmartAction(String transcription) async {
    // 1. Analyze intent
    final intent = await _analyzeIntent(transcription);
    
    // 2. Find matching action
    final action = _findBestAction(intent);
    
    // 3. Execute
    if (action != null) {
      await action.execute({'transcription': transcription, 'intent': intent});
    }
  }
}
```

## User Interface Updates

### Main Screen Redesign

```
┌─────────────────────────────┐
│ 🎙️ Omi AI Assistant        │
│                             │
│ ┌─── Recent Activity ────┐  │
│ │ 🤖 AI Query    2:30pm │  │
│ │ "Weather tomorrow?"    │  │
│ │ → "Sunny, 72°F..."    │  │
│ ├───────────────────────┤  │
│ │ 💭 Knowledge   1:15pm │  │
│ │ "Book: Atomic Habits"  │  │
│ │ Tagged: #books #tips  │  │
│ ├───────────────────────┤  │
│ │ ⚡ Action      12:00pm│  │
│ │ "Log lunch expense"    │  │
│ │ → Saved $45 to Expenses│  │
│ └───────────────────────┘  │
│                             │
│ [🎙️] [🤖] [💭] [⚡] [⚙️] │
└─────────────────────────────┘
```

### Settings Screen - AI Configuration

```dart
class AISettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI Configuration')),
      body: ListView(
        children: [
          // AI Service Selection
          ListTile(
            title: Text('AI Service'),
            subtitle: Text('Perplexity'),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () => _showServicePicker(context),
          ),
          
          // API Key Configuration
          ListTile(
            title: Text('API Key'),
            subtitle: Text('••••••••••••key'),
            trailing: Icon(Icons.edit),
            onTap: () => _showApiKeyDialog(context),
          ),
          
          // Voice Response
          SwitchListTile(
            title: Text('Voice Responses'),
            subtitle: Text('Speak AI answers aloud'),
            value: true,
            onChanged: (v) {},
          ),
          
          // Context Sharing
          SwitchListTile(
            title: Text('Share Context'),
            subtitle: Text('Include location, time with queries'),
            value: false,
            onChanged: (v) {},
          ),
          
          // Knowledge Graph Sync
          ListTile(
            title: Text('Knowledge Base Sync'),
            subtitle: Text('Obsidian'),
            trailing: Icon(Icons.sync),
            onTap: () => _showKnowledgeSyncOptions(context),
          ),
        ],
      ),
    );
  }
}
```

## Implementation Priorities

### Phase 1: Core AI Integration
1. Update button handling to differentiate tap types
2. Implement basic AI service integration (start with OpenAI/Perplexity)
3. Add transcription → AI query pipeline
4. Create UI for viewing AI conversations

### Phase 2: Knowledge Management
1. Implement knowledge graph structure
2. Add entity extraction
3. Create knowledge browser UI
4. Add basic tagging and search

### Phase 3: Smart Actions
1. Design workflow action system
2. Implement common actions (expenses, notes, reminders)
3. Add context awareness
4. Create action configuration UI

## Privacy Considerations

### Local-First Options
- **Local LLM**: Llama, Mistral for offline AI queries
- **On-device transcription**: Whisper for privacy
- **Encrypted storage**: For sensitive knowledge nodes
- **Opt-in context**: User controls what context is shared

### Data Handling
```dart
class PrivacySettings {
  bool useLocalAI = false;
  bool shareLocation = false;
  bool shareCalendar = false;
  bool encryptKnowledge = true;
  int autoDeleteDays = 30; // AI queries
  bool saveAIConversations = true;
}
```

## Future Enhancements

### Advanced AI Features
- **Multi-modal queries**: Include camera for visual questions
- **Continuous conversation**: Follow-up questions
- **Proactive AI**: Suggestions based on context
- **Custom AI personas**: Different assistants for different contexts

### Integration Ecosystem
- **Plugin system**: Users can add custom AI services
- **Webhook support**: Trigger external services
- **IFTTT/Zapier**: Native integration
- **Smart home**: Direct device control

This design transforms the Omi device from a simple recorder into a powerful AI interface that's always available at the tap of a button.