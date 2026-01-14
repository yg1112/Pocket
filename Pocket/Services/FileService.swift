import Foundation
import PDFKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for file operations in Pocket
/// Handles conversion, sending, printing, and AirPlay
actor FileService {

    // MARK: - File Storage

    private let fileManager = FileManager.default

    private var pocketDirectory: URL {
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let pocketDir = urls[0].appendingPathComponent("Pocket", isDirectory: true)

        if !fileManager.fileExists(atPath: pocketDir.path) {
            try? fileManager.createDirectory(at: pocketDir, withIntermediateDirectories: true)
        }

        return pocketDir
    }

    // MARK: - F1: Universal Hold

    func saveItem(_ item: PocketItem) async throws -> URL {
        let fileName = "\(item.id.uuidString)_\(item.name)"
        let fileURL = pocketDirectory.appendingPathComponent(fileName)
        try item.data.write(to: fileURL)
        return fileURL
    }

    func loadAllItems() async throws -> [PocketItem] {
        let contents = try fileManager.contentsOfDirectory(
            at: pocketDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { url -> PocketItem? in
            guard let data = try? Data(contentsOf: url) else { return nil }

            let name = url.lastPathComponent
            let type = determineType(for: url)
            let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

            return PocketItem(
                id: UUID(),
                type: type,
                data: data,
                name: name,
                timestamp: creationDate
            )
        }
    }

    func deleteItem(_ item: PocketItem) async throws {
        let fileName = "\(item.id.uuidString)_\(item.name)"
        let fileURL = pocketDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - F2: Quick Dispatch

    @MainActor
    func sendFile(_ item: PocketItem, to target: String) async throws {
        let tempURL = try await saveTempFile(item)

        #if os(macOS)
        let sharingService = NSSharingServicePicker(items: [tempURL])
        // For macOS, we'd need a view to anchor to
        // For now, just open in Finder
        NSWorkspace.shared.activateFileViewerSelecting([tempURL])
        #else
        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            throw FileServiceError.noPresentingViewController
        }

        rootVC.present(activityVC, animated: true)
        #endif
    }

    // MARK: - F3: Format Alchemist

    func convertFile(_ item: PocketItem, to format: String) async throws -> PocketItem {
        let targetFormat = format.lowercased()
        print("📄 [FileService] Converting \(item.name) (\(item.type.rawValue)) to \(targetFormat)")

        switch (item.type, targetFormat) {
        case (.image, "jpg"), (.image, "jpeg"):
            return try await convertImageToJPEG(item)
        case (.image, "png"):
            return try await convertImageToPNG(item)
        case (.image, "pdf"):
            return try await convertImageToPDF(item)
        case (.document, "pdf"):
            // Try to convert document as text first
            if let _ = String(data: item.data, encoding: .utf8) {
                print("📄 [FileService] Document is text-readable, converting via text")
                return try await convertTextToPDF(item)
            }
            return try await convertToPDF(item)
        case (.text, "pdf"):
            return try await convertTextToPDF(item)
        case (.link, "pdf"):
            return try await convertURLToPDF(item)
        default:
            throw FileServiceError.unsupportedConversion(from: item.type.rawValue, to: targetFormat)
        }
    }

    // MARK: - Image Conversions

    private func convertImageToJPEG(_ item: PocketItem) async throws -> PocketItem {
        #if os(macOS)
        guard let nsImage = NSImage(data: item.data),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw FileServiceError.invalidImageData
        }
        #else
        guard let uiImage = UIImage(data: item.data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
            throw FileServiceError.invalidImageData
        }
        #endif

        return PocketItem(
            id: UUID(),
            type: .image,
            data: jpegData,
            name: item.name.replacingExtension(with: "jpg"),
            timestamp: Date()
        )
    }

    private func convertImageToPNG(_ item: PocketItem) async throws -> PocketItem {
        #if os(macOS)
        guard let nsImage = NSImage(data: item.data),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw FileServiceError.invalidImageData
        }
        #else
        guard let uiImage = UIImage(data: item.data),
              let pngData = uiImage.pngData() else {
            throw FileServiceError.invalidImageData
        }
        #endif

        return PocketItem(
            id: UUID(),
            type: .image,
            data: pngData,
            name: item.name.replacingExtension(with: "png"),
            timestamp: Date()
        )
    }

    private func convertImageToPDF(_ item: PocketItem) async throws -> PocketItem {
        #if os(macOS)
        guard let nsImage = NSImage(data: item.data) else {
            throw FileServiceError.invalidImageData
        }

        let pdfData = NSMutableData()
        var pageRect = CGRect(origin: .zero, size: nsImage.size)

        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw FileServiceError.conversionFailed
        }

        context.beginPDFPage(nil)

        if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: pageRect)
        }

        context.endPDFPage()
        context.closePDF()
        #else
        guard let uiImage = UIImage(data: item.data) else {
            throw FileServiceError.invalidImageData
        }

        let pdfData = NSMutableData()
        let pageRect = CGRect(origin: .zero, size: uiImage.size)

        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()
        uiImage.draw(in: pageRect)
        UIGraphicsEndPDFContext()
        #endif

        return PocketItem(
            id: UUID(),
            type: .document,
            data: pdfData as Data,
            name: item.name.replacingExtension(with: "pdf"),
            timestamp: Date()
        )
    }

    private func convertToPDF(_ item: PocketItem) async throws -> PocketItem {
        if item.name.hasSuffix(".pdf") {
            return item
        }
        throw FileServiceError.unsupportedConversion(from: item.type.rawValue, to: "pdf")
    }

    private func convertTextToPDF(_ item: PocketItem) async throws -> PocketItem {
        guard let text = String(data: item.data, encoding: .utf8) else {
            throw FileServiceError.invalidTextData
        }

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdfData = NSMutableData()

        #if os(macOS)
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FileServiceError.conversionFailed
        }

        context.beginPDFPage(nil)

        let textRect = pageRect.insetBy(dx: 72, dy: 72)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        CTFrameDraw(frame, context)

        context.endPDFPage()
        context.closePDF()
        #else
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()

        let textRect = pageRect.insetBy(dx: 72, dy: 72)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraphStyle
        ]

        (text as NSString).draw(in: textRect, withAttributes: attributes)
        UIGraphicsEndPDFContext()
        #endif

        return PocketItem(
            id: UUID(),
            type: .document,
            data: pdfData as Data,
            name: item.name.replacingExtension(with: "pdf"),
            timestamp: Date()
        )
    }

    private func convertURLToPDF(_ item: PocketItem) async throws -> PocketItem {
        guard let urlString = String(data: item.data, encoding: .utf8),
              let url = URL(string: urlString) else {
            throw FileServiceError.invalidURL
        }

        let text = "URL: \(url.absoluteString)"
        let tempItem = PocketItem.fromText(text, name: "url.txt")
        return try await convertTextToPDF(tempItem)
    }

    // MARK: - F5: Physical Link - Printing

    @MainActor
    func printFile(_ item: PocketItem, copies: Int, options: PrintOptions) async throws {
        #if os(macOS)
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit

        let printOperation: NSPrintOperation

        switch item.type {
        case .image:
            guard let image = NSImage(data: item.data) else {
                throw FileServiceError.invalidImageData
            }
            let imageView = NSImageView(image: image)
            printOperation = NSPrintOperation(view: imageView, printInfo: printInfo)

        case .document:
            if item.name.hasSuffix(".pdf"),
               let pdfDocument = PDFDocument(data: item.data) {
                printOperation = pdfDocument.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true)!
            } else if let textContent = String(data: item.data, encoding: .utf8) {
                // For text-readable documents (like JSON, XML, etc.), print as text
                let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
                textView.string = textContent
                printOperation = NSPrintOperation(view: textView, printInfo: printInfo)
            } else {
                throw FileServiceError.unsupportedPrintFormat
            }

        case .text:
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
            textView.string = String(data: item.data, encoding: .utf8) ?? ""
            printOperation = NSPrintOperation(view: textView, printInfo: printInfo)

        default:
            throw FileServiceError.unsupportedPrintFormat
        }

        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        print("🖨️ [FileService] Running print operation...")
        let success = printOperation.run()
        print("🖨️ [FileService] Print operation result: \(success)")
        #else
        let printController = UIPrintInteractionController.shared

        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = determinePrintOutputType(for: item)
        printInfo.duplex = options.duplex ? .longEdge : .none

        printController.printInfo = printInfo

        switch item.type {
        case .image:
            if let image = UIImage(data: item.data) {
                printController.printingItem = image
            }
        case .document:
            if item.name.hasSuffix(".pdf") {
                printController.printingItem = item.data
            } else {
                let pdfItem = try await convertToPDF(item)
                printController.printingItem = pdfItem.data
            }
        case .text:
            let pdfItem = try await convertTextToPDF(item)
            printController.printingItem = pdfItem.data
        default:
            throw FileServiceError.unsupportedPrintFormat
        }

        let completion: (UIPrintInteractionController, Bool, Error?) -> Void = { _, completed, error in
            if let error = error {
                print("Print error: \(error)")
            }
        }

        printController.present(animated: true, completionHandler: completion)
        #endif
    }

    #if os(iOS)
    private func determinePrintOutputType(for item: PocketItem) -> UIPrintInfo.OutputType {
        switch item.type {
        case .image:
            return .photo
        case .document, .text:
            return .general
        default:
            return .general
        }
    }
    #endif

    // MARK: - F5: Physical Link - AirPlay

    @MainActor
    func airplayFile(_ item: PocketItem, to device: String) async throws {
        throw FileServiceError.airplayNotImplemented
    }

    // MARK: - Helper Methods

    private func saveTempFile(_ item: PocketItem) async throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let fileName = "\(UUID().uuidString)_\(item.name)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try item.data.write(to: fileURL)
        return fileURL
    }

    private func determineType(for url: URL) -> PocketItem.ItemType {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .image
        case "pdf", "doc", "docx", "txt", "rtf":
            return .document
        case "mp4", "mov", "avi":
            return .video
        case "mp3", "wav", "m4a":
            return .audio
        default:
            return .document
        }
    }
}

// MARK: - Errors

enum FileServiceError: LocalizedError {
    case noPresentingViewController
    case unsupportedConversion(from: String, to: String)
    case invalidImageData
    case invalidTextData
    case invalidURL
    case conversionFailed
    case unsupportedPrintFormat
    case unsupportedAirplayFormat
    case airplayNotImplemented
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Cannot present share sheet"
        case .unsupportedConversion(let from, let to):
            return "Cannot convert \(from) to \(to)"
        case .invalidImageData:
            return "Invalid image data"
        case .invalidTextData:
            return "Invalid text data"
        case .invalidURL:
            return "Invalid URL"
        case .conversionFailed:
            return "Conversion failed"
        case .unsupportedPrintFormat:
            return "This format cannot be printed"
        case .unsupportedAirplayFormat:
            return "This format cannot be AirPlayed"
        case .airplayNotImplemented:
            return "AirPlay is not yet implemented"
        case .fileNotFound:
            return "File not found"
        }
    }
}

// MARK: - String Extension

private extension String {
    func replacingExtension(with newExtension: String) -> String {
        let name = (self as NSString).deletingPathExtension
        return "\(name).\(newExtension)"
    }
}
