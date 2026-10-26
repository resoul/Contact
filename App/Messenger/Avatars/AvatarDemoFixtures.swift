import UIKit
import AvatarUI

enum AvatarDemoFixtures {
    static let person = ChannelPerson(name: "Avatar Demo", hue: 0.55)
    private static func resource(_ name: String, _ ext: String) -> AvatarResource? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return AvatarResource(id: name, url: url)
    }
    static func initials(id: String = "demo:initials", person: ChannelPerson = person) -> AvatarDescriptor {
        AvatarDescriptor(id: id, initials: person.initials, colors: colors(person))
    }
    static func photo(id: String = "demo:photo", person: ChannelPerson = person) -> AvatarDescriptor {
        AvatarDescriptor(id: id, initials: person.initials, colors: colors(person),
                         image: resource("avatar-demo-photo", "jpg"))
    }
    static func video(id: String = "demo:video", person: ChannelPerson = person) -> AvatarDescriptor {
        AvatarDescriptor(id: id, initials: person.initials, colors: colors(person),
                         image: resource("avatar-demo-poster", "jpg"),
                         video: resource("avatar-demo-video", "mp4").map { AvatarVideo(resource: $0) },
                         thumbnailVideo: resource("avatar-demo-video-small", "mp4").map { AvatarVideo(resource: $0) })
    }
    static func colors(_ person: ChannelPerson) -> [UIColor] {
        [UIColor(hue: person.hue, saturation: 0.55, brightness: 0.98, alpha: 1),
         UIColor(hue: person.hue + 0.06, saturation: 0.75, brightness: 0.78, alpha: 1)]
    }
}
