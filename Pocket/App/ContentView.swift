import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Main content view of Pocket
/// Displays the Dynamic Island interface and handles global drag detection
struct ContentView: View {
    @EnvironmentObject var pocketState: PocketState
    @EnvironmentObject var dropZoneManager: DropZoneManager
    @EnvironmentObject var voiceIntentManager: VoiceIntentManager

    @State private var showingSettings = false
    @State private var selectedItem: PocketItem?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundView

                // Main content area (placeholder for demo)
                mainContentArea

                // Dynamic Island overlay - always on top
                VStack {
                    DynamicIslandView()
                        .padding(.top, geometry.safeAreaInsets.top)
                    Spacer()
                }
                .ignoresSafeArea()

                // Toast notification overlay
                if case .completion(let success) = pocketState.currentPhase {
                    toastOverlay(success: success)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var backgroundView: some View {
        Color.black
            .ignoresSafeArea()
            .overlay(
                // Subtle gradient for depth
                LinearGradient(
                    colors: [
                        Color(white: 0.05),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var mainContentArea: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 120) // Space for Dynamic Island

            // Welcome message
            welcomeSection

            // Held items grid
            if !pocketState.heldItems.isEmpty {
                heldItemsSection
            }

            Spacer()

            // Demo drag sources (for testing)
            demoDragSources

            // Settings button
            settingsButton
        }
        .padding()
    }

    private var welcomeSection: some View {
        VStack(spacing: 12) {
            Text("Pocket")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Drag anything to the island.\nSpeak your intent.")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    private var heldItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In Your Pocket")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 12)
            ], spacing: 12) {
                ForEach(pocketState.heldItems) { item in
                    PocketItemView(item: item)
                        .onTapGesture {
                            selectedItem = item
                        }
                        .draggable(item.transferable) {
                            PocketItemView(item: item)
                                .frame(width: 60, height: 60)
                        }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        )
        .sheet(item: $selectedItem) { item in
            ItemPreviewView(item: item, pocketState: pocketState)
        }
    }

    private var demoDragSources: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try Dragging")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 16) {
                DemoDragItem(icon: "photo", label: "Photo", type: .image)
                DemoDragItem(icon: "doc.fill", label: "Document", type: .document)
                DemoDragItem(icon: "link", label: "Link", type: .link)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            HStack {
                Image(systemName: "gearshape.fill")
                Text("Settings")
            }
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func toastOverlay(success: Bool) -> some View {
        VStack {
            Spacer()

            ToastView(
                message: success ? "Done" : "Failed",
                icon: success ? "checkmark.circle.fill" : "xmark.circle.fill",
                isSuccess: success
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 100)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pocketState.currentPhase)
    }
}

// MARK: - Demo Drag Item

