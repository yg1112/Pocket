import SwiftUI

/// Toast notification view for displaying completion status
/// Appears at the bottom of the screen after task completion
struct ToastView: View {
    let message: String
    let icon: String
    let isSuccess: Bool

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isSuccess ? .green : .red)
                .symbolEffect(.bounce, value: appeared)

            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            isSuccess ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Detailed Toast

/// Extended toast with more information
struct DetailedToastView: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    let action: (() -> Void)?
    let actionLabel: String?

    @State private var appeared = false

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color = .white,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
        self.actionLabel = actionLabel
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action button
            if let action, let actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Toast Container

/// Container for managing toast presentation
struct ToastContainer<Content: View>: View {
    @Binding var isPresented: Bool
    let duration: TimeInterval
    let content: () -> Content

    @State private var workItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            if isPresented {
                VStack {
                    Spacer()

                    content()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 100)
                        .padding(.horizontal, 24)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
            }
        }
        .onChange(of: isPresented) { _, newValue in
            if newValue {
                scheduleHide()
            }
        }
    }

    private func scheduleHide() {
        workItem?.cancel()

        let task = DispatchWorkItem {
            withAnimation {
                isPresented = false
            }
        }
        workItem = task

        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
}

// MARK: - View Extension

extension View {
    func toast<Content: View>(
        isPresented: Binding<Bool>,
        duration: TimeInterval = 3.0,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ZStack {
            self
            ToastContainer(isPresented: isPresented, duration: duration, content: content)
        }
    }
}

// MARK: - Preview

#Preview("Toast Views") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 24) {
            ToastView(
                message: "Done",
                icon: "checkmark.circle.fill",
                isSuccess: true
            )

            ToastView(
                message: "Failed",
                icon: "xmark.circle.fill",
                isSuccess: false
            )

            DetailedToastView(
                title: "File Converted",
                subtitle: "document.pdf (2.4 MB)",
                icon: "arrow.triangle.2.circlepath",
                iconColor: .blue,
                action: {},
                actionLabel: "Open"
            )

            DetailedToastView(
                title: "Sent to John",
                subtitle: "via iMessage",
                icon: "paperplane.fill",
                iconColor: .green
            )
        }
        .padding()
    }
}
