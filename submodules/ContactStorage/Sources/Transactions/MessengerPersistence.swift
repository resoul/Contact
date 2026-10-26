import Foundation
import GRDB

public struct LocalMessage: Sendable {
    public let id: UUID
    public let peerID: Int64
    public let timestamp: Int64
    public let text: String
    public let outgoing: Bool
    public let unread: Bool
    public let state: MessageState
    public let presentation: Data
    public init(
        id: UUID,
        peerID: Int64,
        timestamp: Int64,
        text: String,
        outgoing: Bool,
        unread: Bool = false,
        state: MessageState,
        presentation: Data
    ) {
        self.id = id; self.peerID = peerID; self.timestamp = timestamp; self.text = text
        self.outgoing = outgoing; self.unread = unread; self.state = state; self.presentation = presentation
    }
}

public struct SeedConversation: Sendable {
    public let peer: StoragePeer
    public let muted: Bool
    public let pinned: Bool
    public let messages: [LocalMessage]
    public init(peer: StoragePeer, muted: Bool, pinned: Bool, messages: [LocalMessage]) {
        self.peer = peer; self.muted = muted; self.pinned = pinned; self.messages = messages
    }
}

public struct StoredChatListState: Equatable, Sendable {
    public let revision: Int64
    public let chats: [StoredChat]
    /// Read in the same snapshot as `chats`, so folder contents never lag the list.
    public let folders: [StoredChatFolder]
    /// Where All Chats sits among `folders`.
    public let allChatsPosition: Int
}

public struct StoredHistoryState: Equatable, Sendable {
    public let revision: Int64
    public let messages: [StoredMessage]
    public let interfaceState: Data?
}

