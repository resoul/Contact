import Foundation

public struct AccountID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID) { self.rawValue = rawValue }
    public var directoryName: String { rawValue.uuidString.lowercased() }
}

public enum PeerKind: String, Codable, Sendable { case person, group, channel, bot }
public enum MessageState: String, Codable, Sendable { case received, pending, sent, delivered, read, failed }

public struct StoragePeer: Equatable, Sendable {
    public let id: Int64
    public let kind: PeerKind
    public let displayName: String
    public let username: String?
    public let presentation: Data?
    public init(id: Int64, kind: PeerKind, displayName: String, username: String? = nil, presentation: Data? = nil) {
        self.id = id; self.kind = kind; self.displayName = displayName; self.username = username
        self.presentation = presentation
    }
}

public struct StoredMessage: Equatable, Sendable {
    public let localID: UUID
    public let peerID: Int64
    public let serverID: Int64?
    /// Unix milliseconds. Together with localID this defines the pagination order.
    public let timestamp: Int64
    public let text: String
    public let isOutgoing: Bool
    public let isUnread: Bool
    public let state: MessageState
    public let editedAt: Int64?
    public let presentation: Data?
}

public struct StoredChat: Equatable, Sendable {
    public let peer: StoragePeer
    public let lastMessage: StoredMessage?
    public let unreadCount: Int
    public let isMuted: Bool
    public let isPinned: Bool
    public let isArchived: Bool
    public let manuallyUnread: Bool
}

public struct MessageCursor: Equatable, Sendable {
    public let timestamp: Int64
    public let localID: UUID
    public init(message: StoredMessage) { timestamp = message.timestamp; localID = message.localID }
}

public struct IncomingMessage: Sendable {
    public let peerID: Int64
    public let serverID: Int64
    public let timestamp: Int64
    public let text: String
    public let isOutgoing: Bool
    public let countsAsUnread: Bool
    public let editedAt: Int64?
    /// An echoed client ID allows an update to match an outgoing pending message.
    public let clientID: UUID?
    public init(peerID: Int64, serverID: Int64, timestamp: Int64, text: String,
                isOutgoing: Bool = false, countsAsUnread: Bool = true, editedAt: Int64? = nil, clientID: UUID? = nil) {
        self.peerID = peerID; self.serverID = serverID; self.timestamp = timestamp; self.text = text
        self.isOutgoing = isOutgoing; self.countsAsUnread = countsAsUnread; self.editedAt = editedAt; self.clientID = clientID
    }
}

public struct SyncCheckpoint: Sendable {
    public let scope: String
    public let cursor: Data
    public init(scope: String, cursor: Data) { self.scope = scope; self.cursor = cursor }
}

public struct PendingSend: Equatable, Sendable {
    public let operationID: UUID
    public let message: StoredMessage
    public let attemptCount: Int
    public let retryAt: Int64?
}

public enum StorageError: Error, Equatable, Sendable {
    case missingKey(AccountID)
    case invalidKeyLength
    case randomGenerationFailed(Int32)
    case keychain(Int32)
    case wrongAccount
    case incompatibleEngine
    case unsupportedSchema
    case invalidRecord
    case invalidArgument(String)
    case messageNotFound
    case messageIdentityConflict
}
