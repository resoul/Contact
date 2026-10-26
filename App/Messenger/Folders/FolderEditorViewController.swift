import UIKit

/// Creates or edits one folder like Telegram's folder screen: name with an icon,
/// included chats and types, excluded chats and types, and a colour. Telegram
/// keeps the colour behind Premium; here every colour is available.
final class FolderEditorViewController: UITableViewController, UITextFieldDelegate {
    private enum Section: Int, CaseIterable { case name, included, excluded, color, delete }
    /// A row of the included or excluded list.
    private enum Entry {
        case add
        case type(ChatFolderType)
        case exclusion(ChatFolderExclusion)
        case chat(Chat)
    }

    private weak var session: AccountSession?
    private var folder: ChatFolder
    private let isNew: Bool
    private let onCreated: ((UUID) -> Void)?
    private let chats: [Chat]
    private let nameField = UITextField()
    private let emojiButton = UIButton(type: .system)
    private let headerIcon = UIImageView()
    private var colorButtons: [UIButton] = []
    private var saving = false
    /// The name follows a single chosen type until the user types one, as in Telegram.
    private var nameEdited: Bool

    init(session: AccountSession, folder: ChatFolder, isNew: Bool = false, onCreated: ((UUID) -> Void)? = nil) {
        self.session = session
        self.folder = folder
        self.isNew = isNew
        self.onCreated = onCreated
        nameEdited = !folder.name.isEmpty
        chats = session.chats
        super.init(style: .insetGrouped)
        title = isNew ? "New Folder" : "Edit Folder"
    }

    required init?(coder: NSCoder) { fatalError("Use init(session:folder:isNew:onCreated:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "contact.folderEditor"
        tableView.backgroundColor = Palette.grouped
        tableView.keyboardDismissMode = .onDrag
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(finish))
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(save))
        // A half-made folder is not thrown away by an accidental swipe.
        isModalInPresentation = true

