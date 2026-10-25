import UIKit
import ParticleTypes

private let xPeople = Array(trickPeople.prefix(6))

final class PhotoViewerDemoViewController: TrickPage, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scroll = UIScrollView()
    private var photos: [UIImageView] = []
    private var viewer: (background: UIView, zoom: UIScrollView, image: UIImageView, chrome: [UIView], source: UIImageView)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = TimelinePalette.background
        navigationItem.title = "Фото"
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        let scenes: [DemoPhotos.Scene] = [.aurora, .desert, .bloom, .forest]
        let texts = ["Ночью на перевале было так 💚", "Песок, ветер и ни души", "Весна в ботаническом саду", "Утро в лесу"]
        for (index, scene) in scenes.enumerated() {
            let row = UIView()
            let avatar = UIImageView(image: ChannelAvatar.image(for: xPeople[index], size: 44))
            let text = UILabel()
            let name = NSMutableAttributedString(string: xPeople[index].name + "  ",
                                                 attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: UIColor.white])
            name.append(NSAttributedString(string: "@user\(index) · \(index + 1) ч\n", attributes: [.font: UIFont.systemFont(ofSize: 15),
                                                                                                .foregroundColor: TimelinePalette.secondary]))
            name.append(NSAttributedString(string: texts[index], attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.white]))
            text.attributedText = name
            text.numberOfLines = 0
            let photo = UIImageView(image: DemoPhotos.image(scene, size: CGSize(width: 800, height: 520), seed: UInt64(index + 60)))
            photo.contentMode = .scaleAspectFill
            photo.clipsToBounds = true
            photo.layer.cornerRadius = 16
            photo.isUserInteractionEnabled = true
            photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open(_:))))
            photos.append(photo)
            for v in [avatar, text, photo] {
                v.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(v)
            }
            NSLayoutConstraint.activate([
                avatar.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
                avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
                avatar.widthAnchor.constraint(equalToConstant: 44),
                avatar.heightAnchor.constraint(equalToConstant: 44),
                text.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
                text.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
                text.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                photo.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 10),
                photo.leadingAnchor.constraint(equalTo: text.leadingAnchor),
                photo.trailingAnchor.constraint(equalTo: text.trailingAnchor),
                photo.heightAnchor.constraint(equalTo: photo.widthAnchor, multiplier: 0.65),
                photo.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -14),
            ])
            stack.addArrangedSubview(row)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Тап по фото · щипок — зум · смахните вниз, чтобы закрыть")
    }

    private func fitRect(for image: UIImage, in bounds: CGRect) -> CGRect {
        let s = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    @objc private func open(_ gesture: UITapGestureRecognizer) {
        guard viewer == nil, let source = gesture.view as? UIImageView, let image = source.image else { return }
        let host = navigationController?.view ?? view!
        let background = UIView(frame: host.bounds)
        background.backgroundColor = .black
        background.alpha = 0
        host.addSubview(background)
        let zoom = UIScrollView(frame: host.bounds)
        zoom.delegate = self
        zoom.maximumZoomScale = 3
        zoom.alwaysBounceVertical = false
        zoom.contentSize = host.bounds.size
        zoom.showsVerticalScrollIndicator = false
        zoom.showsHorizontalScrollIndicator = false
        host.addSubview(zoom)
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.frame = source.convert(source.bounds, to: host)
        zoom.addSubview(imageView)
        source.alpha = 0

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
        close.tintColor = .white
        close.backgroundColor = UIColor(white: 1, alpha: 0.15)
        close.layer.cornerRadius = 18
        close.frame = CGRect(x: 16, y: host.safeAreaInsets.top + 6, width: 36, height: 36)
        close.addAction(UIAction { [weak self] _ in self?.dismissViewer(velocity: 0) }, for: .touchUpInside)
        let actions = UILabel()
        actions.text = "💬 12      🔁 31      ♡ 904      ↗"
        actions.font = .systemFont(ofSize: 16)
        actions.textColor = .white
        actions.textAlignment = .center
        actions.frame = CGRect(x: 0, y: host.bounds.height - host.safeAreaInsets.bottom - 50, width: host.bounds.width, height: 30)
        let chrome: [UIView] = [close, actions]
        chrome.forEach {
            $0.alpha = 0
            host.addSubview($0)
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.delegate = self
        zoom.addGestureRecognizer(pan)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        zoom.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.require(toFail: doubleTap)
        zoom.addGestureRecognizer(tap)
        viewer = (background, zoom, imageView, chrome, source)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.2) {
            imageView.frame = self.fitRect(for: image, in: zoom.bounds)
            imageView.layer.cornerRadius = 0
            background.alpha = 1
            chrome.forEach { $0.alpha = 1 }
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        viewer?.image
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard let viewer else { return }
        // Keep the zoomed photo centered while it is smaller than the screen.
        let size = viewer.image.frame.size
        let insetX = max((scrollView.bounds.width - size.width) / 2, 0)
        let insetY = max((scrollView.bounds.height - size.height) / 2, 0)
        viewer.image.center = CGPoint(x: size.width / 2 + insetX, y: size.height / 2 + insetY)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let viewer else { return true }
        let v = pan.velocity(in: viewer.zoom)
        return viewer.zoom.zoomScale <= 1.01 && abs(v.y) > abs(v.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The zoom scroll view's own pan must not swallow the drag-to-dismiss.
        other.view === viewer?.zoom
    }

    @objc private func zoomTap(_ gesture: UITapGestureRecognizer) {
        guard let viewer else { return }
        if viewer.zoom.zoomScale > 1.01 {
            viewer.zoom.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: viewer.image)
            let size = CGSize(width: viewer.zoom.bounds.width / 2.5, height: viewer.zoom.bounds.height / 2.5)
            viewer.zoom.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
                             animated: true)
        }
    }

    @objc private func toggleChrome() {
        guard let viewer else { return }
        let show = viewer.chrome.first?.alpha ?? 0 < 0.5
        UIView.animate(withDuration: 0.25) { viewer.chrome.forEach { $0.alpha = show ? 1 : 0 } }
    }

    /// Dragging down: the photo follows and shrinks, the black thins out.
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let viewer else { return }
        let t = gesture.translation(in: viewer.zoom)
        let dy = max(t.y, 0)
        switch gesture.state {
        case .changed:
            let s = 1 - min(dy / 1400, 0.3)
            viewer.image.transform = CGAffineTransform(translationX: t.x * 0.7, y: t.y).scaledBy(x: s, y: s)
            viewer.background.alpha = 1 - min(dy / 420, 0.85)
            viewer.chrome.forEach { $0.alpha = max(0, 1 - dy / 80) }
        case .ended, .cancelled:
            let v = gesture.velocity(in: viewer.zoom).y
            if dy > 110 || v > 900 {
                dismissViewer(velocity: v)
            } else {
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3) {
                    viewer.image.transform = .identity
                    viewer.background.alpha = 1
                    viewer.chrome.forEach { $0.alpha = 1 }
                }
            }
        default:
            break
        }
    }

    /// The photo flies back into its place in the timeline.
    private func dismissViewer(velocity: CGFloat) {
        guard let viewer else { return }
        self.viewer = nil
        let host = viewer.background.superview ?? view!
        let target = viewer.source.convert(viewer.source.bounds, to: host)
        let current = viewer.image.convert(viewer.image.bounds, to: host)
        viewer.image.transform = .identity
        host.addSubview(viewer.image)
        viewer.image.frame = current
        viewer.zoom.removeFromSuperview()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: min(velocity / 2000, 1)) {
            viewer.image.frame = target
            viewer.image.layer.cornerRadius = 16
            viewer.background.alpha = 0
            viewer.chrome.forEach { $0.alpha = 0 }
        } completion: { _ in
            viewer.source.alpha = 1
            viewer.image.removeFromSuperview()
            viewer.background.removeFromSuperview()
            viewer.chrome.forEach { $0.removeFromSuperview() }
        }
    }
}

