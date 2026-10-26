import UIKit
import AsyncDisplayKit
import ListUI
import AvatarUI

/// Profile with a shared collapsing header and independently scrolling media panes.
final class ProfileViewController: UIViewController {
    private let person: ChannelPerson
    private let online: Bool
    private weak var home: HomeViewController?

    private let headerNode = ASDisplayNode()
    private let pager = ListPagerNode(theme: ListTheme(background: Palette.grouped, rowBackground: Palette.cell,
                                                      primary: Palette.text, secondary: Palette.secondary,
                                                      separator: Palette.separator, accent: Palette.accent))
    private lazy var container = CollapsingListContainerNode(header: headerNode, height: 464, pager: pager)
    private let tabsHost = UIView()
    private var tabButtons: [UIButton] = []
    private let pageIDs = ["media", "files", "links", "voice"]
    private let mediaPane = ProfileMediaPane()
    private var savedPopGestureEnabled: Bool?
    private let content = UIView()
    private let photo = UIView()
    private let avatarNode = AvatarUI.AvatarNode()
    private let providedAvatars: [AvatarDescriptor]?
    private let peerID: Int?
    private var profileVisible = false
    private let photoShade = CAGradientLayer()
    private let segments = UIStackView()
    private let name = Views.label(size: 24, weight: .semibold)
    private let status = Views.label(size: 15, color: Palette.secondary)
    private let nav = UIView()
    private let navBackground = Views.barBackground()
    private let backButton = Views.iconButton("chevron.backward", size: 18)
    private let editButton = UIButton(type: .system)
    private let navTitle = Views.label(size: 16, weight: .semibold)
    private var buttons: [UIView] = []
    private let info = UIView()
    private let mediaTabs = LiquidSelector(titles: ["Media", "Files", "Links", "Voice"], style: .segments,
                                           liquid: Palette.accent, selectedTint: .white, normalTint: Palette.secondary)
    private let monthPill = UILabel()
    private var monthFade: DispatchWorkItem?

    private var expanded = false
    private var open = Spring1D(0, stiffness: 15, dampingRatio: 0.78)
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private var photos: [AvatarDescriptor] = []
    private var currentPhoto = 0

    private let avatarSize: CGFloat = 100

