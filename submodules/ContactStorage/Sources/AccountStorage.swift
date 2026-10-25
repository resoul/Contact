import Foundation
import GRDB

/// One owner per account (AppEnvironment). SQL and GRDB records stay inside this module.
public final class AccountStorage: Sendable {
    public let accountID: AccountID
    let pool: DatabasePool

    /// Opening/migrations perform I/O. Call on a background executor, never on the UI thread.
    public init(accountID: AccountID, rootDirectory: URL,
                keyStore: any DatabaseKeyStore = KeychainDatabaseKeyStore()) throws {
        self.accountID = accountID
        self.pool = try DatabaseFactory.open(accountID: accountID, rootDirectory: rootDirectory, keyStore: keyStore)
    }

    public func close() throws { try pool.close() }

    func write<T: Sendable>(_ updates: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await pool.write { db in
            let result = try updates(db)
            try db.execute(sql: "UPDATE storage_metadata SET value = CAST(value AS INTEGER) + 1 WHERE key = 'revision'")
            return result
        }
    }

    static func validateLimit(_ limit: Int) throws {
        guard (1...500).contains(limit) else { throw StorageError.invalidArgument("limit must be 1...500") }
    }
}
