import Foundation
import GRDB

extension AccountStorage {
    /// Messages, unread counts and the opaque sync cursor commit atomically. Repeated server IDs are upserts.
    public func applyIncoming(peers: [StoragePeer], messages: [IncomingMessage], checkpoint: SyncCheckpoint? = nil) async throws {
        if let checkpoint, checkpoint.scope.isEmpty { throw StorageError.invalidArgument("empty checkpoint scope") }
        try await write { db in
            for peer in peers { try Self.savePeer(peer, db: db) }
            var changedPeers = Set<Int64>()
            for message in messages {
                let existing = try MessageRecord.fetchOne(db, sql: "SELECT * FROM messages WHERE peer_id = ? AND server_id = ?",
                                                         arguments: [message.peerID, message.serverID])
                var localID = existing?.local_id ?? UUID().uuidString.lowercased()
                if let clientID = message.clientID {
                    guard message.isOutgoing else { throw StorageError.messageIdentityConflict }
                    let client = try Self.findMessage(clientID, db: db)
                    localID = clientID.uuidString.lowercased()
                    if let client {
                        guard client.peer_id == message.peerID, client.is_outgoing,
                              client.server_id == nil || client.server_id == message.serverID else {
                            throw StorageError.messageIdentityConflict
                        }
                        localID = client.local_id
                        try Self.mergeEcho(existing, into: client.local_id, db: db)
                    } else if let existing {
                        // A known server message keeps its already published local identity.
                        localID = existing.local_id
                    }
                }
                if let existing, existing.is_outgoing != message.isOutgoing { throw StorageError.messageIdentityConflict }
                let unread = existing?.is_unread ?? (!message.isOutgoing && message.countsAsUnread)
                // Preserve read/delivered state when a server echo is replayed.
                let state = message.isOutgoing ? (existing?.state == .read ? MessageState.read :
                    existing?.state == .delivered ? .delivered : .sent) : .received
                let statement = try db.cachedStatement(sql: """
                    INSERT INTO messages (local_id, peer_id, server_id, timestamp, text, is_outgoing, is_unread, state, edited_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(local_id) DO UPDATE SET server_id = excluded.server_id, timestamp = excluded.timestamp,
                        text = excluded.text, state = excluded.state, edited_at = excluded.edited_at
                    """)
                try statement.execute(arguments: [localID, message.peerID, message.serverID, message.timestamp, message.text,
                                                  message.isOutgoing, unread, state.rawValue, message.editedAt])
                if message.isOutgoing { try db.execute(sql: "DELETE FROM outbox WHERE message_local_id = ?", arguments: [localID]) }
                changedPeers.insert(message.peerID)
            }
            for peerID in changedPeers { try Self.refreshUnread(peerID, db: db) }
            if let checkpoint {
                try db.execute(sql: "INSERT INTO sync_state VALUES (?, ?) ON CONFLICT(scope) DO UPDATE SET cursor = excluded.cursor",
                               arguments: [checkpoint.scope, checkpoint.cursor])
            }
        }
    }

