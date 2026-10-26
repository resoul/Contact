import UIKit

protocol AvatarPlaybackParticipant: AnyObject {
    var wantsAvatarPlayback: Bool { get }
    var avatarPlaybackPriority: Int { get }
    func setAvatarPlaybackAllowed(_ allowed: Bool)
}

private final class WeakAvatarParticipant {
    weak var value: (any AvatarPlaybackParticipant)?
    let order: Int
    init(_ value: any AvatarPlaybackParticipant, order: Int) { self.value = value; self.order = order }
}

/// UI-facing methods are called on the main thread. Only one visible avatar owns playback.
public final class AvatarPlaybackCoordinator: NSObject {
    public static let shared = AvatarPlaybackCoordinator()
    public var respectsLowPowerMode = true { didSet { update() } }
    public var respectsReduceMotion = true { didSet { update() } }
    private var participants: [ObjectIdentifier: WeakAvatarParticipant] = [:]
    private var nextOrder = 0
    private var active = true

    public override init() {
        super.init()
        for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification,
                     Notification.Name.NSProcessInfoPowerStateDidChange, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: name, object: nil)
        }
    }

    func register(_ participant: any AvatarPlaybackParticipant) {
        nextOrder += 1
        participants[ObjectIdentifier(participant)] = WeakAvatarParticipant(participant, order: nextOrder)
        update()
    }
    func unregister(_ participant: any AvatarPlaybackParticipant) {
        participants.removeValue(forKey: ObjectIdentifier(participant))
        participant.setAvatarPlaybackAllowed(false)
        update()
    }
    func update() {
        participants = participants.filter { $0.value.value != nil }
        let enabled = active && UIApplication.shared.applicationState == .active
            && !(respectsLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled)
            && !(respectsReduceMotion && UIAccessibility.isReduceMotionEnabled)
        let candidates = participants.values.filter { $0.value?.wantsAvatarPlayback == true }
        let winner = enabled ? candidates.max {
            let left = $0.value?.avatarPlaybackPriority ?? 0, right = $1.value?.avatarPlaybackPriority ?? 0
            return left == right ? $0.order < $1.order : left < right
        }?.value : nil
        // Pause previous owners before starting the selected one.
        for item in participants.values where item.value !== winner { item.value?.setAvatarPlaybackAllowed(false) }
        winner?.setAvatarPlaybackAllowed(true)
    }
    @objc private func changed(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if notification.name == UIApplication.willResignActiveNotification { self.active = false }
            if notification.name == UIApplication.didBecomeActiveNotification { self.active = true }
            self.update()
        }
    }
}
