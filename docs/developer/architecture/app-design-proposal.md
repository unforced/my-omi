# Omi App Design Proposal

## Overview
This document outlines a comprehensive design for the Omi app that makes it genuinely useful for capturing, organizing, and leveraging audio recordings.

## Core Concept: Context-Aware Audio Capture

### Tap Gesture Meanings
Each tap pattern captures different types of thoughts:

1. **Single Tap - Quick Thoughts** 
   - For capturing fleeting ideas, reminders, observations
   - Auto-stops after 30 seconds of silence or 2 minutes max
   - Tagged as "Quick Note"
   - Example: "Remember to buy milk" or "Great idea for the presentation"

2. **Double Tap - Conversations/Meetings**
   - For longer form recordings with multiple speakers
   - Continues until manually stopped
   - Enhanced transcription with speaker detection
   - Tagged as "Conversation"
   - Example: Meeting notes, interviews, discussions

3. **Triple Tap - Personal Journal**
   - Private, reflective recordings
   - Optional encryption/privacy mode
   - Tagged as "Journal Entry"
   - Can include mood/emotion tags
   - Example: Daily reflections, personal thoughts

4. **Long Press - Still powers off device**

## User Interface Design

### Main Screen - Timeline View
```
┌─────────────────────────────┐
│ 🎙️ Omi Recordings          │
│ ┌───────────────────────┐   │
│ │ Today                 │   │
│ ├───────────────────────┤   │
│ │ 🔴 Quick Note  2:30pm │   │
│ │ "Pick up dry cleaning"│   │
│ ├───────────────────────┤   │
│ │ 🔵 Conversation 1:15pm│   │
│ │ "Team standup meeting"│   │
│ ├───────────────────────┤   │
│ │ 🟣 Journal     9:00am │   │
│ │ "Morning reflection..." │   │
│ └───────────────────────┘   │
│                             │
│ [🔴] [🔵] [🟣] [🔍] [⚙️]  │
└─────────────────────────────┘
```

### Key Features

#### 1. Smart Transcription
- Local transcription using Whisper (for privacy)
- Or cloud transcription (OpenAI Whisper API, Google Speech-to-Text)
- Automatic language detection
- Smart punctuation and formatting
- Keyword extraction for easy searching

#### 2. Recording Management
```dart
class Recording {
  final String id;
  final DateTime timestamp;
  final RecordingType type; // quick, conversation, journal
  final String audioPath;
  final String? transcription;
  final List<String> keywords;
  final Duration duration;
  final Map<String, dynamic> metadata;
}
```

#### 3. Filtering & Search
- Filter by recording type (tap count)
- Full-text search across transcriptions
- Date range filtering
- Keyword/tag filtering
- Smart suggestions based on content

#### 4. Export & Integration Options

**Quick Sharing**
- Copy transcription to clipboard
- Share audio file via standard share sheet
- Email transcription with audio attachment
- Export to voice memo apps

**Advanced Integrations**
- **Notion Integration**: Auto-create pages from recordings
- **Obsidian Export**: Markdown formatted with metadata
- **Calendar Sync**: Link recordings to calendar events
- **Task Managers**: Extract action items to Todoist/Things
- **AI Processing**: Send to ChatGPT/Claude for summarization

#### 5. Privacy & Security
- Local-first approach (recordings stored on device)
- Optional encryption for journal entries
- Biometric lock for app access
- Auto-delete old recordings (configurable)
- Export before delete option

## Technical Implementation

### Database Schema
```sql
CREATE TABLE recordings (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL, -- 'quick', 'conversation', 'journal'
  timestamp INTEGER NOT NULL,
  duration INTEGER NOT NULL,
  audio_path TEXT NOT NULL,
  transcription TEXT,
  keywords TEXT, -- JSON array
  metadata TEXT, -- JSON object
  is_favorite BOOLEAN DEFAULT 0,
  is_archived BOOLEAN DEFAULT 0
);

CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color TEXT
);

CREATE TABLE recording_tags (
  recording_id TEXT,
  tag_id TEXT,
  FOREIGN KEY(recording_id) REFERENCES recordings(id),
  FOREIGN KEY(tag_id) REFERENCES tags(id)
);
```

### Smart Features

#### Auto-Categorization
Based on transcription content, automatically:
- Detect meeting notes → Add to calendar
- Find todo items → Create task list
- Identify people mentioned → Tag contacts
- Detect locations → Add geo-tags

#### Insights Dashboard
- Recording habits (when you record most)
- Common topics/themes
- Word clouds from transcriptions
- Mood tracking (for journal entries)

### Customization Options

#### User Preferences
```dart
class UserPreferences {
  // Recording settings
  int quickNoteMaxDuration = 120; // seconds
  bool autoTranscribe = true;
  TranscriptionService service = TranscriptionService.local;
  
  // Privacy settings
  bool requireBiometric = false;
  bool encryptJournals = true;
  int autoDeleteDays = 0; // 0 = never
  
  // UI settings
  ThemeMode theme = ThemeMode.system;
  bool showTranscriptionPreview = true;
  SortOrder defaultSort = SortOrder.newest;
  
  // Integration settings
  Map<String, IntegrationConfig> integrations = {};
}
```

## Unique Value Propositions

### 1. Context-Aware Recording
The tap-based system isn't just about starting recording - it's about capturing intent. The app knows whether you're making a quick note or having a conversation, and optimizes accordingly.

### 2. Actionable Audio
Recordings aren't just stored - they're processed into actionable information:
- Meeting recordings → Action items
- Ideas → Organized notes
- Conversations → Contact associations

### 3. Privacy-First Design
- Local transcription option
- Encryption for sensitive recordings
- No cloud requirement
- Full data ownership

### 4. Seamless Workflow Integration
The app becomes a bridge between thought and action:
- Voice → Text → Task
- Idea → Note → Project
- Conversation → Summary → Follow-up

## Future Enhancements

### AI-Powered Features
- Smart summarization
- Action item extraction
- Sentiment analysis for journal entries
- Topic clustering
- Related recording suggestions

### Advanced Hardware Integration
- LED patterns for recording status
- Haptic feedback for transcription complete
- Voice commands for hands-free operation
- Gesture controls beyond taps

### Collaboration Features
- Shared recordings (with permissions)
- Team workspaces
- Collaborative transcription editing
- Meeting minutes generation

## Implementation Priorities

1. **Phase 1: Core Features**
   - Tap-based categorization
   - Basic transcription
   - Simple filtering
   - Audio sharing

2. **Phase 2: Smart Features**
   - Advanced search
   - Auto-categorization
   - First integrations (clipboard, email)
   - Local Whisper integration

3. **Phase 3: Advanced Features**
   - Cloud sync option
   - Third-party integrations
   - AI processing
   - Analytics dashboard

This design makes the Omi device genuinely useful by treating it not just as a recording device, but as a thought capture and organization system that fits seamlessly into modern workflows.