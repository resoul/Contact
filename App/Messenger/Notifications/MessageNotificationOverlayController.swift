import UIKit

/// Owns the real chat's controller lifecycle while its history stays inside the
/// original notification card, between the card's own header and composer.
final class MessageNotificationOverlayController: UIViewController {
    private let notification: MessageNotificationView
    private(set) var navigation: NotificationChatNavigationController?
    private var closing = false

    init(notification: MessageNotificationView) {
        self.notification = notification
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(notification:)") }

    override func loadView() { view = notification }

    /// Builds the history-only chat inside the card while the user is still
    /// replying, so the reveal has content from its first frame.
    func prepareChat(_ chat: Chat, home: HomeViewController) -> NotificationChatNavigationController? {
        if let navigation { return navigation }
        guard !closing, parent != nil else { return nil }
        let controller = ChatViewController(chat: chat, home: home, historyOnly: true)
        let navigation = NotificationChatNavigationController(rootViewController: controller)
        self.navigation = navigation
        navigation.onClose = { [weak notification] in notification?.dismiss() }
        addChild(navigation)
        navigation.beginAppearanceTransition(true, animated: false)
        notification.attachHistory(navigation.view)
        navigation.didMove(toParent: self)
        navigation.endAppearanceTransition()
        return navigation
    }

    func beginClosing() {
        guard !closing else { return }
        closing = true
        beginAppearanceTransition(false, animated: true)
    }

    func remove() {
        guard parent != nil else { return }
        beginClosing()
        willMove(toParent: nil)
        view.removeFromSuperview()
        endAppearanceTransition()
        removeFromParent()
    }
}

final class NotificationChatNavigationController: UINavigationController {
    var onClose: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        // The card's fluid surface shows through behind the history.
        view.backgroundColor = .clear
    }

    func close() { onClose?() }
}
