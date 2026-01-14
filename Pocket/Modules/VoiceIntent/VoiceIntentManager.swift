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

    // 2.0: Synesthesia - Audio-reactive properties
    @Published var voiceHue: Double = 0.3          // 0-1, maps to color wheel (0.3 = green)
    @Published var voiceEnergy: Float = 0          // 0-1, overall voice energy
    @Published var voiceEmotion: VoiceEmotion = .neutral  // Inferred emotion from voice

    enum VoiceEmotion {
        case neutral   // Default, green
        case excited   // High energy, warm colors (orange/red)
        case calm      // Low energy, cool colors (blue/purple)
        case urgent    // Rapid changes, yellow
    }

    // MARK: - Private Properties

    private let groqService: GroqService
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?

    // 2.0: VAD (Voice Activity Detection) properties
    private var vadTimer: Timer?
    private var silenceStartTime: Date?
    private var hasDetectedSpeech: Bool = false
    private var onSilenceDetected: (() -> Void)?

    // VAD Configuration
    private let silenceThreshold: Float = 0.05        // Audio level below this = silence
    private let silenceDuration: TimeInterval = 1.2   // Seconds of silence to trigger stop
    private let maxRecordingDuration: TimeInterval = 10.0  // Maximum recording time
    private let minSpeechDuration: TimeInterval = 0.5 // Minimum speech before allowing silence detection

    // 2.0: Synesthesia analysis properties
    private var audioLevelHistory: [Float] = []
    private let synesthesiaHistorySize: Int = 20
    private var peakLevel: Float = 0
    private var levelChangeRate: Float = 0
    private var lastLevel: Float = 0

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

    // MARK: - 2.0: VAD-Enabled Listening

    /// Start listening with Voice Activity Detection - auto-stops when user finishes speaking
    func startListeningWithVAD(onComplete: @escaping () -> Void) {
        debugLog("🎤 startListeningWithVAD() called")

        guard !isListening else {
            debugLog("🎤 Already listening, returning")
            return
        }

        currentTranscription = nil
        partialTranscription = ""
        error = nil
        hasDetectedSpeech = false
        silenceStartTime = nil
        onSilenceDetected = onComplete

        do {
            try startRecording()
            isListening = true
            startVADMonitoring()
            debugLog("🎤 VAD recording started successfully")
            logger.info("🎤 VAD recording started")
        } catch {
            debugLog("🎤 Failed to start VAD recording: \(error.localizedDescription)")
            self.error = .audioEngineError(error)
        }
    }

    /// Start VAD monitoring timer
    private func startVADMonitoring() {
        let startTime = Date()

        vadTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkVAD(recordingStartTime: startTime)
            }
        }
    }

    /// Check voice activity and auto-stop if silence detected
    private func checkVAD(recordingStartTime: Date) {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        let linearLevel = pow(10, level / 20)
        audioLevel = min(1.0, max(0.0, linearLevel * 2))

        // 2.0: Update synesthesia properties
        updateSynesthesia(level: audioLevel)

        let recordingDuration = Date().timeIntervalSince(recordingStartTime)

        // Check max recording time
        if recordingDuration >= maxRecordingDuration {
            debugLog("🎤 VAD: Max recording time reached (\(maxRecordingDuration)s)")
            triggerVADStop()
            return
        }

        // Detect speech
        if audioLevel > silenceThreshold {
            hasDetectedSpeech = true
            silenceStartTime = nil
            partialTranscription = "Listening..."
        } else if hasDetectedSpeech {
            // We've heard speech, now detect silence
            if silenceStartTime == nil {
                silenceStartTime = Date()
            } else if let silenceStart = silenceStartTime {
                let silenceDurationNow = Date().timeIntervalSince(silenceStart)

                if silenceDurationNow >= silenceDuration {
                    debugLog("🎤 VAD: Silence detected for \(String(format: "%.1f", silenceDurationNow))s, stopping...")
                    triggerVADStop()
                }
            }
        }
    }

    // MARK: - 2.0: Synesthesia Analysis

    /// Update synesthesia properties based on current audio level
    private func updateSynesthesia(level: Float) {
        // Track level history
        audioLevelHistory.append(level)
        if audioLevelHistory.count > synesthesiaHistorySize {
            audioLevelHistory.removeFirst()
        }

        // Track peak level
        if level > peakLevel {
            peakLevel = level
        }

        // Calculate change rate (how rapidly the level is changing)
        levelChangeRate = abs(level - lastLevel)
        lastLevel = level

        // Calculate average energy
        let avgLevel = audioLevelHistory.reduce(0, +) / Float(max(1, audioLevelHistory.count))
        voiceEnergy = avgLevel

        // Determine emotion and hue based on audio characteristics
        updateVoiceEmotionAndHue(avgLevel: avgLevel, peakLevel: peakLevel, changeRate: levelChangeRate)
    }

    /// Map audio characteristics to emotion and color
    private func updateVoiceEmotionAndHue(avgLevel: Float, peakLevel: Float, changeRate: Float) {
        // Classify emotion based on audio characteristics
        if changeRate > 0.3 {
            // Rapid changes = urgent (yellow, hue ~0.15)
            voiceEmotion = .urgent
            voiceHue = 0.15
        } else if avgLevel > 0.4 || peakLevel > 0.7 {
            // High energy = excited (orange/red, hue ~0.05-0.1)
            voiceEmotion = .excited
            voiceHue = 0.05 + Double(avgLevel) * 0.1
        } else if avgLevel < 0.15 && avgLevel > 0.02 {
            // Low steady energy = calm (blue/purple, hue ~0.6-0.7)
            voiceEmotion = .calm
            voiceHue = 0.6 + Double(avgLevel) * 0.5
        } else {
            // Neutral speaking (green, hue ~0.3)
            voiceEmotion = .neutral
            voiceHue = 0.3
        }
    }

    /// Reset synesthesia state
    private func resetSynesthesia() {
        audioLevelHistory.removeAll()
        peakLevel = 0
        levelChangeRate = 0
        lastLevel = 0
        voiceHue = 0.3
        voiceEnergy = 0
        voiceEmotion = .neutral
    }

    /// Trigger stop from VAD detection
    private func triggerVADStop() {
        vadTimer?.invalidate()
        vadTimer = nil
        silenceStartTime = nil

        stopRecording()
        isListening = false

        debugLog("🎤 VAD: Recording stopped, transcribing...")

        Task {
            await transcribeRecording()

            // Notify completion
            await MainActor.run {
                onSilenceDetected?()
                onSilenceDetected = nil
            }
        }
    }

    private func stopVADMonitoring() {
        vadTimer?.invalidate()
        vadTimer = nil
        silenceStartTime = nil
        hasDetectedSpeech = false
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
