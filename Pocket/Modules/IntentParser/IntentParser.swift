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
/// 2.0: Enhanced with multi-file context and auto-correction
@MainActor
final class IntentParser: ObservableObject {

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var lastError: IntentParserError?

    // MARK: - Private Properties

    private let groqService: GroqService
    private let cache = NSCache<NSString, CachedIntent>()
    private let voiceCorrector = VoiceCorrector()

    // MARK: - Initialization

    init(groqService: GroqService = GroqService()) {
        self.groqService = groqService
        cache.countLimit = 100
    }

    // MARK: - Parsing

    /// Parse a voice command into an Intent
    func parse(command: String?, for item: PocketItem) async -> Intent {
        await parse(command: command, for: item, session: nil)
    }

    /// Parse a voice command with session context (2.0: Multi-file support)
    func parse(command: String?, for item: PocketItem, session: PocketSession?) async -> Intent {
        debugLog("🧠 [IntentParser] ========================================")
        debugLog("🧠 [IntentParser] Parsing command: '\(command ?? "nil")'")
        debugLog("🧠 [IntentParser] Item: \(item.name) (type: \(item.type.rawValue))")
        if let session = session, session.isActive {
            debugLog("🧠 [IntentParser] Session: \(session.itemCount) items")
        }
        debugLog("🧠 [IntentParser] ========================================")

        // If no command, default to hold
        guard let rawCommand = command, !rawCommand.isEmpty else {
            debugLog("🧠 [IntentParser] ⚠️ No command provided, defaulting to HOLD")
            return .hold
        }

        // 2.0: Apply auto-correction for common speech recognition errors
        let correctedCommand = voiceCorrector.correct(rawCommand)
        if correctedCommand != rawCommand {
            debugLog("🧠 [IntentParser] 🔧 Auto-corrected: '\(rawCommand)' -> '\(correctedCommand)'")
        }

        // Check cache first
        let cacheKey = "\(correctedCommand.lowercased())_\(item.type.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            debugLog("🧠 [IntentParser] 📦 Cache hit: \(cached.intent.displayDescription)")
            return cached.intent
        }

        // Try quick pattern matching first (no LLM needed)
        debugLog("🧠 [IntentParser] Trying quick pattern match for: '\(correctedCommand)'")
        if let quickAction = VoiceCommandPattern.quickMatch(correctedCommand) {
            debugLog("🧠 [IntentParser] ⚡️ Quick match found! Action: \(quickAction)")
            let intent = Intent(action: quickAction, rawCommand: correctedCommand, confidence: 0.9)
            cache.setObject(CachedIntent(intent: intent), forKey: cacheKey)
            return intent
        }

