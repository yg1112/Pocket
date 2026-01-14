import Foundation
import MultipeerConnectivity
import SwiftUI

/// Portal Manager - Enables cross-device file transfer via MultipeerConnectivity
/// Creates a "wormhole" between Pocket instances on different devices
@MainActor
final class PortalManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Whether portal is actively searching for peers
    @Published var isSearching: Bool = false

    /// Whether portal is connected to another device
    @Published var isConnected: Bool = false

    /// Nearby discovered peers
    @Published var nearbyPeers: [MCPeerID] = []

    /// Currently connected peers
    @Published var connectedPeers: [MCPeerID] = []

    /// Incoming transfer state
    @Published var incomingTransfer: TransferState?

    /// Outgoing transfer state
    @Published var outgoingTransfer: TransferState?

    /// Connection status message
    @Published var statusMessage: String = ""

    // MARK: - Portal State

    enum TransferState {
        case pending(PocketItem)
        case transferring(progress: Double)
        case completed
        case failed(Error)
    }

    // MARK: - Private Properties

    private let serviceType = "pocket-portal"  // Max 15 chars, lowercase + hyphen
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    private var pendingInvitations: [(MCPeerID, (Bool, MCSession?) -> Void)] = []
    private var onItemReceived: ((PocketItem) -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
        setupMultipeerConnectivity()
    }

    private func setupMultipeerConnectivity() {
        // Create unique peer ID based on device name
        #if os(iOS)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        #endif

        peerID = MCPeerID(displayName: deviceName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self

        print("🌀 [Portal] Initialized with peer: \(deviceName)")
    }

    // MARK: - Portal Control

    /// Open the portal - start advertising and browsing
    func openPortal() {
        guard !isSearching else { return }

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isSearching = true
        statusMessage = "Searching for nearby devices..."
        print("🌀 [Portal] Portal opened, searching...")
    }

    /// Close the portal - stop advertising and browsing
    func closePortal() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        isSearching = false
        statusMessage = ""
        print("🌀 [Portal] Portal closed")
    }

    /// Connect to a specific peer
    func connect(to peer: MCPeerID) {
        guard isSearching else { return }

        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
        statusMessage = "Connecting to \(peer.displayName)..."
        print("🌀 [Portal] Inviting \(peer.displayName)")
    }

    /// Disconnect from all peers
    func disconnect() {
        session.disconnect()
        connectedPeers.removeAll()
        isConnected = false
        statusMessage = "Disconnected"
        print("🌀 [Portal] Disconnected")
    }

    // MARK: - File Transfer

    /// Send a PocketItem through the portal
    func sendItem(_ item: PocketItem, to peer: MCPeerID? = nil) async throws {
        let targetPeers = peer.map { [$0] } ?? connectedPeers
        guard !targetPeers.isEmpty else {
            throw PortalError.noConnectedPeers
        }

        outgoingTransfer = .pending(item)
        statusMessage = "Sending \(item.name)..."

        // Encode item for transfer
        let payload = try encodeItem(item)

        do {
            try session.send(payload, toPeers: targetPeers, with: .reliable)
            outgoingTransfer = .completed
            statusMessage = "Sent \(item.name)"
            print("🌀 [Portal] Sent item: \(item.name)")
        } catch {
            outgoingTransfer = .failed(error)
            statusMessage = "Failed to send: \(error.localizedDescription)"
            throw PortalError.transferFailed(error)
        }
    }

    /// Set callback for when items are received
    func onReceive(_ handler: @escaping (PocketItem) -> Void) {
        onItemReceived = handler
    }

    // MARK: - Encoding/Decoding

    private func encodeItem(_ item: PocketItem) throws -> Data {
        let wrapper = TransferWrapper(
            id: item.id,
            type: item.type.rawValue,
            name: item.name,
            data: item.data,
            timestamp: item.timestamp
        )
        return try JSONEncoder().encode(wrapper)
    }

    private func decodeItem(_ data: Data) throws -> PocketItem {
        let wrapper = try JSONDecoder().decode(TransferWrapper.self, from: data)
        return PocketItem(
            id: wrapper.id,
            type: PocketItem.ItemType(rawValue: wrapper.type) ?? .document,
            data: wrapper.data,
            name: wrapper.name,
            timestamp: wrapper.timestamp
        )
    }
}

