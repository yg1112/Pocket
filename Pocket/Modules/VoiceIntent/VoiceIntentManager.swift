import Foundation
import AVFoundation
import Combine
import os.log

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let logger = Logger(subsystem: "com.pocket.app", category: "VoiceIntent")

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

/// Manages voice input using Groq Whisper API for transcription
/// Records audio and sends to Groq for ultra-accurate transcription
@MainActor
final class VoiceIntentManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isListening = false
    @Published var currentTranscription: String?
    @Published var partialTranscription: String = ""
    @Published var audioLevel: Float = 0
    @Published var isTranscribing = false
    @Published var error: VoiceIntentError?

    // MARK: - Private Properties

    private let groqService: GroqService
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?

    // MARK: - Initialization

    init(groqService: GroqService = GroqService()) {
        self.groqService = groqService
        setupAudioSession()
    }

    // MARK: - Setup

    private func setupAudioSession() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("🎤 [VoiceIntentManager] Failed to setup audio session: \(error)")
        }
        #endif

        // Request microphone permission on macOS
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("🎤 [VoiceIntentManager] Microphone authorized")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("🎤 [VoiceIntentManager] Microphone access: \(granted)")
            }
        case .denied, .restricted:
            print("🎤 [VoiceIntentManager] Microphone access denied")
            error = .notAuthorized
        @unknown default:
            break
        }
        #endif
    }

    // MARK: - Recording Control

    func startListening() {
        debugLog("🎤 startListening() called")

        guard !isListening else {
            debugLog("🎤 Already listening, returning")
            logger.warning("Already listening")
            return
        }

        currentTranscription = nil
        partialTranscription = ""
        error = nil

        do {
            try startRecording()
            isListening = true
            startAudioLevelMonitoring()
            debugLog("🎤 Recording started successfully")
            logger.info("🎤 Recording started successfully")
        } catch {
            debugLog("🎤 Failed to start recording: \(error.localizedDescription)")
            logger.error("🎤 Failed to start recording: \(error.localizedDescription)")
            self.error = .audioEngineError(error)
        }
    }

    func stopListening() {
        debugLog("🎤 stopListening() called, isListening=\(isListening)")

        guard isListening else {
            debugLog("🎤 Not listening, returning")
            return
        }

        debugLog("🎤 Stopping recording...")
        stopRecording()
        stopAudioLevelMonitoring()
        isListening = false
        debugLog("🎤 Recording stopped, starting transcription task...")

        // Transcribe the recorded audio
        Task {
            await transcribeRecording()
        }
    }

    func cancelListening() {
        stopRecording()
        stopAudioLevelMonitoring()
        isListening = false
        currentTranscription = nil
        partialTranscription = ""

        // Clean up recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Private Recording Methods

    private func startRecording() throws {
        // Create temporary file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "pocket_recording_\(UUID().uuidString).wav"
        recordingURL = tempDir.appendingPathComponent(fileName)

        guard let url = recordingURL else {
            throw VoiceIntentError.requestCreationFailed
        }

        // Recording settings for Whisper (16kHz, mono, 16-bit)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        print("🎤 [VoiceIntentManager] Recording to: \(url.path)")
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        print("🎤 [VoiceIntentManager] Recording stopped")
    }

    // MARK: - Transcription

    private func transcribeRecording() async {
        debugLog("🎤 transcribeRecording() called")

        guard let url = recordingURL else {
            debugLog("🎤 ERROR: No recording URL")
            logger.error("🎤 No recording URL")
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("🎤 ERROR: Recording file not found at: \(url.path)")
            logger.error("🎤 Recording file not found at: \(url.path)")
            return
        }

        isTranscribing = true
        partialTranscription = "Transcribing..."

        do {
            let audioData = try Data(contentsOf: url)
            debugLog("🎤 Audio data size: \(audioData.count) bytes, sending to Whisper...")

            // Send to Groq Whisper
            let transcription = try await groqService.transcribe(audioData: audioData)

            debugLog("🎤 ✅ TRANSCRIPTION RESULT: '\(transcription)'")
            logger.info("🎤 Transcription result: \(transcription)")

            currentTranscription = transcription
            partialTranscription = transcription

            debugLog("🎤 Set currentTranscription to: '\(transcription)'")

        } catch {
            debugLog("🎤 ❌ Transcription error: \(error.localizedDescription)")
            logger.error("🎤 Transcription error: \(error.localizedDescription)")
            self.error = .transcriptionFailed(error.localizedDescription)
            currentTranscription = nil
            partialTranscription = ""
        }

        isTranscribing = false
        debugLog("🎤 isTranscribing set to false, currentTranscription = '\(currentTranscription ?? "nil")'")

        // Clean up recording file
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevel()
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0
            return
        }

        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        // Convert dB to linear (0-1)
        let linearLevel = pow(10, level / 20)
        audioLevel = min(1.0, max(0.0, linearLevel * 2))
    }
}

