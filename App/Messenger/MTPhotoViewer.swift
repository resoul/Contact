//
//  MTPhotoViewer.swift
//  controller
//
//  Full-screen photos from a chat album. The tapped photo flies out of its bubble (which stays
//  empty while it is open), the album pages sideways, pinch or double-tap zooms, a tap hides the
//  bars, and dragging down lets the photo go back into its bubble.
//

import UIKit

final class MTPhotoViewer: UIView, UIScrollViewDelegate {
    private let images: [UIImage]
    private let sources: [UIImageView]
    private let title: String
    private let dim = UIView()
    private let pager = UIScrollView()
    private var pages: [UIScrollView] = []
    private let topBar = UIView()
    private let counter = MTViews.label(size: 16, weight: .semibold, color: .white)
    private let subtitle = MTViews.label(size: 13, color: UIColor(white: 1, alpha: 0.7))
    private let bottomBar = UIView()
    private var index: Int
    private var chromeHidden = false
    private var dragStart = CGPoint.zero

    init(in host: UIView, sources: [UIImageView], start: Int, title: String) {
        self.sources = sources
        images = sources.map { $0.image ?? UIImage() }
        index = start
        self.title = title
        super.init(frame: host.bounds)
        host.addSubview(self)
        dim.backgroundColor = .black
        dim.frame = bounds
        dim.alpha = 0
        addSubview(dim)

        pager.frame = bounds
        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.delegate = self
        pager.contentSize = CGSize(width: bounds.width * CGFloat(images.count), height: bounds.height)
        addSubview(pager)
        for (page, image) in images.enumerated() {
            let zoom = UIScrollView(frame: CGRect(x: bounds.width * CGFloat(page), y: 0, width: bounds.width, height: bounds.height))
            zoom.minimumZoomScale = 1
            zoom.maximumZoomScale = 4
            zoom.delegate = self
            zoom.showsVerticalScrollIndicator = false
            zoom.showsHorizontalScrollIndicator = false
            zoom.contentInsetAdjustmentBehavior = .never
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFit
            view.frame = fittedFrame(image)
            zoom.addSubview(view)
            zoom.contentSize = bounds.size
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            double.numberOfTapsRequired = 2
            zoom.addGestureRecognizer(double)
            let single = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
            single.require(toFail: double)
            zoom.addGestureRecognizer(single)
            pager.addSubview(zoom)
            pages.append(zoom)
        }
        pager.contentOffset.x = bounds.width * CGFloat(start)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        drag.delegate = self
        addGestureRecognizer(drag)

        buildChrome(safeTop: host.safeAreaInsets.top, safeBottom: host.safeAreaInsets.bottom)
        open()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func fittedFrame(_ image: UIImage) -> CGRect {
        let size = image.size.width > 0 ? image.size : CGSize(width: 1, height: 1)
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2, width: fitted.width,
                      height: fitted.height)
    }

    private var imageView: UIImageView? { pages[index].subviews.first as? UIImageView }

