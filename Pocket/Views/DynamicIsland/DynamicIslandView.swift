import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.pocket.app", category: "DynamicIsland")

/// The main Dynamic Island view that serves as the Pocket interface
/// Implements the "Grip & Speak Loop" interaction pattern
struct DynamicIslandView: View {
    @EnvironmentObject var pocketState: PocketState
    @EnvironmentObject var dropZoneManager: DropZoneManager
    @EnvironmentObject var voiceIntentManager: VoiceIntentManager
    @EnvironmentObject var intentPredictor: IntentPredictor  // 2.0: Intent prediction
    @EnvironmentObject var pocketSession: PocketSession      // 3.0: Multi-file session
    @EnvironmentObject var portalManager: PortalManager      // 5.0: Cross-device portal

    @State private var isHovering = false
    @State private var haloOpacity: Double = 0
    @State private var islandScale: CGFloat = 1.0
    @State private var previousPhase: PocketState.InteractionPhase = .idle

    // 2.0: Metaball effect states
    @State private var dragProximity: CGFloat = 0
    @State private var showGooeyEffect: Bool = false

    // MARK: - Layout Constants

    private enum Layout {
        static let collapsedWidth: CGFloat = 126
        static let collapsedHeight: CGFloat = 37
        static let expandedWidth: CGFloat = 350
        static let expandedHeight: CGFloat = 84
        static let cornerRadius: CGFloat = 44
        static let haloRadius: CGFloat = 8
    }

    // MARK: - Animation Constants