// MARK: - 17. Translate

final class TranslateDemoViewController: TrickPage {
    var author: ChannelPerson?
    var original = "Liquid interfaces aren't about looks. They're about feeling real physics under your finger — springs, drops and light."
    var translation = "Жидкие интерфейсы — это не про внешний вид. Это про ощущение настоящей физики под пальцем: пружины, капли и свет."
    private let textLabel = UILabel()
    private let button = UIButton(type: .system)
    private let note = UILabel()
    private var translated = false
    private var revealStart: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var revealText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = TimelinePalette.background
        navigationItem.title = "Пост"
        let avatar = UIImageView(image: ChannelAvatar.image(for: author ?? trickPeople[7], size: 48))
        let name = UILabel()
        let header = NSMutableAttributedString(string: (author?.name ?? "Alex Rivera") + "\n", attributes: [.font: UIFont.systemFont(ofSize: 16, weight: .bold),
                                                                                     .foregroundColor: UIColor.white])
        header.append(NSAttributedString(string: "@alex_rivera", attributes: [.font: UIFont.systemFont(ofSize: 15),
                                                                                .foregroundColor: TimelinePalette.secondary]))
        name.attributedText = header
        name.numberOfLines = 2
        textLabel.text = original
        textLabel.numberOfLines = 0
        textLabel.font = .systemFont(ofSize: 20)
        textLabel.textColor = .white
        button.setTitle("Перевести пост", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.tintColor = TimelinePalette.accent
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        note.font = .systemFont(ofSize: 13)
        note.textColor = TimelinePalette.secondary
        note.text = " "
        let time = UILabel()
        time.text = "10:24 · 23 окт. 2026 · 48,1 тыс. просмотров"
        time.font = .systemFont(ofSize: 14)
        time.textColor = TimelinePalette.secondary
        for v in [avatar, name, textLabel, button, note, time] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            avatar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48),
            name.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            textLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 14),
            textLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            textLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            note.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 10),
            note.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
            button.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 2),
            button.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
            time.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 14),
            time.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        link?.invalidate()
    }

    /// The text crumbles into dust; the other language types itself in, letters fading up one after another.
    private func toggle() {
        translated.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DustAnimator.blowAway(textLabel, wind: CGVector(dx: 80, dy: -40), gravity: -20, grain: 1, releaseWindow: 0.45)
        revealText = translated ? translation : original
        button.setTitle(translated ? "Показать оригинал" : "Перевести пост", for: .normal)
        UIView.transition(with: note, duration: 0.25, options: .transitionCrossDissolve) {
            self.note.text = self.translated ? "Переведено с английского" : " "
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            textLabel.attributedText = attributed(revealed: 0)
            textLabel.alpha = 1
            revealStart = CACurrentMediaTime()
            link?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    private func attributed(revealed: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, char) in revealText.enumerated() {
            let alpha = min(max((revealed - CGFloat(index)) / 8, 0), 1)
            result.append(NSAttributedString(string: String(char), attributes: [
                .font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor(white: 1, alpha: alpha)]))
        }
        return result
    }

    @objc private func tick() {
        let revealed = CGFloat(CACurrentMediaTime() - revealStart) * 110
        textLabel.attributedText = attributed(revealed: revealed)
        if revealed > CGFloat(revealText.count) + 8 {
            link?.invalidate()
            link = nil
        }
    }
}

