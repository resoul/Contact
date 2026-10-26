import UIKit

@MainActor
enum FolderCreation {
    static func present(
        from presenter: UIViewController,
        accountID: UUID,
        created: @escaping (SessionFolder) -> Void = { _ in }
    ) {
        let alert = UIAlertController(title: "New Folder", message: "Enter a name for your folder.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Folder name"
            field.autocapitalizationType = .sentences
            field.returnKeyType = .done
            field.enablesReturnKeyAutomatically = true
            field.accessibilityIdentifier = "contact.folderName"
        }
        let create = UIAlertAction(title: "Create", style: .default) { [weak alert] _ in
            guard let name = alert?.textFields?.first?.text,
                  let folder = FolderSessionStore.shared.create(name: name, accountID: accountID) else { return }
            created(folder)
        }
        create.isEnabled = false
        alert.textFields?.first?.addAction(UIAction { [weak alert, weak create] _ in
            let text = alert?.textFields?.first?.text ?? ""
            create?.isEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }, for: .editingChanged)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(create)
        alert.preferredAction = create
        presenter.present(alert, animated: true)
    }
}
