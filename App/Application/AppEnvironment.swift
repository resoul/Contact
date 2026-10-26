import Foundation
import ContactStorage
import OSLog

actor AppEnvironment {
    static let shared = AppEnvironment()
    private var accounts: [AccountID: AccountContext] = [:]

    func accountContext(for id: AccountID) throws -> AccountContext {
        if let context = accounts[id] { return context }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let storage: AccountStorage
        do {
            storage = try AccountStorage(accountID: id, rootDirectory: support.appendingPathComponent("Contact/Accounts", isDirectory: true))
        } catch {
            let logger = Logger(subsystem: "org.airlance.Contact", category: "Storage")
            if case let StorageError.keychain(status) = error {
                logger.error("Opening account storage failed: Keychain status \(status)")
            } else {
                let nsError = error as NSError
                logger.error("Opening account storage failed: \(nsError.domain, privacy: .public) / \(nsError.code)")
            }
            throw error
        }
        let context = AccountContext(id: id, storage: storage)
        accounts[id] = context
        return context
    }
}
