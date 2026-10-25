import UIKit

extension MTData {
    static let channelExamples = [
        MTChat(id: 3, person: ChannelPerson(name: "VFX Daily", hue: 0.72), kind: .channel,
               message: "Soft springs and lively interfaces 🌀", time: "19:12", unread: 4, muted: true),
        MTChat(id: 9, person: ChannelPerson(name: "Motion Lab", hue: 0.93), kind: .channel,
               message: "Why transitions should follow your finger", time: "18:40", unread: 3),
        MTChat(id: 16, person: ChannelPerson(name: "Metal Notes", hue: 0.55), kind: .channel,
               message: "Light, color, and a little shader magic ✨", time: "17:20", unread: 5, muted: true),
        MTChat(id: 17, person: ChannelPerson(name: "UI Kitchen", hue: 0.12), kind: .channel,
               message: "Building an interface from small details", time: "16:05", unread: 2),
    ]

    static func channelSections(for chat: MTChat) -> [(title: String, messages: [MTMessage])] {
        let topics: [(String, String)]
        switch chat.id {
        case 3:
            topics = [
                ("Living interfaces 🌀", "Today we explore springs. The same transition can feel heavy or light; speed and damping make all the difference."),
                ("Smooth motion", "Initial velocity carries the user’s gesture forward. When you lift your finger, the spring takes over and keeps the same direction."),
                ("A soft landing", "Not every element needs a bounce. A heading can stop smoothly, while a small reaction can hop."),
                ("Animation helps readability", "Keep an anchor point on screen. It helps the eye see where the new card came from and where the previous one went."),
                ("Today’s experiment", "Place two transition options side by side and try them with your finger. Feel often says more than settings numbers."),
                ("A quick breakdown", "The main object moves first, then the details. A short delay adds depth and keeps the focus clear."),
            ]
        case 9:
            topics = [
                ("In the motion lab", "We’re building a transition controlled by your gesture. While your finger is on screen, progress is entirely in your hands."),
                ("Threshold and feedback", "The ring shows how much farther to pull. A vibration marks when the action is ready."),
                ("It’s okay to change your mind", "Didn’t pull far enough and let go? The interface calmly returns. No unexpected transitions."),
                ("Continuity", "The next channel’s avatar becomes the header avatar. One object connects two different screens."),
                ("Rhythm", "The old feed leaves a little faster than the new one appears. Motion stays directional without feeling abrupt."),
                ("Try it yourself", "Try a quick flick, a slow pull, and a return before the threshold. A good gesture feels clear every time."),
            ]
        case 16:
            topics = [
                ("Metal notes ✨", "A shader gets a pixel coordinate and decides which color to show. Light, glass, and smoke grow from this simple rule."),
                ("Shapes from distance", "An SDF describes the distance to an edge. Change this field to merge circles into a soft, fluid shape."),
                ("Color and transparency", "Transparency looks more convincing when it accounts for the background. Check the effect in both light and dark themes."),
                ("Edge lighting", "A subtle highlight helps show depth. Too bright distracts from text; too wide obscures the shape."),
                ("Frame budget", "Stop rendering when the effect isn’t visible. A still screen shouldn’t keep calculating animation."),
                ("Golden reaction", "Hold ⭐ under a post: golden fluid fills the reaction, the counter speeds up, and sparks fly when you let go."),
            ]
        default:
            topics = [
                ("In the interface kitchen", "Start with the basics: a clear heading, readable text, and enough space between posts."),
                ("Hierarchy", "Size and contrast guide reading order. The main idea should come before decorative details."),
                ("Touch targets", "A small icon can have a large tap area. This matters especially for actions near the screen edge."),
                ("States", "Every action has a start, a wait, and a result. Show them in order to keep the interface clear."),
                ("Theme", "A dark theme needs its own palette. Simply inverting colors won’t create a calm background and readable text."),
                ("Putting it all together", "Channels are in the main list. Pull up at the bottom of the feed; the ring shows when to move to the next one."),
            ]
        }
        let scenes: [DemoPhotos.Scene] = [.city, .sunset, .ocean]
        let messages = topics.enumerated().map { index, topic -> MTMessage in
            let body = "\(topic.0)\n\n\(topic.1)"
            let time = String(format: "%02d:10", 10 + index)
            var message = MTMessage(kind: .text(body), outgoing: false, time: time)
            message.channelPost = ChannelPost(
                image: index == 1 || index == 4 ? scenes[index % scenes.count] : nil,
                quote: index == 2 ? "From the editors’ notes «\(chat.person.name)»" : nil,
                body: body, reactions: [ChannelReaction(emoji: "⭐", count: 12 + index * 7),
                                       ChannelReaction(emoji: "❤️", count: 48 + index * 11),
                                       ChannelReaction(emoji: "🔥", count: 16 + index * 3),
                                       ChannelReaction(emoji: "👍", count: 9 + index)],
                views: 1240 + index * 803, time: time, comments: 18 + index * 9,
                commenters: Array(trickPeople.dropFirst(index).prefix(3)))
            return message
        }
        return [("Today", messages)]
    }
}
