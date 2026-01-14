import SwiftUI
import UniformTypeIdentifiers
import Combine

/// Manages the drop zone functionality for Pocket
/// Handles drag detection, hover states, and drop processing
@MainActor
final class DropZoneManager: ObservableObject {

    // MARK: - Published Properties

    /// Whether an item is currently being dragged anywhere in the app
    @Published var isDragging = false

    /// Whether an item is hovering over the drop zone
    @Published var isHovering = false

    /// The proximity of the dragged item to the drop zone (0 to 1)
    @Published var hoverProximity: CGFloat = 0

    /// Current item being dragged (if detectable)
    @Published var currentDragItem: DragItem?

    /// Drop zone frame in global coordinates
    @Published var dropZoneFrame: CGRect = .zero

    // 2.0: For intent prediction
    /// Last detected item type during drag
    @Published var lastDetectedType: PocketItem.ItemType?

    /// Cache of last processed items for prediction execution
    private var lastProcessedItems: [PocketItem] = []

    // MARK: - Configuration

    /// Supported drop types
    let supportedTypes: [UTType] = [
        .image,
        .jpeg,
        .png,
        .heic,
        .gif,
        .pdf,
        .plainText,
        .rtf,
        .url,
        .fileURL,
        .movie,
        .video,
        .audio,
        .data
    ]

    /// Magnetic attraction radius (how close items snap to drop zone)
    let magneticRadius: CGFloat = 100

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Monitor hover state changes for haptic feedback
        $isHovering
            .removeDuplicates()
            .sink { [weak self] hovering in
                if hovering {
                    self?.onHoverEnter()
                } else {
                    self?.onHoverExit()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Update the drop zone frame (called from DynamicIslandView)
    func updateDropZoneFrame(_ frame: CGRect) {
        dropZoneFrame = frame
    }

    /// Called when drag starts in the app
    func onDragStart() {
        isDragging = true
    }

    /// Called when drag ends
    func onDragEnd() {
        isDragging = false
        isHovering = false
        hoverProximity = 0
        currentDragItem = nil
        lastDetectedType = nil
    }

    // 2.0: Get cached items for prediction execution
    func getLastProcessedItems() async -> [PocketItem] {
        return lastProcessedItems
    }

    /// Detect item type from providers (for prediction before drop)
    func detectType(from providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                lastDetectedType = .image
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                lastDetectedType = .document
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                lastDetectedType = .link
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                lastDetectedType = .audio
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
               provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) {
                lastDetectedType = .video
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                lastDetectedType = .text
                return
            }
        }
        lastDetectedType = .document  // Default
    }

    /// Calculate hover proximity based on drag location
    func updateProximity(dragLocation: CGPoint) {
        guard !dropZoneFrame.isEmpty else { return }

        let center = CGPoint(
            x: dropZoneFrame.midX,
            y: dropZoneFrame.midY
        )

        let distance = sqrt(
            pow(dragLocation.x - center.x, 2) +
            pow(dragLocation.y - center.y, 2)
        )

        // Calculate proximity (1 = at center, 0 = outside magnetic radius)
        let normalizedDistance = min(distance / magneticRadius, 1)
        hoverProximity = 1 - normalizedDistance

        // Update hover state
        isHovering = dropZoneFrame.insetBy(dx: -20, dy: -20).contains(dragLocation)
    }

    /// Process incoming drop data
    func processDropData(_ providers: [NSItemProvider]) async -> [PocketItem] {
        print("🔄 [DropZoneManager] processDropData called with \(providers.count) providers")

        // 2.0: Detect type first for predictions
        detectType(from: providers)

        var items: [PocketItem] = []

        for (index, provider) in providers.enumerated() {
            print("🔄 [DropZoneManager] Processing provider \(index)...")
            print("🔄 [DropZoneManager] Registered types: \(provider.registeredTypeIdentifiers)")
            if let item = await loadItem(from: provider) {
                print("🔄 [DropZoneManager] Successfully loaded item: \(item.name)")
                items.append(item)
            } else {
                print("🔄 [DropZoneManager] Failed to load item from provider \(index)")
            }
        }

        // 2.0: Cache items for prediction execution
        lastProcessedItems = items

        print("🔄 [DropZoneManager] Total items loaded: \(items.count)")
        return items
    }

    // MARK: - Private Methods

    private func onHoverEnter() {
        // Trigger haptic feedback via HapticsManager
        // This is handled by PocketState
    }

    private func onHoverExit() {
        // Clear proximity
        hoverProximity = 0
    }

    private func loadItem(from provider: NSItemProvider) async -> PocketItem? {
        print("🔍 [DropZoneManager] loadItem - checking provider types...")

        // Try loading as file URL first (most common for Finder drops)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            print("🔍 [DropZoneManager] Trying to load as fileURL...")
            if let item = await loadFileURL(from: provider) {
                return item
            }
        }

