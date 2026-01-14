import SwiftUI
import UniformTypeIdentifiers

/// Displays prediction bubbles around the Dynamic Island during drag
/// Users can drop directly onto a bubble to execute that action instantly
struct PredictionBubblesView: View {

    // MARK: - Properties

    @ObservedObject var predictor: IntentPredictor

    /// Called when user drops on a specific prediction bubble
    let onPredictionSelected: (PredictedAction) -> Void

    /// Whether bubbles should be visible
    let isVisible: Bool

    // MARK: - State

    @State private var hoveredPrediction: PredictedAction?
    @State private var bubbleScales: [UUID: CGFloat] = [:]

    // MARK: - Layout

    private let bubbleSize: CGFloat = 56
    private let bubbleSpacing: CGFloat = 70
    private let verticalOffset: CGFloat = 60

    // MARK: - Body

    var body: some View {
        ZStack {
            ForEach(Array(predictor.predictions.enumerated()), id: \.element.id) { index, prediction in
                predictionBubble(prediction, at: index)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: predictor.predictions.map(\.id))
    }

    // MARK: - Bubble View

    @ViewBuilder
    private func predictionBubble(_ prediction: PredictedAction, at index: Int) -> some View {
        let position = bubblePosition(for: index, total: predictor.predictions.count)
        let isHovered = hoveredPrediction?.id == prediction.id
        let scale = bubbleScales[prediction.id] ?? 1.0

        VStack(spacing: 6) {
            // Bubble
            ZStack {
                // Glow effect
                Circle()
                    .fill(prediction.color.opacity(0.3))
                    .frame(width: bubbleSize + 10, height: bubbleSize + 10)
                    .blur(radius: 10)
                    .opacity(isHovered ? 1 : 0)

                // Main bubble
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                prediction.color.opacity(0.9),
                                prediction.color.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: bubbleSize, height: bubbleSize)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: prediction.color.opacity(0.5), radius: isHovered ? 15 : 5)

                // Icon
                Image(systemName: prediction.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(scale * (isHovered ? 1.15 : 1.0))

            // Label
            Text(prediction.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .opacity(isVisible ? 1 : 0)
        }
        .offset(x: position.x, y: position.y)
        .contentShape(Circle().size(CGSize(width: bubbleSize + 20, height: bubbleSize + 20)))
        .onDrop(of: [.fileURL, .url, .image, .plainText, .data], isTargeted: Binding(
            get: { hoveredPrediction?.id == prediction.id },
            set: { isTargeted in
                withAnimation(.spring(response: 0.2)) {
                    hoveredPrediction = isTargeted ? prediction : nil
                }
            }
        )) { providers in
            onPredictionSelected(prediction)
            return true
        }
        .onAppear {
            // Staggered entrance animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double(index) * 0.05)) {
                bubbleScales[prediction.id] = 1.0
            }
        }
        .onDisappear {
            bubbleScales[prediction.id] = 0.5
        }
    }

    // MARK: - Layout Calculation

    /// Calculate bubble position in a semi-circle below the island
    private func bubblePosition(for index: Int, total: Int) -> CGPoint {
        guard total > 0 else { return .zero }

        // Spread bubbles in a semi-circle
        let angleRange: CGFloat = .pi * 0.6  // 108 degrees spread
        let startAngle: CGFloat = .pi + (.pi - angleRange) / 2  // Center the spread

        let angleStep = total > 1 ? angleRange / CGFloat(total - 1) : 0
        let angle = startAngle + angleStep * CGFloat(index)

        let radius = bubbleSpacing + CGFloat(total) * 5

        return CGPoint(
            x: cos(angle) * radius,
            y: sin(angle) * radius + verticalOffset
        )
    }
}

// MARK: - Animated Bubble

/// A single animated prediction bubble with entrance animation
struct AnimatedPredictionBubble: View {

    let prediction: PredictedAction
    let delay: Double
    let onTap: () -> Void

    @State private var isVisible = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(prediction.color.gradient)
                        .frame(width: 50, height: 50)

                    Image(systemName: prediction.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .shadow(color: prediction.color.opacity(0.5), radius: 8)

                Text(prediction.label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isVisible ? 1 : 0.3)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(delay)) {
                isVisible = true
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Preview

#Preview("Prediction Bubbles") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            // Mock island
            RoundedRectangle(cornerRadius: 44)
                .fill(Color.black)
                .frame(width: 200, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 44)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )

            Spacer().frame(height: 20)

            // Predictions
            PredictionBubblesView(
                predictor: {
                    let p = IntentPredictor()
                    p.predict(for: .image)
                    return p
                }(),
                onPredictionSelected: { prediction in
                    print("Selected: \(prediction.label)")
                },
                isVisible: true
            )
        }
        .padding(.top, 100)
    }
}
