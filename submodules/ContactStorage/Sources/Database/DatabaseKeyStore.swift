import Foundation
import Security

/// Implementations must be thread safe. Production uses Keychain; injection is for verification.
public protocol DatabaseKeyStore: Sendable {
    func readKey(for accountID: AccountID) throws -> Data?
    func createKeyIfAbsent(for accountID: AccountID) throws -> Data
}

public struct KeychainDatabaseKeyStore: DatabaseKeyStore {
    private let service: String
    public init(service: String = "org.airlance.Contact.database") { self.service = service }

    private func query(_ id: AccountID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.directoryName,
         kSecAttrSynchronizable as String: false]
    }

    public func readKey(for accountID: AccountID) throws -> Data? {
        var request = query(accountID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
        guard let key = result as? Data, key.count == 32 else { throw StorageError.invalidKeyLength }
        return key
    }

    public func createKeyIfAbsent(for accountID: AccountID) throws -> Data {
        if let key = try readKey(for: accountID) { return key }
        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw StorageError.randomGenerationFailed(randomStatus) }
        let key = Data(bytes)
        var request = query(accountID)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        request[kSecValueData as String] = key
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard let existing = try readKey(for: accountID) else { throw StorageError.keychain(status) }
            return existing
        }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
        return key
    }
}