struct DemoDragItem: View {
    let icon: String
    let label: String
    let type: PocketItem.ItemType

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.8))
            }

            Text(label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .draggable(createDraggableContent()) {
            // Drag preview
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
        }
    }

    private func createDraggableContent() -> String {
        // Return actual content based on type
        switch type {
        case .image:
            return "Demo Image Content - This is a sample image item from Pocket"
        case .document:
            return "Demo Document Content - This is a sample document item from Pocket"
        case .link:
            return "https://example.com/pocket-demo"
        case .text:
            return "Demo Text Content - This is a sample text item from Pocket"
        case .video:
            return "Demo Video Content - This is a sample video item from Pocket"
        case .audio:
            return "Demo Audio Content - This is a sample audio item from Pocket"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("groqApiKey") private var groqApiKey = ""
    @AppStorage("preferredVoiceLanguage") private var voiceLanguage = "en-US"

    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
                    SecureField("Groq API Key", text: $groqApiKey)
                        .textContentType(.password)
                }

                Section("Voice") {
                    Picker("Language", selection: $voiceLanguage) {
                        Text("English (US)").tag("en-US")
                        Text("Chinese (Simplified)").tag("zh-CN")
                        Text("Japanese").tag("ja-JP")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Item Preview View

struct ItemPreviewView: View {
    let item: PocketItem
    let pocketState: PocketState
    @Environment(\.dismiss) private var dismiss

    @State private var processedContent: String?
    @State private var isProcessing = false
    @State private var selectedOperation: String?

    private let groqService = GroqService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with item info
                    itemHeader

                    // Action buttons for text content
                    if item.type == .text || item.type == .document {
                        actionButtons
                    }

                    Divider()
                        .background(Color.white.opacity(0.2))

                    // Processed content (if any)
                    if let processed = processedContent {
                        processedContentView(processed)
                    }

                    // Original content preview
                    contentPreview
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle(item.name == "File" ? "Preview" : item.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var itemHeader: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                Circle()
                    .fill(item.type.color.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: item.type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(item.type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Text(item.type.rawValue.capitalized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(item.type.color)

                    Text("•")
                        .foregroundColor(.white.opacity(0.3))

                    Text(item.sizeString)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 12) {
                ActionButton(
                    title: "Summarize",
                    icon: "text.alignleft",
                    color: .blue,
                    isLoading: isProcessing && selectedOperation == "summarize"
                ) {
                    Task { await processContent(operation: "summarize") }
                }

                ActionButton(
                    title: "Explain",
                    icon: "lightbulb",
                    color: .yellow,
                    isLoading: isProcessing && selectedOperation == "explain"
                ) {
                    Task { await processContent(operation: "explain") }
                }

                ActionButton(
                    title: "Translate",
                    icon: "globe",
                    color: .green,
                    isLoading: isProcessing && selectedOperation == "translate"
                ) {
                    Task { await processContent(operation: "translate") }
                }
            }
        }
    }

    private func processContent(operation: String) async {
        guard let content = String(data: item.data, encoding: .utf8) else { return }

        isProcessing = true
        selectedOperation = operation

        let prompt: String
        switch operation {
        case "summarize":
            prompt = """
            Please summarize this content concisely in 2-3 sentences. If it's code or config, explain what it does:

            \(content)
            """
        case "explain":
            prompt = """
            Please explain this content in simple terms. What is it? What does it do? Who would use it?

            \(content)
            """
        case "translate":
            prompt = """
            Please translate this content to Chinese (中文). Keep the format if it's code/config:

            \(content)
            """
        default:
            prompt = "Summarize: \(content)"
        }

        do {
            let result = try await groqService.complete(prompt: prompt)
            await MainActor.run {
                processedContent = result
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                processedContent = "Error: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }

    private func processedContentView(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Analysis")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.purple)
            }

            Text(content)
                .font(.system(.body, design: .rounded))
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                        )
                )
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text, .document:
            textContentView

        case .image:
            imageContentView

        case .link:
            linkContentView

        case .video, .audio:
            mediaPlaceholderView
        }
    }

    private var textContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Original Content")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            if let content = String(data: item.data, encoding: .utf8) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                    .textSelection(.enabled)
            } else {
                Text("Unable to display content")
                    .foregroundColor(.white.opacity(0.5))
                    .italic()
            }
        }
    }

    private var imageContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image Preview")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            if let thumbnail = item.thumbnail {
                thumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                #if os(macOS)
                if let nsImage = NSImage(data: item.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                #else
                if let uiImage = UIImage(data: item.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                #endif
            }
        }
    }

    private var linkContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            if let urlString = String(data: item.data, encoding: .utf8) {
                Link(destination: URL(string: urlString) ?? URL(string: "https://example.com")!) {
                    HStack {
                        Image(systemName: "link")
                        Text(urlString)
                            .lineLimit(2)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                }
                .foregroundColor(.green)
            }
        }
    }

    private var mediaPlaceholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: item.type == .video ? "play.circle" : "waveform")
                .font(.system(size: 48))
                .foregroundColor(item.type.color.opacity(0.5))

            Text("Preview not available")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(color)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }

                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
            )
        }
        .disabled(isLoading)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(PocketState())
        .environmentObject(DropZoneManager())
        .environmentObject(VoiceIntentManager())
}
