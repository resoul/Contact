import Foundation
import GRDB

extension AccountStorage {
    public func chats(limit: Int = 100) async throws -> [StoredChat] {
        try Self.validateLimit(limit)
        return try await pool.read { try Self.fetchChats($0, limit: limit) }
    }

    /// Newest first; pass the last returned message as the cursor for older history.
    public func messages(peerID: Int64, before: MessageCursor? = nil, limit: Int = 50) async throws -> [StoredMessage] {
        try Self.validateLimit(limit)
        return try await pool.read { try Self.fetchMessages($0, peerID: peerID, before: before, limit: limit) }
    }

    public func observeChats(limit: Int = 100) throws -> StorageObservation<[StoredChat]> {
        try Self.validateLimit(limit)
        return StorageObservation(ValueObservation.tracking { db in
            try Self.fetchChats(db, limit: limit)
        }.removeDuplicates().values(in: pool, bufferingPolicy: .bufferingNewest(1)))
    }

    public func observeMessages(peerID: Int64, limit: Int = 50) throws -> StorageObservation<[StoredMessage]> {
        try Self.validateLimit(limit)
        return StorageObservation(ValueObservation.tracking { db in
            try Self.fetchMessages(db, peerID: peerID, before: nil, limit: limit)
        }.removeDuplicates().values(in: pool, bufferingPolicy: .bufferingNewest(1)))
    }

    public func checkpoint(scope: String) async throws -> Data? {
        try await pool.read { db in try Data.fetchOne(db, sql: "SELECT cursor FROM sync_state WHERE scope = ?", arguments: [scope]) }
    }

    public func pendingSends(limit: Int = 100) async throws -> [PendingSend] {
        try Self.validateLimit(limit)
        return try await pool.read { db in
            let statement = try db.cachedStatement(sql: """
                SELECT m.*, o.id AS operation_id, o.attempt_count, o.retry_at
                FROM outbox o JOIN messages m ON m.local_id = o.message_local_id
                ORDER BY m.timestamp, m.local_id LIMIT ?
                """)
            return try Row.fetchAll(statement, arguments: [limit]).map { row in
                guard let id = UUID(uuidString: row["operation_id"]) else { throw StorageError.invalidRecord }
                return PendingSend(operationID: id, message: try MessageRecord(row: row).value(),
                                   attemptCount: row["attempt_count"], retryAt: row["retry_at"])
            }
        }
    }

    static func fetchMessages(_ db: Database, peerID: Int64, before: MessageCursor?, limit: Int) throws -> [StoredMessage] {
        let predicate = before == nil ? "" : "AND (timestamp, local_id) < (?, ?)"
        var args: [any DatabaseValueConvertible] = [peerID]
        if let before { args += [before.timestamp, before.localID.uuidString.lowercased()] }
        args.append(limit)
        let statement = try db.cachedStatement(sql: """
            SELECT * FROM messages WHERE peer_id = ? \(predicate)
            ORDER BY timestamp DESC, local_id DESC LIMIT ?
            """)
        return try MessageRecord.fetchAll(statement, arguments: StatementArguments(args)).map { try $0.value() }
    }

    static func fetchChats(_ db: Database, limit: Int) throws -> [StoredChat] {
        let statement = try db.cachedStatement(sql: """
            SELECT p.id, p.kind, p.display_name, p.username, p.presentation AS peer_presentation,
                   c.peer_id, c.unread_count, c.is_muted, c.is_pinned, c.is_archived, c.manual_unread,
                   m.local_id, m.server_id, m.timestamp, m.text, m.is_outgoing, m.is_unread, m.state, m.edited_at, m.presentation
            FROM chats c JOIN peers p ON p.id = c.peer_id
            LEFT JOIN messages m ON m.local_id = (
                SELECT local_id FROM messages WHERE peer_id = c.peer_id
                ORDER BY timestamp DESC, local_id DESC LIMIT 1
            )
            WHERE c.is_archived = 0
            ORDER BY c.is_pinned DESC, COALESCE(m.timestamp, 0) DESC, c.peer_id DESC LIMIT ?
            """)
        return try Row.fetchAll(statement, arguments: [limit]).map { row in
            let localID: String? = row["local_id"]
            guard let kind = PeerKind(rawValue: row["kind"]) else { throw StorageError.invalidRecord }
            let peer = StoragePeer(id: row["id"], kind: kind, displayName: row["display_name"], username: row["username"], presentation: row["peer_presentation"])
            return StoredChat(peer: peer,
                              lastMessage: localID == nil ? nil : try MessageRecord(row: row).value(),
                              unreadCount: row["unread_count"], isMuted: row["is_muted"], isPinned: row["is_pinned"],
                              isArchived: row["is_archived"], manuallyUnread: row["manual_unread"])
        }
    }
}
