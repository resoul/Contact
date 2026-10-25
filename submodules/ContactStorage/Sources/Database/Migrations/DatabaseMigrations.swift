import GRDB

enum DatabaseMigrations {
    static func migrate(_ pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        // Never enable eraseDatabaseOnSchemaChange for account data.
        migrator.registerMigration("v001_initial") { db in
            try db.execute(sql: """
                CREATE TABLE storage_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL) WITHOUT ROWID;
                CREATE TABLE peers (
                    id INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL CHECK (kind IN ('person','group','channel','bot')),
                    display_name TEXT NOT NULL,
                    username TEXT
                );
                CREATE TABLE chats (
                    peer_id INTEGER PRIMARY KEY REFERENCES peers(id) ON DELETE CASCADE,
                    unread_count INTEGER NOT NULL DEFAULT 0 CHECK (unread_count >= 0),
                    is_muted INTEGER NOT NULL DEFAULT 0 CHECK (is_muted IN (0,1)),
                    is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0,1))
                );
                CREATE TABLE messages (
                    local_id TEXT PRIMARY KEY NOT NULL,
                    peer_id INTEGER NOT NULL REFERENCES chats(peer_id) ON DELETE CASCADE,
                    server_id INTEGER,
                    timestamp INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    is_outgoing INTEGER NOT NULL CHECK (is_outgoing IN (0,1)),
                    is_unread INTEGER NOT NULL CHECK (is_unread IN (0,1)),
                    state TEXT NOT NULL CHECK (state IN ('received','pending','sent','delivered','read','failed')),
                    edited_at INTEGER,
                    UNIQUE (peer_id, server_id),
                    CHECK (is_outgoing = 0 OR is_unread = 0)
                );
                CREATE INDEX messages_timeline ON messages(peer_id, timestamp DESC, local_id DESC);
                CREATE INDEX messages_unread ON messages(peer_id) WHERE is_unread = 1;
                CREATE TABLE attachments (
                    id TEXT PRIMARY KEY NOT NULL,
                    message_local_id TEXT NOT NULL REFERENCES messages(local_id) ON DELETE CASCADE,
                    resource_id TEXT,
                    local_path TEXT,
                    mime_type TEXT NOT NULL,
                    byte_count INTEGER NOT NULL CHECK (byte_count >= 0)
                );
                CREATE INDEX attachments_message ON attachments(message_local_id);
                CREATE TABLE outbox (
                    id TEXT PRIMARY KEY NOT NULL,
                    message_local_id TEXT NOT NULL UNIQUE REFERENCES messages(local_id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK (kind = 'send_message'),
                    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
                    retry_at INTEGER
                );
                CREATE INDEX outbox_retry ON outbox(retry_at, id);
                CREATE TABLE sync_state (scope TEXT PRIMARY KEY NOT NULL, cursor BLOB NOT NULL) WITHOUT ROWID;
                """)
        }
        migrator.registerMigration("v002_messenger_presentation") { db in
            try db.execute(sql: """
                ALTER TABLE peers ADD COLUMN presentation BLOB;
                ALTER TABLE messages ADD COLUMN presentation BLOB;
                ALTER TABLE chats ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1));
                ALTER TABLE chats ADD COLUMN manual_unread INTEGER NOT NULL DEFAULT 0 CHECK (manual_unread IN (0,1));
                CREATE TABLE peer_interface_state (
                    peer_id INTEGER PRIMARY KEY REFERENCES chats(peer_id) ON DELETE CASCADE,
                    payload BLOB NOT NULL
                );
                INSERT INTO storage_metadata VALUES ('revision', '0');
                """)
        }
        let registered = migrator
        try pool.read { db in
            guard try !registered.hasBeenSuperseded(db) else { throw StorageError.unsupportedSchema }
        }
        try migrator.migrate(pool)
    }
}
