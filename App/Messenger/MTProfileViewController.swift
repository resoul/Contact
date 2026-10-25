//
//  MTProfileViewController.swift
//  controller
//
//  A Mini-Telegram profile. Pull it down and the round avatar opens into a full-width photo
//  gallery (segment bars on top, tap the sides to flip); scroll up and it folds back into the
//  circle. Below, the shared-media grid changes density with a pinch, every cell flowing to its
//  place in the new layout, and a month pill shows up while scrolling through it.
//

import UIKit

final class MTProfileViewController: UIViewController, UIScrollViewDelegate {
    private let person: ChannelPerson
    private let online: Bool
    private weak var home: MTHomeViewController?

    private let scroll = UIScrollView()
    private let content = UIView()
    private let photo = UIImageView()
    private let photoShade = CAGradientLayer()
    private let segments = UIStackView()
    private let name = MTViews.label(size: 24, weight: .semibold)
    private let status = MTViews.label(size: 15, color: MTPalette.secondary)
    private let nav = UIView()
    private let navBackground = MTViews.barBackground()
    private let backButton = MTViews.iconButton("chevron.backward", size: 18)
    private let editButton = UIButton(type: .system)
    private let navTitle = MTViews.label(size: 16, weight: .semibold)
    private var buttons: [UIView] = []
    private let info = UIView()
    private let mediaTabs = LiquidSelector(titles: ["Media", "Files", "Links", "Voice"], style: .segments,
                                           liquid: MTPalette.accent, selectedTint: .white, normalTint: MTPalette.secondary)
    private let grid = MTMediaGrid(count: 72)
    private let monthPill = UILabel()
    private var monthFade: DispatchWorkItem?

    private var expanded = false
    private var open = Spring1D(0, stiffness: 15, dampingRatio: 0.78)
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private var photos: [UIImage] = []
    private var currentPhoto = 0

    private let avatarSize: CGFloat = 100