extension AccountStorage {
    public func hasFixtureSeed() async throws -> Bool {
        try await pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM storage_metadata WHERE key = 'fixtures_v1')")!
        }
    }

    /// The marker and every fixture row commit together. Empty/deleted chats never trigger reseeding.
    public func seedFixturesIfNeeded(_ conversations: [SeedConversation]) async throws {
        try await write { db in
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM storage_metadata WHERE key = 'fixtures_v1')")! { return }
            for conversation in conversations {
                // Preserve preexisting user data if this account was used before fixture adoption.
                if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM peers WHERE id = ?)", arguments: [conversation.peer.id])! { continue }
                try Self.ensurePeer(conversation.peer, db: db)
                try db.execute(sql: "UPDATE chats SET is_muted = ?, is_pinned = ? WHERE peer_id = ?",
                               arguments: [conversation.muted, conversation.pinned, conversation.peer.id])
                for message in conversation.messages { try Self.storeLocal(message, db: db) }
                try Self.recount(conversation.peer.id, db: db)
            }
            try db.execute(sql: "INSERT INTO storage_metadata VALUES ('fixtures_v1', 'complete')")
        }
    }

    public func ensureConversation(_ peer: StoragePeer) async throws {
        try await write { db in try Self.ensurePeer(peer, db: db) }
    }

    public func storeMessage(
        _ message: LocalMessage,
        creating peer: StoragePeer? = nil,
        markingChatRead: Bool = false
    ) async throws {
        try await write { db in
            if let peer {
                guard peer.id == message.peerID else { throw StorageError.messageIdentityConflict }
                try Self.ensurePeer(peer, db: db)
            }
            try Self.storeLocal(message, db: db)
            if markingChatRead {
                try db.execute(sql: "UPDATE messages SET is_unread = 0 WHERE peer_id = ? AND is_unread = 1", arguments: [message.peerID])
                try db.execute(sql: "UPDATE chats SET manual_unread = 0 WHERE peer_id = ?", arguments: [message.peerID])
            }
            try Self.recount(message.peerID, db: db)
            if message.outgoing && message.state == .pending {
                try db.execute(sql: "INSERT OR IGNORE INTO outbox (id, message_local_id, kind) VALUES (?, ?, 'send_message')",
                               arguments: [UUID().uuidString.lowercased(), message.id.uuidString.lowercased()])
            } else if message.outgoing {
                try db.execute(sql: "DELETE FROM outbox WHERE message_local_id = ?", arguments: [message.id.uuidString.lowercased()])
            }
        }
    }

    public func setChatArchived(peerID: Int64, archived: Bool) async throws {
        try await write { db in try db.execute(sql: "UPDATE chats SET is_archived = ? WHERE peer_id = ?", arguments: [archived, peerID]) }
    }

    public func setChatManuallyUnread(peerID: Int64, unread: Bool) async throws {
        if !unread { try await markChatRead(peerID: peerID); return }
        try await write { db in try db.execute(sql: "UPDATE chats SET manual_unread = 1 WHERE peer_id = ?", arguments: [peerID]) }
    }

    public func storeInterfaceState(peerID: Int64, payload: Data) async throws {
        try await write { db in
            try db.execute(sql: "INSERT INTO peer_interface_state VALUES (?, ?) ON CONFLICT(peer_id) DO UPDATE SET payload = excluded.payload",
                           arguments: [peerID, payload])
        }
    }

    public func chatListState() async throws -> StoredChatListState {
        try await pool.read { try Self.fetchChatListState($0) }
    }

    public func message(localID: UUID) async throws -> StoredMessage? {
        try await pool.read { db in
            try MessageRecord.fetchOne(db, sql: "SELECT * FROM messages WHERE local_id = ?", arguments: [localID.uuidString.lowercased()])?.value()
        }
    }

    public func historyState(peerID: Int64, before: MessageCursor? = nil, limit: Int = 500) async throws -> StoredHistoryState {
        try Self.validateLimit(limit)
        return try await pool.read { try Self.fetchHistoryState($0, peerID: peerID, before: before, limit: limit) }
    }

    public func observeChatListState() -> StorageObservation<StoredChatListState> {
        StorageObservation(ValueObservation.tracking { try Self.fetchChatListState($0) }
            .removeDuplicates().values(in: pool, bufferingPolicy: .bufferingNewest(1)))
    }

    public func observeHistoryState(peerID: Int64) -> StorageObservation<StoredHistoryState> {
        StorageObservation(ValueObservation.tracking { try Self.fetchHistoryState($0, peerID: peerID, before: nil, limit: 500) }
            .removeDuplicates().values(in: pool, bufferingPolicy: .bufferingNewest(1)))
    }

    private static func revision(_ db: Database) throws -> Int64 {
        try Int64.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM storage_metadata WHERE key = 'revision'")!
    }

    private static func fetchChatListState(_ db: Database) throws -> StoredChatListState {
        StoredChatListState(revision: try revision(db), chats: try fetchChats(db, limit: 500), folders: try fetchChatFolders(db),
                            allChatsPosition: try fetchAllChatsPosition(db))
    }

    private static func fetchHistoryState(_ db: Database, peerID: Int64, before: MessageCursor?, limit: Int) throws -> StoredHistoryState {
        StoredHistoryState(revision: try revision(db), messages: try fetchMessages(db, peerID: peerID, before: before, limit: limit),
            interfaceState: try Data.fetchOne(db, sql: "SELECT payload FROM peer_interface_state WHERE peer_id = ?", arguments: [peerID]))
    }

    private static func ensurePeer(_ peer: StoragePeer, db: Database) throws {
        try db.execute(sql: "INSERT OR IGNORE INTO peers (id, kind, display_name, username, presentation) VALUES (?, ?, ?, ?, ?)",
                       arguments: [peer.id, peer.kind.rawValue, peer.displayName, peer.username, peer.presentation])
        try db.execute(sql: "INSERT OR IGNORE INTO chats (peer_id) VALUES (?)", arguments: [peer.id])
    }

    private static func recount(_ peer: Int64, db: Database) throws {
        try db.execute(sql: "UPDATE chats SET unread_count = (SELECT count(*) FROM messages WHERE peer_id = ? AND is_unread = 1) WHERE peer_id = ?",
                       arguments: [peer, peer])
    }

    private static func storeLocal(_ message: LocalMessage, db: Database) throws {
        let id = message.id.uuidString.lowercased()
        if let existing = try Row.fetchOne(db, sql: "SELECT peer_id, is_outgoing FROM messages WHERE local_id = ?", arguments: [id]) {
            let peer: Int64 = existing["peer_id"]
            let outgoing: Bool = existing["is_outgoing"]
            guard peer == message.peerID, outgoing == message.outgoing else { throw StorageError.messageIdentityConflict }
        }
        let statement = try db.cachedStatement(sql: """
            INSERT INTO messages (local_id, peer_id, timestamp, text, is_outgoing, is_unread, state, presentation)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(local_id) DO UPDATE SET text = excluded.text, state = excluded.state,
                edited_at = CASE WHEN messages.text <> excluded.text
                    THEN CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) ELSE messages.edited_at END,
                presentation = excluded.presentation
            """)
        try statement.execute(arguments: [id, message.peerID, message.timestamp, message.text, message.outgoing,
                                          message.outgoing ? false : message.unread, message.state.rawValue, message.presentation])
    }
}
