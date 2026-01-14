import SwiftUI

/// Animated voice waveform visualization
/// Displays when microphone is active during engagement phase
struct VoiceWaveformView: View {
    let isActive: Bool

    @State private var animationPhases: [CGFloat] = Array(repeating: 0, count: 7)

    private let barCount = 7
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 16
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                waveformBar(index: index)
            }
        }
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    private func waveformBar(index: Int) -> some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(
                LinearGradient(
                    colors: [.green, .green.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(
                width: barWidth,
                height: isActive ? barHeight(for: index) : minHeight
            )
            .animation(
                .easeInOut(duration: animationDuration(for: index))
                .repeatForever(autoreverses: true),
                value: animationPhases[index]
            )
    }

    private func barHeight(for index: Int) -> CGFloat {
        let phase = animationPhases[index]
        let baseHeight = minHeight + (maxHeight - minHeight) * phase

        // Add some variation based on bar position (center bars taller)
        let centerIndex = CGFloat(barCount - 1) / 2
        let distanceFromCenter = abs(CGFloat(index) - centerIndex)
        let centerMultiplier = 1.0 - (distanceFromCenter / centerIndex) * 0.3

        return baseHeight * centerMultiplier
    }

    private func animationDuration(for index: Int) -> Double {
        // Slightly different durations for organic feel
        let baseDuration = 0.3
        let variation = Double(index % 3) * 0.1
        return baseDuration + variation
    }

    private func startAnimation() {
        for index in 0..<barCount {
            let delay = Double(index) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                animationPhases[index] = 1.0
            }
        }
    }

    private func stopAnimation() {
        for index in 0..<barCount {
            animationPhases[index] = 0
        }
    }
}

// MARK: - Audio Level Waveform

/// More sophisticated waveform that responds to actual audio levels
struct AudioLevelWaveformView: View {
    @Binding var audioLevel: Float  // 0.0 to 1.0

    private let barCount = 12
    private let barWidth: CGFloat = 2
    private let maxHeight: CGFloat = 24
    private let minHeight: CGFloat = 2

    @State private var barHeights: [CGFloat] = []

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                audioBar(index: index)
            }
        }
        .onAppear {
            barHeights = Array(repeating: minHeight, count: barCount)
        }
        .onChange(of: audioLevel) { _, newLevel in
            updateBars(level: CGFloat(newLevel))
        }
    }

    private func audioBar(index: Int) -> some View {
        let height = index < barHeights.count ? barHeights[index] : minHeight

        return RoundedRectangle(cornerRadius: 1)
            .fill(barColor(for: height))
            .frame(width: barWidth, height: height)
            .animation(.easeOut(duration: 0.08), value: height)
    }

    private func barColor(for height: CGFloat) -> Color {
        let normalizedHeight = (height - minHeight) / (maxHeight - minHeight)

        if normalizedHeight > 0.8 {
            return .red
        } else if normalizedHeight > 0.6 {
            return .yellow
        } else {
            return .green
        }
    }

    private func updateBars(level: CGFloat) {
        // Create a natural-looking distribution based on audio level
        var newHeights: [CGFloat] = []

        for i in 0..<barCount {
            let centerIndex = CGFloat(barCount - 1) / 2
            let distanceFromCenter = abs(CGFloat(i) - centerIndex) / centerIndex

            // Bars near center are taller
            let centerWeight = 1.0 - distanceFromCenter * 0.5

            // Add randomness
            let randomFactor = CGFloat.random(in: 0.7...1.3)

            let height = minHeight + (maxHeight - minHeight) * level * centerWeight * randomFactor
            newHeights.append(min(maxHeight, max(minHeight, height)))
        }

        barHeights = newHeights
    }
}

// MARK: - Preview

#Preview("Voice Waveforms") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            VStack {
                Text("Simple Waveform")
                    .foregroundColor(.white.opacity(0.6))
                VoiceWaveformView(isActive: true)
                    .frame(height: 24)
            }

            VStack {
                Text("Inactive")
                    .foregroundColor(.white.opacity(0.6))
                VoiceWaveformView(isActive: false)
                    .frame(height: 24)
            }

            VStack {
                Text("Audio Level Waveform")
                    .foregroundColor(.white.opacity(0.6))
                AudioLevelWaveformView(audioLevel: .constant(0.6))
                    .frame(height: 24)
            }
        }
        .padding()
    }
}
