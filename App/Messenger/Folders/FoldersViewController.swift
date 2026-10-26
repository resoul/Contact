import UIKit

/// Settings → Chat Folders, as in Telegram: create a folder, tap one to edit it,
/// and use Edit to delete folders or reorder them. All Chats can be moved among the
/// folders but not deleted. Everything is stored in the account database.
final class FoldersViewController: UITableViewController {
    /// A row below Create Folder, in the order of the chat list's tabs.
    private enum Slot {
        case allChats
        case folder(ChatFolder)
    }

    private weak var session: AccountSession?
    private var slots: [Slot] = []

    init(session: AccountSession) {
        self.session = session
        super.init(style: .insetGrouped)
        title = "Chat Folders"
    }

    required init?(coder: NSCoder) { fatalError("Use init(session:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "contact.folderSettings"
        tableView.backgroundColor = Palette.grouped
        tableView.rowHeight = 52
        navigationItem.rightBarButtonItem = editButtonItem
        let header = UIView()
        let icon = Views.label("🗂️", size: 80)
        icon.textAlignment = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(icon)
        let description = Views.label("Create folders for different groups of chats and quickly switch between them.",
                                      size: 15, color: Palette.secondary)
        description.numberOfLines = 0
        description.textAlignment = .center
        description.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(description)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: header.topAnchor, constant: 24),
            icon.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            icon.heightAnchor.constraint(equalToConstant: 108),
            description.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 20),
            description.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32),
            description.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -32),
            description.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor, constant: -16),
        ])
        header.frame.size.height = 220
        tableView.tableHeaderView = header
        NotificationCenter.default.addObserver(self, selector: #selector(foldersChanged),
                                               name: AccountSession.foldersDidChange, object: session)
        reloadFolders()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView, header.frame.width != tableView.bounds.width else { return }
        header.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = header
    }

    private func reloadFolders() {
        var slots = (session?.folders ?? []).map(Slot.folder)
        slots.insert(.allChats, at: min(session?.allChatsPosition ?? 0, slots.count))
        self.slots = slots
        tableView.reloadData()
        // Nothing to reorder or delete without folders.
        if slots.count < 2, isEditing { setEditing(false, animated: true) }
        editButtonItem.isEnabled = slots.count > 1
    }

    @objc private func foldersChanged() { reloadFolders() }

    private func saveOrder() {
        var ids: [UUID] = []
        var allChatsPosition = 0
        for slot in slots {
            switch slot {
            case .allChats: allChatsPosition = ids.count
            case .folder(let folder): ids.append(folder.id)
            }
        }
        session?.reorderFolders(ids, allChatsPosition: allChatsPosition)
    }

    private func confirmDelete(_ folder: ChatFolder) {
        let alert = UIAlertController(title: "Delete “\(folder.name)”?", message: "Chats in this folder are not deleted.",
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete Folder", style: .destructive) { [weak self] _ in
            self?.session?.deleteFolder(id: folder.id)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { slots.count + 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "Folders" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        slots.count > 1 ? "Tap Edit to delete folders or change their order. All Chats can be moved but not deleted." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Palette.cell
        var content = cell.defaultContentConfiguration()
        content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        if indexPath.row == 0 {
            content.text = "Create Folder"
            content.image = UIImage(systemName: "folder.badge.plus")
            content.textProperties.color = Palette.accent
            content.imageProperties.tintColor = Palette.accent
            cell.accessibilityIdentifier = "contact.createFolder"
        } else {
            content.textProperties.color = Palette.text
            switch slots[indexPath.row - 1] {
            case .allChats:
                content.text = "All Chats"
                content.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")
                content.imageProperties.tintColor = Palette.accent
                cell.selectionStyle = .none
                cell.accessibilityIdentifier = "contact.folderAllChats"
            case .folder(let folder):
                content.text = folder.name
                content.image = FolderIcons.folder(folder, size: 28)
                if let session {
                    let count = session.chats.filter(folder.contains).count
                    content.secondaryText = count == 0 ? "Empty" : "\(count)"
                }
                cell.accessoryType = .disclosureIndicator
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let session else { return }
        if indexPath.row == 0 {
            FolderCreation.present(from: self, session: session)
        } else if case .folder(let folder) = slots[indexPath.row - 1] {
            navigationController?.pushViewController(FolderEditorViewController(session: session, folder: folder), animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { indexPath.row > 0 }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { indexPath.row > 0 }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard indexPath.row > 0, case .folder = slots[indexPath.row - 1] else { return .none }
        return .delete
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { true }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, case .folder(let folder) = slots[indexPath.row - 1] else { return }
        confirmDelete(folder)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt source: IndexPath,
        toProposedIndexPath proposed: IndexPath
    ) -> IndexPath {
        proposed.row < 1 ? IndexPath(row: 1, section: 0) : proposed
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let slot = slots.remove(at: source.row - 1)
        slots.insert(slot, at: destination.row - 1)
        saveOrder()
    }
}
