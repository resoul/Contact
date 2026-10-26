//
//  OtherPages.swift
//  controller
//
//  Mini-Telegram's other tabs: Contacts, Calls (all / missed on a liquid segment) and Settings,
//  which shows the account list once there is more than one account, the passcode switch, and
//  the sun/moon button that floods the app with the other theme.
//

import UIKit

/// A page with a simple blurred title bar over a table.
class TablePage: Page, UITableViewDataSource, UITableViewDelegate {
    let table = UITableView(frame: .zero, style: .plain)
    let bar = UIView()
    private let barBackground = Views.barBackground()
    let titleLabel = Views.label(size: 17, weight: .semibold)
    var barExtra: CGFloat { 0 }

    override func viewDidLoad() {
        super.viewDidLoad()
        table.backgroundColor = Palette.background
        table.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 0)
        table.separatorColor = Palette.separator
        table.contentInsetAdjustmentBehavior = .never
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 64
        view.addSubview(table)
        view.addSubview(bar)
        bar.addSubview(barBackground)
        titleLabel.textAlignment = .center
        bar.addSubview(titleLabel)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        bar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: top + 44 + barExtra)
        barBackground.frame = bar.bounds
        titleLabel.frame = CGRect(x: 60, y: top, width: view.bounds.width - 120, height: 44)
        table.frame = view.bounds
        table.contentInset = UIEdgeInsets(top: bar.frame.height, left: 0, bottom: home?.bottomInset ?? 0, right: 0)
        table.verticalScrollIndicatorInsets = table.contentInset
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { UITableViewCell() }

    /// A cell with an avatar, a title and a subtitle.
    func personCell(
        _ person: ChannelPerson,
        title: String? = nil,
        subtitle: String,
        subtitleColor: UIColor = Palette.secondary,
        titleColor: UIColor = Palette.text,
        online: Bool = false
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Palette.background
        var content = cell.defaultContentConfiguration()
        content.text = title ?? person.name
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.textProperties.color = titleColor
        content.secondaryText = subtitle
        content.secondaryTextProperties.color = subtitleColor
        content.secondaryTextProperties.font = .systemFont(ofSize: 14)
        content.image = ChannelAvatar.image(for: person, size: 46)
        content.imageProperties.maximumSize = CGSize(width: 46, height: 46)
        content.imageToTextPadding = 14
        cell.contentConfiguration = content
        if online {
            let dot = UIView(frame: CGRect(x: 51, y: 44, width: 13, height: 13))
            dot.backgroundColor = Palette.online
            dot.layer.cornerRadius = 6.5
            dot.layer.borderWidth = 2
            dot.layer.borderColor = Palette.background.resolvedColor(with: traitCollection).cgColor
            cell.contentView.addSubview(dot)
        }
        return cell
    }
}

// MARK: - Contacts

final class ContactsPage: TablePage {
    private let people = trickPeople.sorted { $0.name < $1.name }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = "Contacts"
        table.accessibilityIdentifier = "contact.contacts"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { people.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let person = people[indexPath.row]
        let online = indexPath.row % 3 == 0
        return personCell(person, subtitle: online ? "online" : "last seen \(indexPath.row + 2) min ago",
                          subtitleColor: online ? Palette.accent : Palette.secondary, online: online)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        home?.openChat(with: people[indexPath.row])
    }
}

// MARK: - Calls

final class CallsPage: TablePage {
    private struct Call {
        let person: ChannelPerson
        let kind: Int   // 0 incoming, 1 outgoing, 2 missed
        let video: Bool
        let time: String
    }

    private let all: [Call] = trickPeople.enumerated().map { index, person in
        Call(person: person, kind: index % 3 == 2 ? 2 : index % 2, video: index % 4 == 1,
             time: ["21:10", "19:42", "Yesterday", "Yesterday", "Mon", "Sun", "Sat", "12.10", "10.10", "08.10"][index])
    }
    private var shown: [Call] = []
    private let segment = LiquidSelector(titles: ["All", "Missed"], style: .segments, liquid: Palette.accent,
                                         selectedTint: .white, normalTint: Palette.secondary)

