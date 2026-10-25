import Foundation
import GRDB

struct PeerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "peers"
    var id: Int64
    var kind: PeerKind
    var display_name: String
    var username: String?
    var presentation: Data?
    init(_ peer: StoragePeer) { id = peer.id; kind = peer.kind; display_name = peer.displayName; username = peer.username; presentation = peer.presentation }
    var value: StoragePeer { StoragePeer(id: id, kind: kind, displayName: display_name, username: username, presentation: presentation) }
}

struct MessageRecord: Decodable, FetchableRecord {
    var local_id: String
    var peer_id: Int64
    var server_id: Int64?
    var timestamp: Int64
    var text: String
    var is_outgoing: Bool
    var is_unread: Bool
    var state: MessageState
    var edited_at: Int64?
    var presentation: Data?
    func value() throws -> StoredMessage {
        guard let id = UUID(uuidString: local_id) else { throw StorageError.invalidRecord }
        return StoredMessage(localID: id, peerID: peer_id, serverID: server_id, timestamp: timestamp, text: text,
                             isOutgoing: is_outgoing, isUnread: is_unread, state: state, editedAt: edited_at, presentation: presentation)
    }
}
