import Foundation
import GRDB

extension AccountStorage {
    /// Appends the folder after the existing ones. Its peers must already be chats.
    public func createChatFolder(_ folder: StoredChatFolder) async throws {
        let title = try Self.validatedTitle(folder.title)
        try await write { db in
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM chat_folders")!
            try db.execute(sql: """
                INSERT INTO chat_folders (id, title, emoticon, color, position, categories, exclude_muted, exclude_read)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [Self.key(folder.id), title, folder.emoticon, folder.color, position,
                                 folder.categories.rawValue, folder.excludeMuted, folder.excludeRead])
            try Self.replacePeers(of: folder, db: db)
        }
    }

    /// Replaces the folder's settings and peer lists; its position is kept.
    public func updateChatFolder(_ folder: StoredChatFolder) async throws {
        let title = try Self.validatedTitle(folder.title)
        try await write { db in
            try db.execute(sql: """
                UPDATE chat_folders SET title = ?, emoticon = ?, color = ?, categories = ?, exclude_muted = ?, exclude_read = ?
                WHERE id = ?
                """, arguments: [title, folder.emoticon, folder.color, folder.categories.rawValue,
                                 folder.excludeMuted, folder.excludeRead, Self.key(folder.id)])
            guard db.changesCount == 1 else { throw StorageError.invalidArgument("unknown folder") }
            try Self.replacePeers(of: folder, db: db)
        }
    }

    public func deleteChatFolder(id: UUID) async throws {
        try await write { db in try db.execute(sql: "DELETE FROM chat_folders WHERE id = ?", arguments: [Self.key(id)]) }
    }

    /// `ids` is the complete new order of the account's folders; `allChatsPosition`
    /// places the built-in All Chats tab among them (0 puts it first).
    public func reorderChatFolders(_ ids: [UUID], allChatsPosition: Int) async throws {
        guard (0...ids.count).contains(allChatsPosition) else {
            throw StorageError.invalidArgument("All Chats position must be 0...folder count")
        }
        try await write { db in
            let existing = Set(try String.fetchAll(db, sql: "SELECT id FROM chat_folders"))
            let keys = ids.map(Self.key)
            guard Set(keys) == existing, keys.count == existing.count else {
                throw StorageError.invalidArgument("folder order must list every folder once")
            }
            for (position, key) in keys.enumerated() {
                try db.execute(sql: "UPDATE chat_folders SET position = ? WHERE id = ?", arguments: [position, key])
            }
            try db.execute(sql: """
                INSERT INTO storage_metadata VALUES ('folders_all_chats_position', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [String(allChatsPosition)])
        }
    }

    /// 0 until the user moves All Chats; may exceed the folder count after deletions.
    static func fetchAllChatsPosition(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM storage_metadata WHERE key = 'folders_all_chats_position'") ?? 0
    }

    static func fetchChatFolders(_ db: Database) throws -> [StoredChatFolder] {
        var peers: [String: (included: [Int64], excluded: [Int64])] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT folder_id, peer_id, role FROM chat_folder_peers ORDER BY folder_id, peer_id") {
            let folder: String = row["folder_id"]
            let peer: Int64 = row["peer_id"]
            let role: String = row["role"]
            if role == "include" { peers[folder, default: ([], [])].included.append(peer) }
            else { peers[folder, default: ([], [])].excluded.append(peer) }
        }
        return try Row.fetchAll(db, sql: "SELECT * FROM chat_folders ORDER BY position, id").map { row in
            let key: String = row["id"]
            guard let id = UUID(uuidString: key) else { throw StorageError.invalidRecord }
            return StoredChatFolder(id: id, title: row["title"], emoticon: row["emoticon"], color: row["color"],
                                    categories: ChatFolderCategories(rawValue: row["categories"]),
                                    excludeMuted: row["exclude_muted"], excludeRead: row["exclude_read"],
                                    includedPeers: peers[key]?.included ?? [], excludedPeers: peers[key]?.excluded ?? [])
        }
    }

    private static func replacePeers(of folder: StoredChatFolder, db: Database) throws {
        let key = Self.key(folder.id)
        try db.execute(sql: "DELETE FROM chat_folder_peers WHERE folder_id = ?", arguments: [key])
        // An exclusion wins over an inclusion of the same peer.
        let excluded = Set(folder.excludedPeers)
        let statement = try db.cachedStatement(sql: "INSERT OR IGNORE INTO chat_folder_peers (folder_id, peer_id, role) VALUES (?, ?, ?)")
        for peer in excluded { try statement.execute(arguments: [key, peer, "exclude"]) }
        for peer in Set(folder.includedPeers).subtracting(excluded) { try statement.execute(arguments: [key, peer, "include"]) }
    }

    private static func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StorageError.invalidArgument("empty folder title") }
        return trimmed
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
}
