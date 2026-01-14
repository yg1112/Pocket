import Foundation

// Debug file logger
private func debugLog(_ message: String) {
    let logPath = "/tmp/pocket_debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logLine = "[\(timestamp)] \(message)\n"
    if let data = logLine.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}

/// Parses voice commands into structured intents using LLM
/// Uses Groq API for ultra-fast inference
@MainActor
final class IntentParser: ObservableObject {

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var lastError: IntentParserError?

    // MARK: - Private Properties

    private let groqService: GroqService
    private let cache = NSCache<NSString, CachedIntent>()

    // MARK: - Initialization

    init(groqService: GroqService = GroqService()) {
        self.groqService = groqService
        cache.countLimit = 100
    }

    // MARK: - Parsing

    /// Parse a voice command into an Intent
    func parse(command: String?, for item: PocketItem) async -> Intent {
        debugLog("🧠 [IntentParser] ========================================")
        debugLog("🧠 [IntentParser] Parsing command: '\(command ?? "nil")'")
        debugLog("🧠 [IntentParser] Item: \(item.name) (type: \(item.type.rawValue))")
        debugLog("🧠 [IntentParser] ========================================")

        // If no command, default to hold
        guard let command = command, !command.isEmpty else {
            debugLog("🧠 [IntentParser] ⚠️ No command provided, defaulting to HOLD")
            return .hold
        }

        // Check cache first
        let cacheKey = "\(command.lowercased())_\(item.type.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            debugLog("🧠 [IntentParser] 📦 Cache hit: \(cached.intent.displayDescription)")
            return cached.intent
        }

        // Try quick pattern matching first (no LLM needed)
        debugLog("🧠 [IntentParser] Trying quick pattern match for: '\(command)'")
        if let quickAction = VoiceCommandPattern.quickMatch(command) {
            debugLog("🧠 [IntentParser] ⚡️ Quick match found! Action: \(quickAction)")
            let intent = Intent(action: quickAction, rawCommand: command, confidence: 0.9)
            cache.setObject(CachedIntent(intent: intent), forKey: cacheKey)
            return intent
        }

        // Use LLM for complex parsing
        debugLog("🧠 [IntentParser] 🤖 No quick match, using LLM...")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let intent = try await parseWithLLM(command: command, itemType: item.type)
            debugLog("🧠 [IntentParser] 🤖 LLM result: \(intent.displayDescription)")
            cache.setObject(CachedIntent(intent: intent), forKey: cacheKey)
            return intent
        } catch {
            debugLog("🧠 [IntentParser] ❌ LLM parsing error: \(error)")
            lastError = error as? IntentParserError ?? .parsingFailed(error.localizedDescription)
            // Fallback to hold on error
            return Intent(action: .hold, rawCommand: command, confidence: 0.5)
        }
    }

    /// Process content using LLM (for F4: Content Distiller)
    func processContent(_ item: PocketItem, operation: ExtractionOperation) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        let content = String(data: item.data, encoding: .utf8) ?? ""

        let prompt: String
        switch operation {
        case .summarize:
            prompt = """
            Summarize the following content concisely in 2-3 sentences:

            \(content)
            """

        case .extractText:
            prompt = """
            Extract the main text content, removing any formatting or metadata:

            \(content)
            """

        case .translate(let language):
            prompt = """
            Translate the following to \(language):

            \(content)
            """

        case .transcribe:
            prompt = """
            Transcribe and clean up the following text:

            \(content)
            """

        case .custom(let userPrompt):
            prompt = """
            \(userPrompt)

            Content:
            \(content)
            """
        }

        return try await groqService.complete(prompt: prompt)
    }

    // MARK: - Private Methods

    private func parseWithLLM(command: String, itemType: PocketItem.ItemType) async throws -> Intent {
        let systemPrompt = """
        You are a JSON parser for a file management app. Parse user commands into structured actions.

        Available actions:
        - hold: Store the item temporarily
        - send: Send to a person (extract target name)
        - convert: Convert file format (extract target format like pdf, jpg, png)
        - summarize: Summarize content
        - extract_text: Extract text from image/document
        - translate: Translate content (extract target language)
        - print: Print document (extract copies count if mentioned)
        - airplay: Send to display device (extract device name)

        Respond ONLY with JSON in this exact format:
        {"action": "action_name", "target": "optional_target", "confidence": 0.0-1.0}

        Examples:
        - "Send this to John" -> {"action": "send", "target": "John", "confidence": 0.95}
        - "Convert to PDF" -> {"action": "convert", "target": "pdf", "confidence": 0.95}
        - "Summarize this" -> {"action": "summarize", "confidence": 0.9}
        - "Print 2 copies" -> {"action": "print", "target": "2", "confidence": 0.9}
        """

        let userPrompt = """
        File type: \(itemType.rawValue)
        Command: "\(command)"
        """

        let response = try await groqService.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        return try parseJSON(response, rawCommand: command)
    }

    private func parseJSON(_ json: String, rawCommand: String) throws -> Intent {
        // Clean up JSON string (remove markdown code blocks if present)
        var cleanJSON = json
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleanJSON.data(using: .utf8) else {
            throw IntentParserError.invalidJSON
        }

        let parsed = try JSONDecoder().decode(ParsedIntent.self, from: data)
        let action = try mapAction(parsed)

        return Intent(
            action: action,
            rawCommand: rawCommand,
            confidence: parsed.confidence ?? 0.8
        )
    }

    private func mapAction(_ parsed: ParsedIntent) throws -> Action {
        switch parsed.action.lowercased() {
        case "hold", "store", "save", "keep":
            return .hold

        case "send", "share":
            return .send(target: parsed.target ?? "Unknown")

        case "convert", "change":
            return .convert(format: parsed.target ?? "pdf")

        case "summarize", "summary":
            return .extract(operation: .summarize)

        case "extract_text", "extract", "ocr":
            return .extract(operation: .extractText)

        case "translate":
            return .extract(operation: .translate(to: parsed.target ?? "English"))

        case "transcribe":
            return .extract(operation: .transcribe)

        case "print":
            let copies = Int(parsed.target ?? "1") ?? 1
            return .print(copies: copies, options: .default)

        case "airplay", "cast", "mirror":
            return .airplay(device: parsed.target ?? "TV")

        default:
            throw IntentParserError.unknownAction(parsed.action)
        }
    }
}

// MARK: - Supporting Types

/// Intermediate structure for JSON parsing
private struct ParsedIntent: Codable {
    let action: String
    let target: String?
    let confidence: Double?
}

/// Cache wrapper for intents
private class CachedIntent {
    let intent: Intent
    let timestamp: Date

    init(intent: Intent) {
        self.intent = intent
        self.timestamp = Date()
    }
}

// MARK: - Errors

enum IntentParserError: LocalizedError {
    case parsingFailed(String)
    case invalidJSON
    case unknownAction(String)
    case networkError
    case timeout

    var errorDescription: String? {
        switch self {
        case .parsingFailed(let reason):
            return "Failed to parse command: \(reason)"
        case .invalidJSON:
            return "Invalid response format"
        case .unknownAction(let action):
            return "Unknown action: \(action)"
        case .networkError:
            return "Network connection failed"
        case .timeout:
            return "Request timed out"
        }
    }
}
