import SwiftUI

/// Central repository for animation configurations
/// Ensures consistent, fluid animations across the app
enum AnimationConstants {

    // MARK: - Spring Animations

    /// Fluid morphing animation for Dynamic Island shape changes
    /// Response: 0.5s for smooth feel, Damping: 0.7 for natural settling
    static let morphing = Animation.spring(response: 0.5, dampingFraction: 0.7)

    /// Quick response for UI element changes
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Snappy for button presses and selections
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.9)

    /// Bouncy for playful elements
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Gentle for subtle state changes
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.85)

    // MARK: - Timing Animations

    /// Standard ease-in-out
    static let standard = Animation.easeInOut(duration: 0.3)

    /// Fast for micro-interactions
    static let fast = Animation.easeInOut(duration: 0.15)

    /// Slow for dramatic effect
    static let slow = Animation.easeInOut(duration: 0.5)

    // MARK: - Repeating Animations

    /// Breathing effect (for halo)
    static func breathing(duration: Double = 1.2) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    /// Continuous rotation (for loading)
    static func rotation(duration: Double = 1.0) -> Animation {
        .linear(duration: duration).repeatForever(autoreverses: false)
    }

    /// Pulsing effect
    static func pulsing(duration: Double = 0.8) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    // MARK: - Transition Presets

    /// Slide up with fade
    static let slideUpFade = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    /// Slide down with fade
    static let slideDownFade = AnyTransition.move(edge: .top).combined(with: .opacity)

    /// Scale with fade
    static let scaleFade = AnyTransition.scale.combined(with: .opacity)

    /// Asymmetric slide (different in/out)
    static let asymmetricSlide = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )

    // MARK: - Duration Constants

    enum Duration {
        static let instant: Double = 0.1
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
        static let verySlow: Double = 0.8
    }

    // MARK: - Delay Constants

    enum Delay {
        static let short: Double = 0.1
        static let medium: Double = 0.3
        static let long: Double = 0.5
    }
}

// MARK: - View Extension for Common Animations

extension View {
    /// Apply morphing animation to any view
    func morphingAnimation() -> some View {
        animation(AnimationConstants.morphing, value: UUID())
    }

    /// Animate with spring when a condition changes
    func animateSpring<V: Equatable>(value: V) -> some View {
        animation(AnimationConstants.morphing, value: value)
    }

    /// Animate entrance with scale and fade
    func animateEntrance(_ isPresented: Bool) -> some View {
        self
            .scaleEffect(isPresented ? 1 : 0.8)
            .opacity(isPresented ? 1 : 0)
            .animation(AnimationConstants.bouncy, value: isPresented)
    }

    /// Add breathing animation
    func breathingAnimation(isActive: Bool) -> some View {
        modifier(BreathingModifier(isActive: isActive))
    }
}

// MARK: - Breathing Modifier

private struct BreathingModifier: ViewModifier {
    let isActive: Bool
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                if isActive {
                    withAnimation(AnimationConstants.breathing()) {
                        scale = 1.05
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    withAnimation(AnimationConstants.breathing()) {
                        scale = 1.05
                    }
                } else {
                    withAnimation(AnimationConstants.quick) {
                        scale = 1.0
                    }
                }
            }
    }
}

// MARK: - Timing Functions

enum TimingFunction {
    /// Deceleration curve - fast start, slow end (for entering elements)
    static let decelerate = Animation.timingCurve(0.0, 0.0, 0.2, 1.0, duration: 0.3)

    /// Acceleration curve - slow start, fast end (for exiting elements)
    static let accelerate = Animation.timingCurve(0.4, 0.0, 1.0, 1.0, duration: 0.3)

    /// Standard curve - balanced acceleration and deceleration
    static let standard = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.3)

    /// Emphasized curve - for important state changes
    static let emphasized = Animation.timingCurve(0.2, 0.0, 0.0, 1.0, duration: 0.5)
}
