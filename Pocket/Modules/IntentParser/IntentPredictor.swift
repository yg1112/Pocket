import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Predicts user intent based on file type before voice command
/// Provides quick action suggestions that appear during drag
@MainActor
final class IntentPredictor: ObservableObject {

    // MARK: - Published Properties

    /// Predicted actions for the current drag operation
    @Published var predictions: [PredictedAction] = []

    /// Whether predictions are currently shown
    @Published var isShowingPredictions: Bool = false

    // MARK: - Prediction Generation

    /// Generate predictions based on UTType
    func predict(for types: [UTType]) {
        let primaryType = types.first ?? .data

        var actions: [PredictedAction] = []

        // Always offer Hold as first option
        actions.append(PredictedAction(
            action: .hold,
            icon: "tray.and.arrow.down.fill",
            label: "Hold",
            confidence: 1.0,
            color: .gray
        ))

        // Type-specific predictions
        if types.contains(where: { $0.conforms(to: .image) }) {
            actions.append(contentsOf: imageActions)
        } else if types.contains(where: { $0.conforms(to: .pdf) }) {
            actions.append(contentsOf: pdfActions)
        } else if types.contains(where: { $0.conforms(to: .text) || $0.conforms(to: .sourceCode) }) {
            actions.append(contentsOf: textActions)
        } else if types.contains(where: { $0.conforms(to: .url) }) {
            actions.append(contentsOf: urlActions)
        } else if types.contains(where: { $0.conforms(to: .audio) }) {
            actions.append(contentsOf: audioActions)
        } else {
            // Generic document actions
            actions.append(contentsOf: documentActions)
        }

        // Limit to 4 predictions (including Hold)
        predictions = Array(actions.prefix(4))
    }

    /// Generate predictions based on PocketItem type
    func predict(for itemType: PocketItem.ItemType) {
        var actions: [PredictedAction] = []

        // Always offer Hold
        actions.append(PredictedAction(
            action: .hold,
            icon: "tray.and.arrow.down.fill",
            label: "Hold",
            confidence: 1.0,
            color: .gray
        ))

        switch itemType {
        case .image:
            actions.append(contentsOf: imageActions)
        case .document:
            actions.append(contentsOf: documentActions)
        case .text:
            actions.append(contentsOf: textActions)
        case .link:
            actions.append(contentsOf: urlActions)
        case .audio:
            actions.append(contentsOf: audioActions)
        case .video:
            actions.append(contentsOf: videoActions)
        }

        predictions = Array(actions.prefix(4))
    }

    /// Clear predictions
    func clearPredictions() {
        withAnimation(.easeOut(duration: 0.2)) {
            predictions = []
            isShowingPredictions = false
        }
    }

    /// Show predictions with animation
    func showPredictions() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isShowingPredictions = true
        }
    }

    // MARK: - Type-Specific Actions

    private var imageActions: [PredictedAction] {
        [
            PredictedAction(
                action: .extract(operation: .extractText),
                icon: "doc.text.viewfinder",
                label: "OCR",
                confidence: 0.9,
                color: .blue
            ),
            PredictedAction(
                action: .convert(format: "pdf"),
                icon: "doc.fill",
                label: "PDF",
                confidence: 0.8,
                color: .red
            ),
            PredictedAction(
                action: .send(target: ""),
                icon: "paperplane.fill",
                label: "Send",
                confidence: 0.7,
                color: .green
            )
        ]
    }

    private var pdfActions: [PredictedAction] {
        [
            PredictedAction(
                action: .extract(operation: .summarize),
                icon: "text.alignleft",
                label: "Summary",
                confidence: 0.9,
                color: .purple
            ),
            PredictedAction(
                action: .print(copies: 1, options: .default),
                icon: "printer.fill",
                label: "Print",
                confidence: 0.85,
                color: .orange
            ),
            PredictedAction(
                action: .send(target: ""),
                icon: "paperplane.fill",
                label: "Send",
                confidence: 0.7,
                color: .green
            )
        ]
    }

    private var textActions: [PredictedAction] {
        [
            PredictedAction(
                action: .extract(operation: .summarize),
                icon: "text.alignleft",
                label: "Summary",
                confidence: 0.9,
                color: .purple
            ),
            PredictedAction(
                action: .convert(format: "pdf"),
                icon: "doc.fill",
                label: "PDF",
                confidence: 0.8,
                color: .red
            ),
            PredictedAction(
                action: .extract(operation: .translate(to: "English")),
                icon: "globe",
                label: "Translate",
                confidence: 0.75,
                color: .cyan
            )
        ]
    }

    private var urlActions: [PredictedAction] {
        [
            PredictedAction(
                action: .send(target: "Mac"),
                icon: "desktopcomputer",
                label: "To Mac",
                confidence: 0.85,
                color: .blue
            ),
            PredictedAction(
                action: .convert(format: "pdf"),
                icon: "doc.fill",
                label: "Save PDF",
                confidence: 0.7,
                color: .red
            ),
            PredictedAction(
                action: .send(target: ""),
                icon: "paperplane.fill",
                label: "Share",
                confidence: 0.65,
                color: .green
            )
        ]
    }

    private var audioActions: [PredictedAction] {
        [
            PredictedAction(
                action: .extract(operation: .transcribe),
                icon: "waveform",
                label: "Transcribe",
                confidence: 0.95,
                color: .purple
            ),
            PredictedAction(
                action: .send(target: ""),
                icon: "paperplane.fill",
                label: "Send",
                confidence: 0.7,
                color: .green
            ),
            PredictedAction(
                action: .airplay(device: ""),
                icon: "airplayaudio",
                label: "AirPlay",
                confidence: 0.6,
                color: .blue
            )
        ]
    }

    private var videoActions: [PredictedAction] {
        [
            PredictedAction(
                action: .airplay(device: "TV"),
                icon: "tv.fill",
                label: "AirPlay",
                confidence: 0.9,
                color: .blue
            ),
            PredictedAction(
                action: .send(target: ""),
                icon: "paperplane.fill",
                label: "Send",
                confidence: 0.7,
                color: .green
            ),
            PredictedAction(
                action: .convert(format: "gif"),
                icon: "photo.on.rectangle",
                label: "GIF",
                confidence: 0.5,
                color: .pink
            )
        ]
    }

    private var documentActions: [PredictedAction] {
        [
            PredictedAction(
                action: .extract(operation: .summarize),
                icon: "text.alignleft",
                label: "Summary",
                confidence: 0.85,
                color: .purple
            ),
            PredictedAction(
                action: .convert(format: "pdf"),
                icon: "doc.fill",
                label: "PDF",
                confidence: 0.8,
                color: .red
            ),
            PredictedAction(
                action: .print(copies: 1, options: .default),
                icon: "printer.fill",
                label: "Print",
                confidence: 0.7,
                color: .orange
            )
        ]
    }
}

// MARK: - Predicted Action Model

struct PredictedAction: Identifiable, Equatable {
    let id = UUID()
    let action: Action
    let icon: String
    let label: String
    let confidence: Double  // 0.0 - 1.0
    let color: SwiftUI.Color

    static func == (lhs: PredictedAction, rhs: PredictedAction) -> Bool {
        lhs.id == rhs.id
    }
}
