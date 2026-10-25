import UIKit

final class MetalEffectsViewController: UIViewController {
    private enum Effect: Int, CaseIterable {
        case lava, fire, gravity, smoke, swarm

        var title: String {
            switch self {
            case .lava: return "Лава"
            case .fire: return "Огонь"
            case .gravity: return "Гравитация"
            case .smoke: return "Дым"
            case .swarm: return "Рой"
            }
        }

        var hint: String {
            switch self {
            case .lava: return "Слайдер меняет заполнение прогресс-бара."
            case .fire: return "Слайдер меняет высоту пламени. Палец создаёт ветер."
            case .gravity: return "Две галактики притягивают друг друга. Касание создаёт центр притяжения."
            case .smoke: return "Ведите пальцем, чтобы толкать и окрашивать дым."
            case .swarm: return "Стая движется вместе и избегает пальца."
            }
        }

        func makeView() -> MetalAnimationView {
            switch self {
            case .lava: return MetalLavaProgressBarView()
            case .fire: return MetalFireView()
            case .gravity: return NBodyView()
            case .smoke: return SmokeFluidView()
            case .swarm: return BoidsView()
            }
        }
    }

    private let modes = UISegmentedControl(items: Effect.allCases.map(\.title))
    private let stage = UIView()
    private let controls = UIStackView()
    private let hint = UILabel()
    private var effectView: MetalAnimationView?
    private var isVisible = false
    private let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(nibName: nil, bundle: nil)
        title = "Metal Effects"
    }

    required init?(coder: NSCoder) { fatalError("Use init(onBack:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.grouped

        let back = Views.iconButton("chevron.backward", size: 18)
        back.accessibilityLabel = "Back"
        back.accessibilityIdentifier = "contact.metalEffects.back"
        back.addAction(UIAction { [weak self] _ in self?.onBack() }, for: .touchUpInside)
        let heading = Views.label("Metal Effects", size: 17, weight: .semibold)
        heading.textAlignment = .center
        heading.accessibilityTraits = .header
        for child in [back, heading] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }

        modes.selectedSegmentIndex = 0
        modes.apportionsSegmentWidthsByContent = true
        modes.accessibilityIdentifier = "contact.metalEffects.mode"
        modes.addAction(UIAction { [weak self] _ in self?.showEffect() }, for: .valueChanged)
        stage.backgroundColor = .black
        stage.layer.cornerRadius = 20
        stage.layer.cornerCurve = .continuous
        stage.clipsToBounds = true
        stage.setContentHuggingPriority(.defaultLow, for: .vertical)
        stage.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        controls.axis = .vertical
        controls.spacing = 10
        hint.numberOfLines = 0
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = Palette.secondary

        let stack = UIStackView(arrangedSubviews: [modes, stage, controls, hint])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 4),
            back.topAnchor.constraint(equalTo: safe.topAnchor),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
            heading.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 8),
            heading.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -56),
            heading.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            stack.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
            modes.heightAnchor.constraint(equalToConstant: 34),
        ])
        showEffect()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        effectView?.startAnimation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        effectView?.stopAnimation()
    }

    private func showEffect() {
        guard let effect = Effect(rawValue: modes.selectedSegmentIndex) else { return }
        effectView?.stopAnimation()
        effectView?.removeFromSuperview()
        effectView = nil
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let effectView = effect.makeView()
        effectView.progress = 0.6
        effectView.accessibilityIdentifier = "contact.metalEffects.canvas.\(effect.rawValue)"
        effectView.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(effectView)
        if effect == .lava {
            NSLayoutConstraint.activate([
                effectView.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 16),
                effectView.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -16),
                effectView.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
                effectView.heightAnchor.constraint(equalToConstant: 34),
            ])
        } else {
            NSLayoutConstraint.activate([
                effectView.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
                effectView.topAnchor.constraint(equalTo: stage.topAnchor),
                effectView.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
            ])
        }
        self.effectView = effectView
        effectView.controls.forEach { controls.addArrangedSubview(makeControl($0)) }
        hint.text = effect.hint
        if isVisible { effectView.startAnimation() }
    }

    private func makeControl(_ control: MetalEffectControl) -> UIView {
        switch control {
        case let .slider(title, range, value, logarithmic, format, onChange):
            let label = Views.label(title, size: 13, color: Palette.secondary)
            label.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let output = Views.label(format(value), size: 13)
            output.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            output.textAlignment = .right
            output.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let slider = UISlider()
            slider.tintColor = Palette.accent
            slider.accessibilityLabel = title
            slider.minimumValue = logarithmic ? 0 : range.lowerBound
            slider.maximumValue = logarithmic ? 1 : range.upperBound
            slider.value = logarithmic
                ? log(value / range.lowerBound) / log(range.upperBound / range.lowerBound) : value
            slider.accessibilityValue = format(value)
            slider.addAction(UIAction { [weak slider] _ in
                guard let slider else { return }
                let value = logarithmic
                    ? range.lowerBound * pow(range.upperBound / range.lowerBound, slider.value) : slider.value
                output.text = format(value)
                slider.accessibilityValue = format(value)
                onChange(value)
            }, for: .valueChanged)
            let row = UIStackView(arrangedSubviews: [label, slider, output])
            row.spacing = 8
            row.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return row
        case let .segments(items, selected, onChange):
            let segments = UISegmentedControl(items: items)
            segments.selectedSegmentIndex = selected
            segments.addAction(UIAction { [weak segments] _ in
                guard let segments else { return }
                onChange(segments.selectedSegmentIndex)
            }, for: .valueChanged)
            return segments
        case let .button(title, action):
            var configuration = UIButton.Configuration.tinted()
            configuration.title = title
            configuration.baseForegroundColor = Palette.accent
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            return button
        }
    }
}