// MARK: - 18. Community notes

final class CommunityNotesDemoViewController: TrickPage {
    var postText: String?
    var noteText: String?
    var author: ChannelPerson?
    var highlightedFacts: [String]?
    private let body = UILabel()
    private let bodyContainer = UIStackView()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
    private var expanded = false
    private var underlines: [CAShapeLayer] = []
    private var facts: [String] { highlightedFacts ?? ["снято в 2019 году", "Онежском озере", "не на Байкале"] }
    private var rateButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = TimelinePalette.background
        navigationItem.title = "Пост"
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        let header = UILabel()
        let text = NSMutableAttributedString(string: (author?.name ?? "Travel Daily") + "  ", attributes: [.font: UIFont.systemFont(ofSize: 16, weight: .bold),
                                                                                    .foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: "@travel_daily · 3 ч", attributes: [.font: UIFont.systemFont(ofSize: 15),
                                                                                   .foregroundColor: TimelinePalette.secondary]))
        header.attributedText = text
        stack.addArrangedSubview(header)
        let post = UILabel()
        post.text = postText ?? "Это фото сделано вчера на Байкале! Невероятный лёд 🧊"
        post.numberOfLines = 0
        post.font = .systemFont(ofSize: 17)
        post.textColor = .white
        stack.addArrangedSubview(post)
        let photo = UIImageView(image: DemoPhotos.image(.ocean, size: CGSize(width: 800, height: 500), seed: 71))
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = 16
        photo.heightAnchor.constraint(equalTo: photo.widthAnchor, multiplier: 0.58).isActive = true
        stack.addArrangedSubview(photo)

