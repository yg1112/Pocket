# Pocket 2.0 - The Intent Hub

A multimodal hub residing in the Dynamic Island for drag-drop file handling with voice commands.

**Metaphor:** A magical pocket. Toss in an action, speak your intent. Now with synesthesia, batch intelligence, and cross-device portals.

## What's New in 2.0

### Phase 1: Visual Life (视觉生命力)
- **Differentiated Animations**: Eager spring for opening, settled spring for closing
- **Metaball Effect**: Gooey liquid merge when items approach the island

### Phase 2: Intelligent Prediction (智能预判)
- **Intent Bubbles**: Context-aware action predictions appear during drag
- **VAD Recording**: Voice Activity Detection auto-stops when you finish speaking

### Phase 3: Batch Intelligence (批量智能)
- **Multi-file Sessions**: Stack up to 10 items for batch operations
- **Smart Prompts**: Multi-file context awareness + auto-correction for speech errors

### Phase 4: Synesthesia Feedback (通感反馈)
- **Voice-Reactive Halo**: Halo color shifts based on voice tone (excited→red, calm→blue)
- **Heartbeat Haptics**: Continuous lub-DUB pattern during processing

### Phase 5: Portal Wormhole (虫洞传送)
- **Cross-Device Transfer**: MultipeerConnectivity for instant file sharing between devices

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
│   (Island glows)│  Prediction bubbles appear
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   ENGAGEMENT    │  Item hovers over island
│ (Mic activates) │  Metaball merge effect
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    LISTENING    │  Voice-reactive halo
│  (VAD active)   │  Auto-stops on silence
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   PROCESSING    │  Heartbeat haptics
│  (Task runs)    │  Status indicator
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   COMPLETION    │  Success/error feedback
│  (Result ready) │  Toast notification
└─────────────────┘
```

## Project Structure

```
Pocket/
├── App/
│   ├── PocketApp.swift              # App entry + PocketState
│   └── ContentView.swift            # Main view
├── Models/
│   ├── PocketItem.swift             # Item representation
│   ├── Intent.swift                 # Parsed user intent
│   └── PocketTask.swift             # Task execution
├── Views/
│   ├── DynamicIsland/
│   │   └── DynamicIslandView.swift  # Main island UI
│   ├── Effects/
│   │   ├── HaloEffectView.swift     # 2.0: Synesthesia halo
│   │   ├── MetaballEffectView.swift # 2.0: Gooey merge effect
│   │   ├── VoiceWaveformView.swift
│   │   └── ToastView.swift
│   └── Components/
│       ├── PocketItemView.swift
│       └── PredictionBubblesView.swift  # 2.0: Intent bubbles
├── Modules/
│   ├── DropZone/
│   │   └── DropZoneManager.swift
│   ├── VoiceIntent/
│   │   └── VoiceIntentManager.swift # 2.0: VAD + Synesthesia
│   ├── IntentParser/
│   │   ├── IntentParser.swift       # 2.0: VoiceCorrector
│   │   └── IntentPredictor.swift    # 2.0: Action prediction
│   ├── Session/
│   │   └── PocketSession.swift      # 2.0: Multi-file batching
│   └── Portal/
│       └── PortalManager.swift      # 2.0: Cross-device transfer
├── Services/
│   ├── GroqService.swift            # LLM API
│   └── FileService.swift            # File operations
├── Utilities/
│   ├── HapticsManager.swift         # 2.0: Heartbeat pattern
│   ├── AudioManager.swift
│   └── AnimationConstants.swift
└── Resources/
    └── (Assets, sounds, etc.)
```

## Design Principles

### Visual (Fluid, Organic, Tactile)

- **Morphing**: Differentiated springs - eager open (0.35s), settled close (0.55s)
- **Metaball**: Canvas + blur + contrast threshold for liquid merge
- **Material**: `Material.ultraThin` + `Color.black.opacity(0.8)`
- **Typography**: SF Pro Rounded, Semibold for titles

### Haptics

| Action | Feedback | Implementation |
|--------|----------|----------------|
| Hover | Soft continuous | `UIImpactFeedbackGenerator(style: .light)` |
| Mic Activate | Crisp tap | `UIImpactFeedbackGenerator(style: .rigid)` |
| Processing | Heartbeat | CoreHaptics lub-DUB pattern |
| Task Complete | Success ding | `UINotificationFeedbackGenerator().success` |

### Synesthesia Color Mapping

| Voice Emotion | Hue | Trigger |
|---------------|-----|---------|
| Neutral | Green (0.3) | Normal speaking |
| Excited | Red/Orange (0.05-0.1) | High energy, loud |
| Calm | Blue/Purple (0.6-0.7) | Low, steady voice |
| Urgent | Yellow (0.15) | Rapid level changes |

## Requirements

- iOS 17.0+ / macOS 14.0+
- iPhone with Dynamic Island (iPhone 14 Pro and later) or Mac
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

- **UI**: SwiftUI + Canvas (for metaball effects)
- **Speech**: Groq Whisper API + VAD
- **LLM**: Groq API (Llama 3.3 70B)
- **Haptics**: Core Haptics (heartbeat patterns)
- **Networking**: MultipeerConnectivity (Portal)
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
"发给小明"              → Send to Xiaoming
```

### Auto-Correction (2.0)

The VoiceCorrector automatically fixes common speech recognition errors:
- "sent" → "send"
- "pee dee eff" → "pdf"
- "some arise" → "summarize"
- "发个" → "发给"

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        ContentView                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                  DynamicIslandView                      │  │
│  │  ┌──────────┐ ┌─────────────┐ ┌──────────────────────┐ │  │
│  │  │ Metaball │ │ Synesthesia │ │  Prediction Bubbles  │ │  │
│  │  │  Effect  │ │    Halo     │ │                      │ │  │
│  │  └──────────┘ └─────────────┘ └──────────────────────┘ │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐
│ DropZone   │  │ VoiceIntent│  │  Intent    │  │  Pocket    │
│  Manager   │  │  Manager   │  │ Predictor  │  │  Session   │
└────────────┘  └────────────┘  └────────────┘  └────────────┘
         │              │              │              │
         └──────────────┼──────────────┴──────────────┘
                        ▼
              ┌─────────────────┐
              │  IntentParser   │ ← VoiceCorrector
              │   (Groq LLM)    │
              └─────────────────┘
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
    ┌─────────────────┐  ┌─────────────────┐
    │   FileService   │  │  PortalManager  │
    └─────────────────┘  └─────────────────┘
```

## Portal (Cross-Device)

The Portal feature enables instant file transfer between Pocket instances:

1. Tap the antenna icon in idle state to open portal
2. Nearby devices appear automatically
3. Tap to connect (encrypted peer-to-peer)
4. Drag files to send through the portal

## License

Proprietary - All rights reserved

---

Built with SwiftUI and powered by Groq LPU for ultra-fast inference.

**Pocket 2.0** - From voice-enabled file basket to digital life form.
