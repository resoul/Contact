import UIKit

/// Shared media whose column count follows a pinch continuously: every cell sits between its spot
/// in the two neighbouring layouts, so the grid flows from 3 to 5 columns rather than jumping.
final class MediaGrid: UIView {
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