        let note = UIStackView()
        note.axis = .vertical
        note.spacing = 10
        note.isLayoutMarginsRelativeArrangement = true
        note.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        note.layer.borderColor = UIColor(white: 1, alpha: 0.2).cgColor
        note.layer.borderWidth = 1
        note.layer.cornerRadius = 14
        let title = UILabel()
        title.text = "👥  Читатели добавили контекст"
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textColor = .white
        chevron.tintColor = TimelinePalette.secondary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let titleRow = UIStackView(arrangedSubviews: [title, chevron])
        titleRow.isUserInteractionEnabled = true
        titleRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
        note.addArrangedSubview(titleRow)
        body.text = noteText ?? ("Фото снято в 2019 году на Онежском озере, а не на Байкале. Оригинал опубликован фотографом в его портфолио; " +
            "метаданные и место съёмки совпадают с исходной публикацией.")
        body.numberOfLines = 0
        body.font = .systemFont(ofSize: 15)
        body.textColor = UIColor(white: 1, alpha: 0.85)
        let question = UILabel()
        question.text = "Насколько полезна эта заметка?"
        question.font = .systemFont(ofSize: 14, weight: .semibold)
        question.textColor = .white
        let buttons = UIStackView(arrangedSubviews: ["Полезно", "Бесполезно"].enumerated().map { index, title in
            var config = UIButton.Configuration.bordered()
            config.title = title
            config.cornerStyle = .capsule
            config.baseForegroundColor = .white
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.rate(index) })
            button.clipsToBounds = true
            rateButtons.append(button)
            return button
        })
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        for v in [body, question, buttons] as [UIView] {
            bodyContainer.addArrangedSubview(v)
        }
        bodyContainer.axis = .vertical
        bodyContainer.spacing = 12
        bodyContainer.isHidden = true
        bodyContainer.alpha = 0
        note.addArrangedSubview(bodyContainer)
        stack.addArrangedSubview(note)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Нажмите на «Читатели добавили контекст»")
    }

    @objc private func toggle() {
        expanded.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        underlines.forEach { $0.removeFromSuperlayer() }
        underlines = []
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2) {
            self.bodyContainer.isHidden = !self.expanded
            self.bodyContainer.alpha = self.expanded ? 1 : 0
            self.chevron.transform = self.expanded ? CGAffineTransform(rotationAngle: .pi) : .identity
            self.view.layoutIfNeeded()
        } completion: { _ in
            if self.expanded {
                self.underlineFacts()
            }
        }
    }

    /// Each key fact gets a highlighter stroke drawn under it, one after another.
    private func underlineFacts() {
        guard let text = body.text else { return }
        let storage = NSTextStorage(string: text, attributes: [.font: body.font!])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: body.bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var delay: CFTimeInterval = 0
        for fact in facts {
            let range = (text as NSString).range(of: fact)
            guard range.location != NSNotFound else { continue }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                           in: container) { rect, _ in
                let line = CAShapeLayer()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - 3))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
                line.path = path.cgPath
                line.strokeColor = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.55).cgColor
                line.lineWidth = 8
                line.lineCap = .round
                line.strokeEnd = 0
                self.body.layer.insertSublayer(line, at: 0)
                self.underlines.append(line)
                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0
                draw.toValue = 1
                draw.duration = 0.35
                draw.beginTime = CACurrentMediaTime() + delay
                draw.fillMode = .backwards
                draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
                line.strokeEnd = 1
                line.add(draw, forKey: "draw")
                delay += 0.3
            }
        }
        for i in 0..<facts.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * Double(i) + 0.2) {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    /// The chosen answer fills with colour from the left, the other fades.
    private func rate(_ index: Int) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        for (i, button) in rateButtons.enumerated() {
            if i == index {
                let fill = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: button.bounds.height))
                fill.backgroundColor = index == 0 ? UIColor(red: 0.1, green: 0.7, blue: 0.4, alpha: 0.6) : UIColor(red: 0.9, green: 0.25, blue: 0.3, alpha: 0.6)
                fill.isUserInteractionEnabled = false
                button.insertSubview(fill, at: 0)
                UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut]) {
                    fill.frame.size.width = button.bounds.width
                }
                button.configuration?.title = index == 0 ? "Спасибо! ✓" : "Учтём ✓"
            } else {
                UIView.animate(withDuration: 0.3) { button.alpha = 0.35 }
            }
            button.isUserInteractionEnabled = false
        }
    }
}

// MARK: - 19. Post analytics

final class PostAnalyticsDemoViewController: TrickPage {
    private struct Metric {
        let title: String
        let total: Int
        let values: [Double]
        let color: UIColor
        let extra: [(String, Int)]
    }