    init(person: ChannelPerson, online: Bool, home: MTHomeViewController) {
        self.person = person
        self.online = online
        self.home = home
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = MTPalette.grouped
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        view.addSubview(scroll)
        scroll.addSubview(content)
        // The photo floats above the scroll view; drags anywhere (the photo included) scroll it.
        view.addGestureRecognizer(scroll.panGestureRecognizer)

        photos = [Self.squareAvatar(person)]
            + [DemoPhotos.Scene.sunset, .aurora, .city].enumerated().map { index, scene in
                DemoPhotos.image(scene, size: CGSize(width: 420, height: 420), seed: UInt64(index + 21))
            }
        photo.image = photos[0]
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.isUserInteractionEnabled = true
        photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTapped(_:))))
        photoShade.colors = [UIColor(white: 0, alpha: 0.35).cgColor, UIColor.clear.cgColor, UIColor.clear.cgColor,
                             UIColor(white: 0, alpha: 0.5).cgColor]
        photoShade.locations = [0, 0.25, 0.6, 1]
        photo.layer.addSublayer(photoShade)
        view.addSubview(photo)
        segments.axis = .horizontal
        segments.spacing = 4
        segments.distribution = .fillEqually
        for _ in photos {
            let bar = UIView()
            bar.backgroundColor = UIColor(white: 1, alpha: 0.4)
            bar.layer.cornerRadius = 1.5
            segments.addArrangedSubview(bar)
        }
        view.addSubview(segments)
        name.text = person.name
        view.addSubview(name)
        status.text = online ? "online" : "last seen recently"
        view.addSubview(status)

        for (symbol, title) in [("bubble.left.fill", "Chat"), ("bell.fill", "Sound"), ("phone.fill", "Call"), ("ellipsis", "More")] {
            let button = UIControl()
            button.backgroundColor = MTPalette.cell
            button.layer.cornerRadius = 12
            button.layer.cornerCurve = .continuous
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = MTPalette.accent
            icon.contentMode = .center
            icon.tag = 1
            button.addSubview(icon)
            let label = MTViews.label(title, size: 11, color: MTPalette.accent)
            label.textAlignment = .center
            label.tag = 2
            button.addSubview(label)
            button.addAction(UIAction { [weak self] _ in self?.buttonTapped(title, button) }, for: .touchUpInside)
            content.addSubview(button)
            buttons.append(button)
        }

        info.backgroundColor = MTPalette.cell
        info.layer.cornerRadius = 12
        info.layer.cornerCurve = .continuous
        let rows = [("phone", "+7 900 \(100 + Int(person.hue * 800)) 21-12"),
                    ("username", "@" + person.name.split(separator: " ")[0].lowercased()),
                    ("about", "Design, Metal and fluid interfaces 💧")]
        for (index, row) in rows.enumerated() {
            let value = MTViews.label(row.1, size: 16, color: index == 1 ? MTPalette.accent : MTPalette.text)
            let key = MTViews.label(row.0, size: 13, color: MTPalette.secondary)
            value.frame = CGRect(x: 16, y: CGFloat(index) * 62 + 10, width: 300, height: 21)
            key.frame = CGRect(x: 16, y: CGFloat(index) * 62 + 32, width: 300, height: 17)
            info.addSubview(value)
            info.addSubview(key)
            if index < rows.count - 1 {
                let line = UIView(frame: CGRect(x: 16, y: CGFloat(index + 1) * 62, width: 1000, height: 0.5))
                line.backgroundColor = MTPalette.separator
                info.addSubview(line)
            }
        }
        info.clipsToBounds = true
        content.addSubview(info)
        mediaTabs.addTarget(self, action: #selector(mediaTabChanged), for: .valueChanged)
        content.addSubview(mediaTabs)
        grid.onHeightChange = { [weak self] in self?.view.setNeedsLayout() }
        content.addSubview(grid)

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
        editButton.tintColor = MTPalette.accent
        nav.addSubview(editButton)
        navTitle.text = person.name
        navTitle.textAlignment = .center
        navTitle.alpha = 0
        nav.addSubview(navTitle)
        showHint()
    }

    /// The avatar's gradient and initials on a full square, for the open gallery.
    private static func squareAvatar(_ person: ChannelPerson) -> UIImage {
        let size: CGFloat = 420
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let top = UIColor(hue: person.hue, saturation: 0.55, brightness: 0.98, alpha: 1)
            let bottom = UIColor(hue: person.hue + 0.06, saturation: 0.75, brightness: 0.78, alpha: 1)
            let gradient = CGGradient(colorsSpace: nil, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            let text = person.initials as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size * 0.4, weight: .semibold),
                                                             .foregroundColor: UIColor.white]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
        }
    }

    private func showHint() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            MTViews.toast("Pull down · pinch media", symbol: "hand.draw", in: self.view,
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        scroll.frame = view.bounds
        nav.frame = CGRect(x: 0, y: 0, width: width, height: navHeight)
        navBackground.frame = nav.bounds
        backButton.frame = CGRect(x: 4, y: view.safeAreaInsets.top, width: 44, height: 44)
        editButton.frame = CGRect(x: width - 64, y: view.safeAreaInsets.top, width: 56, height: 44)
        navTitle.frame = CGRect(x: 60, y: view.safeAreaInsets.top, width: width - 120, height: 44)

        var y = nameBottom + 14
        let buttonWidth = (width - 32 - 24) / 4
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: 16 + CGFloat(index) * (buttonWidth + 8), y: y, width: buttonWidth, height: 58)
            button.viewWithTag(1)?.frame = CGRect(x: 0, y: 8, width: buttonWidth, height: 24)
            button.viewWithTag(2)?.frame = CGRect(x: 0, y: 34, width: buttonWidth, height: 16)
        }
        y += 58 + 16
        info.frame = CGRect(x: 16, y: y, width: width - 32, height: 186)
        y += 186 + 20
        mediaTabs.frame = CGRect(x: 16, y: y, width: width - 32, height: 32)
        y += 44
        grid.frame = CGRect(x: 0, y: y, width: width, height: grid.contentHeight(for: width))
        y += grid.frame.height
        content.frame = CGRect(x: 0, y: 0, width: width, height: y)
        scroll.contentSize = content.frame.size
        scroll.contentInset.bottom = view.safeAreaInsets.bottom
        layoutHeader()
    }

    // MARK: Avatar ↔ gallery

    private func layoutHeader() {
        let width = view.bounds.width
        let origin = -scroll.contentOffset.y   // where content y = 0 is on screen
        let p = min(max(open.value, 0), 1.08)
        let folded = CGRect(x: (width - avatarSize) / 2, y: origin + avatarTop, width: avatarSize, height: avatarSize)
        // Open: full width, bottom at the name line, stretching when pulled further.
        let bottom = origin + nameBottom
        let height = max(width, bottom)
        let opened = CGRect(x: 0, y: bottom - height, width: width, height: height)
        photo.frame = CGRect(x: folded.minX + (opened.minX - folded.minX) * p,
                             y: folded.minY + (opened.minY - folded.minY) * p,
                             width: folded.width + (opened.width - folded.width) * p,
                             height: folded.height + (opened.height - folded.height) * p)
        photo.layer.cornerRadius = avatarSize / 2 * max(0, 1 - p * 1.2)
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
        name.textColor = p > 0.5 ? .white : MTPalette.text
        status.textColor = p > 0.5 ? UIColor(white: 1, alpha: 0.8) : (online ? MTPalette.accent : MTPalette.secondary)

        segments.frame = CGRect(x: 8, y: max(photo.frame.minY, 0) + view.safeAreaInsets.top + 48, width: width - 16, height: 3)
        segments.alpha = islandSmoothstep(0.85, 1, p)

        // The bar fills in once the header has scrolled under it.
        let under = origin + nameBottom < navHeight + 20
        let navAlpha: CGFloat = under ? 1 : 0
        if navBackground.alpha != navAlpha {
            UIView.animate(withDuration: 0.2) {
                self.navBackground.alpha = navAlpha
                self.navTitle.alpha = navAlpha
            }
        }
        let onPhoto = p > 0.5 && !under
        backButton.tintColor = onPhoto ? .white : MTPalette.accent
        editButton.tintColor = onPhoto ? .white : MTPalette.accent
    }

    private func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        expanded = value
        UIImpactFeedbackGenerator(style: value ? .medium : .light).impactOccurred()
        scroll.contentInset.top = value ? extra : 0
        if !value {
            currentPhoto = 0
            photo.image = photos[0]
            updateSegments()
        } else {
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
        layoutHeader()
        if open.isSettled(at: target, tolerance: 0.001) {
            open.value = target
            layoutHeader()
            link.invalidate()
            self.link = nil
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pulled = -scrollView.contentOffset.y
        if !expanded, scrollView.isDragging, pulled > 44 {
            setExpanded(true)
        } else if expanded, pulled < extra * 0.45 {
            setExpanded(false)
        }
        layoutHeader()
        updateMonthPill()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // Open: rest either fully open or folded, never half way.
        guard expanded else { return }
        let target = -targetContentOffset.pointee.y
        if target > 0, target < extra {
            targetContentOffset.pointee.y = target > extra * 0.5 ? -extra : 0
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleMonthFade()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleMonthFade() }
    }

    @objc private func photoTapped(_ gesture: UITapGestureRecognizer) {
        guard expanded else {
            scroll.setContentOffset(CGPoint(x: 0, y: -extra), animated: false)
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
        UIView.transition(with: photo, duration: 0.2, options: .transitionCrossDissolve) {
            self.photo.image = self.photos[next]
        }
        updateSegments()
    }

    private func updateSegments() {
        for (index, bar) in segments.arrangedSubviews.enumerated() {
            bar.backgroundColor = index == currentPhoto ? .white : UIColor(white: 1, alpha: 0.4)
        }
    }

    // MARK: Buttons, media

    private func buttonTapped(_ title: String, _ button: UIView) {
        MTViews.pop(button, scale: 0.92)
        switch title {
        case "Chat": home?.root?.pop()
        case "Call": home?.call(person)
        case "Sound":
            if let icon = button.viewWithTag(1) as? UIImageView {
                let muted = icon.image == UIImage(systemName: "bell.fill")
                icon.setContactSymbol(UIImage(systemName: muted ? "bell.slash.fill" : "bell.fill")!, transition: .replace)
                MTViews.toast(muted ? "Notifications disabled" : "Notifications enabled",
                              symbol: muted ? "bell.slash.fill" : "bell.fill", in: view)
            }
        default: break
        }
    }

    @objc private func mediaTabChanged() {
        UIView.animate(withDuration: 0.15, animations: { self.grid.alpha = 0 }, completion: { _ in
            self.grid.shuffle(seed: self.mediaTabs.selectedIndex)
            UIView.animate(withDuration: 0.25) { self.grid.alpha = 1 }
        })
    }

    private func updateMonthPill() {
        let topInGrid = scroll.contentOffset.y + navHeight - grid.frame.minY
        guard topInGrid > 0, scroll.isDragging || scroll.isDecelerating else { return }
        monthFade?.cancel()
        let months = ["October 2026", "September 2026", "August 2026", "July 2026", "June 2026", "May 2026", "April 2026"]
        let month = months[min(grid.month(at: topInGrid), months.count - 1)]
        if monthPill.text != month {
            monthPill.text = month
            let width = monthPill.intrinsicContentSize.width + 22
            monthPill.frame = CGRect(x: (view.bounds.width - width) / 2, y: navHeight + 10, width: width, height: 24)
        }
        if monthPill.alpha < 1 { UIView.animate(withDuration: 0.15) { self.monthPill.alpha = 1 } }
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

// MARK: - Media grid

/// Shared media whose column count follows a pinch continuously: every cell sits between its spot
/// in the two neighbouring layouts, so the grid flows from 3 to 5 columns rather than jumping.
final class MTMediaGrid: UIView {
    var onHeightChange: (() -> Void)?

    private var cells: [UIImageView] = []
    private var columns: CGFloat = 3
    private var pinchStart: CGFloat = 3
    private var spring = Spring1D(3, stiffness: 14, dampingRatio: 0.8)
    private var target: CGFloat = 3
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private let gap: CGFloat = 1.5
    static let perMonth = 12

    init(count: Int) {
        super.init(frame: .zero)
        clipsToBounds = true
        let scenes = DemoPhotos.Scene.allCases
        for index in 0..<count {
            let cell = UIImageView(image: DemoPhotos.image(scenes[index % scenes.count], size: CGSize(width: 160, height: 160),
                                                           seed: UInt64(index + 100)))
            cell.contentMode = .scaleAspectFill
            cell.clipsToBounds = true
            addSubview(cell)
            cells.append(cell)
        }
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func cellSize(_ columns: Int, width: CGFloat) -> CGFloat {
        (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func frame(_ index: Int, columns: Int, width: CGFloat) -> CGRect {
        let size = cellSize(columns, width: width)
        return CGRect(x: CGFloat(index % columns) * (size + gap), y: CGFloat(index / columns) * (size + gap), width: size, height: size)
    }

    private func height(columns: Int, width: CGFloat) -> CGFloat {
        let rows = (cells.count + columns - 1) / columns
        return CGFloat(rows) * (cellSize(columns, width: width) + gap)
    }

    func contentHeight(for width: CGFloat) -> CGFloat {
        let low = Int(floor(columns)), high = Int(ceil(columns))
        let t = columns - CGFloat(low)
        return height(columns: low, width: width) * (1 - t) + height(columns: high, width: width) * t
    }

    /// Which month (counted back from now) the row at `y` belongs to.
    func month(at y: CGFloat) -> Int {
        let count = Int(round(columns))
        let row = Int(y / (cellSize(count, width: bounds.width) + gap))
        return row * count / Self.perMonth
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let low = Int(floor(columns)), high = Int(ceil(columns))
        let t = columns - CGFloat(low)
        for (index, cell) in cells.enumerated() {
            let a = frame(index, columns: low, width: width), b = frame(index, columns: high, width: width)
            cell.frame = CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                                width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
        }
    }

    func shuffle(seed: Int) {
        var generator = SplitMix(seed: UInt64(seed + 1) * 31)
        let scenes = DemoPhotos.Scene.allCases
        for (index, cell) in cells.enumerated() {
            let scene = scenes[Int(generator.next() * CGFloat(scenes.count)) % scenes.count]
            cell.image = DemoPhotos.image(scene, size: CGSize(width: 160, height: 160), seed: UInt64(index + 100 + seed * 7))
        }
    }

    private func setColumns(_ value: CGFloat) {
        columns = value
        setNeedsLayout()
        onHeightChange?()
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            link?.invalidate()
            link = nil
            pinchStart = columns
        case .changed:
            // Spread fingers = bigger photos = fewer columns. Soft limits past 2…6.
            var value = pinchStart / gesture.scale
            if value < 2 { value = 2 - (2 - value) * 0.3 }
            if value > 6 { value = 6 + (value - 6) * 0.3 }
            setColumns(min(max(value, 1.6), 6.6))
        case .ended, .cancelled:
            target = min(max(round(columns), 2), 6)
            if target != round(pinchStart) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            spring.value = columns
            spring.velocity = 0
            lastTime = nil
            link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        default:
            break
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTime.map { min(link.timestamp - $0, 1.0 / 30) } ?? 1.0 / 60
        lastTime = link.timestamp
        spring.step(toward: target, deltaTime: dt)
        let settled = spring.isSettled(at: target, tolerance: 0.001)
        setColumns(settled ? target : min(max(spring.value, 1.6), 6.6))
        if settled {
            link.invalidate()
            self.link = nil
        }
    }
}
