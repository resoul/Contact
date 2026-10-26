import UIKit
import AsyncDisplayKit

public struct ItemListHeaderAction {
    public let title: String
    public let systemImage: String
    public let showsTitle: Bool
    public let isSelected: Bool
    public let handler: () -> Void
    public init(
        title: String,
        systemImage: String,
        showsTitle: Bool = false,
        isSelected: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.showsTitle = showsTitle
        self.isSelected = isSelected
        self.handler = handler
    }
}

open class ItemListController: UIViewController {
    public let pager: ListPagerNode
    public private(set) var collapsingContainer: CollapsingListContainerNode?
    public var onBack: (() -> Void)?
    public var subtitle: String = "" { didSet { subtitleLabel.text = subtitle } }
    private let heading = UILabel()
    private let subtitleLabel = UILabel()
    private let back = UIButton(type: .system)
    private let actions = UIStackView()
    private var state: ItemListState
    private var theme: ListTheme
    private var savedPopGestureEnabled: Bool?
    private var actionsWidth: CGFloat = 0

    public init(title: String, state: ItemListState, theme: ListTheme = ListTheme()) {
        self.state = state
        self.theme = theme
        pager = ListPagerNode(theme: theme)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    public required init?(coder: NSCoder) { fatalError("Use init(title:state:theme:)") }

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        view.addSubview(pager.view)
        heading.text = title
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.adjustsFontForContentSizeCategory = true
        heading.textColor = theme.primary
        heading.accessibilityTraits = .header
        view.addSubview(heading)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = theme.secondary
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 2
        view.addSubview(subtitleLabel)
        back.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        back.tintColor = theme.accent
        back.accessibilityLabel = "Back"
        back.accessibilityIdentifier = "listui.back"
        back.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if let onBack = self.onBack { onBack() } else { self.navigationController?.popViewController(animated: true) }
        }, for: .touchUpInside)
        view.addSubview(back)
        actions.axis = .horizontal
        actions.spacing = 0
        view.addSubview(actions)
        pager.apply(state: state, theme: theme, animated: false)
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collapsingContainer?.setSuspended(false)

        if let gesture = navigationController?.interactivePopGestureRecognizer {
            savedPopGestureEnabled = gesture.isEnabled
            gesture.isEnabled = false
        }
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        collapsingContainer?.setSuspended(true)
        pager.currentList?.closeReveals(animated: false)
        if let enabled = savedPopGestureEnabled { navigationController?.interactivePopGestureRecognizer?.isEnabled = enabled }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let contentNode: ASDisplayNode = collapsingContainer ?? pager
        ASTraitCollectionPropagateDown(contentNode, ASPrimitiveTraitCollectionFromUITraitCollection(traitCollection))
        let top = view.safeAreaInsets.top
        let width = view.bounds.width
        back.frame = CGRect(x: 4, y: top, width: 44, height: 48)
        actions.frame = CGRect(x: width - actionsWidth - 12, y: top + 3, width: actionsWidth, height: 42)
        heading.frame = CGRect(x: 56, y: top, width: max(0, width - actionsWidth - 76), height: 48)
        subtitleLabel.frame = CGRect(x: 20, y: top + 48, width: max(0, width - 40), height: 36)
        let contentFrame = CGRect(x: 0, y: top + 88, width: width,
                                  height: max(0, view.bounds.height - top - 88 - view.safeAreaInsets.bottom))
        if let collapsingContainer {
            collapsingContainer.frame = contentFrame
        } else {
            pager.frame = contentFrame
        }
    }

    public func setScrollingHeader(_ header: ASDisplayNode, height: CGFloat) {
        loadViewIfNeeded()
        collapsingContainer?.stopMotion()
        collapsingContainer?.view.removeFromSuperview()
        let container = CollapsingListContainerNode(header: header, height: height, pager: pager)
        collapsingContainer = container
        view.insertSubview(container.view, at: 0)
        view.setNeedsLayout()
    }

    public func setHeaderActions(_ items: [ItemListHeaderAction]) {
        loadViewIfNeeded()
        actions.arrangedSubviews.forEach { actions.removeArrangedSubview($0); $0.removeFromSuperview() }
        actionsWidth = 0
        for item in items {
            let button = UIButton(type: .system)
            if item.showsTitle {
                var config = item.isSelected ? UIButton.Configuration.tinted() : UIButton.Configuration.plain()
                config.title = item.title
                config.cornerStyle = .capsule
                button.configuration = config
            } else {
                button.setImage(UIImage(systemName: item.systemImage), for: .normal)
            }
            button.tintColor = theme.accent
            button.accessibilityLabel = item.title
            button.accessibilityIdentifier = "listui.\(item.title)"
            button.accessibilityTraits = item.isSelected ? [.button, .selected] : [.button]
            button.addAction(UIAction { _ in item.handler() }, for: .touchUpInside)
            let width: CGFloat = item.showsTitle ? 66 : 42
            actionsWidth += width
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            actions.addArrangedSubview(button)
        }
        view.setNeedsLayout()
    }

    public func apply(state: ItemListState, animated: Bool = true) {
        self.state = state
        guard isViewLoaded else { return }
        pager.apply(state: state, theme: theme, animated: animated)
    }
}
