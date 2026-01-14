import Foundation

/// Represents a parsed user intent from voice command
/// The Intent describes what action to perform on a PocketItem
struct Intent: Identifiable, Equatable, Sendable {
    let id: UUID
    let action: Action
    let rawCommand: String?
    let confidence: Double
    let timestamp: Date

    init(
        id: UUID = UUID(),
        action: Action,
        rawCommand: String? = nil,
        confidence: Double = 1.0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.rawCommand = rawCommand
        self.confidence = confidence
        self.timestamp = timestamp
    }

    /// Human-readable description of the intent
    var displayDescription: String {
        switch action {
        case .hold:
            return "Holding item..."
        case .send(let target):
            return "Sending to \(target)..."
        case .convert(let format):
            return "Converting to \(format.uppercased())..."
        case .extract(let operation):
            return operation.displayDescription
        case .print(let copies, _):
            return "Printing \(copies) cop\(copies == 1 ? "y" : "ies")..."
        case .airplay(let device):
            return "Playing on \(device)..."
        }
    }

    /// Default intent when no voice command is given
    static var hold: Intent {
        Intent(action: .hold, rawCommand: nil, confidence: 1.0)
    }
}

// MARK: - Action

/// All possible actions that can be performed on a PocketItem
enum Action: Equatable, Sendable {
    // F1: Universal Hold
    case hold

    // F2: Quick Dispatch
    case send(target: String)

    // F3: Format Alchemist
    case convert(format: String)

    // F4: Content Distiller
    case extract(operation: ExtractionOperation)

    // F5: Physical Link - Print
    case print(copies: Int, options: PrintOptions)

    // F5: Physical Link - AirPlay
    case airplay(device: String)

    /// Icon for the action
    var icon: String {
        switch self {
        case .hold: return "tray.and.arrow.down.fill"
        case .send: return "paperplane.fill"
        case .convert: return "arrow.triangle.2.circlepath"
        case .extract: return "text.magnifyingglass"
        case .print: return "printer.fill"
        case .airplay: return "airplayvideo"
        }
    }
}

// MARK: - Extraction Operation

/// Types of content extraction/processing operations
enum ExtractionOperation: Equatable, Sendable {
    case summarize
    case extractText
    case translate(to: String)
    case transcribe
    case custom(prompt: String)

    var displayDescription: String {
        switch self {
        case .summarize:
            return "Summarizing..."
        case .extractText:
            return "Extracting text..."
        case .translate(let language):
            return "Translating to \(language)..."
        case .transcribe:
            return "Transcribing..."
        case .custom:
            return "Processing..."
        }
    }
}

// MARK: - Print Options

/// Options for printing
struct PrintOptions: Equatable, Sendable {
    var duplex: Bool = false
    var color: Bool = true
    var paperSize: PaperSize = .a4

    enum PaperSize: String, Sendable {
        case a4 = "A4"
        case letter = "Letter"
        case a3 = "A3"
    }

    static var `default`: PrintOptions {
        PrintOptions()
    }
}

// MARK: - Intent Parsing Result

/// Result from the IntentParser
struct IntentParsingResult: Sendable {
    let intent: Intent
    let alternativeIntents: [Intent]
    let requiresConfirmation: Bool
    let clarificationQuestion: String?

    init(
        intent: Intent,
        alternativeIntents: [Intent] = [],
        requiresConfirmation: Bool = false,
        clarificationQuestion: String? = nil
    ) {
        self.intent = intent
        self.alternativeIntents = alternativeIntents
        self.requiresConfirmation = requiresConfirmation
        self.clarificationQuestion = clarificationQuestion
    }
}
