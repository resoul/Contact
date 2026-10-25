//
//  PhotoPostView.swift
//  controller
//
//  An Instagram-style photo post: a swipeable carousel with liquid page dots, double-tap for a
//  liquid heart, a like that pops, saving that shrinks the photo into a drop and drops it into the
//  bookmark, and (when enabled) filter chips that wash the new look over the photo as a wave.
//

import UIKit

struct PhotoPostModel {
    let author: ChannelPerson
    let location: String
    let photos: [DemoPhotos.Scene]
    var likes: Int
    let caption: String
    let comments: Int
    let time: String
    var showsFilters = false
}

final class PhotoPostView: UIView, UIScrollViewDelegate {
    private(set) var model: PhotoPostModel
    private let carousel = UIScrollView()
    private var pages: [UIImageView] = []
    private var originals: [UIImage] = []
    private let dots: GooeyPageDots
    private let likeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let likesLabel = RollingCounterLabel()
    private let wave = FilterWaveView()
    private var filterButtons: [UIButton] = []
    private var filter = PhotoFilter.original
    private var liked = false
    private var saved = false
    private let photoContainer = LayoutCallbackView()

    init(model: PhotoPostModel) {
        self.model = model
        dots = GooeyPageDots(count: model.photos.count)
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var page: Int {
        Int((carousel.contentOffset.x / max(carousel.bounds.width, 1)).rounded())
    }

    private func build() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Header
        let avatar = UIImageView(image: ChannelAvatar.image(for: model.author, size: 32))
        avatar.widthAnchor.constraint(equalToConstant: 32).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let name = UILabel()
        name.text = model.author.name.lowercased().replacingOccurrences(of: " ", with: "_")
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.textColor = .white
        let place = UILabel()
        place.text = model.location
        place.font = .systemFont(ofSize: 12)
        place.textColor = .white
        let names = UIStackView(arrangedSubviews: [name, place])
        names.axis = .vertical
        let more = UIImageView(image: UIImage(systemName: "ellipsis"))
        more.tintColor = .white
        let header = UIStackView(arrangedSubviews: [avatar, names, UIView(), more])
        header.spacing = 10
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 14)
        stack.addArrangedSubview(header)

        // Carousel
        carousel.isPagingEnabled = true
        carousel.showsHorizontalScrollIndicator = false
        carousel.delegate = self
        photoContainer.addSubview(carousel)
        for (index, scene) in model.photos.enumerated() {
            let image = DemoPhotos.image(scene, size: CGSize(width: 600, height: 600), seed: UInt64(index + 1))
            originals.append(image)
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            carousel.addSubview(view)
            pages.append(view)
        }
        photoContainer.addSubview(wave)
        photoContainer.onLayout = { [weak self] in self?.layoutPhotos() }
        photoContainer.heightAnchor.constraint(equalTo: photoContainer.widthAnchor).isActive = true
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        photoContainer.addGestureRecognizer(doubleTap)
        stack.addArrangedSubview(photoContainer)

        if model.showsFilters {
            stack.addArrangedSubview(makeFilterRow())
        }

