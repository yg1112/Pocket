import AVFoundation

#if os(macOS)
import AppKit
#endif

/// Manages audio for Pocket
/// Handles sound effects for UI feedback
@MainActor
final class AudioManager {

    static let shared = AudioManager()

    private var audioPlayers: [SoundEffect: AVAudioPlayer] = [:]
    private var isMuted: Bool = false

    enum SoundEffect: String, CaseIterable {
        case micActivate = "mic_activate"
        case drop = "drop"
        case success = "success"
        case error = "error"
        case processing = "processing"

        var fileName: String { rawValue }
        var fileExtension: String { "wav" }
    }

    private init() {
        preloadSounds()
    }

    private func preloadSounds() {
        for effect in SoundEffect.allCases {
            if let player = createPlayer(for: effect) {
                audioPlayers[effect] = player
            }
        }
    }

    private func createPlayer(for effect: SoundEffect) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(
            forResource: effect.fileName,
            withExtension: effect.fileExtension
        ) else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.volume = 0.5
            return player
        } catch {
            print("Failed to create audio player: \(error)")
            return nil
        }
    }

    func play(_ effect: SoundEffect) {
        guard !isMuted else { return }

        if let player = audioPlayers[effect] {
            player.currentTime = 0
            player.play()
        } else {
            // Fallback to system sounds on macOS
            #if os(macOS)
            NSSound.beep()
            #endif
        }
    }

    func playMicActivate() { play(.micActivate) }
    func playDrop() { play(.drop) }
    func playSuccess() { play(.success) }
    func playError() { play(.error) }

    func mute() { isMuted = true }
    func unmute() { isMuted = false }
    func toggleMute() { isMuted.toggle() }

    func setVolume(_ volume: Float) {
        let clampedVolume = max(0, min(1, volume))
        for player in audioPlayers.values {
            player.volume = clampedVolume
        }
    }
}
