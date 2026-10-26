import Foundation

struct ChatListFolder {
    let id: String
    let title: String
    let builtin: Folder?
    let customID: UUID?

    func chats(from all: [Chat]) -> [Chat] {
        guard let builtin else { return [] }
        return all.filter { $0.belongs(to: builtin) }
    }
}

enum ChatListAdapter {
    static func folders(accountID: UUID, custom: [SessionFolder]) -> [ChatListFolder] {
        let filters: [Folder] = custom.isEmpty ? [.all] : Folder.allCases
        let prefix = accountID.uuidString
        return filters.map {
            ChatListFolder(id: "\(prefix):filter:\($0.rawValue)", title: $0.title, builtin: $0, customID: nil)
        } + custom.map {
            ChatListFolder(id: "\(prefix):folder:\($0.id.uuidString)", title: $0.name, builtin: nil, customID: $0.id)
        }
    }
}