        // Actions: like, comment, share · dots · save
        configure(likeButton, symbol: "heart")
        likeButton.addAction(UIAction { [weak self] _ in self?.setLiked(!(self?.liked ?? false), from: nil) }, for: .touchUpInside)
        let comment = UIButton(type: .system)
        configure(comment, symbol: "bubble.right")
        let share = UIButton(type: .system)
        configure(share, symbol: "paperplane")
        configure(saveButton, symbol: "bookmark")
        saveButton.addAction(UIAction { [weak self] _ in self?.toggleSave() }, for: .touchUpInside)
        let left = UIStackView(arrangedSubviews: [likeButton, comment, share])
        left.spacing = 4
        let actions = UIView()
        for view in [left, dots, saveButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            actions.addSubview(view)
        }
        NSLayoutConstraint.activate([
            actions.heightAnchor.constraint(equalToConstant: 36),
            left.leadingAnchor.constraint(equalTo: actions.leadingAnchor, constant: 6),
            left.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            dots.centerXAnchor.constraint(equalTo: actions.centerXAnchor),
            dots.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: actions.trailingAnchor, constant: -6),
            saveButton.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
        ])
        dots.isHidden = model.photos.count < 2
        stack.setCustomSpacing(2, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(actions)

        // Likes, caption, comments, time
        likesLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        likesLabel.setText(likesText, animated: false)
        let likesRow = UIView()
        likesLabel.translatesAutoresizingMaskIntoConstraints = false
        likesRow.addSubview(likesLabel)
        NSLayoutConstraint.activate([
            likesLabel.leadingAnchor.constraint(equalTo: likesRow.leadingAnchor, constant: 14),
            likesLabel.topAnchor.constraint(equalTo: likesRow.topAnchor),
            likesLabel.bottomAnchor.constraint(equalTo: likesRow.bottomAnchor),
        ])
        stack.addArrangedSubview(likesRow)
        let caption = UILabel()
        let text = NSMutableAttributedString(string: name.text ?? "", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)])
        text.append(NSAttributedString(string: "  " + model.caption, attributes: [.font: UIFont.systemFont(ofSize: 14)]))
        caption.attributedText = text
        caption.textColor = .white
        caption.numberOfLines = 0
        let comments = UILabel()
        comments.text = "View all comments (\(model.comments))\n\(model.time)"
        comments.numberOfLines = 2
        comments.font = .systemFont(ofSize: 13)
        comments.textColor = PhotoFeedPalette.secondary
        for label in [caption, comments] {
            let row = UIStackView(arrangedSubviews: [label])
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
        ])
    }

    private var likesText: String {
        "Likes: \(model.likes.formatted(.number.grouping(.automatic)))"
    }

    private func configure(_ button: UIButton, symbol: String) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)),
                        for: .normal)
        button.tintColor = .white
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func makeFilterRow() -> UIView {
        let row = UIStackView()
        row.spacing = 8
        for (index, filter) in PhotoFilter.allCases.enumerated() {
            var config = UIButton.Configuration.filled()
            config.title = filter.rawValue
            config.cornerStyle = .capsule
            config.buttonSize = .small
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in self?.pick(filter, index: index) }, for: .touchUpInside)
            filterButtons.append(button)
            row.addArrangedSubview(button)
        }
        styleFilterButtons()
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: 34),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return scroll
    }

    private func styleFilterButtons() {
        for (index, button) in filterButtons.enumerated() {
            let selected = PhotoFilter.allCases[index] == filter
            button.configuration?.baseBackgroundColor = selected ? .white : UIColor(white: 1, alpha: 0.12)
            button.configuration?.baseForegroundColor = selected ? .black : .white
        }
    }

    /// Called by the photo container once it has its size (after the stack view laid it out).
    private func layoutPhotos() {
        let size = photoContainer.bounds.size
        carousel.frame = photoContainer.bounds
        carousel.contentSize = CGSize(width: size.width * CGFloat(pages.count), height: size.height)
        for (index, page) in pages.enumerated() {
            page.frame = CGRect(x: size.width * CGFloat(index), y: 0, width: size.width, height: size.height)
        }
        wave.frame = photoContainer.bounds
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        dots.setProgress(scrollView.contentOffset.x / max(scrollView.bounds.width, 1))
    }

    // MARK: Like

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard let host = window?.rootViewController?.view else { return }
        HeartPop.show(at: gesture.location(in: host), in: host, target: nil, arrive: nil)
        setLiked(true, from: gesture)
    }

    private func setLiked(_ value: Bool, from gesture: UIGestureRecognizer?) {
        let changed = value != liked
        liked = value
        if changed {
            model.likes += value ? 1 : -1
            likesLabel.setText(likesText, animated: true, up: value)
        }
        likeButton.setImage(UIImage(systemName: value ? "heart.fill" : "heart",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)), for: .normal)
        likeButton.tintColor = value ? PhotoFeedPalette.like : .white
        likeButton.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.8) {
            self.likeButton.transform = .identity
        }
        if value, gesture == nil, let window {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            IslandConfetti.burst(in: window, from: likeButton.convert(CGPoint(x: 20, y: 18), to: window), direction: -.pi / 2,
                                 spread: 2 * .pi, particles: 60, sparkShare: 1, sparkColor: PhotoFeedPalette.like, speedScale: 0.28)
        }
    }

    // MARK: Save

    /// The photo shrinks into a drop and falls into the bookmark, which gulps it.
    private func toggleSave() {
        saved.toggle()
        guard saved, let window else {
            saveButton.setImage(UIImage(systemName: "bookmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                                for: .normal)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let photo = UIImageView(image: pages[page].image)
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        let start = photoContainer.convert(photoContainer.bounds, to: window)
        photo.frame = start
        window.addSubview(photo)
        let end = saveButton.convert(CGPoint(x: 20, y: 18), to: window)
        let drop: CGFloat = 22
        let duration = 0.7
        let path = UIBezierPath()
        path.move(to: start.center)
        path.addQuadCurve(to: end, controlPoint: CGPoint(x: (start.midX + end.x) / 2 + 60, y: start.midY - 40))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path.cgPath
        let shrink = CABasicAnimation(keyPath: "bounds.size")
        shrink.fromValue = start.size
        shrink.toValue = CGSize(width: drop, height: drop)
        let round = CABasicAnimation(keyPath: "cornerRadius")
        round.fromValue = 0
        round.toValue = drop / 2
        let group = CAAnimationGroup()
        group.animations = [move, shrink, round]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.3, 1)
        photo.layer.add(group, forKey: "save")
        photo.layer.position = end
        photo.layer.bounds.size = CGSize(width: drop, height: drop)
        photo.layer.cornerRadius = drop / 2
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            photo.removeFromSuperview()
            guard let self else { return }
            saveButton.setImage(UIImage(systemName: "bookmark.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                                for: .normal)
            saveButton.transform = CGAffineTransform(scaleX: 1.4, y: 0.8)
            UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.35, initialSpringVelocity: 0.6) {
                self.saveButton.transform = .identity
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: Filters

    private func pick(_ new: PhotoFilter, index: Int) {
        guard new != filter, wave.isHidden else { return }
        let oldIndex = PhotoFilter.allCases.firstIndex(of: filter) ?? 0
        let current = page
        let old = pages[current].image ?? originals[current]
        let filtered = originals.map { new.apply(to: $0) }
        filter = new
        styleFilterButtons()
        wave.wash(from: old, to: filtered[current], forward: index > oldIndex) { [weak self] in
            guard let self else { return }
            for (page, image) in zip(pages, filtered) {
                page.image = image
            }
        }
    }
}

/// A view that reports its own layout pass, for content sized by a parent stack view.
final class LayoutCallbackView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
