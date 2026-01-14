import SwiftUI

/// Visual representation of a PocketItem
/// Used in the held items grid and drag previews
struct PocketItemView: View {
    let item: PocketItem

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 6) {
            // Item visual
            itemVisual
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)

            // Item name
            Text(displayName)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    @ViewBuilder
    private var itemVisual: some View {
        switch item.type {
        case .image:
            imagePreview

        case .document:
            documentPreview

        case .link:
            linkPreview

        case .text:
            textPreview

        case .video:
            videoPreview

        case .audio:
            audioPreview
        }
    }

    // MARK: - Type-specific Previews

    private var imagePreview: some View {
        Group {
            if let thumbnail = item.thumbnail {
                thumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallbackIcon
            }
        }
    }

    private var documentPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)

                // File extension badge
                if let ext = fileExtension {
                    Text(ext.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange)
                        )
                }
            }
        }
    }

    private var linkPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.3), Color.green.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 24))
                    .foregroundColor(.green)

                // Domain preview
                if let domain = extractDomain() {
                    Text(domain)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    private var textPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.3), Color.purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 2) {
                // Preview first few lines
                if let preview = textPreviewContent {
                    Text(preview)
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(4)
                        .padding(4)
                } else {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24))
                        .foregroundColor(.purple)
                }
            }
        }
    }

    private var videoPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.3), Color.red.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.red)
        }
    }

    private var audioPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.3), Color.pink.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundColor(.pink)
        }
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))

            Image(systemName: item.type.icon)
                .font(.system(size: 24))
                .foregroundColor(item.type.color)
        }
    }

    // MARK: - Helper Methods

    /// Display name - shows actual filename or type description
    private var displayName: String {
        let name = item.name
        // If name is generic "File" or empty, show type-based name
        if name == "File" || name.isEmpty {
            return item.type.rawValue.capitalized
        }
        return name
    }

    private var fileExtension: String? {
        let components = item.name.split(separator: ".")
        guard components.count > 1 else { return nil }
        return String(components.last ?? "")
    }

    private func extractDomain() -> String? {
        guard let urlString = String(data: item.data, encoding: .utf8),
              let url = URL(string: urlString) else {
            return nil
        }
        return url.host?.replacingOccurrences(of: "www.", with: "")
    }

    private var textPreviewContent: String? {
        guard let text = String(data: item.data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return String(text.prefix(100))
    }
}

// MARK: - Compact Item View

/// Smaller version for inline display
struct CompactPocketItemView: View {
    let item: PocketItem

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            ZStack {
                Circle()
                    .fill(item.type.color.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: item.type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(item.type.color)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(item.sizeString)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Preview

#Preview("Pocket Items") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            HStack(spacing: 16) {
                PocketItemView(item: PocketItem(
                    id: UUID(),
                    type: .image,
                    data: Data(),
                    name: "photo.jpg",
                    timestamp: Date()
                ))

                PocketItemView(item: PocketItem(
                    id: UUID(),
                    type: .document,
                    data: Data(),
                    name: "report.pdf",
                    timestamp: Date()
                ))

                PocketItemView(item: PocketItem(
                    id: UUID(),
                    type: .link,
                    data: "https://apple.com".data(using: .utf8)!,
                    name: "Apple",
                    timestamp: Date()
                ))
            }

            CompactPocketItemView(item: PocketItem(
                id: UUID(),
                type: .document,
                data: Data(count: 2400000),
                name: "quarterly_report.pdf",
                timestamp: Date()
            ))
            .frame(width: 200)
        }
        .padding()
    }
}
