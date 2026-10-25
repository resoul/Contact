import UIKit

/// Folder names only. Chat membership and editing are intentionally deferred.
final class FoldersViewController: UITableViewController {
    private let accountID: UUID
    private let openFolder: (UUID?) -> Void
    private var folders: [SessionFolder] = []

    init(accountID: UUID, openFolder: @escaping (UUID?) -> Void) {
        self.accountID = accountID
        self.openFolder = openFolder
        super.init(style: .insetGrouped)
        title = "Chat Folders"
    }

    required init?(coder: NSCoder) { fatalError("Use init(accountID:openFolder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "contact.folderSettings"
        tableView.backgroundColor = Palette.grouped
        tableView.rowHeight = 52
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        let header = UIView()
        let icon = Views.label("🗂️", size: 80)
        icon.textAlignment = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(icon)
        let description = Views.label("Create folders and switch between them in Chats.", size: 15, color: Palette.secondary)
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
        NotificationCenter.default.addObserver(self, selector: #selector(foldersChanged(_:)),
                                               name: FolderSessionStore.didChange, object: FolderSessionStore.shared)
        reloadFolders()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView, header.frame.width != tableView.bounds.width else { return }
        header.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = header
    }

    private func reloadFolders() {
        folders = FolderSessionStore.shared.folders(for: accountID)
        tableView.reloadData()
    }

    @objc private func foldersChanged(_ notification: Notification) {
        guard notification.userInfo?["accountID"] as? UUID == accountID else { return }
        reloadFolders()
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { folders.count + 2 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "Folders" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "New folders are empty for now. They are kept until the app restarts."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Palette.cell
        var content = cell.defaultContentConfiguration()
        if indexPath.row == 0 {
            content.text = "Create Folder"
            content.image = UIImage(systemName: "folder.badge.plus")
            content.textProperties.color = Palette.accent
            content.imageProperties.tintColor = Palette.accent
            cell.accessibilityIdentifier = "contact.createFolder"
        } else {
            content.text = indexPath.row == 1 ? "All Chats" : folders[indexPath.row - 2].name
            content.image = UIImage(systemName: indexPath.row == 1 ? "bubble.left.and.bubble.right" : "folder")
            content.textProperties.color = Palette.text
            content.imageProperties.tintColor = Palette.accent
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            FolderCreation.present(from: self, accountID: accountID) { [weak self] folder in
                guard let self, let index = self.folders.firstIndex(where: { $0.id == folder.id }) else { return }
                self.tableView.scrollToRow(at: IndexPath(row: index + 2, section: 0), at: .middle, animated: true)
            }
        } else {
            let id = indexPath.row == 1 ? nil : folders[indexPath.row - 2].id
            dismiss(animated: true) { [openFolder] in openFolder(id) }
        }
    }
}
