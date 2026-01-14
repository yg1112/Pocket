import SwiftUI

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

/// Pocket 1.0 - The Intent Hub
/// A multimodal hub residing in the Dynamic Island for drag-drop file handling with voice commands.
@main
struct PocketApp: App {
    @StateObject private var pocketState = PocketState()
    @StateObject private var dropZoneManager = DropZoneManager()
    @StateObject private var voiceIntentManager = VoiceIntentManager()
    @StateObject private var intentPredictor = IntentPredictor()  // 2.0: Intent prediction
    @StateObject private var pocketSession = PocketSession()      // 3.0: Multi-file session
    @StateObject private var portalManager = PortalManager()      // 5.0: Cross-device portal

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pocketState)
                .environmentObject(dropZoneManager)
                .environmentObject(voiceIntentManager)
                .environmentObject(intentPredictor)
                .environmentObject(pocketSession)
                .environmentObject(portalManager)
        }
    }
}

/// Central state management for Pocket
/// Coordinates between drop zone, voice intent, and file operations
@MainActor
final class PocketState: ObservableObject {

    // MARK: - Published Properties

    /// Current phase of the Grip & Speak Loop
    @Published var currentPhase: InteractionPhase = .idle

    /// Items currently held in the pocket
    @Published var heldItems: [PocketItem] = []

    /// Current processing task, if any
    @Published var activeTask: PocketTask?

    /// History of completed tasks
    @Published var taskHistory: [PocketTask] = []

    // MARK: - Services

    let hapticsManager = HapticsManager()
    let fileService = FileService()
    let intentParser = IntentParser()

    // MARK: - Interaction Phase

    enum InteractionPhase: Hashable {
        case idle                    // Default state
        case anticipation            // User started dragging, Pocket is ready
        case engagement              // Item hovering over drop zone, mic active
        case listening               // Item dropped, waiting for voice command
        case processing(String)      // Executing command with status message
        case completion(Bool)        // Task completed (success/failure)
    }

    /// Item waiting for voice command
    @Published var pendingItem: PocketItem?

    /// Listening timeout duration (seconds)
    let listeningTimeout: TimeInterval = 5.0

    // MARK: - Methods

    /// Transition to anticipation phase when drag begins
    func onDragDetected() {
        guard currentPhase == .idle else { return }
        currentPhase = .anticipation
        hapticsManager.prepareAll()
    }

    /// Transition to engagement when item hovers over drop zone
    func onHoverEnter() {
        guard currentPhase == .anticipation else { return }
        currentPhase = .engagement
        hapticsManager.playHoverFeedback()
    }

    /// Handle hover exit (user moved away without dropping)
    func onHoverExit() {
        guard currentPhase == .engagement else { return }
        currentPhase = .anticipation
    }

    /// Called when drop is detected - plays haptic feedback
    func onDropDetected() {
        print("📥 [PocketState] onDropDetected called")
        hapticsManager.playDropFeedback()
    }

    /// Process pending item with voice command
    func processWithVoiceCommand(_ voiceCommand: String?) async {
        debugLog("📥 [PocketState] processWithVoiceCommand called")
        debugLog("📥 [PocketState] Voice command: '\(voiceCommand ?? "nil")'")

        guard let item = pendingItem else {
            debugLog("📥 [PocketState] ERROR: No pending item to process")
            resetToIdle()
            return
        }

        debugLog("📥 [PocketState] Processing item: \(item.name) with command: \(voiceCommand ?? "none")")

        // Parse intent from voice command
        let intent = await intentParser.parse(command: voiceCommand, for: item)
        debugLog("📥 [PocketState] Parsed intent: \(intent.displayDescription)")

        // Create and execute task
        let task = PocketTask(item: item, intent: intent)
        activeTask = task
        currentPhase = .processing(intent.displayDescription)

        // 2.0: Start heartbeat haptics during processing
        hapticsManager.startHeartbeat()

        do {
            debugLog("📥 [PocketState] Executing task...")
            try await executeTask(task)

            // 2.0: Stop heartbeat before completion feedback
            hapticsManager.stopHeartbeat()

            currentPhase = .completion(true)
            hapticsManager.playSuccessFeedback()
            debugLog("📥 [PocketState] ✅ Task completed successfully")
        } catch {
            // 2.0: Stop heartbeat before error feedback
            hapticsManager.stopHeartbeat()

            currentPhase = .completion(false)
            hapticsManager.playErrorFeedback()
            debugLog("📥 [PocketState] ❌ Task failed: \(error)")
        }

        // Clear pending item
        pendingItem = nil

        // Reset after delay
        try? await Task.sleep(for: .seconds(2))
        resetToIdle()
    }

