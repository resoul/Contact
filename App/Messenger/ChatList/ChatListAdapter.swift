import Foundation

/// One tab of the chat list: All Chats (`custom == nil`) or a user folder.
struct ChatListFolder {
    let id: String
    let title: String
    let custom: ChatFolder?

    var customID: UUID? { custom?.id }

    func chats(from all: [Chat]) -> [Chat] {
        guard let custom else { return all }
        return all.filter(custom.contains)
    }
}

enum ChatListAdapter {
    /// All Chats alone, or All Chats at its saved place among the user's folders.
    static func folders(accountID: UUID, custom: [ChatFolder], allChatsPosition: Int) -> [ChatListFolder] {
        let prefix = accountID.uuidString
        var result = custom.map {
            ChatListFolder(id: "\(prefix):folder:\($0.id.uuidString)", title: $0.name, custom: $0)
        }
        let all = ChatListFolder(id: "\(prefix):all", title: "All Chats", custom: nil)
        result.insert(all, at: min(max(allChatsPosition, 0), result.count))
        return result
    }
}
