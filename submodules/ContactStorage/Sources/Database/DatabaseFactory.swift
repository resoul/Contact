import Foundation
import GRDB

enum DatabaseFactory {
    static func open(accountID: AccountID, rootDirectory: URL, keyStore: any DatabaseKeyStore) throws -> DatabasePool {
        let directory = rootDirectory.appendingPathComponent(accountID.directoryName, isDirectory: true)
        let file = directory.appendingPathComponent("storage.sqlite")
        let fm = FileManager.default
        let hasDatabase = [file.path, file.path + "-wal", file.path + "-shm"].contains { fm.fileExists(atPath: $0) }
        let existingKey = try keyStore.readKey(for: accountID)
        if hasDatabase && existingKey == nil { throw StorageError.missingKey(accountID) }
        let key = try existingKey ?? keyStore.createKeyIfAbsent(for: accountID)
        guard key.count == 32 else { throw StorageError.invalidKeyLength }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        // ThisDeviceOnly keys cannot decrypt a database restored onto another device.
        var protectedDirectory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        #endif
        let rawKey = "x'" + key.map { String(format: "%02x", $0) }.joined() + "'"
        var config = Configuration()
        config.label = "ContactStorage.\(accountID.directoryName)"
        config.busyMode = .timeout(5)
        config.maximumReaderCount = 4
        config.prepareDatabase { db in
            try db.usePassphrase(rawKey)
            guard try String.fetchOne(db, sql: "PRAGMA cipher_version") == "4.19.0 community" else {
                throw StorageError.incompatibleEngine
            }
            try db.execute(sql: """
                PRAGMA foreign_keys = ON;
                PRAGMA secure_delete = ON;
                PRAGMA synchronous = NORMAL;
                PRAGMA cache_size = -8192;
                PRAGMA temp_store = MEMORY;
                PRAGMA mmap_size = 0;
                PRAGMA cipher_memory_security = OFF;
                """)
        }
        let pool = try DatabasePool(path: file.path, configuration: config)
        do {
            try pool.read { db in
                if try db.tableExists("storage_metadata"),
                   let saved = try String.fetchOne(db, sql: "SELECT value FROM storage_metadata WHERE key = 'account_id'"),
                   saved != accountID.directoryName {
                    throw StorageError.wrongAccount
                }
            }
            try DatabaseMigrations.migrate(pool)
            try pool.write { db in
                if let saved = try String.fetchOne(db, sql: "SELECT value FROM storage_metadata WHERE key = 'account_id'") {
                    guard saved == accountID.directoryName else { throw StorageError.wrongAccount }
                } else {
                    try db.execute(sql: "INSERT INTO storage_metadata VALUES ('account_id', ?)", arguments: [accountID.directoryName])
                }
            }
            #if os(iOS)
            for path in [file.path, file.path + "-wal", file.path + "-shm"] where fm.fileExists(atPath: path) {
                try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            }
            #endif
            return pool
        } catch {
            try? pool.close()
            throw error
        }
    }
}