// MARK: - Voice Intent Error

enum VoiceIntentError: LocalizedError {
    case notAuthorized
    case speechRecognizerUnavailable
    case audioEngineError(Error)
    case requestCreationFailed
    case noTranscription
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone access not authorized"
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available"
        case .audioEngineError(let error):
            return "Audio error: \(error.localizedDescription)"
        case .requestCreationFailed:
            return "Failed to create recording"
        case .noTranscription:
            return "No speech was detected"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

// MARK: - Voice Command Patterns

enum VoiceCommandPattern {
    static let sendPatterns = ["send to", "send this to", "share with", "share to", "发给", "发送给", "分享给"]
    static let convertPatterns = ["convert to", "change to", "make it", "turn into", "转成", "转换成", "改成"]
    static let summarizePatterns = ["summarize", "summary", "sum up", "key points", "总结", "摘要", "概括"]
    static let translatePatterns = ["translate to", "translate into", "in english", "in chinese", "翻译成", "翻成"]
    static let printPatterns = ["print", "print this", "print out", "打印", "列印"]
    static let holdPatterns = ["hold", "keep", "save", "store", "put here", "先放着", "保存", "存一下"]

    static func quickMatch(_ text: String) -> Action? {
        let lowercased = text.lowercased()

        for pattern in holdPatterns {
            if lowercased.contains(pattern) {
                return .hold
            }
        }

        for pattern in sendPatterns {
            if lowercased.contains(pattern) {
                let target = extractTarget(from: text, after: pattern)
                return .send(target: target ?? "unknown")
            }
        }

        for pattern in convertPatterns {
            if lowercased.contains(pattern) {
                let format = extractFormat(from: text, after: pattern)
                return .convert(format: format ?? "pdf")
            }
        }

        for pattern in summarizePatterns {
            if lowercased.contains(pattern) {
                return .extract(operation: .summarize)
            }
        }

        for pattern in translatePatterns {
            if lowercased.contains(pattern) {
                let language = extractLanguage(from: text, after: pattern)
                return .extract(operation: .translate(to: language ?? "English"))
            }
        }

        for pattern in printPatterns {
            if lowercased.contains(pattern) {
                let copies = extractCopies(from: text) ?? 1
                return .print(copies: copies, options: .default)
            }
        }

        return nil
    }

    private static func extractTarget(from text: String, after pattern: String) -> String? {
        guard let range = text.lowercased().range(of: pattern) else { return nil }
        let remaining = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let words = remaining.split(separator: " ")
        guard let firstWord = words.first else { return nil }
        return String(firstWord).capitalized
    }

    private static func extractFormat(from text: String, after pattern: String) -> String? {
        guard let range = text.lowercased().range(of: pattern) else { return nil }
        let remaining = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let words = remaining.split(separator: " ")
        guard let firstWord = words.first else { return nil }
        return String(firstWord).lowercased()
    }

    private static func extractLanguage(from text: String, after pattern: String) -> String? {
        guard let range = text.lowercased().range(of: pattern) else { return nil }
        let remaining = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let words = remaining.split(separator: " ")
        guard let firstWord = words.first else { return nil }
        return String(firstWord).capitalized
    }

    private static func extractCopies(from text: String) -> Int? {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        return numbers.first
    }
}
