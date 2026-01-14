import SwiftUI

/// Breathing halo effect around the Dynamic Island
/// Creates a subtle glow that indicates Pocket is ready to receive items
struct HaloEffectView: View {
    let isActive: Bool
    let phase: PocketState.InteractionPhase

    @State private var animationPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0

    // MARK: - Configuration

    private var haloColor: Color {
        switch phase {
        case .idle:
            return .clear
        case .anticipation:
            return .white.opacity(0.3)
        case .engagement:
            return .green.opacity(0.5)
        case .listening:
            return .green.opacity(0.6)  // Brighter green while listening
        case .processing:
            return .blue.opacity(0.4)
        case .completion(let success):
            return success ? .green.opacity(0.6) : .red.opacity(0.6)
        }
    }

    private var animationSpeed: Double {
        switch phase {
        case .idle:
            return 0
        case .anticipation:
            return 2.0
        case .engagement:
            return 1.5
        case .listening:
            return 1.2  // Smooth animation while listening
        case .processing:
            return 0.8  // Faster rotation during processing
        case .completion:
            return 0
        }
    }

    var body: some View {
        ZStack {
            // Outer glow layer
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            haloColor,
                            haloColor.opacity(0.5),
                            haloColor.opacity(0.2),
                            haloColor.opacity(0.5),
                            haloColor
                        ]),
                        center: .center,
                        startAngle: .degrees(animationPhase),
                        endAngle: .degrees(animationPhase + 360)
                    ),
                    lineWidth: 3
                )
                .blur(radius: 4)
                .scaleEffect(pulseScale)

            // Inner sharp line
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .stroke(haloColor.opacity(0.8), lineWidth: 1)
                .scaleEffect(pulseScale * 0.98)
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .onAppear {
            startAnimation()
        }
        .onChange(of: phase) { _, _ in
            startAnimation()
        }
    }

    private func startAnimation() {
        guard animationSpeed > 0 else {
            // Stop animation for completion state
            return
        }

        // Rotation animation
        withAnimation(
            .linear(duration: animationSpeed)
            .repeatForever(autoreverses: false)
        ) {
            animationPhase = 360
        }

        // Pulse animation
        withAnimation(
            .easeInOut(duration: animationSpeed / 2)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.03
        }
    }
}

// MARK: - Magnetic Pull Effect

/// Visual effect for the magnetic "pull" when item hovers over drop zone
struct MagneticPullView: View {
    let isActive: Bool
    let strength: CGFloat  // 0 to 1

    @State private var lineOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Converging lines effect
                ForEach(0..<8, id: \.self) { index in
                    magneticLine(index: index, size: geometry.size)
                }
            }
        }
        .opacity(isActive ? Double(strength) : 0)
        .animation(.easeOut(duration: 0.2), value: isActive)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                lineOffset = 1
            }
        }
    }

    private func magneticLine(index: Int, size: CGSize) -> some View {
        let angle = Double(index) * 45.0
        let radians = angle * .pi / 180

        return Path { path in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let startRadius = max(size.width, size.height) * 0.8
            let endRadius: CGFloat = 20

            let currentRadius = startRadius - (startRadius - endRadius) * lineOffset

            let startX = center.x + cos(radians) * startRadius
            let startY = center.y + sin(radians) * startRadius
            let endX = center.x + cos(radians) * currentRadius
            let endY = center.y + sin(radians) * currentRadius

            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
        .stroke(
            LinearGradient(
                colors: [.clear, .white.opacity(0.3)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            lineWidth: 1
        )
    }
}

// MARK: - Preview

#Preview("Halo Effect") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            ForEach([
                PocketState.InteractionPhase.anticipation,
                .engagement,
                .processing("Converting..."),
                .completion(true)
            ], id: \.self) { phase in
                ZStack {
                    HaloEffectView(isActive: true, phase: phase)
                        .frame(width: 150, height: 50)

                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 126, height: 37)
                }
            }
        }
    }
}
