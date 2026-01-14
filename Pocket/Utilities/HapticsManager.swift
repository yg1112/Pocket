import Foundation

#if os(iOS)
import UIKit
import CoreHaptics
#else
import AppKit
#endif

/// Manages haptic feedback for Pocket interactions
/// On macOS, provides stub implementations (no haptics available)
@MainActor
final class HapticsManager {

    #if os(iOS)
    // MARK: - Haptic Engines (iOS only)

    private var impactLight: UIImpactFeedbackGenerator?
    private var impactMedium: UIImpactFeedbackGenerator?
    private var impactRigid: UIImpactFeedbackGenerator?
    private var selectionGenerator: UISelectionFeedbackGenerator?
    private var notificationGenerator: UINotificationFeedbackGenerator?

    private var coreHapticsEngine: CHHapticEngine?
    private var supportsHaptics: Bool = false

    // 2.0: Heartbeat haptic player
    private var heartbeatPlayer: CHHapticAdvancedPatternPlayer?
    private var isHeartbeatActive: Bool = false
    #endif

    // MARK: - Initialization

    init() {
        #if os(iOS)
        setupGenerators()
        setupCoreHaptics()
        #endif
    }

    #if os(iOS)
    private func setupGenerators() {
        impactLight = UIImpactFeedbackGenerator(style: .light)
        impactMedium = UIImpactFeedbackGenerator(style: .medium)
        impactRigid = UIImpactFeedbackGenerator(style: .rigid)
        selectionGenerator = UISelectionFeedbackGenerator()
        notificationGenerator = UINotificationFeedbackGenerator()
    }

    private func setupCoreHaptics() {
        let hapticCapability = CHHapticEngine.capabilitiesForHardware()
        supportsHaptics = hapticCapability.supportsHaptics

        guard supportsHaptics else { return }

        do {
            coreHapticsEngine = try CHHapticEngine()
            try coreHapticsEngine?.start()

            coreHapticsEngine?.resetHandler = { [weak self] in
                do {
                    try self?.coreHapticsEngine?.start()
                } catch {
                    print("Failed to restart haptic engine: \(error)")
                }
            }
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    #endif

    // MARK: - Prepare

    func prepareAll() {
        #if os(iOS)
        impactLight?.prepare()
        impactMedium?.prepare()
        impactRigid?.prepare()
        selectionGenerator?.prepare()
        notificationGenerator?.prepare()
        #endif
    }

    // MARK: - Interaction Haptics

    func playHoverFeedback() {
        #if os(iOS)
        impactLight?.impactOccurred(intensity: 0.5)
        #else
        // macOS: Could play a sound instead
        NSSound.beep()
        #endif
    }

    func playMicActivateFeedback() {
        #if os(iOS)
        impactRigid?.impactOccurred()
        #endif
    }

    func playDropFeedback() {
        #if os(iOS)
        impactMedium?.impactOccurred(intensity: 0.8)
        #endif
    }

    func playSuccessFeedback() {
        #if os(iOS)
        notificationGenerator?.notificationOccurred(.success)
        #else
        NSSound(named: "Glass")?.play()
        #endif
    }

    func playErrorFeedback() {
        #if os(iOS)
        notificationGenerator?.notificationOccurred(.error)
        #else
        NSSound.beep()
        #endif
    }

    func playWarningFeedback() {
        #if os(iOS)
        notificationGenerator?.notificationOccurred(.warning)
        #endif
    }

    func playSelectionFeedback() {
        #if os(iOS)
        selectionGenerator?.selectionChanged()
        #endif
    }

    func playProcessingHaptic() {
        #if os(iOS)
        impactLight?.impactOccurred(intensity: 0.3)
        #endif
    }

    func playCelebrationHaptic() {
        #if os(iOS)
        notificationGenerator?.notificationOccurred(.success)
        #else
        NSSound(named: "Glass")?.play()
        #endif
    }

    // MARK: - Engine Management

    func stopEngine() {
        #if os(iOS)
        coreHapticsEngine?.stop()
        #endif
    }

    func restartEngine() {
        #if os(iOS)
        guard supportsHaptics else { return }
        do {
            try coreHapticsEngine?.start()
        } catch {
            print("Failed to restart haptic engine: \(error)")
        }
        #endif
    }
}

// MARK: - Haptic Intensity

extension HapticsManager {
    enum Intensity: Float {
        case subtle = 0.3
        case light = 0.5
        case medium = 0.7
        case strong = 1.0
    }

    func playImpact(intensity: Intensity) {
        #if os(iOS)
        impactMedium?.impactOccurred(intensity: CGFloat(intensity.rawValue))
        #endif
    }
}

// MARK: - 2.0: Heartbeat Haptics (Processing state)

extension HapticsManager {

    /// Start continuous heartbeat-like haptics during processing
    func startHeartbeat() {
        #if os(iOS)
        guard supportsHaptics, let engine = coreHapticsEngine else { return }
        guard !isHeartbeatActive else { return }

        isHeartbeatActive = true

        do {
            let pattern = try createHeartbeatPattern()
            heartbeatPlayer = try engine.makeAdvancedPlayer(with: pattern)
            heartbeatPlayer?.loopEnabled = true

            try heartbeatPlayer?.start(atTime: CHHapticTimeImmediate)
            print("💓 [Haptics] Heartbeat started")
        } catch {
            print("💓 [Haptics] Failed to start heartbeat: \(error)")
        }
        #endif
    }

    /// Stop heartbeat haptics
    func stopHeartbeat() {
        #if os(iOS)
        guard isHeartbeatActive else { return }

        do {
            try heartbeatPlayer?.stop(atTime: CHHapticTimeImmediate)
            heartbeatPlayer = nil
            isHeartbeatActive = false
            print("💓 [Haptics] Heartbeat stopped")
        } catch {
            print("💓 [Haptics] Failed to stop heartbeat: \(error)")
        }
        #endif
    }

    #if os(iOS)
    /// Create a heartbeat pattern: lub-DUB ... lub-DUB
    private func createHeartbeatPattern() throws -> CHHapticPattern {
        // Heartbeat timing constants
        let beatDuration: TimeInterval = 0.08
        let interBeatGap: TimeInterval = 0.12
        let cyclePause: TimeInterval = 0.7

        var events: [CHHapticEvent] = []

        // "Lub" - first beat (softer)
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ],
            relativeTime: 0
        ))

        // "DUB" - second beat (stronger)
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: beatDuration + interBeatGap
        ))

        // Pattern length for looping
        let patternLength = beatDuration + interBeatGap + beatDuration + cyclePause

        return try CHHapticPattern(
            events: events,
            parameterCurves: [],
            duration: patternLength
        )
    }
    #endif
}