        let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 120))
        headerIcon.contentMode = .center
        headerIcon.frame = header.bounds
        headerIcon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        header.addSubview(headerIcon)
        tableView.tableHeaderView = header

        nameField.text = folder.name
        nameField.placeholder = "Folder Name"
        nameField.font = .systemFont(ofSize: 17)
        nameField.returnKeyType = .done
        nameField.accessibilityIdentifier = "contact.folderEditorName"
        nameField.delegate = self
        nameField.addAction(UIAction { [weak self] _ in self?.nameChanged() }, for: .editingChanged)
        emojiButton.tintColor = Palette.secondary
        emojiButton.accessibilityLabel = "Folder icon"
        emojiButton.addAction(UIAction { [weak self] _ in self?.pickEmoji() }, for: .touchUpInside)
        updateStyle()
        updateSave()
    }

    // MARK: State

    private func nameChanged() {
        folder.name = nameField.text ?? ""
        nameEdited = !folder.name.isEmpty
        updateSave()
    }

    private func updateSave() {
        let named = !folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !saving && named && !folder.isEmpty
    }

    private func updateStyle() {
        headerIcon.image = FolderIcons.folder(folder, size: 84)
        if let emoji = folder.emoji { emojiButton.setImage(FolderIcons.emoji(emoji, size: 26).withRenderingMode(.alwaysOriginal), for: .normal) }
        else { emojiButton.setImage(UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal) }
        for (button, index) in zip(colorButtons, ChatFolder.colorOrder) { styleColor(button, selected: folder.color == index) }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    private func entries(_ section: Section) -> [Entry] {
        switch section {
        case .included:
            return [.add] + ChatFolderType.allCases.filter(folder.types.contains).map(Entry.type)
                + chats.filter { folder.included.contains($0.id) }.map(Entry.chat)
        case .excluded:
            return [.add] + ChatFolderExclusion.allCases.filter(folder.exclusions.contains).map(Entry.exclusion)
                + chats.filter { folder.excluded.contains($0.id) }.map(Entry.chat)
        default: return []
        }
    }

    private func openPicker(_ mode: FolderChatPickerViewController.Mode) {
        view.endEditing(true)
        let picker = FolderChatPickerViewController(mode: mode, folder: folder, chats: chats) { [weak self] updated in
            guard let self else { return }
            self.folder = updated
            // Telegram names a folder after its only type until a name is typed.
            if !self.nameEdited {
                let type = updated.included.isEmpty && updated.types.count == 1 ? updated.types.first : nil
                self.folder.name = type?.title ?? ""
                self.nameField.text = self.folder.name
            }
            UIView.performWithoutAnimation {
                self.tableView.reloadSections(IndexSet([Section.included.rawValue, Section.excluded.rawValue]), with: .none)
            }
            self.updateSave()
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func pickEmoji() {
        let picker = FolderEmojiPickerViewController(selected: folder.emoji) { [weak self] emoji in
            self?.folder.emoji = emoji
            self?.updateStyle()
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        present(navigation, animated: true)
    }

    private func selectColor(_ index: Int) {
        folder.color = folder.color == index ? nil : index
        UISelectionFeedbackGenerator().selectionChanged()
        updateStyle()
    }

    @objc private func save() {
        guard let session else { return }
        view.endEditing(true)
        folder.name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        updateSave()
        let failed: () -> Void = { [weak self] in
            self?.saving = false
            self?.updateSave()
        }
        if isNew {
            let id = folder.id
            session.createFolder(folder, onFailure: failed) { [weak self] in
                let created = self?.onCreated
                self?.finish()
                created?(id)
            }
        } else {
            session.saveFolder(folder, onFailure: failed) { [weak self] in self?.finish() }
        }
    }

    @objc private func finish() {
        if navigationController?.viewControllers.first === self { dismiss(animated: true) }
        else { navigationController?.popViewController(animated: true) }
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "Delete “\(folder.name)”?", message: "Chats in this folder are not deleted.",
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete Folder", style: .destructive) { [weak self] _ in
            guard let self, let session = self.session else { return }
            session.deleteFolder(id: self.folder.id) { [weak self] in self?.finish() }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count - (isNew ? 1 : 0) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .name, .color, .delete: return 1
        case .included, .excluded: return entries(Section(rawValue: section)!).count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .name: return "Folder Name"
        case .included: return "Included Chats"
        case .excluded: return "Excluded Chats"
        case .color: return "Folder Color"
        case .delete: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .included: return "Choose chats or types of chats that will appear in this folder."
        case .excluded: return "Choose chats or types of chats that will never appear in this folder."
        case .color: return "This color is used for the folder's icon."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Palette.cell
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = Palette.text
        content.imageProperties.maximumSize = CGSize(width: 30, height: 30)
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .name:
            cell.selectionStyle = .none
            nameField.frame = cell.contentView.bounds.inset(by: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 52))
            nameField.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            emojiButton.frame = CGRect(x: cell.contentView.bounds.width - 48, y: 0, width: 44, height: cell.contentView.bounds.height)
            emojiButton.autoresizingMask = [.flexibleLeftMargin, .flexibleHeight]
            cell.contentView.addSubview(nameField)
            cell.contentView.addSubview(emojiButton)
            return cell
        case .included, .excluded:
            switch entries(section)[indexPath.row] {
            case .add:
                content.text = section == .included ? "Add Chats" : "Add Chats to Exclude"
                content.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))
                content.imageProperties.tintColor = Palette.accent
                content.textProperties.color = Palette.accent
                cell.accessibilityIdentifier = section == .included ? "contact.folderAddIncluded" : "contact.folderAddExcluded"
            case .type(let type):
                content.text = type.title
                content.image = FolderIcons.badge(type.symbol, color: type.color)
            case .exclusion(let exclusion):
                content.text = exclusion.title
                content.image = FolderIcons.badge(exclusion.symbol, color: exclusion.color)
            case .chat(let chat):
                content.text = chat.person.name
                content.image = ChannelAvatar.image(for: chat.person, size: 30)
                content.imageProperties.cornerRadius = 15
            }
        case .color:
            cell.selectionStyle = .none
            cell.contentView.addSubview(colorPalette(width: tableView.bounds.width - 40))
            return cell
        case .delete:
            content.text = "Delete Folder"
            content.textProperties.color = Palette.red
            content.textProperties.alignment = .center
            cell.accessibilityIdentifier = "contact.folderDelete"
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        Section(rawValue: indexPath.section) == .color ? 64 : 52
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .name: nameField.becomeFirstResponder()
        case .included, .excluded:
            guard case .add = entries(section)[indexPath.row] else { return }
            openPicker(section == .included ? .include : .exclude)
        case .delete: confirmDelete()
        case .color: break
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard let section = Section(rawValue: indexPath.section), section == .included || section == .excluded else { return nil }
        let entry = entries(section)[indexPath.row]
        if case .add = entry { return nil }
        let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            guard let self else { return done(false) }
            switch entry {
            case .type(let type): self.folder.types.remove(type)
            case .exclusion(let exclusion): self.folder.exclusions.remove(exclusion)
            case .chat(let chat):
                if section == .included { self.folder.included.remove(chat.id) } else { self.folder.excluded.remove(chat.id) }
            case .add: break
            }
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.updateSave()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }

    // MARK: Colour palette

    private func colorPalette(width: CGFloat) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.frame = CGRect(x: 20, y: 12, width: max(0, width - 20), height: 40)
        stack.autoresizingMask = [.flexibleWidth]
        colorButtons = ChatFolder.colorOrder.map { index in
            let button = UIButton(type: .custom)
            button.backgroundColor = ChatFolder.colors[index]
            button.layer.cornerRadius = 20
            button.accessibilityLabel = "Color \(index + 1)"
            button.addAction(UIAction { [weak self] _ in self?.selectColor(index) }, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 40).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            stack.addArrangedSubview(button)
            return button
        }
        updateStyle()
        return stack
    }

    /// The selected colour gets Telegram's ring: a gap in the cell colour, then the colour.
    private func styleColor(_ button: UIButton, selected: Bool) {
        button.layer.borderWidth = selected ? 3 : 0
        button.layer.borderColor = Palette.cell.resolvedColor(with: traitCollection).cgColor
        button.layer.shadowColor = button.backgroundColor?.cgColor
        button.layer.shadowOpacity = selected ? 1 : 0
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = .zero
        button.layer.shadowPath = selected ? UIBezierPath(ovalIn: CGRect(x: -2.5, y: -2.5, width: 45, height: 45)).cgPath : nil
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
