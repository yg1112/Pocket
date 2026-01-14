import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Represents an item that can be held in the Pocket
/// Supports images, documents, links, and text content
struct PocketItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: ItemType
    let data: Data
    let name: String
    let timestamp: Date
    var metadata: [String: String] = [:]

    // MARK: - Item Types

    enum ItemType: String, Codable, Sendable {
        case image
        case document
        case link
        case text
        case video
        case audio

        var icon: String {
            switch self {
            case .image: return "photo.fill"
            case .document: return "doc.fill"
            case .link: return "link"
            case .text: return "text.alignleft"
            case .video: return "video.fill"
            case .audio: return "waveform"
            }
        }

        var color: Color {
            switch self {
            case .image: return .blue
            case .document: return .orange
            case .link: return .green
            case .text: return .purple
            case .video: return .red
            case .audio: return .pink
            }
        }

        var supportedUTTypes: [UTType] {
            switch self {
            case .image: return [.image, .jpeg, .png, .heic, .gif]
            case .document: return [.pdf, .plainText, .rtf]
            case .link: return [.url]
            case .text: return [.plainText, .utf8PlainText]
            case .video: return [.movie, .video, .mpeg4Movie]
            case .audio: return [.audio, .mp3, .wav]
            }
        }
    }

    // MARK: - Computed Properties

    /// Thumbnail image for display
    var thumbnail: Image? {
        switch type {
        case .image:
            #if os(macOS)
            if let nsImage = NSImage(data: data) {
                return Image(nsImage: nsImage)
            }
            #else
            if let uiImage = UIImage(data: data) {
                return Image(uiImage: uiImage)
            }
            #endif
            return nil
        default:
            return nil
        }
    }

    /// Display size string
    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(data.count))
    }

    // MARK: - Transferable Support

    var transferable: PocketItemTransferable {
        PocketItemTransferable(item: self)
    }

    // MARK: - Factory Methods

    #if os(macOS)
    static func fromImage(_ image: NSImage, name: String = "Image") -> PocketItem? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return PocketItem(
            id: UUID(),
            type: .image,
            data: data,
            name: name,
            timestamp: Date()
        )
    }
    #else
    static func fromImage(_ image: UIImage, name: String = "Image") -> PocketItem? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        return PocketItem(
            id: UUID(),
            type: .image,
            data: data,
            name: name,
            timestamp: Date()
        )
    }
    #endif

    static func fromURL(_ url: URL, name: String? = nil) -> PocketItem {
        let itemName = name ?? url.lastPathComponent
        let data = url.absoluteString.data(using: .utf8) ?? Data()
        return PocketItem(
            id: UUID(),
            type: .link,
            data: data,
            name: itemName,
            timestamp: Date()
        )
    }

    static func fromText(_ text: String, name: String = "Text") -> PocketItem {
        PocketItem(
            id: UUID(),
            type: .text,
            data: text.data(using: .utf8) ?? Data(),
            name: name,
            timestamp: Date()
        )
    }
}

// MARK: - Transferable Wrapper

/// Wrapper to make PocketItem work with SwiftUI's drag and drop
struct PocketItemTransferable: Transferable {
    let item: PocketItem

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { wrapper in
            try JSONEncoder().encode(wrapper.item)
        }
        DataRepresentation(importedContentType: .data) { data in
            let item = try JSONDecoder().decode(PocketItem.self, from: data)
            return PocketItemTransferable(item: item)
        }
    }
}

// MARK: - Codable Conformance

extension PocketItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, type, data, name, timestamp, metadata
    }
}

// MARK: - Hashable Conformance

extension PocketItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