    private let chart = ParticleChartView()
    private let selector = LiquidSelector(titles: ["Показы", "Вовлечения", "Лайки"], style: .segments,
                                          liquid: UIColor(white: 1, alpha: 0.9), selectedTint: .black, normalTint: UIColor(white: 1, alpha: 0.7))
    private var rows: [(UILabel, RollingCounterLabel)] = []
    private var laidOut = CGSize.zero
    private let metrics: [Metric] = {
        var random = SplitMix(seed: 9)
        func series(_ scale: Double, _ peak: Double) -> [Double] {
            (0..<24).map { i in
                let x = Double(i) / 23
                return scale * (0.15 + exp(-pow((x - peak) / 0.16, 2)) + 0.25 * Double(random.next()))
            }
        }
        return [
            Metric(title: "Показы", total: 128_400, values: series(1, 0.3), color: UIColor(red: 0.3, green: 0.65, blue: 1, alpha: 1),
                   extra: [("Переходы в профиль", 1_840), ("Клики по ссылке", 3_210), ("Новые подписчики", 412)]),
            Metric(title: "Вовлечения", total: 9_870, values: series(1, 0.55), color: UIColor(red: 0.6, green: 0.45, blue: 1, alpha: 1),
                   extra: [("Ответы", 640), ("Репосты", 1_130), ("Закладки", 2_480)]),
            Metric(title: "Лайки", total: 6_215, values: series(1, 0.7), color: UIColor(red: 1, green: 0.3, blue: 0.5, alpha: 1),
                   extra: [("Лайки от подписчиков", 4_020), ("Лайки из поиска", 1_380), ("Лайки из рекомендаций", 815)]),
        ]
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = "Аналитика поста"
        chart.particleCount = 12_000
        chart.pointSize = 2.0
        view.addSubview(chart)
        selector.addAction(UIAction { [weak self] _ in self?.showMetric(animated: true) }, for: .valueChanged)
        view.addSubview(selector)
        for _ in 0..<3 {
            let title = UILabel()
            title.font = .systemFont(ofSize: 15)
            title.textColor = TrickPalette.secondary
            let value = RollingCounterLabel()
            value.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
            value.textColor = .white
            view.addSubview(title)
            view.addSubview(value)
            rows.append((title, value))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        let width = view.bounds.width
        selector.frame = CGRect(x: (width - 320) / 2, y: top + 10, width: 320, height: 40)
        chart.frame = CGRect(x: 0, y: selector.frame.maxY + 10, width: width, height: 340)
        for (index, row) in rows.enumerated() {
            let y = chart.frame.maxY + 14 + CGFloat(index) * 44
            row.0.frame = CGRect(x: 20, y: y, width: width - 160, height: 24)
            let size = row.1.intrinsicContentSize
            row.1.frame = CGRect(x: width - 20 - size.width, y: y, width: size.width, height: 24)
        }
        if chart.bounds.size != laidOut, chart.bounds.width > 0 {
            let first = laidOut == .zero
            laidOut = chart.bounds.size
            showMetric(animated: !first, first: first)
        }
    }

    private func showMetric(animated: Bool, first: Bool = false) {
        let metric = metrics[selector.selectedIndex]
        let width = chart.bounds.width
        // The total, as text drawn with particles.
        let number = SVGToParticleConverter.path(forText: metric.total.formatted(.number.grouping(.automatic)),
                                                 font: .systemFont(ofSize: 54, weight: .heavy))
        let box = number.cgPath.boundingBoxOfPath
        number.apply(CGAffineTransform(translationX: 20 - box.minX, y: 26 - box.minY))
        // The 24-hour line under it.
        let plot = CGRect(x: 20, y: 140, width: width - 40, height: 170)
        let maxValue = metric.values.max() ?? 1
        let line = UIBezierPath()
        for (index, value) in metric.values.enumerated() {
            let point = CGPoint(x: plot.minX + plot.width * CGFloat(index) / CGFloat(metric.values.count - 1),
                                y: plot.maxY - plot.height * CGFloat(value / maxValue))
            index == 0 ? line.move(to: point) : line.addLine(to: point)
        }
        let baseline = UIBezierPath(rect: CGRect(x: plot.minX, y: plot.maxY + 6, width: plot.width, height: 1))
        let counts = ParticleChartView.split(chart.particleCount, weights: [0.6, 0.33, 0.07])
        var text = ParticleChartSegment(path: number, count: counts[0], pointSize: 1.7, color: .white, alpha: 1, order: { $0.x })
        text.stiffness = 4
        text.affectsBrightness = false
        let curve = ParticleChartSegment(path: line, lineWidth: 3, count: counts[1], color: metric.color, alpha: 1, order: { $0.x })
        var axis = ParticleChartSegment(path: baseline, lineWidth: 1, count: counts[2], pointSize: 1.2,
                                        color: UIColor(white: 1, alpha: 1), alpha: 0.25, order: { $0.x })
        axis.affectsBrightness = false
        chart.show([text, curve, axis], from: first ? CGRect(x: plot.minX, y: plot.maxY, width: plot.width, height: 2) : nil)
        for (index, row) in rows.enumerated() {
            row.0.text = metric.extra[index].0
            row.1.setText(metric.extra[index].1.formatted(.number.grouping(.automatic)), animated: animated)
        }
        view.setNeedsLayout()
        if animated {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