    private enum Animation {
        // 2.0: Differentiated animations - open is eager, close is settled
        static let expand = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.6, blendDuration: 0.1)  // Fast, bouncy - eager to receive
        static let collapse = SwiftUI.Animation.spring(response: 0.55, dampingFraction: 0.85, blendDuration: 0.1)  // Slow, heavy - satisfied and settled
        static let halo = SwiftUI.Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        static let content = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.7)  // Snappy content transitions
        static let anticipation = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.5)  // Eager anticipation wiggle
    }

    var body: some View {
        ZStack {
            // Halo effect layer (behind island)
            // 2.0: Now with synesthesia - voice drives halo color
            if shouldShowHalo {
                HaloEffectView(
                    isActive: isHovering,
                    phase: pocketState.currentPhase,
                    voiceHue: voiceIntentManager.voiceHue,
                    voiceEnergy: voiceIntentManager.voiceEnergy
                )
                .frame(width: currentWidth + Layout.haloRadius * 2,
                       height: currentHeight + Layout.haloRadius * 2)
            }

            // 2.0: Gooey metaball effect layer
            if showGooeyEffect {
                gooeyEffectLayer
            }

            // Main island container
            islandContainer
                .frame(width: currentWidth, height: currentHeight)
                .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                .scaleEffect(islandScale)
                // 2.0: Add "reaching" bulge when item approaches
                .overlay(
                    reachingBulge
                        .opacity(dragProximity > 0.3 ? 1 : 0)
                )

            // Drop zone overlay (invisible, handles drag & drop)
            dropZoneOverlay

            // 2.0: Prediction bubbles
            PredictionBubblesView(
                predictor: intentPredictor,
                onPredictionSelected: { prediction in
                    handlePredictionSelected(prediction)
                },
                isVisible: intentPredictor.isShowingPredictions && pocketState.currentPhase == .anticipation
            )
            .offset(y: 40)  // Position below the island
        }
        .onChange(of: pocketState.currentPhase) { oldPhase, newPhase in
            // 2.0: Apply directional animation based on expand/collapse
            let isExpanding = phaseSize(newPhase) > phaseSize(oldPhase)
            withAnimation(isExpanding ? Animation.expand : Animation.collapse) {
                previousPhase = newPhase
            }
        }
        .onChange(of: isHovering) { _, newValue in
            print("🎯 [DynamicIsland] isHovering changed to: \(newValue)")
            if newValue {
                // First trigger anticipation, then engagement
                print("🎯 [DynamicIsland] Triggering onDragDetected and onHoverEnter")
                pocketState.onDragDetected()
                pocketState.onHoverEnter()

                // 2.0: Activate gooey effect
                withAnimation(Animation.anticipation) {
                    showGooeyEffect = true
                    dragProximity = 0.8  // Simulate high proximity when hovering
                }

                // 2.0: Show prediction bubbles based on detected item type
                if let detectedType = dropZoneManager.lastDetectedType {
                    intentPredictor.predict(for: detectedType)
                } else {
                    intentPredictor.predict(for: .document)  // Default
                }
                intentPredictor.showPredictions()
            } else {
                print("🎯 [DynamicIsland] Triggering onHoverExit")
                pocketState.onHoverExit()

                // 2.0: Deactivate gooey effect
                withAnimation(Animation.collapse) {
                    dragProximity = 0
                    showGooeyEffect = false
                }

                // 2.0: Hide predictions after a delay (give time for drop)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !isHovering {
                        intentPredictor.clearPredictions()
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var currentWidth: CGFloat {
        switch pocketState.currentPhase {
        case .idle:
            return Layout.collapsedWidth
        case .anticipation:
            return Layout.collapsedWidth * 1.1
        case .engagement, .listening, .processing, .completion:
            return Layout.expandedWidth
        }
    }

    private var currentHeight: CGFloat {
        switch pocketState.currentPhase {
        case .idle:
            return Layout.collapsedHeight
        case .anticipation:
            return Layout.collapsedHeight * 1.05
        case .engagement, .listening, .processing, .completion:
            return Layout.expandedHeight
        }
    }

    private var shouldShowHalo: Bool {
        switch pocketState.currentPhase {
        case .idle:
            return false
        case .anticipation, .engagement, .listening, .processing, .completion:
            return true
        }
    }

    /// Returns a numeric size value for animation direction calculation
    private func phaseSize(_ phase: PocketState.InteractionPhase) -> Int {
        switch phase {
        case .idle: return 0
        case .anticipation: return 1
        case .engagement: return 2
        case .listening: return 3
        case .processing: return 3
        case .completion: return 2
        }
    }

    // MARK: - 2.0 Gooey Effect Views

    /// The gooey metaball effect layer that creates liquid merging illusion
    private var gooeyEffectLayer: some View {
        SimpleGooeyEffect(
            islandWidth: currentWidth,
            islandHeight: currentHeight,
            dragOffset: CGPoint(x: 0, y: -50), // Item approaches from above
            proximity: dragProximity,
            isActive: showGooeyEffect
        )
        .allowsHitTesting(false)
    }

    /// A bulge that "reaches" toward the approaching item
    private var reachingBulge: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.3), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 20
                )
            )
            .frame(width: 40 * dragProximity, height: 40 * dragProximity)
            .offset(y: -(currentHeight / 2 + 10 * dragProximity))
            .animation(Animation.anticipation, value: dragProximity)
    }

    // MARK: - 2.0 Prediction Handling

    /// Handle when user drops on a prediction bubble - skip voice input
    private func handlePredictionSelected(_ prediction: PredictedAction) {
        print("🔮 [DynamicIsland] Prediction selected: \(prediction.label)")

        // Clear predictions
        intentPredictor.clearPredictions()

        // Get the pending item from DropZoneManager
        Task {
            let items = await dropZoneManager.getLastProcessedItems()
            guard let item = items.first else {
                print("🔮 [DynamicIsland] No item found for prediction")
                return
            }

            // Create intent directly from prediction (skip voice)
            let intent = Intent(
                action: prediction.action,
                rawCommand: "[Predicted: \(prediction.label)]",
                confidence: prediction.confidence
            )

            // Execute directly
            pocketState.pendingItem = item
            pocketState.currentPhase = .processing(intent.displayDescription)
            pocketState.hapticsManager.playDropFeedback()

            do {
                let task = PocketTask(item: item, intent: intent)
                pocketState.activeTask = task
                try await pocketState.executeTaskDirectly(task)
                pocketState.currentPhase = .completion(true)
                pocketState.hapticsManager.playSuccessFeedback()
            } catch {
                pocketState.currentPhase = .completion(false)
                pocketState.hapticsManager.playErrorFeedback()
            }

            // Reset after delay
            try? await Task.sleep(for: .seconds(2))
            pocketState.resetToIdle()
        }
    }

    // MARK: - Subviews

    private var islandContainer: some View {
        ZStack {
            // Background with ultra-thin material effect
            islandBackground

            // Content based on current phase
            islandContent
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var islandBackground: some View {
        ZStack {
            // Base black
            Color.black

            // Ultra thin material overlay for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.15)
        }
    }

    @ViewBuilder
    private var islandContent: some View {
        switch pocketState.currentPhase {
        case .idle:
            idleContent

        case .anticipation:
            anticipationContent

        case .engagement:
            engagementContent

        case .listening:
            listeningContent

        case .processing(let status):
            processingContent(status: status)

        case .completion(let success):
            completionContent(success: success)
        }
    }

    private var idleContent: some View {
        HStack(spacing: 8) {
            // Camera indicator (mimicking actual Dynamic Island)
            Circle()
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            Spacer()

            // 3.0: Session indicator (stacked items)
            if pocketSession.isActive {
                HStack(spacing: 4) {
                    Image(systemName: pocketSession.state.icon)
                        .font(.system(size: 10))
                    Text("\(pocketSession.itemCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
            }

            // Pocket indicator (held items)
            if !pocketState.heldItems.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 10))
                    Text("\(pocketState.heldItems.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.6))
            }

            // 5.0: Portal button
            PortalButtonView(portalManager: portalManager)
        }
    }

    private var anticipationContent: some View {
        HStack(spacing: 12) {
            // Pulsing indicator
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 8, height: 8)
                .scaleEffect(haloOpacity > 0.5 ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: haloOpacity)
                .onAppear { haloOpacity = 1.0 }

            Text("Drop here")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Spacer()
        }
    }

    private var engagementContent: some View {
        HStack(spacing: 16) {
            // File preview / icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "doc.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Drop to continue")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)

                Text("Release to start listening")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Drop indicator
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.blue)
        }
    }

    private var listeningContent: some View {
        HStack(spacing: 16) {
            // File icon with item info
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: pocketState.pendingItem?.type.icon ?? "doc.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Show transcription if available, otherwise prompt
                if !voiceIntentManager.partialTranscription.isEmpty {
                    Text(voiceIntentManager.partialTranscription)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                } else {
                    Text("Speak your command...")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Status indicator
                HStack(spacing: 4) {
                    Image(systemName: voiceIntentManager.isListening ? "mic.fill" : "mic.slash")
                        .font(.system(size: 12))
                        .foregroundColor(voiceIntentManager.isListening ? .green : .orange)
                    Text(voiceIntentManager.isListening ? "Listening..." : "Processing...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            // Animated mic indicator
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(.green)
                .symbolEffect(.variableColor.iterative)
        }
    }

    private func processingContent(status: String) -> some View {
        HStack(spacing: 16) {
            // Spinning indicator
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Processing")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)

                Text(status)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
    }

    private func completionContent(success: Bool) -> some View {
        HStack(spacing: 16) {
            // Result icon
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(success ? .green : .red)
                .symbolEffect(.bounce, value: success)

            VStack(alignment: .leading, spacing: 2) {
                Text(success ? "Done" : "Failed")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)

                if let task = pocketState.activeTask, let result = task.result {
                    Text(result.displayMessage)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }

    // MARK: - Drop Zone Overlay

    private var dropZoneOverlay: some View {
        Rectangle()
            .fill(Color.clear) // Invisible drop zone
            .frame(width: Layout.expandedWidth + 50, height: Layout.expandedHeight + 50) // Larger hit area
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .url, .image, .plainText, .data], isTargeted: $isHovering) { providers in
                print("🎯 [DynamicIsland] onDrop triggered with \(providers.count) providers")
                return handleDrop(providers: providers)
            }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("📦 [DynamicIsland] handleDrop called with \(providers.count) providers")

        guard !providers.isEmpty else {
            print("📦 [DynamicIsland] No providers, returning false")
            return false
        }

        // Log provider details
        for (index, provider) in providers.enumerated() {
            print("📦 [DynamicIsland] Provider \(index): \(provider.registeredTypeIdentifiers)")
        }

        // Process the drop using DropZoneManager
        Task {
            print("📦 [DynamicIsland] Processing drop data...")
            let items = await dropZoneManager.processDropData(providers)
            print("📦 [DynamicIsland] Processed \(items.count) items")

            if let firstItem = items.first {
                print("📦 [DynamicIsland] First item: \(firstItem.name), type: \(firstItem.type)")

                // Play haptic feedback
                pocketState.onDropDetected()

                // 3.0: Add to session if active, or start new session
                if pocketSession.isActive {
                    // Add to existing session
                    let added = pocketSession.addItems(items)
                    print("📚 [DynamicIsland] Added \(added) items to session (total: \(pocketSession.itemCount))")
                } else {
                    // Start new session
                    pocketSession.startSession(with: firstItem)
                    for item in items.dropFirst() {
                        _ = pocketSession.addItem(item)
                    }
                }

                // Enter listening phase
                pocketState.pendingItem = firstItem
                pocketState.currentPhase = .listening

                // Clear predictions since we're now in voice mode
                intentPredictor.clearPredictions()

                // 2.0: Use VAD-enabled listening (auto-stops when user finishes speaking)
                print("🎤 [DynamicIsland] Starting VAD-enabled voice listening...")

                await withCheckedContinuation { continuation in
                    voiceIntentManager.startListeningWithVAD {
                        continuation.resume()
                    }
                }

                // Wait for transcription to complete
                print("🎤 [DynamicIsland] VAD stopped, waiting for transcription...")
                var waitCount = 0
                let maxWait = 100 // 10 seconds max wait for transcription
                while waitCount < maxWait {
                    if !voiceIntentManager.isTranscribing && voiceIntentManager.currentTranscription != nil {
                        break
                    }
                    if waitCount > 30 && !voiceIntentManager.isTranscribing {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                    waitCount += 1
                }

                let voiceCommand = voiceIntentManager.currentTranscription
                print("🎤 [DynamicIsland] ========================================")
                print("🎤 [DynamicIsland] Voice command captured: '\(voiceCommand ?? "nil")'")
                print("🎤 [DynamicIsland] VAD auto-stopped after detecting silence")
                print("🎤 [DynamicIsland] ========================================")

                // Process with voice command
                await pocketState.processWithVoiceCommand(voiceCommand)
            } else {
                print("📦 [DynamicIsland] No items processed from providers")
            }
        }

        return true
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            DynamicIslandView()
                .padding(.top, 60)
            Spacer()
        }
    }
    .environmentObject(PocketState())
    .environmentObject(DropZoneManager())
    .environmentObject(VoiceIntentManager())
}
