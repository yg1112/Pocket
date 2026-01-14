import Foundation

/// Represents a task being executed by Pocket
/// Tracks the state of file processing operations
struct PocketTask: Identifiable, Equatable, Sendable {
    let id: UUID
    let item: PocketItem
    let intent: Intent
    let createdAt: Date
    var status: TaskStatus
    var result: TaskResult?
    var progress: Double

    init(
        id: UUID = UUID(),
        item: PocketItem,
        intent: Intent,
        createdAt: Date = Date(),
        status: TaskStatus = .pending,
        result: TaskResult? = nil,
        progress: Double = 0.0
    ) {
        self.id = id
        self.item = item
        self.intent = intent
        self.createdAt = createdAt
        self.status = status
        self.result = result
        self.progress = progress
    }

    /// Duration since task creation
    var duration: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }

    /// Whether the task is still active
    var isActive: Bool {
        switch status {
        case .pending, .processing:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }
}

// MARK: - Task Status

enum TaskStatus: Equatable, Sendable {
    case pending
    case processing
    case completed
    case failed(Error)
    case cancelled

    static func == (lhs: TaskStatus, rhs: TaskStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.processing, .processing),
             (.completed, .completed),
             (.cancelled, .cancelled):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Task Result

enum TaskResult: Equatable, Sendable {
    case item(PocketItem)           // New item created (e.g., converted file)
    case text(String)               // Text result (e.g., summary)
    case sent(to: String)           // Successfully sent
    case printed(copies: Int)       // Successfully printed
    case airplayed(to: String)      // Successfully airplayed

    var displayMessage: String {
        switch self {
        case .item(let item):
            return "Created: \(item.name)"
        case .text(let summary):
            let preview = summary.prefix(50)
            return String(preview) + (summary.count > 50 ? "..." : "")
        case .sent(let target):
            return "Sent to \(target)"
        case .printed(let copies):
            return "Printed \(copies) cop\(copies == 1 ? "y" : "ies")"
        case .airplayed(let device):
            return "Playing on \(device)"
        }
    }
}

// MARK: - Task Error

enum PocketTaskError: LocalizedError {
    case conversionFailed(from: String, to: String)
    case sendingFailed(reason: String)
    case printingFailed(reason: String)
    case airplayFailed(reason: String)
    case extractionFailed(reason: String)
    case unsupportedOperation
    case networkError
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let from, let to):
            return "Failed to convert from \(from) to \(to)"
        case .sendingFailed(let reason):
            return "Failed to send: \(reason)"
        case .printingFailed(let reason):
            return "Failed to print: \(reason)"
        case .airplayFailed(let reason):
            return "Failed to AirPlay: \(reason)"
        case .extractionFailed(let reason):
            return "Failed to extract: \(reason)"
        case .unsupportedOperation:
            return "This operation is not supported"
        case .networkError:
            return "Network connection failed"
        case .timeout:
            return "Operation timed out"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}