        // Use LLM for complex parsing
        debugLog("🧠 [IntentParser] 🤖 No quick match, using LLM...")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let intent = try await parseWithLLM(
                command: correctedCommand,
                itemType: item.type,
                session: session
            )
            debugLog("🧠 [IntentParser] 🤖 LLM result: \(intent.displayDescription)")
            cache.setObject(CachedIntent(intent: intent), forKey: cacheKey)
            return intent
        } catch {
            debugLog("🧠 [IntentParser] ❌ LLM parsing error: \(error)")
            lastError = error as? IntentParserError ?? .parsingFailed(error.localizedDescription)
            // Fallback to hold on error
            return Intent(action: .hold, rawCommand: correctedCommand, confidence: 0.5)
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

    // MARK: - 2.0: Batch Processing

    /// Process multiple items from a session with context-aware prompts
    func processSession(_ session: PocketSession, operation: ExtractionOperation) async throws -> String {
        guard session.isActive && !session.items.isEmpty else {
            throw IntentParserError.parsingFailed("No items in session")
        }

        isProcessing = true
        defer { isProcessing = false }

        // Build combined context from all items
        var combinedContent = ""
        for (index, item) in session.items.enumerated() {
            let itemContent = String(data: item.data, encoding: .utf8) ?? "[Binary content]"
            combinedContent += """

            === Document \(index + 1): \(item.name) (\(item.type.rawValue)) ===
            \(itemContent.prefix(2000))
            """
        }

        let prompt: String
        switch operation {
        case .summarize:
            prompt = """
            You have \(session.itemCount) documents. Provide a unified summary that:
            1. Summarizes each document briefly (1 sentence each)
            2. Identifies common themes or connections
            3. Provides an overall synthesis (2-3 sentences)

            Documents:
            \(combinedContent)
            """

        case .extractText:
            prompt = """
            Extract and combine the main text from all \(session.itemCount) documents:
            \(combinedContent)
            """

        case .translate(let language):
            prompt = """
            Translate all \(session.itemCount) documents to \(language).
            Preserve the document structure and indicate which translation belongs to which document.

            Documents:
            \(combinedContent)
            """

        case .transcribe:
            prompt = """
            Transcribe and clean up all \(session.itemCount) documents:
            \(combinedContent)
            """

        case .custom(let userPrompt):
            prompt = """
            \(userPrompt)

            Documents (\(session.itemCount) total):
            \(combinedContent)
            """
        }

        return try await groqService.complete(prompt: prompt)
    }

    /// Generate a comparison/diff between session items
    func compareSessionItems(_ session: PocketSession) async throws -> String {
        guard session.isActive && session.itemCount >= 2 else {
            throw IntentParserError.parsingFailed("Need at least 2 items to compare")
        }

        isProcessing = true
        defer { isProcessing = false }

        var combinedContent = ""
        for (index, item) in session.items.enumerated() {
            let itemContent = String(data: item.data, encoding: .utf8) ?? "[Binary content]"
            combinedContent += """

            === Document \(index + 1): \(item.name) ===
            \(itemContent.prefix(2000))
            """
        }

        let prompt = """
        Compare these \(session.itemCount) documents and identify:
        1. Key similarities
        2. Key differences
        3. Any conflicts or contradictions
        4. Recommended action (if applicable)

        Documents:
        \(combinedContent)
        """

        return try await groqService.complete(prompt: prompt)
    }

    // MARK: - Private Methods

    private func parseWithLLM(command: String, itemType: PocketItem.ItemType, session: PocketSession? = nil) async throws -> Intent {
        // 2.0: Build context-aware system prompt
        var systemPrompt = """
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
        """

        // 2.0: Add batch actions for multi-file sessions
        if let session = session, session.isActive && session.itemCount > 1 {
            systemPrompt += """


        BATCH MODE - Multiple files detected. Additional actions:
        - batch_convert: Convert all files to same format
        - batch_send: Send all files to same person
        - merge: Combine files into one (for compatible types)
        - compare: Compare/diff files (for similar types)

        For batch operations, set "apply_to_all": true in the response.
        """
        }

        systemPrompt += """


        Respond ONLY with JSON in this exact format:
        {"action": "action_name", "target": "optional_target", "confidence": 0.0-1.0, "apply_to_all": false}

        Examples:
        - "Send this to John" -> {"action": "send", "target": "John", "confidence": 0.95}
        - "Convert to PDF" -> {"action": "convert", "target": "pdf", "confidence": 0.95}
        - "Summarize this" -> {"action": "summarize", "confidence": 0.9}
        - "Print 2 copies" -> {"action": "print", "target": "2", "confidence": 0.9}
        - "Send all to Mike" -> {"action": "send", "target": "Mike", "confidence": 0.95, "apply_to_all": true}
        - "Convert everything to PDF" -> {"action": "convert", "target": "pdf", "confidence": 0.95, "apply_to_all": true}
        """

        // 2.0: Build context-aware user prompt
        var userPrompt = """
        File type: \(itemType.rawValue)
        Command: "\(command)"
        """

        // Add session context for multi-file scenarios
        if let session = session, session.isActive && session.itemCount > 1 {
            userPrompt += """


        Session context:
        \(session.sessionContext)
        """
        }

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
    let apply_to_all: Bool?  // 2.0: For batch operations
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

// MARK: - Voice Corrector (2.0: Auto-correction for speech recognition errors)

/// Corrects common speech recognition errors and homophones
/// Learns from user patterns over time
struct VoiceCorrector {

    // MARK: - Homophone/Misrecognition Corrections

    /// Common speech recognition errors: wrong word -> correct word
    private let corrections: [String: String] = [
        // English homophones and common misrecognitions
        "sent": "send",
        "cents": "send",
        "scent": "send",
        "sand": "send",
        "sended": "send",
        "sendit": "send it",
        "pdf'd": "pdf",
        "pee dee eff": "pdf",
        "p d f": "pdf",
        "jpeg": "jpg",
        "jay peg": "jpg",
        "j peg": "jpg",
        "pin": "png",
        "ping": "png",
        "some arise": "summarize",
        "some rise": "summarize",
        "summarise": "summarize",
        "summary eyes": "summarize",
        "convict": "convert",
        "can vert": "convert",
        "hold it": "hold",
        "holder": "hold",
        "share it": "share",
        "sharing": "share",
        "traded": "translate",
        "trans late": "translate",
        "air play": "airplay",
        "a play": "airplay",
        "printout": "print",
        "print out": "print",
        "printer": "print",

        // Chinese common corrections
        "发给他": "发给",
        "发个": "发给",
        "转成PDF": "转成 pdf",
        "转PDF": "转成 pdf",
        "翻译程": "翻译成",
        "总接": "总结",
        "摘药": "摘要",

        // Names (common misrecognitions)
        "mike": "Mike",
        "john": "John",
        "mary": "Mary",
        "tom": "Tom",
        "alice": "Alice",
        "bob": "Bob",
    ]

    /// Phrase-level corrections (multi-word patterns)
    private let phraseCorrections: [(pattern: String, replacement: String)] = [
        ("send to all", "send all"),
        ("convert them all", "convert all"),
        ("do all of them", "apply to all"),
        ("for all files", "all"),
        ("every file", "all"),
        ("send this 2", "send this to"),
        ("send 2", "send to"),
        ("2 john", "to John"),
        ("2 mike", "to Mike"),
    ]

    // MARK: - Correction

    /// Apply corrections to raw speech text
    func correct(_ text: String) -> String {
        var result = text.lowercased()

        // 1. Apply phrase-level corrections first (longer patterns)
        for (pattern, replacement) in phraseCorrections {
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }

        // 2. Apply word-level corrections
        var words = result.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() {
            if let correction = corrections[word] {
                words[index] = correction
            }
        }

        result = words.joined(separator: " ")

        // 3. Normalize whitespace
        result = result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return result
    }

    /// Check if text contains recognizable command patterns
    func hasCommandIntent(_ text: String) -> Bool {
        let corrected = correct(text)
        let commandKeywords = [
            "send", "share", "convert", "summarize", "translate",
            "print", "hold", "save", "airplay", "extract",
            "发给", "分享", "转成", "总结", "翻译", "打印", "保存"
        ]
        return commandKeywords.contains { corrected.contains($0) }
    }
}