    /// Execute a pocket task based on its intent
    private func executeTask(_ task: PocketTask) async throws {
        debugLog("⚡️ [PocketState] Executing action: \(task.intent.action)")

        switch task.intent.action {
        case .hold:
            // F1: Universal Hold - just store the item
            debugLog("⚡️ [PocketState] HOLD: Storing item '\(task.item.name)'")
            heldItems.append(task.item)
            debugLog("⚡️ [PocketState] Items in pocket: \(heldItems.count)")

        case .send(let target):
            // F2: Quick Dispatch - send to contact
            debugLog("⚡️ [PocketState] SEND: Sending '\(task.item.name)' to '\(target)'")
            try await fileService.sendFile(task.item, to: target)
            debugLog("⚡️ [PocketState] SEND: Complete")

        case .convert(let format):
            // F3: Format Alchemist - convert format
            debugLog("⚡️ [PocketState] CONVERT: Converting '\(task.item.name)' to '\(format)'")
            let converted = try await fileService.convertFile(task.item, to: format)
            heldItems.append(converted)
            debugLog("⚡️ [PocketState] CONVERT: Complete, created '\(converted.name)'")

        case .extract(let operation):
            // F4: Content Distiller - summarize/extract/translate
            debugLog("⚡️ [PocketState] EXTRACT: Processing '\(task.item.name)' with \(operation)")
            let result = try await intentParser.processContent(task.item, operation: operation)
            // Store result as new item
            let resultItem = PocketItem(
                id: UUID(),
                type: .text,
                data: result.data(using: .utf8) ?? Data(),
                name: "Summary",
                timestamp: Date()
            )
            heldItems.append(resultItem)
            debugLog("⚡️ [PocketState] EXTRACT: Complete, result: \(result.prefix(100))...")

        case .print(let copies, let options):
            // F5: Physical Link - print
            debugLog("⚡️ [PocketState] PRINT: Printing '\(task.item.name)' x\(copies)")
            try await fileService.printFile(task.item, copies: copies, options: options)
            debugLog("⚡️ [PocketState] PRINT: Complete")

        case .airplay(let device):
            // F5: Physical Link - AirPlay
            debugLog("⚡️ [PocketState] AIRPLAY: Sending '\(task.item.name)' to '\(device)'")
            try await fileService.airplayFile(task.item, to: device)
            debugLog("⚡️ [PocketState] AIRPLAY: Complete")
        }

        taskHistory.append(task)
        activeTask = nil
    }

    /// Reset to idle state
    func resetToIdle() {
        currentPhase = .idle
        activeTask = nil
    }

    /// Remove item from pocket (user dragged it out)
    func removeItem(_ item: PocketItem) {
        heldItems.removeAll { $0.id == item.id }
    }

    // MARK: - 2.0: Direct Task Execution (for predictions)

    /// Execute a task directly without voice input (used by prediction bubbles)
    func executeTaskDirectly(_ task: PocketTask) async throws {
        debugLog("⚡️ [PocketState] Direct execution: \(task.intent.action)")

        switch task.intent.action {
        case .hold:
            debugLog("⚡️ [PocketState] HOLD: Storing item '\(task.item.name)'")
            heldItems.append(task.item)
            debugLog("⚡️ [PocketState] Items in pocket: \(heldItems.count)")

        case .send(let target):
            debugLog("⚡️ [PocketState] SEND: Sending '\(task.item.name)' to '\(target)'")
            try await fileService.sendFile(task.item, to: target)
            debugLog("⚡️ [PocketState] SEND: Complete")

        case .convert(let format):
            debugLog("⚡️ [PocketState] CONVERT: Converting '\(task.item.name)' to '\(format)'")
            let converted = try await fileService.convertFile(task.item, to: format)
            heldItems.append(converted)
            debugLog("⚡️ [PocketState] CONVERT: Complete, created '\(converted.name)'")

        case .extract(let operation):
            debugLog("⚡️ [PocketState] EXTRACT: Processing '\(task.item.name)' with \(operation)")
            let result = try await intentParser.processContent(task.item, operation: operation)
            let resultItem = PocketItem(
                id: UUID(),
                type: .text,
                data: result.data(using: .utf8) ?? Data(),
                name: "Summary",
                timestamp: Date()
            )
            heldItems.append(resultItem)
            debugLog("⚡️ [PocketState] EXTRACT: Complete")

        case .print(let copies, let options):
            debugLog("⚡️ [PocketState] PRINT: Printing '\(task.item.name)' x\(copies)")
            try await fileService.printFile(task.item, copies: copies, options: options)
            debugLog("⚡️ [PocketState] PRINT: Complete")

        case .airplay(let device):
            debugLog("⚡️ [PocketState] AIRPLAY: Sending '\(task.item.name)' to '\(device)'")
            try await fileService.airplayFile(task.item, to: device)
            debugLog("⚡️ [PocketState] AIRPLAY: Complete")
        }

        taskHistory.append(task)
        activeTask = nil
    }
}