        // Try loading as image
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            print("🔍 [DropZoneManager] Trying to load as image...")
            if let item = await loadImage(from: provider) {
                return item
            }
        }

        // Try loading as URL
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            print("🔍 [DropZoneManager] Trying to load as URL...")
            if let item = await loadURL(from: provider) {
                return item
            }
        }

        // Try loading as plain text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            print("🔍 [DropZoneManager] Trying to load as plainText...")
            if let item = await loadText(from: provider) {
                return item
            }
        }

        // Try loading as data
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            print("🔍 [DropZoneManager] Trying to load as data...")
            if let item = await loadData(from: provider) {
                return item
            }
        }

        print("🔍 [DropZoneManager] No matching type found")
        return nil
    }

    private func loadImage(from provider: NSItemProvider) async -> PocketItem? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                guard let data = data else {
                    continuation.resume(returning: nil)
                    return
                }

                let item = PocketItem(
                    id: UUID(),
                    type: .image,
                    data: data,
                    name: provider.suggestedName ?? "Image",
                    timestamp: Date()
                )
                continuation.resume(returning: item)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> PocketItem? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url = url else {
                    continuation.resume(returning: nil)
                    return
                }

                let item = PocketItem.fromURL(url)
                continuation.resume(returning: item)
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> PocketItem? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                if let error = error {
                    print("🔍 [DropZoneManager] loadFileURL error: \(error)")
                }

                guard let data = data else {
                    print("🔍 [DropZoneManager] loadFileURL - no data received")
                    continuation.resume(returning: nil)
                    return
                }

                guard let urlString = String(data: data, encoding: .utf8) else {
                    print("🔍 [DropZoneManager] loadFileURL - cannot decode URL string")
                    continuation.resume(returning: nil)
                    return
                }

                print("🔍 [DropZoneManager] loadFileURL - URL string: \(urlString)")

                guard let url = URL(string: urlString) else {
                    print("🔍 [DropZoneManager] loadFileURL - invalid URL")
                    continuation.resume(returning: nil)
                    return
                }

                print("🔍 [DropZoneManager] loadFileURL - URL: \(url)")

                // Determine type from file extension
                let itemType = self.itemType(for: url)
                print("🔍 [DropZoneManager] loadFileURL - itemType: \(itemType)")

                // Load file data
                do {
                    let fileData = try Data(contentsOf: url)
                    print("🔍 [DropZoneManager] loadFileURL - loaded \(fileData.count) bytes")

                    let item = PocketItem(
                        id: UUID(),
                        type: itemType,
                        data: fileData,
                        name: url.lastPathComponent,
                        timestamp: Date()
                    )
                    continuation.resume(returning: item)
                } catch {
                    print("🔍 [DropZoneManager] loadFileURL - failed to read file: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> PocketItem? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, error in
                guard let text = text else {
                    continuation.resume(returning: nil)
                    return
                }

                let item = PocketItem.fromText(text)
                continuation.resume(returning: item)
            }
        }
    }

    private func loadData(from provider: NSItemProvider) async -> PocketItem? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, error in
                guard let data = data else {
                    continuation.resume(returning: nil)
                    return
                }

                let item = PocketItem(
                    id: UUID(),
                    type: .document,
                    data: data,
                    name: provider.suggestedName ?? "File",
                    timestamp: Date()
                )
                continuation.resume(returning: item)
            }
        }
    }

    private func itemType(for url: URL) -> PocketItem.ItemType {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .image
        case "pdf", "doc", "docx", "pages":
            return .document
        // Text-based files that can be converted to PDF
        case "txt", "rtf", "json", "xml", "html", "css", "js", "ts", "swift", "py", "md", "yaml", "yml", "csv", "log":
            return .text
        case "mp4", "mov", "avi", "mkv":
            return .video
        case "mp3", "wav", "m4a", "aac":
            return .audio
        default:
            // Try to detect if it's a text file by checking if content is readable
            return .document
        }
    }
}

// MARK: - Drag Item Info

/// Information about the item being dragged
struct DragItem {
    let providers: [NSItemProvider]
    let suggestedName: String?
    let estimatedType: PocketItem.ItemType?

    init(providers: [NSItemProvider]) {
        self.providers = providers
        self.suggestedName = providers.first?.suggestedName

        // Try to determine type from providers
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            self.estimatedType = .image
        } else if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            self.estimatedType = .link
        } else if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            self.estimatedType = .text
        } else {
            self.estimatedType = .document
        }
    }
}

// MARK: - Drop Zone Preference Key

/// Preference key for reporting drop zone frame
struct DropZoneFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Drop Zone Modifier

/// View modifier for making a view act as a drop zone
struct DropZoneModifier: ViewModifier {
    @EnvironmentObject var dropZoneManager: DropZoneManager
    @EnvironmentObject var pocketState: PocketState
    @EnvironmentObject var voiceIntentManager: VoiceIntentManager

    let onDrop: ([PocketItem], String?) async -> Void

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: DropZoneFramePreferenceKey.self,
                            value: geometry.frame(in: .global)
                        )
                }
            )
            .onPreferenceChange(DropZoneFramePreferenceKey.self) { frame in
                dropZoneManager.updateDropZoneFrame(frame)
            }
            .dropDestination(for: Data.self) { items, location in
                // This is a simplified handler - in production, use NSItemProvider
                return true
            } isTargeted: { targeted in
                if targeted {
                    dropZoneManager.isHovering = true
                    pocketState.onHoverEnter()
                    voiceIntentManager.startListening()
                } else {
                    dropZoneManager.isHovering = false
                    pocketState.onHoverExit()
                }
            }
    }
}

extension View {
    func pocketDropZone(onDrop: @escaping ([PocketItem], String?) async -> Void) -> some View {
        modifier(DropZoneModifier(onDrop: onDrop))
    }
}