// MARK: - MCSessionDelegate

extension PortalManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                }
                isConnected = !connectedPeers.isEmpty
                statusMessage = "Connected to \(peerID.displayName)"
                print("🌀 [Portal] Connected: \(peerID.displayName)")

            case .connecting:
                statusMessage = "Connecting to \(peerID.displayName)..."
                print("🌀 [Portal] Connecting: \(peerID.displayName)")

            case .notConnected:
                connectedPeers.removeAll { $0 == peerID }
                isConnected = !connectedPeers.isEmpty
                if connectedPeers.isEmpty {
                    statusMessage = "Disconnected"
                }
                print("🌀 [Portal] Disconnected: \(peerID.displayName)")

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let item = try decodeItem(data)
                incomingTransfer = .completed
                statusMessage = "Received \(item.name) from \(peerID.displayName)"
                print("🌀 [Portal] Received: \(item.name)")
                onItemReceived?(item)
            } catch {
                incomingTransfer = .failed(error)
                print("🌀 [Portal] Failed to decode received data: \(error)")
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for simple transfers
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        Task { @MainActor in
            incomingTransfer = .transferring(progress: progress.fractionCompleted)
        }
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            if let error = error {
                incomingTransfer = .failed(error)
            } else {
                incomingTransfer = .completed
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PortalManager: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Auto-accept invitations for now
            // In production, you might want to show a UI prompt
            print("🌀 [Portal] Received invitation from: \(peerID.displayName)")
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("🌀 [Portal] Failed to advertise: \(error)")
            statusMessage = "Failed to advertise"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PortalManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            if !nearbyPeers.contains(peerID) {
                nearbyPeers.append(peerID)
                print("🌀 [Portal] Found peer: \(peerID.displayName)")
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            nearbyPeers.removeAll { $0 == peerID }
            print("🌀 [Portal] Lost peer: \(peerID.displayName)")
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("🌀 [Portal] Failed to browse: \(error)")
            statusMessage = "Failed to search"
        }
    }
}

// MARK: - Supporting Types

/// Wrapper for encoding PocketItem for transfer
private struct TransferWrapper: Codable {
    let id: UUID
    let type: String
    let name: String
    let data: Data
    let timestamp: Date
}

/// Portal-specific errors
enum PortalError: LocalizedError {
    case noConnectedPeers
    case transferFailed(Error)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .noConnectedPeers:
            return "No connected devices"
        case .transferFailed(let error):
            return "Transfer failed: \(error.localizedDescription)"
        case .decodingFailed:
            return "Failed to decode received data"
        }
    }
}

// MARK: - Portal Button View

/// A button that opens portal connection UI
struct PortalButtonView: View {
    @ObservedObject var portalManager: PortalManager

    var body: some View {
        Button(action: {
            if portalManager.isSearching {
                portalManager.closePortal()
            } else {
                portalManager.openPortal()
            }
        }) {
            ZStack {
                Circle()
                    .fill(portalManager.isConnected ? Color.blue : Color.white.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: portalManager.isConnected ? "link" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(portalManager.isSearching ? .blue : .white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .overlay(
            // Connection indicator
            Group {
                if !portalManager.connectedPeers.isEmpty {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: 12, y: -12)
                }
            }
        )
    }
}

// MARK: - Nearby Peers List

struct NearbyPeersView: View {
    @ObservedObject var portalManager: PortalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !portalManager.nearbyPeers.isEmpty {
                Text("Nearby Devices")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                ForEach(portalManager.nearbyPeers, id: \.displayName) { peer in
                    PeerRowView(
                        peer: peer,
                        isConnected: portalManager.connectedPeers.contains(peer),
                        onTap: {
                            if portalManager.connectedPeers.contains(peer) {
                                portalManager.disconnect()
                            } else {
                                portalManager.connect(to: peer)
                            }
                        }
                    )
                }
            } else if portalManager.isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
}

struct PeerRowView: View {
    let peer: MCPeerID
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isConnected ? .green : .white.opacity(0.5))

                Text(peer.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white)

                Spacer()

                if isConnected {
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
