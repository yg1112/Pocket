import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.pocket.app", category: "DynamicIsland")

/// The main Dynamic Island view that serves as the Pocket interface
/// Implements the "Grip & Speak Loop" interaction pattern
struct DynamicIslandView: View {
    @EnvironmentObject var pocketState: PocketState
    @EnvironmentObject var dropZoneManager: DropZoneManager
    @EnvironmentObject var voiceIntentManager: VoiceIntentManager

    @State private var isHovering = false
    @State private var haloOpacity: Double = 0
    @State private var islandScale: CGFloat = 1.0

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
        static let morphing = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.7)
        static let halo = SwiftUI.Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        static let content = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
    }

    var body: some View {
        ZStack {
            // Halo effect layer (behind island)
            if shouldShowHalo {
                HaloEffectView(
                    isActive: isHovering,
                    phase: pocketState.currentPhase
                )
                .frame(width: currentWidth + Layout.haloRadius * 2,
                       height: currentHeight + Layout.haloRadius * 2)
            }

            // Main island container
            islandContainer
                .frame(width: currentWidth, height: currentHeight)
                .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                .scaleEffect(islandScale)
                .animation(Animation.morphing, value: pocketState.currentPhase)
                .animation(Animation.morphing, value: isHovering)

            // Drop zone overlay (invisible, handles drag & drop)
            dropZoneOverlay
        }
        .onChange(of: isHovering) { _, newValue in
            print("🎯 [DynamicIsland] isHovering changed to: \(newValue)")
            if newValue {
                // First trigger anticipation, then engagement
                print("🎯 [DynamicIsland] Triggering onDragDetected and onHoverEnter")
                pocketState.onDragDetected()
                pocketState.onHoverEnter()
            } else {
                print("🎯 [DynamicIsland] Triggering onHoverExit")
                pocketState.onHoverExit()
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

            // Pocket indicator
            if !pocketState.heldItems.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 10))
                    Text("\(pocketState.heldItems.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.6))
            }
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

                // Start listening for voice command
                print("🎤 [DynamicIsland] Starting voice listening...")
                voiceIntentManager.startListening()

                // Enter listening phase
                pocketState.pendingItem = firstItem
                pocketState.currentPhase = .listening

                // Wait for voice input (5 seconds recording time)
                print("🎤 [DynamicIsland] Recording for 5 seconds...")
                try? await Task.sleep(for: .seconds(5))

                // Stop recording - this triggers transcription
                print("🎤 [DynamicIsland] Stopping recording, starting transcription...")
                voiceIntentManager.stopListening()

                // Wait a moment for transcription task to start
                try? await Task.sleep(for: .milliseconds(200))

                // Wait for transcription to complete
                // Either: isTranscribing becomes false, OR currentTranscription is set
                print("🎤 [DynamicIsland] Waiting for transcription...")
                var waitCount = 0
                let maxWait = 150 // 15 seconds max wait
                while waitCount < maxWait {
                    // Check if transcription is done
                    if !voiceIntentManager.isTranscribing && voiceIntentManager.currentTranscription != nil {
                        break
                    }
                    // Also break if we've been waiting and isTranscribing is false (error case)
                    if waitCount > 50 && !voiceIntentManager.isTranscribing {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                    waitCount += 1
                }

                let voiceCommand = voiceIntentManager.currentTranscription
                print("🎤 [DynamicIsland] ========================================")
                print("🎤 [DynamicIsland] Voice command captured: '\(voiceCommand ?? "nil")'")
                print("🎤 [DynamicIsland] isTranscribing: \(voiceIntentManager.isTranscribing)")
                print("🎤 [DynamicIsland] partialTranscription: '\(voiceIntentManager.partialTranscription)'")
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