    override var barExtra: CGFloat { 0 }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.isHidden = true
        table.accessibilityIdentifier = "contact.calls"
        segment.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        bar.addSubview(segment)
        shown = all
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        segment.frame = CGRect(x: (view.bounds.width - 230) / 2, y: view.safeAreaInsets.top + 6, width: 230, height: 32)
    }

    @objc private func segmentChanged() {
        let old = shown
        shown = segment.selectedIndex == 0 ? all : all.filter { $0.kind == 2 }
        // Rows that are not missed calls fold away; they come back when switching to all.
        let oldIDs = old.map(\.person.name), newIDs = shown.map(\.person.name)
        table.performBatchUpdates {
            table.deleteRows(at: oldIDs.enumerated().filter { !newIDs.contains($0.element) }
                .map { IndexPath(row: $0.offset, section: 0) }, with: .fade)
            table.insertRows(at: newIDs.enumerated().filter { !oldIDs.contains($0.element) }
                .map { IndexPath(row: $0.offset, section: 0) }, with: .fade)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let call = shown[indexPath.row]
        let subtitle = ["↙︎ Incoming", "↗︎ Outgoing", "↙︎ Missed"][call.kind] + (call.video ? " video call" : "")
        let cell = personCell(call.person, subtitle: subtitle, titleColor: call.kind == 2 ? Palette.red : Palette.text)
        let time = Views.label(call.time, size: 14, color: Palette.secondary)
        time.sizeToFit()
        let info = Views.iconButton(call.video ? "video" : "phone", size: 18)
        info.frame = CGRect(x: time.bounds.width + 6, y: 0, width: 36, height: 36)
        info.addAction(UIAction { [weak self] _ in self?.home?.call(call.person) }, for: .touchUpInside)
        let accessory = UIView(frame: CGRect(x: 0, y: 0, width: time.bounds.width + 42, height: 36))
        time.center.y = 18
        accessory.addSubview(time)
        accessory.addSubview(info)
        cell.accessoryView = accessory
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        home?.call(shown[indexPath.row].person)
    }
}

// MARK: - Settings

final class SettingsPage: Page, UITableViewDataSource, UITableViewDelegate {
    private struct Row {
        let title: String
        let symbol: String
        let color: UIColor
        var detail: String? = nil
        var action: Action
    }

    fileprivate enum Action {
        case profile, saved, calls, devices, folders, notifications, privacy, passcode, theme, language, mascotLogin, metalEffects, vfx, about, add
        case account(Int)
    }

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = UIView()
    private let avatar = UIImageView()
    private let nameLabel = Views.label(size: 24, weight: .semibold)
    private let phoneLabel = Views.label(size: 15, color: Palette.secondary)
    private let themeButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private var sections: [[Row]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.grouped
        table.backgroundColor = Palette.grouped
        table.contentInsetAdjustmentBehavior = .never
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 46
        view.addSubview(table)

        avatar.layer.cornerRadius = 50
        avatar.clipsToBounds = true
        headerView.addSubview(avatar)
        nameLabel.textAlignment = .center
        headerView.addSubview(nameLabel)
        phoneLabel.textAlignment = .center
        headerView.addSubview(phoneLabel)

        themeButton.accessibilityLabel = "Change theme"
        themeButton.accessibilityIdentifier = "contact.theme"
        themeButton.tintColor = Palette.accent
        themeButton.addAction(UIAction { [weak self] _ in self?.toggleTheme() }, for: .touchUpInside)
        view.addSubview(themeButton)
        editButton.setTitle("Edited", for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 17)
        editButton.tintColor = Palette.accent
        view.addSubview(editButton)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        table.frame = view.bounds
        table.contentInset = UIEdgeInsets(top: top, left: 0, bottom: home?.bottomInset ?? 0, right: 0)
        let width = view.bounds.width
        headerView.frame = CGRect(x: 0, y: 0, width: width, height: 196)
        avatar.frame = CGRect(x: (width - 100) / 2, y: 30, width: 100, height: 100)
        nameLabel.frame = CGRect(x: 20, y: 140, width: width - 40, height: 30)
        phoneLabel.frame = CGRect(x: 20, y: 170, width: width - 40, height: 20)
        if table.tableHeaderView !== headerView { table.tableHeaderView = headerView }
        themeButton.frame = CGRect(x: 8, y: top, width: 44, height: 44)
        editButton.frame = CGRect(x: width - 64, y: top, width: 56, height: 44)
        updateThemeIcon(animated: false)
    }

