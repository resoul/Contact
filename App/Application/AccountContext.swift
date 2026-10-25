import ContactStorage

final class AccountContext: Sendable {
    let id: AccountID
    let storage: AccountStorage
    init(id: AccountID, storage: AccountStorage) { self.id = id; self.storage = storage }
}
