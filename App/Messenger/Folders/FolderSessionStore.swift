import Foundation

struct SessionFolder: Identifiable {
    let id: UUID
    let name: String
}

/// Process-local state shared by scenes; never written to defaults or account databases.
@MainActor
final class FolderSessionStore {
    static let shared = FolderSessionStore()
    static let didChange = Notification.Name("Contact.SessionFoldersDidChange")
    private var accounts: [UUID: [SessionFolder]] = [:]

    func folders(for accountID: UUID) -> [SessionFolder] { accounts[accountID] ?? [] }

    @discardableResult
    func create(name: String, accountID: UUID) -> SessionFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = SessionFolder(id: UUID(), name: trimmed)
        accounts[accountID, default: []].append(folder)
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["accountID": accountID])
        return folder
    }
}
