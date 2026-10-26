import UIKit
import AvatarUI

/// Application identities and fixtures stay outside the AvatarUI module.
enum AvatarProvider {
    private static var previews: [AvatarResource: UIImage] = [:]

    static func descriptor(for person: ChannelPerson, peerID: Int? = nil) -> AvatarDescriptor {
        let id = peerID.map { "peer:\($0)" } ?? "initials:\(person.name)|\(person.hue)"
        switch MessengerAvatarFixtures.media(for: person) {
        case .video: return AvatarDemoFixtures.video(id: id, person: person)
        case .photo: return AvatarDemoFixtures.photo(id: id, person: person)
        case nil: return AvatarDemoFixtures.initials(id: id, person: person)
        }
    }

    /// Static UIKit surfaces use the same bundled photo or video poster as AvatarUI.
    static func preview(for person: ChannelPerson) -> UIImage? {
        guard let resource = descriptor(for: person).image, resource.url.isFileURL else { return nil }
        if let image = previews[resource] { return image }
        guard let image = UIImage(contentsOfFile: resource.url.path) else { return nil }
        previews[resource] = image
        return image
    }

    static func gallery(for person: ChannelPerson, peerID: Int? = nil) -> [AvatarDescriptor] {
        let first = descriptor(for: person, peerID: peerID)
        guard first.image != nil else { return [first] }
        return [first, AvatarDemoFixtures.photo(id: first.id + ":photo-history", person: person),
                AvatarDemoFixtures.initials(id: first.id + ":initials", person: person)]
    }
}
