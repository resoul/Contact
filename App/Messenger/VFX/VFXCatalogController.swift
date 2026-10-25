import UIKit

/// A contained navigation stack keeps preview chrome separate from messenger navigation.
final class VFXNavigationHost: UIViewController {
    private let content: UIViewController
    private let onClose: () -> Void
    private var stack: UINavigationController?
    private var savedPopGesture: Bool?

    init(_ content: UIViewController, onClose: @escaping () -> Void) {
        self.content = content
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:onClose:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = UINavigationController(rootViewController: content)
        self.stack = stack
        content.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"),
            primaryAction: UIAction { [weak self] _ in self?.onClose() })
        content.navigationItem.leftBarButtonItem?.accessibilityLabel = "Back to Messenger"
        addChild(stack)
        stack.view.frame = view.bounds
        stack.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(stack.view)
        stack.didMove(toParent: self)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let gesture = navigationController?.interactivePopGestureRecognizer {
            savedPopGesture = gesture.isEnabled
            gesture.isEnabled = false
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let enabled = savedPopGesture { navigationController?.interactivePopGestureRecognizer?.isEnabled = enabled }
    }
}

extension HomeViewController {
    func openVFX(_ controller: UIViewController) {
        root?.push(VFXNavigationHost(controller, onClose: { [weak self] in self?.root?.pop() }))
    }
}

final class VFXCatalogController: UITableViewController {
    weak var home: HomeViewController?
    private let pages: [(String, String, () -> UIViewController)] = [
        ("Matrix + Kinetic Login", "Animated registration heading", { RegistrationEffectsController() }),
        ("Photo Feed", "Carousel with liquid page dots", { PhotoFeedDemoViewController() }),
        ("Voice Room", "Group audio call design", { VoiceRoomDemoViewController() }),
        ("Bubble Cluster", "Public channel audio broadcast", { BubbleClusterDemoViewController() }),
        ("Particle Morph", "Pay · AI · VIP · Load", { ParticleMorphDemoViewController() }),
        ("Particle Charts", "Storage · Bars · Line · Morph", { ParticleChartsDemoViewController() }),
        ("Photo Viewer", "Photo transitions from X", { PhotoViewerDemoViewController() }),
        ("Translate Post", "Animated translation example", { TranslateDemoViewController() }),
        ("Community Notes", "Expandable context for public posts", { CommunityNotesDemoViewController() }),
        ("Post Analytics", "Public channel administrator preview", { PostAnalyticsDemoViewController() }),
        ("Vanish Mode", "Pull up to change chat mode", { VanishModeDemoViewController() }),
        ("Liquid Toast + Quick Reply", "Notification and inline reply", { QuickReplyDemoViewController() }),
    ]
    init() { super.init(style: .insetGrouped); title = "VFX" }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { pages.count + 1 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.row == pages.count {
            cell.textLabel?.text = "Chat Playground"
            cell.detailTextLabel?.text = "Photo stack · Send effects · Vanish · Paper Burn"
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        let page = pages[indexPath.row]
        cell.textLabel?.text = page.0
        cell.detailTextLabel?.text = page.1
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == pages.count, let home {
            home.root?.push(ChatViewController(chat: VFXChatFixtures.playground, home: home))
            return
        }
        let page = pages[indexPath.row]
        let controller = page.2()
        if controller.title == nil { controller.title = page.0 }
        navigationController?.pushViewController(controller, animated: true)
    }
}

final class RegistrationEffectsController: UIViewController {
    private let rain = MatrixDigitalRainView()
    private let heading = KineticTextView()
    private var index = 0
    private let lines = ["Contact", "Your people", "Stay connected", "Welcome"]
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Registration"
        view.backgroundColor = .black
        view.addSubview(rain)
        heading.textColor = .white
        heading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heading)
        let next = UIButton(configuration: .tinted(), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.index = (self.index + 1) % self.lines.count
            self.heading.setText(self.lines[self.index])
        })
        next.setTitle("Next heading", for: .normal)
        next.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(next)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            heading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            heading.heightAnchor.constraint(equalToConstant: 140),
            next.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            next.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 24),
        ])
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); rain.frame = view.bounds }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rain.isPaused = false
        heading.setText(lines[index])
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        rain.isPaused = true
        heading.isPaused = true
    }
}
