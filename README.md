# Pocket 1.0 - The Intent Hub

A multimodal hub residing in the Dynamic Island for drag-drop file handling with voice commands.

**Metaphor:** A magical pocket. Toss in an action, speak your intent.

## Features

### The "High-Five" Features

1. **F1: Universal Hold** - Temporary storage for items between apps
2. **F2: Quick Dispatch** - Send files to contacts with voice ("Send to John")
3. **F3: Format Alchemist** - Convert files ("Convert to PDF")
4. **F4: Content Distiller** - Summarize, extract, translate content
5. **F5: Physical Link** - Print and AirPlay files

## Interaction Flow: The Grip & Speak Loop

```
┌─────────────────┐
│   ANTICIPATION  │  User starts dragging
│   (Island glows)│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   ENGAGEMENT    │  Item hovers over island
│ (Mic activates) │  User speaks command
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     ACTION      │  User releases
│  (Item absorbed)│  Task begins
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   COMPLETION    │  Toast notification
│  (Result ready) │
└─────────────────┘
```

## Project Structure

```
Pocket/
├── App/
│   ├── PocketApp.swift          # App entry point
│   └── ContentView.swift        # Main view
├── Models/
│   ├── PocketItem.swift         # Item representation
│   ├── Intent.swift             # Parsed user intent
│   └── PocketTask.swift         # Task execution
├── Views/
│   ├── DynamicIsland/
│   │   └── DynamicIslandView.swift
│   ├── Effects/
│   │   ├── HaloEffectView.swift
│   │   ├── VoiceWaveformView.swift
│   │   └── ToastView.swift
│   └── Components/
│       └── PocketItemView.swift
├── Modules/
│   ├── DropZone/
│   │   └── DropZoneManager.swift
│   ├── VoiceIntent/
│   │   └── VoiceIntentManager.swift
│   └── IntentParser/
│       └── IntentParser.swift
├── Services/
│   ├── GroqService.swift        # LLM API
│   └── FileService.swift        # File operations
├── Utilities/
│   ├── HapticsManager.swift     # Tactile feedback
│   ├── AudioManager.swift       # Sound effects
│   └── AnimationConstants.swift # Animation presets
└── Resources/
    └── (Assets, sounds, etc.)
```

## Design Principles

### Visual (Fluid, Organic, Tactile)

- **Morphing**: Use `.matchedGeometryEffect` with `spring(response: 0.5, dampingFraction: 0.7)`
- **Material**: `Material.ultraThin` + `Color.black.opacity(0.8)`
- **Typography**: SF Pro Rounded, Semibold for titles

### Haptics

| Action | Feedback | Implementation |
|--------|----------|----------------|
| Hover | Soft continuous | `UIImpactFeedbackGenerator(style: .light)` |
| Mic Activate | Crisp tap | `UIImpactFeedbackGenerator(style: .rigid)` |
| Task Complete | Success ding | `UINotificationFeedbackGenerator().success` |

## Requirements

- iOS 17.0+
- iPhone with Dynamic Island (iPhone 14 Pro and later)
- Xcode 15.0+

## Setup

1. Clone the repository
2. Open `Pocket.xcodeproj` in Xcode
3. Add your Groq API key in Settings
4. Build and run on a device with Dynamic Island

## Configuration

### Groq API Key (Required)

This app requires a Groq API key for voice transcription (Whisper) and intent parsing (LLM).

1. Get a free API key at [console.groq.com](https://console.groq.com)
2. Set your API key using one of these methods:
   - **Environment variable**: `export GROQ_API_KEY=your_key_here`
   - **UserDefaults**: Store with key `groqApiKey`
   - **In code**: Pass to `GroqService(apiKey: "your_key")`

## Technical Stack

- **UI**: SwiftUI
- **Speech**: SFSpeechRecognizer (on-device)
- **LLM**: Groq API (Llama 3.3 70B)
- **Haptics**: Core Haptics
- **Files**: PDFKit, UniformTypeIdentifiers

## Voice Commands

### Examples

```
"Send to [name]"       → Quick Dispatch
"Convert to PDF"       → Format conversion
"Convert to JPG"       → Image conversion
"Summarize"            → Content extraction
"Translate to Chinese" → Translation
"Print 2 copies"       → Printing
"先放着" (Hold it)      → Universal hold
```

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    ContentView                        │
│  ┌────────────────────────────────────────────────┐  │
│  │              DynamicIslandView                  │  │
│  │  ┌─────────────┐ ┌────────────────────────────┐│  │
│  │  │  HaloEffect │ │  Voice Waveform / Status   ││  │
│  │  └─────────────┘ └────────────────────────────┘│  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  DropZoneManager │  │ VoiceIntentMgr  │  │   PocketState   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              ▼
                    ┌─────────────────┐
                    │  IntentParser   │
                    │   (Groq LLM)    │
                    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   FileService   │
                    └─────────────────┘
```

## License

Proprietary - All rights reserved

---

Built with SwiftUI and powered by Groq LPU for ultra-fast inference.