    @discardableResult
    public func enqueueMessage(peerID: Int64, text: String, localID: UUID = UUID(),
                               timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async throws -> StoredMessage {
        guard !text.isEmpty else { throw StorageError.invalidArgument("empty message") }
        return try await write { db in
            if let existing = try Self.findMessage(localID, db: db) {
                guard existing.peer_id == peerID, existing.is_outgoing, existing.text == text else {
                    throw StorageError.messageIdentityConflict
                }
                return try existing.value()
            }
            let id = localID.uuidString.lowercased()
            try db.execute(sql: """
                INSERT INTO messages (local_id, peer_id, timestamp, text, is_outgoing, is_unread, state)
                VALUES (?, ?, ?, ?, 1, 0, 'pending')
                """, arguments: [id, peerID, timestamp, text])
            try db.execute(sql: "INSERT INTO outbox (id, message_local_id, kind) VALUES (?, ?, 'send_message')",
                           arguments: [UUID().uuidString.lowercased(), id])
            guard let stored = try Self.findMessage(localID, db: db) else { throw StorageError.messageNotFound }
            return try stored.value()
        }
    }

    public func confirmMessage(localID: UUID, serverID: Int64, timestamp: Int64? = nil) async throws {
        try await write { db in
            guard let message = try Self.findMessage(localID, db: db) else { throw StorageError.messageNotFound }
            guard message.is_outgoing, message.server_id == nil || message.server_id == serverID else {
                throw StorageError.messageIdentityConflict
            }
            let echo = try MessageRecord.fetchOne(db, sql: "SELECT * FROM messages WHERE peer_id = ? AND server_id = ?",
                                                  arguments: [message.peer_id, serverID])
            if let echo, !echo.is_outgoing { throw StorageError.messageIdentityConflict }
            try Self.mergeEcho(echo, into: message.local_id, db: db)
            try db.execute(sql: """
                UPDATE messages SET server_id = ?, timestamp = COALESCE(?, timestamp),
                    state = CASE WHEN state IN ('read','delivered') THEN state ELSE 'sent' END WHERE local_id = ?
                """, arguments: [serverID, timestamp, message.local_id])
            try db.execute(sql: "DELETE FROM outbox WHERE message_local_id = ?", arguments: [message.local_id])
        }
    }

    /// A transient send failure keeps its outbox entry so a future worker can retry after relaunch.
    public func recordSendFailure(localID: UUID, retryAt: Int64?) async throws {
        try await write { db in
            let id = localID.uuidString.lowercased()
            guard try Int.fetchOne(db, sql: "SELECT count(*) FROM outbox WHERE message_local_id = ?", arguments: [id]) == 1 else {
                throw StorageError.messageNotFound
            }
            try db.execute(sql: "UPDATE outbox SET attempt_count = attempt_count + 1, retry_at = ? WHERE message_local_id = ?",
                           arguments: [retryAt, id])
            try db.execute(sql: "UPDATE messages SET state = 'failed' WHERE local_id = ?", arguments: [id])
        }
    }

    public func markChatRead(peerID: Int64) async throws {
        try await write { db in
            try db.execute(sql: "UPDATE messages SET is_unread = 0 WHERE peer_id = ? AND is_unread = 1", arguments: [peerID])
            try Self.refreshUnread(peerID, db: db)
            try db.execute(sql: "UPDATE chats SET manual_unread = 0 WHERE peer_id = ?", arguments: [peerID])
        }
    }

    public func setChatOptions(peerID: Int64, isMuted: Bool, isPinned: Bool) async throws {
        try await write { db in
            try db.execute(sql: "UPDATE chats SET is_muted = ?, is_pinned = ? WHERE peer_id = ?", arguments: [isMuted, isPinned, peerID])
        }
    }

    public func deleteMessages(_ localIDs: [UUID]) async throws {
        try await write { db in
            var peers = Set<Int64>()
            let deletion = try db.cachedStatement(sql: "DELETE FROM messages WHERE local_id = ?")
            for id in localIDs {
                if let message = try Self.findMessage(id, db: db) { peers.insert(message.peer_id) }
                try deletion.execute(arguments: [id.uuidString.lowercased()])
            }
            for peer in peers { try Self.refreshUnread(peer, db: db) }
        }
    }

    public func deleteChat(peerID: Int64) async throws {
        try await write { db in try db.execute(sql: "DELETE FROM chats WHERE peer_id = ?", arguments: [peerID]) }
    }

    private static func savePeer(_ peer: StoragePeer, db: Database) throws {
        try PeerRecord(peer).upsert(db)
        try db.execute(sql: "INSERT OR IGNORE INTO chats (peer_id) VALUES (?)", arguments: [peer.id])
    }

    private static func findMessage(_ id: UUID, db: Database) throws -> MessageRecord? {
        try MessageRecord.fetchOne(db, sql: "SELECT * FROM messages WHERE local_id = ?", arguments: [id.uuidString.lowercased()])
    }

    private static func refreshUnread(_ id: Int64, db: Database) throws {
        try db.execute(sql: "UPDATE chats SET unread_count = (SELECT count(*) FROM messages WHERE peer_id = ? AND is_unread = 1) WHERE peer_id = ?",
                       arguments: [id, id])
    }

    private static func mergeEcho(_ echo: MessageRecord?, into localID: String, db: Database) throws {
        guard let echo, echo.local_id != localID else { return }
        try db.execute(sql: "UPDATE attachments SET message_local_id = ? WHERE message_local_id = ?", arguments: [localID, echo.local_id])
        try db.execute(sql: "DELETE FROM messages WHERE local_id = ?", arguments: [echo.local_id])
    }
}