    private func buildChrome(safeTop: CGFloat, safeBottom: CGFloat) {
        topBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: safeTop + 52)
        topBar.backgroundColor = UIColor(white: 0, alpha: 0.4)
        let close = MTViews.iconButton("chevron.backward", size: 19, tint: .white)
        close.frame = CGRect(x: 6, y: safeTop + 4, width: 44, height: 44)
        close.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        topBar.addSubview(close)
        counter.textAlignment = .center
        counter.frame = CGRect(x: 60, y: safeTop + 6, width: bounds.width - 120, height: 20)
        subtitle.textAlignment = .center
        subtitle.frame = CGRect(x: 60, y: safeTop + 26, width: bounds.width - 120, height: 16)
        subtitle.text = title
        topBar.addSubview(counter)
        topBar.addSubview(subtitle)
        addSubview(topBar)
        bottomBar.frame = CGRect(x: 0, y: bounds.height - safeBottom - 52, width: bounds.width, height: safeBottom + 52)
        bottomBar.backgroundColor = UIColor(white: 0, alpha: 0.4)
        for (position, symbol) in ["arrowshape.turn.up.right", "square.and.arrow.down", "trash"].enumerated() {
            let button = MTViews.iconButton(symbol, size: 20, tint: .white)
            button.frame = CGRect(x: CGFloat(position) * (bounds.width - 60) / 2 + 8, y: 4, width: 44, height: 44)
            button.addAction(UIAction { _ in MTViews.pop(button, scale: 0.85) }, for: .touchUpInside)
            bottomBar.addSubview(button)
        }
        addSubview(bottomBar)
        updateCounter()
        for bar in [topBar, bottomBar] { bar.alpha = 0 }
    }

    private func updateCounter() {
        counter.text = images.count > 1 ? "\(index + 1) of \(images.count)" : "Photo"
    }

    // MARK: Opening and closing

    private func open() {
        guard let target = imageView else { return }
        let source = sources[index]
        let flyer = flyingCopy(of: source)
        target.alpha = 0
        source.alpha = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, animations: {
            flyer.frame = target.frame
            flyer.layer.cornerRadius = 0
            self.dim.alpha = 1
            self.topBar.alpha = 1
            self.bottomBar.alpha = 1
        }, completion: { _ in
            target.alpha = 1
            flyer.removeFromSuperview()
        })
    }

    private func flyingCopy(of source: UIImageView) -> UIImageView {
        let flyer = UIImageView(image: source.image)
        flyer.contentMode = .scaleAspectFill
        flyer.clipsToBounds = true
        flyer.layer.cornerRadius = 12
        flyer.frame = source.convert(source.bounds, to: self)
        insertSubview(flyer, belowSubview: topBar)
        return flyer
    }

    /// The photo goes back into its bubble from wherever it is now.
    func close() {
        guard let current = imageView else { return }
        isUserInteractionEnabled = false
        let source = sources[index]
        let flyer = UIImageView(image: current.image)
        flyer.contentMode = .scaleAspectFill
        flyer.clipsToBounds = true
        flyer.frame = current.convert(current.bounds, to: self)
        flyer.transform = .identity
        insertSubview(flyer, belowSubview: topBar)
        pager.isHidden = true
        let target = source.convert(source.bounds, to: self)
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, animations: {
            flyer.frame = target
            flyer.layer.cornerRadius = 12
            self.dim.alpha = 0
            self.topBar.alpha = 0
            self.bottomBar.alpha = 0
        }, completion: { _ in
            self.sources.forEach { $0.alpha = 1 }
            self.removeFromSuperview()
        })
    }

    // MARK: Gestures

    @objc private func toggleChrome() {
        chromeHidden.toggle()
        UIView.animate(withDuration: 0.25) {
            self.topBar.alpha = self.chromeHidden ? 0 : 1
            self.bottomBar.alpha = self.chromeHidden ? 0 : 1
        }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        let zoom = pages[index]
        if zoom.zoomScale > 1 {
            zoom.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: zoom.subviews.first)
            let size = CGSize(width: zoom.bounds.width / 2.5, height: zoom.bounds.height / 2.5)
            zoom.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
                      animated: true)
        }
    }

    /// Drag down: the photo follows the finger and shrinks, the black fades; far enough lets it go.
    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard let current = imageView else { return }
        let translation = gesture.translation(in: self)
        let progress = min(max(translation.y / 400, 0), 1)
        switch gesture.state {
        case .changed:
            let scale = 1 - progress * 0.3
            current.transform = CGAffineTransform(translationX: translation.x, y: translation.y).scaledBy(x: scale, y: scale)
            dim.alpha = 1 - progress
            topBar.alpha = chromeHidden ? 0 : 1 - progress * 3
            bottomBar.alpha = topBar.alpha
        case .ended, .cancelled:
            if translation.y > 120 || gesture.velocity(in: self).y > 900 {
                close()
            } else {
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    current.transform = .identity
                    self.dim.alpha = 1
                    self.topBar.alpha = self.chromeHidden ? 0 : 1
                    self.bottomBar.alpha = self.topBar.alpha
                }
            }
        default:
            break
        }
    }

    // MARK: Scroll views

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        scrollView === pager ? nil : scrollView.subviews.first
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard let view = scrollView.subviews.first else { return }
        // Keep the zoomed photo centered while it is smaller than the screen.
        let x = max(0, (scrollView.bounds.width - view.frame.width) / 2)
        let y = max(0, (scrollView.bounds.height - view.frame.height) / 2)
        view.frame.origin = CGPoint(x: x, y: y)
        scrollView.contentSize = CGSize(width: max(view.frame.width, scrollView.bounds.width),
                                        height: max(view.frame.height, scrollView.bounds.height))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pager else { return }
        let page = Int((pager.contentOffset.x / max(pager.bounds.width, 1)).rounded())
        guard page != index, images.indices.contains(page) else { return }
        pages[index].setZoomScale(1, animated: false)
        // The bubble shows the photo that is not open, and hides the one that is.
        sources[index].alpha = 1
        index = page
        sources[index].alpha = 0
        updateCounter()
    }
}

extension MTPhotoViewer: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer, pan.view === self else { return true }
        let velocity = pan.velocity(in: self)
        return pages[index].zoomScale <= 1.01 && velocity.y > abs(velocity.x)
    }

    /// The pager's own pan must not block the drag-down.
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gesture.view === self && other.view is UIScrollView
    }
}