    init(
        person: ChannelPerson,
        online: Bool,
        home: HomeViewController,
        peerID: Int? = nil,
        avatarGallery: [AvatarDescriptor]? = nil
    ) {
        self.person = person
        self.peerID = peerID
        providedAvatars = avatarGallery
        self.online = online
        self.home = home
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.grouped
        view.addSubview(container.view)
        headerNode.view.addSubview(content)
        tabsHost.backgroundColor = Palette.grouped
        let tabsNode = ASDisplayNode(viewBlock: { [tabsHost] in tabsHost })
        pager.setTabsNode(tabsNode, height: 44)
        pager.usesFullWidthPaging = true
        container.headerProgressChanged = { [weak self] _ in self?.scrollingChanged() }
        mediaPane.offsetChanged = { [weak self] in self?.updateMonthPill() }
        mediaPane.zoomBegan = { [weak self] in self?.container.stopMotion() }
        pager.pageTransitionUpdated = { [weak self] position in
            self?.mediaTabs.setInteractivePosition(position)
        }
        pager.selectedPageChanged = { [weak self] id in
            guard let self, let index = self.pageIDs.firstIndex(of: id) else { return }
            self.mediaTabs.select(index)
            self.updateTabAccessibility(index)
            self.pager.currentList?.contentInsets.bottom = self.view.safeAreaInsets.bottom
            self.monthPill.alpha = 0
        }

        photos = providedAvatars.flatMap { $0.isEmpty ? nil : $0 }
            ?? AvatarProvider.gallery(for: person, peerID: peerID)
        avatarNode.avatarCornerRadius = 0
        avatarNode.isUserInteractionEnabled = false
        photo.addSubview(avatarNode.view)
        updateAvatarContent()
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.isUserInteractionEnabled = true
        photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTapped(_:))))
        photoShade.colors = [UIColor(white: 0, alpha: 0.35).cgColor, UIColor.clear.cgColor, UIColor.clear.cgColor,
                             UIColor(white: 0, alpha: 0.5).cgColor]
        photoShade.locations = [0, 0.25, 0.6, 1]
        photo.layer.addSublayer(photoShade)
        content.addSubview(photo)
        segments.axis = .horizontal
        segments.spacing = 4
        segments.distribution = .fillEqually
        for _ in photos {
            let bar = UIView()
            bar.backgroundColor = UIColor(white: 1, alpha: 0.4)
            bar.layer.cornerRadius = 1.5
            segments.addArrangedSubview(bar)
        }
        content.addSubview(segments)
        name.text = person.name
        content.addSubview(name)
        status.text = online ? "online" : "last seen recently"
        content.addSubview(status)

        for (symbol, title) in [("bubble.left.fill", "Chat"), ("bell.fill", "Sound"), ("phone.fill", "Call"), ("ellipsis", "More")] {
            let button = UIControl()
            button.backgroundColor = Palette.cell
            button.layer.cornerRadius = 12
            button.layer.cornerCurve = .continuous
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = Palette.accent
            icon.contentMode = .center
            icon.tag = 1
            button.addSubview(icon)
            let label = Views.label(title, size: 11, color: Palette.accent)
            label.textAlignment = .center
            label.tag = 2
            button.addSubview(label)
            button.addAction(UIAction { [weak self] _ in self?.buttonTapped(title, button) }, for: .touchUpInside)
            content.addSubview(button)
            buttons.append(button)
        }

        info.backgroundColor = Palette.cell
        info.layer.cornerRadius = 12
        info.layer.cornerCurve = .continuous
        let rows = [("phone", "+7 900 \(100 + Int(person.hue * 800)) 21-12"),
                    ("username", "@" + person.name.split(separator: " ")[0].lowercased()),
                    ("about", "Design, Metal and fluid interfaces 💧")]
        for (index, row) in rows.enumerated() {
            let value = Views.label(row.1, size: 16, color: index == 1 ? Palette.accent : Palette.text)
            let key = Views.label(row.0, size: 13, color: Palette.secondary)
            value.frame = CGRect(x: 16, y: CGFloat(index) * 62 + 10, width: 300, height: 21)
            key.frame = CGRect(x: 16, y: CGFloat(index) * 62 + 32, width: 300, height: 17)
            info.addSubview(value)
            info.addSubview(key)
            if index < rows.count - 1 {
                let line = UIView(frame: CGRect(x: 16, y: CGFloat(index + 1) * 62, width: 1000, height: 0.5))
                line.backgroundColor = Palette.separator
                info.addSubview(line)
            }
        }
        info.clipsToBounds = true
        content.addSubview(info)
        mediaTabs.isUserInteractionEnabled = false
        mediaTabs.accessibilityElementsHidden = true
        tabsHost.addSubview(mediaTabs)
        for (index, title) in ["Media", "Files", "Links", "Voice"].enumerated() {
            let button = UIButton(type: .custom)
            button.accessibilityLabel = title
            button.accessibilityIdentifier = "contact.profile.tab.\(pageIDs[index])"
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.pager.selectPage(id: self.pageIDs[index])
            }, for: .touchUpInside)
            tabsHost.addSubview(button)
            tabButtons.append(button)
        }
        updateTabAccessibility(0)
        let pages = [ListPage(id: "media", title: "Media", makePane: { [mediaPane] _ in mediaPane })]
            + ProfileAttachmentItem.pages { [weak self] title in
                guard let self else { return }
                Views.toast(title, symbol: "doc", in: self.view)
            }
        pager.apply(state: ItemListState(pages: pages, selectedPageID: "media"),
                    theme: ListTheme(background: Palette.grouped, rowBackground: Palette.cell,
                                     primary: Palette.text, secondary: Palette.secondary,
                                     separator: Palette.separator, accent: Palette.accent), animated: false)

        monthPill.font = .systemFont(ofSize: 13, weight: .semibold)
        monthPill.textColor = .white
        monthPill.textAlignment = .center
        monthPill.backgroundColor = UIColor(white: 0, alpha: 0.5)
        monthPill.layer.cornerRadius = 12
        monthPill.clipsToBounds = true
        monthPill.alpha = 0
        view.addSubview(monthPill)

        view.addSubview(nav)
        nav.addSubview(navBackground)
        navBackground.alpha = 0
        backButton.addAction(UIAction { [weak self] _ in self?.home?.root?.pop() }, for: .touchUpInside)
        nav.addSubview(backButton)
        editButton.setTitle("Edited", for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 17)
        editButton.tintColor = Palette.accent
        nav.addSubview(editButton)
        navTitle.text = person.name
        navTitle.textAlignment = .center
        navTitle.alpha = 0
        nav.addSubview(navTitle)
        showHint()
    }

    private func showHint() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            Views.toast("Pull down · pinch media", symbol: "hand.draw", in: self.view,
                          top: self.view.bounds.height - self.view.safeAreaInsets.bottom - 60)
        }
    }

    private var navHeight: CGFloat { view.safeAreaInsets.top + 44 }
    /// Content-space y of the avatar's top when folded.
    private var avatarTop: CGFloat { navHeight + 4 }
    /// Where the name sits under the circle (content space): the photo's bottom when open.
    private var nameBottom: CGFloat { avatarTop + avatarSize + 66 }
    /// How much taller the open photo is than the folded header.
    private var extra: CGFloat { max(0, view.bounds.width - nameBottom) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        container.setSuspended(false)
        profileVisible = true
        if let gesture = navigationController?.interactivePopGestureRecognizer {
            savedPopGestureEnabled = gesture.isEnabled
            gesture.isEnabled = false
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        container.setSuspended(true)
        profileVisible = false
        avatarNode.setVisible(false)
        link?.invalidate()
        link = nil
        monthFade?.cancel()
        if let enabled = savedPopGestureEnabled {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = enabled
        }
    }

    deinit { link?.invalidate(); monthFade?.cancel() }

    private func updateTabAccessibility(_ selected: Int) {
        for (index, button) in tabButtons.enumerated() {
            button.accessibilityTraits = index == selected ? [.button, .selected] : [.button]
        }
    }

    private var expansion: CGFloat { extra * min(max(open.value, 0), 1) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        ASTraitCollectionPropagateDown(container, ASPrimitiveTraitCollectionFromUITraitCollection(traitCollection))
        container.pinnedTopInset = navHeight
        container.frame = view.bounds
        mediaPane.bottomInset = view.safeAreaInsets.bottom
        pager.currentList?.contentInsets.bottom = view.safeAreaInsets.bottom
        nav.frame = CGRect(x: 0, y: 0, width: width, height: navHeight)
        navBackground.frame = nav.bounds
        backButton.frame = CGRect(x: 4, y: view.safeAreaInsets.top, width: 44, height: 44)
        editButton.frame = CGRect(x: width - 64, y: view.safeAreaInsets.top, width: 56, height: 44)
        navTitle.frame = CGRect(x: 60, y: view.safeAreaInsets.top, width: width - 120, height: 44)

        var y = nameBottom + 14 + expansion
        let buttonWidth = (width - 32 - 24) / 4
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: 16 + CGFloat(index) * (buttonWidth + 8), y: y, width: buttonWidth, height: 58)
            button.viewWithTag(1)?.frame = CGRect(x: 0, y: 8, width: buttonWidth, height: 24)
            button.viewWithTag(2)?.frame = CGRect(x: 0, y: 34, width: buttonWidth, height: 16)
        }
        y += 58 + 16
        info.frame = CGRect(x: 16, y: y, width: width - 32, height: 186)
        y += 186 + 20
        content.frame = CGRect(x: 0, y: 0, width: width, height: y)
        let height = max(0, y - navHeight)
        if abs(container.coordinator.headerHeight - height) > 0.01 {
            container.setHeaderHeight(height, preservingContentPosition: true)
        }
        mediaTabs.frame = CGRect(x: 16, y: 0, width: width - 32, height: 32)
        for (index, button) in tabButtons.enumerated() {
            button.frame = CGRect(x: 16 + CGFloat(index) * (width - 32) / 4, y: 0,
                                  width: (width - 32) / 4, height: 44)
        }
        layoutHeader()
    }

    // MARK: Avatar ↔ gallery

    private func layoutHeader() {
        let width = view.bounds.width
        let origin: CGFloat = 0 // Header translation is owned by the shared vertical coordinator.
        let p = min(max(open.value, 0), 1.08)
        let folded = CGRect(x: (width - avatarSize) / 2, y: origin + avatarTop, width: avatarSize, height: avatarSize)
        // Open: full width, bottom at the name line, stretching when pulled further.
        let bottom = origin + nameBottom + expansion
        let height = max(width, bottom + container.coordinator.topStretch)
        let opened = CGRect(x: 0, y: bottom - height, width: width, height: height)
        photo.frame = CGRect(x: folded.minX + (opened.minX - folded.minX) * p,
                             y: folded.minY + (opened.minY - folded.minY) * p,
                             width: folded.width + (opened.width - folded.width) * p,
                             height: folded.height + (opened.height - folded.height) * p)
        photo.layer.cornerRadius = avatarSize / 2 * max(0, 1 - p * 1.2)
        avatarNode.frame = photo.bounds
        updateAvatarVisibility()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        photoShade.frame = photo.bounds
        photoShade.opacity = Float(min(p, 1))
        CATransaction.commit()

        // Name: centered under the circle → bottom-left on the photo, white.
        name.sizeToFit()
        status.sizeToFit()
        let foldedName = CGPoint(x: (width - name.bounds.width) / 2, y: folded.maxY + 12)
        let openName = CGPoint(x: 16, y: bottom - 60)
        name.frame.origin = CGPoint.lerp(foldedName, openName, min(p, 1))
        let foldedStatus = CGPoint(x: (width - status.bounds.width) / 2, y: folded.maxY + 44)
        let openStatus = CGPoint(x: 16, y: bottom - 30)
        status.frame.origin = CGPoint.lerp(foldedStatus, openStatus, min(p, 1))
        name.textColor = p > 0.5 ? .white : Palette.text
        status.textColor = p > 0.5 ? UIColor(white: 1, alpha: 0.8) : (online ? Palette.accent : Palette.secondary)

        segments.frame = CGRect(x: 8, y: max(photo.frame.minY, -container.coordinator.topStretch) + view.safeAreaInsets.top + 48, width: width - 16, height: 3)
        segments.alpha = islandSmoothstep(0.85, 1, p)

        // The bar fills in once the header has scrolled under it.
        let under = -container.coordinator.headerOffset + container.coordinator.topStretch + nameBottom + expansion < navHeight + 20
        let navAlpha: CGFloat = under ? 1 : 0
        if navBackground.alpha != navAlpha {
            UIView.animate(withDuration: 0.2) {
                self.navBackground.alpha = navAlpha
                self.navTitle.alpha = navAlpha
            }
        }
        let onPhoto = p > 0.5 && !under
        backButton.tintColor = onPhoto ? .white : Palette.accent
        editButton.tintColor = onPhoto ? .white : Palette.accent
    }

    private func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        expanded = value
        UIImpactFeedbackGenerator(style: value ? .medium : .light).impactOccurred()
        if !value {
            currentPhoto = 0
            updateAvatarContent()
            updateSegments()
        } else {
            updateAvatarContent()
            updateSegments()
        }
        startLink()
    }

    private func startLink() {
        guard link == nil else { return }
        lastTime = nil
        link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTime.map { min(link.timestamp - $0, 1.0 / 30) } ?? 1.0 / 60
        lastTime = link.timestamp
        let target: CGFloat = expanded ? 1 : 0
        open.step(toward: target, deltaTime: dt)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        if open.isSettled(at: target, tolerance: 0.001) {
            open.value = target
            layoutHeader()
            link.invalidate()
            self.link = nil
        }
    }

    private func scrollingChanged() {
        let coordinator = container.coordinator
        if !expanded, container.isDragging, coordinator.topStretch > 24 {
            setExpanded(true)
        } else if expanded, coordinator.headerOffset > extra * 0.55 {
            setExpanded(false)
        }
        layoutHeader()
        updateMonthPill()
    }

    @objc private func photoTapped(_ gesture: UITapGestureRecognizer) {
        guard expanded else {
            container.stopMotion()
            container.coordinator.scrollToTop()
            setExpanded(true)
            return
        }
        let forward = gesture.location(in: photo).x > photo.bounds.width / 2
        let next = currentPhoto + (forward ? 1 : -1)
        guard photos.indices.contains(next) else {
            // A bounce at the ends, like Telegram's.
            let shake = CAKeyframeAnimation(keyPath: "transform.rotation.y")
            shake.values = [0, forward ? -0.12 : 0.12, 0]
            shake.duration = 0.3
            photo.layer.add(shake, forKey: "edge")
            return
        }
        currentPhoto = next
        UISelectionFeedbackGenerator().selectionChanged()
        updateAvatarContent()
        updateSegments()
    }

    private func updateAvatarContent() {
        guard photos.indices.contains(currentPhoto) else { return }
        avatarNode.apply(photos[currentPhoto], presentation: expanded ? .gallery : .profile)
        updateAvatarVisibility()
    }

    private func updateAvatarVisibility() {
        guard isViewLoaded else { return }
        let top: CGFloat = expanded ? 0 : navHeight
        let viewport = CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, view.bounds.height - top))
        let frame = photo.convert(photo.bounds, to: view)
        avatarNode.setVisible(profileVisible && view.window != nil && frame.intersects(viewport) && !frame.isEmpty)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        profileVisible = true
        updateAvatarVisibility()
    }

    private func updateSegments() {
        for (index, bar) in segments.arrangedSubviews.enumerated() {
            bar.backgroundColor = index == currentPhoto ? .white : UIColor(white: 1, alpha: 0.4)
        }
    }

    // MARK: Buttons, media

    private func buttonTapped(_ title: String, _ button: UIView) {
        Views.pop(button, scale: 0.92)
        switch title {
        case "Chat": home?.root?.pop()
        case "Call": home?.call(person)
        case "Sound":
            if let icon = button.viewWithTag(1) as? UIImageView {
                let muted = icon.image == UIImage(systemName: "bell.fill")
                icon.setContactSymbol(UIImage(systemName: muted ? "bell.slash.fill" : "bell.fill")!, transition: .replace)
                Views.toast(muted ? "Notifications disabled" : "Notifications enabled",
                              symbol: muted ? "bell.slash.fill" : "bell.fill", in: view)
            }
        default: break
        }
    }

    private func updateMonthPill() {
        guard pager.selectedPageID == "media", mediaPane.verticalOffset > 0 else {
            monthPill.alpha = 0
            return
        }
        monthFade?.cancel()
        let months = ["October 2026", "September 2026", "August 2026", "July 2026", "June 2026", "May 2026", "April 2026"]
        monthPill.text = months[min(max(0, mediaPane.month), months.count - 1)]
        let width = monthPill.intrinsicContentSize.width + 22
        monthPill.frame = CGRect(x: (view.bounds.width - width) / 2, y: navHeight + 54, width: width, height: 24)
        if monthPill.alpha < 1 { UIView.animate(withDuration: 0.15) { self.monthPill.alpha = 1 } }
        scheduleMonthFade()
    }

    private func scheduleMonthFade() {
        monthFade?.cancel()
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.35) { self?.monthPill.alpha = 0 }
        }
        monthFade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}

