import UIKit

@MainActor
enum FolderCreation {
    /// Opens the folder editor for a new folder, as Telegram does; it is stored
    /// in the account only when saved with a name and at least one chat or type.
    static func present(
        from presenter: UIViewController,
        session: AccountSession,
        created: @escaping (UUID) -> Void = { _ in }
    ) {
        let editor = FolderEditorViewController(session: session, folder: ChatFolder(name: ""), isNew: true, onCreated: created)
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .pageSheet
        presenter.present(navigation, animated: true)
    }
}