    func reload() {
        guard isViewLoaded, let home else { return }
        let account = home.account
        avatar.image = ChannelAvatar.image(for: account.person, size: 100)
        nameLabel.text = account.person.name
        phoneLabel.text = "\(account.phone) · \(account.username)"
        var accounts: [Row] = []
        if home.accountCount > 1 {
            for index in 0..<home.accountCount {
                let person = MessengerData.accounts[index].person
                accounts.append(Row(title: person.name, symbol: "", color: .clear,
                                    detail: index == home.currentAccount ? "✓" : nil, action: .account(index)))
            }
        }
        if home.accountCount < MessengerData.accounts.count {
            accounts.append(Row(title: "Add account", symbol: "plus", color: Palette.accent, action: .add))
        }
        sections = [
            accounts,
            [Row(title: "My Profile", symbol: "person.crop.circle.fill", color: Palette.red, action: .profile),
             Row(title: "Saved Messages", symbol: "bookmark.fill", color: Palette.accent, action: .saved),
             Row(title: "Recent Calls", symbol: "phone.fill", color: Palette.online, action: .calls),
             Row(title: "Devices", symbol: "laptopcomputer", color: Palette.orange, detail: "3", action: .devices),
             Row(title: "Chat Folders", symbol: "folder.fill", color: UIColor(red: 0.2, green: 0.7, blue: 0.9, alpha: 1),
                 action: .folders)],
            [Row(title: "Notifications and Sounds", symbol: "bell.badge.fill", color: Palette.red, action: .notifications),
             Row(title: "Privacy", symbol: "lock.fill", color: UIColor(white: 0.55, alpha: 1), action: .privacy),
             Row(title: "Passcode", symbol: "lock.shield.fill", color: Palette.online,
                 detail: home.passcodeEnabled ? "On" : "Off", action: .passcode),
             Row(title: "Appearance", symbol: "paintbrush.fill", color: Palette.accent,
                 detail: home.isDark ? "Night" : "Day", action: .theme),
             Row(title: "Language", symbol: "globe", color: UIColor(red: 0.6, green: 0.35, blue: 0.9, alpha: 1), detail: "English",
                 action: .language),
             Row(title: "Mascot Login", symbol: "face.smiling.fill", color: Palette.orange, action: .mascotLogin),
             Row(title: "Metal Effects", symbol: "flame.fill", color: Palette.orange, action: .metalEffects),
             Row(title: "VFX", symbol: "sparkles", color: Palette.accent, action: .vfx)],
            [Row(title: "About Contact", symbol: "info.circle", color: Palette.accent, action: .about)],
        ]
        table.reloadData()
    }

    private func updateThemeIcon(animated: Bool) {
        let symbol = (home?.isDark ?? true) ? "sun.max.fill" : "moon.fill"
        let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))!
        guard let imageView = themeButton.imageView, animated else {
            themeButton.setImage(image, for: .normal)
            return
        }
        imageView.setContactSymbol(image, transition: .offUp)
        themeButton.setImage(image, for: .normal)
    }

    private func toggleTheme() {
        guard let home else { return }
        home.toggleTheme(from: themeButton)
        updateThemeIcon(animated: true)
        reload()
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section][indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Palette.cell
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.textProperties.color = row.action.isAdd ? Palette.accent : Palette.text
        content.secondaryText = row.detail == "✓" ? nil : row.detail
        var icon: UIImage?
        if case .account(let index) = row.action {
            icon = ChannelAvatar.image(for: MessengerData.accounts[index].person, size: 30)
            if row.detail == "✓" { cell.accessoryType = .checkmark }
        } else {
            icon = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { context in
                UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 30, height: 30), cornerRadius: 7).addClip()
                row.color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
                let symbol = UIImage(systemName: row.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                if let symbol {
                    symbol.draw(at: CGPoint(x: (30 - symbol.size.width) / 2, y: (30 - symbol.size.height) / 2))
                }
            }
            if !row.action.isAdd { cell.accessoryType = .disclosureIndicator }
        }
        // A fixed 30 pt icon; the content configuration would shrink it to the text size.
        content.directionalLayoutMargins.leading = 60
        cell.contentConfiguration = content
        let iconView = UIImageView(image: icon)
        iconView.frame = CGRect(x: 16, y: 8, width: 30, height: 30)
        cell.contentView.addSubview(iconView)
        cell.separatorInset.left = 60
        if case .mascotLogin = row.action { cell.accessibilityIdentifier = "contact.mascotLogin" }
        if case .metalEffects = row.action { cell.accessibilityIdentifier = "contact.metalEffects" }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let home else { return }
        switch sections[indexPath.section][indexPath.row].action {
        case .account(let index): home.switchAccount(to: index)
        case .add: home.addAccount()
        case .folders: home.openFolders()
        case .profile: home.openProfile(home.account.person, online: true)
        case .calls: home.tabBar.select(.calls); home.tabBar.onSelect?(.calls)
        case .passcode:
            home.setPasscode(!home.passcodeEnabled)
        case .mascotLogin:
            home.root?.push(MascotLoginViewController())
        case .metalEffects:
            home.root?.push(MetalEffectsViewController(onBack: { [weak home] in home?.root?.pop() }))
        case .vfx:
            let catalog = VFXCatalogController()
            catalog.home = home
            home.openVFX(catalog)
        case .theme:
            if let cell = tableView.cellForRow(at: indexPath) {
                home.toggleTheme(from: cell)
                updateThemeIcon(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.reload() }
            }
        case .about:
            let alert = UIAlertController(title: "Contact", message: "Messenger prototype · 1.0\nChats and calls currently work locally.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Done", style: .default))
            present(alert, animated: true)
        case .saved:
            home.openChat(Chat(id: 999, person: ChannelPerson(name: "Saved Messages", hue: 0.58), kind: .person, message: "", time: ""))
        default:
            if let cell = tableView.cellForRow(at: indexPath) { Views.pop(cell, scale: 0.97) }
        }
    }
}

private extension SettingsPage.Action {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}
