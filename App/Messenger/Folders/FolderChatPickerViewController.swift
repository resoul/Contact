import UIKit

/// Telegram's "Chats in Folder" / "Excluded Chats" picker: whole types on top,
/// then every chat with a round check. Works on a copy until Done.
final class FolderChatPickerViewController: UITableViewController, UISearchResultsUpdating {
    enum Mode { case include, exclude }

    private let mode: Mode
    private var folder: ChatFolder
    private let chats: [Chat]
    private var shown: [Chat]
    private let onDone: (ChatFolder) -> Void
    private let search = UISearchController(searchResultsController: nil)

    init(mode: Mode, folder: ChatFolder, chats: [Chat], onDone: @escaping (ChatFolder) -> Void) {
        self.mode = mode
        self.folder = folder
        self.chats = chats
        shown = chats
        self.onDone = onDone
        super.init(style: .plain)
        title = mode == .include ? "Chats in Folder" : "Excluded Chats"
    }

    required init?(coder: NSCoder) { fatalError("Use init(mode:folder:chats:onDone:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = mode == .include ? "contact.folderIncludePicker" : "contact.folderExcludePicker"
        tableView.backgroundColor = Palette.background
        tableView.rowHeight = 56
        tableView.keyboardDismissMode = .onDrag
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search Chats"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func done() {
        onDone(folder)
        dismiss(animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
        shown = query.isEmpty ? chats : chats.filter { $0.person.name.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
    }

    private var searching: Bool { !(search.searchBar.text ?? "").isEmpty }
    private var typeCount: Int {
        if searching { return 0 }
        return mode == .include ? ChatFolderType.allCases.count : ChatFolderExclusion.allCases.count
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? typeCount : shown.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return typeCount == 0 ? nil : "Chat Types" }
        return shown.isEmpty ? nil : "Chats"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Palette.background
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = Palette.text
        content.imageProperties.maximumSize = CGSize(width: 36, height: 36)
        content.imageToTextPadding = 14
        let selected: Bool
        if indexPath.section == 0 {
            if mode == .include {
                let type = ChatFolderType.allCases[indexPath.row]
                content.text = type.title
                content.image = FolderIcons.badge(type.symbol, color: type.color, size: 36)
                selected = folder.types.contains(type)
            } else {
                let exclusion = ChatFolderExclusion.allCases[indexPath.row]
                content.text = exclusion.title
                content.image = FolderIcons.badge(exclusion.symbol, color: exclusion.color, size: 36)
                selected = folder.exclusions.contains(exclusion)
            }
        } else {
            let chat = shown[indexPath.row]
            content.text = chat.person.name
            content.image = ChannelAvatar.image(for: chat.person, size: 36)
            content.imageProperties.cornerRadius = 18
            selected = mode == .include ? folder.included.contains(chat.id) : folder.excluded.contains(chat.id)
        }
        cell.contentConfiguration = content
        let check = UIImageView(image: UIImage(systemName: selected ? "checkmark.circle.fill" : "circle",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)))
        check.tintColor = selected ? Palette.accent : Palette.muted
        cell.accessoryView = check
        cell.accessibilityTraits = selected ? [.button, .selected] : .button
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if indexPath.section == 0 {
            if mode == .include { folder.types.formSymmetricDifference([ChatFolderType.allCases[indexPath.row]]) }
            else { folder.exclusions.formSymmetricDifference([ChatFolderExclusion.allCases[indexPath.row]]) }
        } else {
            // A chat is either always included or always excluded, never both.
            let id = shown[indexPath.row].id
            if mode == .include {
                folder.excluded.remove(id)
                folder.included.formSymmetricDifference([id])
            } else {
                folder.included.remove(id)
                folder.excluded.formSymmetricDifference([id])
            }
        }
        UISelectionFeedbackGenerator().selectionChanged()
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
