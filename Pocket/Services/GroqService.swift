import Foundation

// Debug file logger for capturing logs from GUI app
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

/// Service for interacting with Groq's ultra-fast LLM API
/// Uses Groq's LPU for near-instant inference
actor GroqService {

    // MARK: - Configuration

    private struct Config {
        static let chatURL = "https://api.groq.com/openai/v1/chat/completions"
        static let whisperURL = "https://api.groq.com/openai/v1/audio/transcriptions"
        static let defaultModel = "llama-3.3-70b-versatile"  // Fast and capable
        static let fastModel = "llama-3.1-8b-instant"       // Ultra-fast for simple tasks
        static let whisperModel = "whisper-large-v3-turbo"  // Fast and accurate transcription
        static let timeout: TimeInterval = 30
    }

    // MARK: - Properties

    private let apiKey: String
    private let session: URLSession

    // MARK: - Initialization

    init(apiKey: String? = nil) {
        // Try to get API key from parameter, UserDefaults, or environment
        // Users must provide their own Groq API key via:
        // 1. Pass directly to init
        // 2. Set in UserDefaults with key "groqApiKey"
        // 3. Set GROQ_API_KEY environment variable
        self.apiKey = apiKey
            ?? UserDefaults.standard.string(forKey: "groqApiKey")
            ?? ProcessInfo.processInfo.environment["GROQ_API_KEY"]
            ?? ""

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Config.timeout
        config.timeoutIntervalForResource = Config.timeout
        self.session = URLSession(configuration: config)

        print("🔑 [GroqService] Initialized with API key: \(String(self.apiKey.prefix(20)))...")
    }

    // MARK: - Public Methods

    /// Complete a prompt with the default model
    func complete(prompt: String) async throws -> String {
        try await complete(systemPrompt: nil, userPrompt: prompt, model: Config.defaultModel)
    }

    /// Complete with system and user prompts
    func complete(systemPrompt: String?, userPrompt: String, model: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else {
            print("🤖 [GroqService] Error: Missing API key")
            throw GroqError.missingAPIKey
        }

        let selectedModel = model ?? Config.defaultModel
        print("🤖 [GroqService] Calling API with model: \(selectedModel)")
        print("🤖 [GroqService] User prompt: \(userPrompt.prefix(100))...")

        let request = try buildRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, model: selectedModel)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("🤖 [GroqService] Error: Invalid response")
            throw GroqError.invalidResponse
        }

        print("🤖 [GroqService] Response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("🤖 [GroqService] API error: \(errorMessage)")
            throw GroqError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)

        guard let content = groqResponse.choices.first?.message.content else {
            print("🤖 [GroqService] Error: Empty response")
            throw GroqError.emptyResponse
        }

        print("🤖 [GroqService] Response: \(content.prefix(100))...")
        return content
    }

    /// Quick completion using the fast model (for simple tasks)
    func quickComplete(prompt: String) async throws -> String {
        try await complete(systemPrompt: nil, userPrompt: prompt, model: Config.fastModel)
    }

    // MARK: - Whisper Transcription

    /// Transcribe audio data using Whisper
    func transcribe(audioData: Data, language: String? = nil) async throws -> String {
        debugLog("🎤 [GroqService] transcribe() called with \(audioData.count) bytes")

        guard !apiKey.isEmpty else {
            debugLog("🎤 [GroqService] Error: Missing API key")
            throw GroqError.missingAPIKey
        }

        guard let url = URL(string: Config.whisperURL) else {
            debugLog("🎤 [GroqService] Error: Invalid URL")
            throw GroqError.invalidURL
        }

        debugLog("🎤 [GroqService] Sending \(audioData.count) bytes to Whisper...")

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(Config.whisperModel)\r\n".data(using: .utf8)!)

        // Add language field if specified
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        debugLog("🎤 [GroqService] Received response, data size: \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("🎤 [GroqService] Error: Invalid response")
            throw GroqError.invalidResponse
        }

        debugLog("🎤 [GroqService] Whisper response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("🎤 [GroqService] Whisper API error: \(errorMessage)")
            throw GroqError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let responseString = String(data: data, encoding: .utf8) ?? "nil"
        debugLog("🎤 [GroqService] Raw response JSON: \(responseString)")

        let whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
        debugLog("🎤 [GroqService] ✅ Transcription: '\(whisperResponse.text)'")
        return whisperResponse.text
    }

    // MARK: - Private Methods

    private func buildRequest(systemPrompt: String?, userPrompt: String, model: String) throws -> URLRequest {
        guard let url = URL(string: Config.chatURL) else {
            throw GroqError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: String]] = []

        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }

        messages.append(["role": "user", "content": userPrompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,  // Low temperature for consistent parsing
            "max_tokens": 256    // Short responses for intent parsing
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }
}

// MARK: - Response Models

private struct WhisperResponse: Codable {
    let text: String
}

private struct GroqResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - Errors

enum GroqError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case apiError(statusCode: Int, message: String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Groq API key is not configured. Please add your API key in Settings."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Groq API"
        case .emptyResponse:
            return "Empty response from Groq API"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Streaming Support (Future)

extension GroqService {
    /// Stream completion for long responses (not used in v1.0 but prepared for future)
    func streamComplete(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // For now, just return the complete response
                    // Future: Implement actual streaming with SSE
                    let result = try await complete(prompt: prompt)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
