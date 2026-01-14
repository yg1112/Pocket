import Foundation
import SwiftUI

/// Manages a session of multiple items for batch processing
/// Supports the "stacking shelf" pattern where multiple items can be combined
@MainActor
final class PocketSession: ObservableObject {

    // MARK: - Published Properties

    /// Items currently in this session
    @Published var items: [PocketItem] = []

    /// Whether the session is active (has items)
    @Published var isActive: Bool = false

    /// Session creation time
    @Published var startTime: Date?

    /// Last activity time
    @Published var lastActivityTime: Date?

    // MARK: - Configuration

    /// Maximum items allowed in a session
    let maxItems: Int = 10

    /// Session timeout (auto-clear after inactivity)
    let sessionTimeout: TimeInterval = 300  // 5 minutes

    // MARK: - Computed Properties

    /// Number of items in session
    var itemCount: Int { items.count }

    /// Whether session can accept more items
    var canAddMore: Bool { items.count < maxItems }

    /// Summary of item types in session
    var itemTypeSummary: String {
        let types = Dictionary(grouping: items, by: { $0.type })
        let parts = types.map { "\($0.value.count) \($0.key.rawValue)" }
        return parts.joined(separator: ", ")
    }

    /// Combined description for LLM context
    var sessionContext: String {
        var context = "Session contains \(items.count) items:\n"
        for (index, item) in items.enumerated() {
            context += "\(index + 1). \(item.name) (\(item.type.rawValue))\n"
        }
        return context
    }

    // MARK: - Session Management

    /// Start a new session with an item
    func startSession(with item: PocketItem) {
        items = [item]
        isActive = true
        startTime = Date()
        lastActivityTime = Date()
        print("📚 [Session] Started with: \(item.name)")
    }

    /// Add an item to the current session
    func addItem(_ item: PocketItem) -> Bool {
        guard canAddMore else {
            print("📚 [Session] Cannot add more items (max: \(maxItems))")
            return false
        }

        items.append(item)
        lastActivityTime = Date()
        print("📚 [Session] Added: \(item.name) (total: \(items.count))")
        return true
    }

    /// Add multiple items at once
    func addItems(_ newItems: [PocketItem]) -> Int {
        var added = 0
        for item in newItems {
            if addItem(item) {
                added += 1
            } else {
                break
            }
        }
        return added
    }

    /// Remove an item from session
    func removeItem(_ item: PocketItem) {
        items.removeAll { $0.id == item.id }
        lastActivityTime = Date()

        if items.isEmpty {
            endSession()
        }
        print("📚 [Session] Removed: \(item.name) (remaining: \(items.count))")
    }

    /// Remove item at index
    func removeItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        let item = items.remove(at: index)
        lastActivityTime = Date()

        if items.isEmpty {
            endSession()
        }
        print("📚 [Session] Removed at \(index): \(item.name)")
    }

    /// Clear all items and end session
    func endSession() {
        items.removeAll()
        isActive = false
        startTime = nil
        lastActivityTime = nil
        print("📚 [Session] Ended")
    }

    /// Check if session has timed out
    func checkTimeout() -> Bool {
        guard let lastActivity = lastActivityTime else { return false }
        let elapsed = Date().timeIntervalSince(lastActivity)
        if elapsed > sessionTimeout {
            print("📚 [Session] Timed out after \(elapsed)s")
            endSession()
            return true
        }
        return false
    }

    // MARK: - Batch Operations

    /// Get all items for batch processing
    func getAllItems() -> [PocketItem] {
        return items
    }

    /// Get items of a specific type
    func getItems(ofType type: PocketItem.ItemType) -> [PocketItem] {
        return items.filter { $0.type == type }
    }

    /// Merge session into a single compound item (for sending as package)
    func createPackage(name: String = "Package") -> PocketItem? {
        guard !items.isEmpty else { return nil }

        // Create a JSON manifest of the package
        let manifest = items.map { item -> [String: Any] in
            return [
                "id": item.id.uuidString,
                "name": item.name,
                "type": item.type.rawValue,
                "size": item.data.count
            ]
        }

        guard let manifestData = try? JSONSerialization.data(withJSONObject: manifest) else {
            return nil
        }

        return PocketItem(
            id: UUID(),
            type: .document,
            data: manifestData,
            name: "\(name)_\(items.count)_items.json",
            timestamp: Date()
        )
    }
}

// MARK: - Session State for UI

extension PocketSession {

    /// Visual representation of session state
    enum SessionState {
        case empty
        case single(PocketItem)
        case multiple(count: Int)
        case full

        var displayText: String {
            switch self {
            case .empty: return ""
            case .single(let item): return item.name
            case .multiple(let count): return "\(count) items"
            case .full: return "Full (\(10) items)"
            }
        }

        var icon: String {
            switch self {
            case .empty: return "tray"
            case .single: return "doc.fill"
            case .multiple: return "doc.on.doc.fill"
            case .full: return "tray.full.fill"
            }
        }
    }

    var state: SessionState {
        switch items.count {
        case 0: return .empty
        case 1: return .single(items[0])
        case maxItems: return .full
        default: return .multiple(count: items.count)
        }
    }
}

// MARK: - Session Badge View

/// Small badge showing session item count
struct SessionBadgeView: View {
    @ObservedObject var session: PocketSession

    var body: some View {
        if session.itemCount > 0 {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)

                Text("\(session.itemCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Session Items Preview

/// Stacked preview of items in session
struct SessionStackView: View {
    @ObservedObject var session: PocketSession
    let maxVisible: Int = 3

    var body: some View {
        ZStack {
            ForEach(Array(session.items.prefix(maxVisible).enumerated()), id: \.element.id) { index, item in
                itemCard(item, at: index)
            }
        }
        .frame(width: 60, height: 60)
    }

    private func itemCard(_ item: PocketItem, at index: Int) -> some View {
        let offset = CGFloat(index) * 4
        let scale = 1.0 - CGFloat(index) * 0.08

        return RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: item.type.icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            )
            .scaleEffect(scale)
            .offset(x: offset, y: -offset)
    }
}
