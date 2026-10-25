import UIKit

final class PhotoFeedDemoViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var stories: StoryRingsView!

    private let people = [
        ChannelPerson(name: "Вы", hue: 0.55), ChannelPerson(name: "Анна Смирнова", hue: 0.93),
        ChannelPerson(name: "Михаил Орлов", hue: 0.58), ChannelPerson(name: "Катя Лебедева", hue: 0.08),
        ChannelPerson(name: "Игорь Ким", hue: 0.36), ChannelPerson(name: "Ольга Белова", hue: 0.75),
        ChannelPerson(name: "Дмитрий Волков", hue: 0.15), ChannelPerson(name: "Софья Ли", hue: 0.5),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = PhotoFeedPalette.background
        let wordmark = UILabel()
        wordmark.text = "Photogram"
        wordmark.font = UIFont(name: "SnellRoundhand-Black", size: 28) ?? .systemFont(ofSize: 24, weight: .heavy)
        wordmark.textColor = .white
        navigationItem.titleView = wordmark
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "paperplane"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: nil, action: nil),
        ]

        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])

        let scenes = DemoPhotos.Scene.allCases
        let users = people.enumerated().map { index, person in
            StoryUser(person: person, photos: (0..<(2 + index % 2)).map { scenes[(index + $0) % scenes.count] },
                      seen: index >= 6)
        }
        stories = StoryRingsView(users: users)
        stories.onOpen = { [weak self] index in self?.openStories(at: index) }
        stack.addArrangedSubview(stories)
        let separator = UIView()
        separator.backgroundColor = UIColor(white: 1, alpha: 0.12)
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(separator)

        let posts = [
            PhotoPostModel(author: people[2], location: "Домбай", photos: [.sunset, .aurora, .forest], likes: 1284,
                           caption: "Три вечера в горах. Листайте → и попробуйте фильтры 👇", comments: 48, time: "2 часа назад",
                           showsFilters: true),
            PhotoPostModel(author: people[3], location: "Москва-Сити", photos: [.city, .ocean], likes: 932,
                           caption: "Огни после дождя", comments: 17, time: "5 часов назад"),
            PhotoPostModel(author: people[5], location: "Ботанический сад", photos: [.bloom, .desert, .ocean, .forest], likes: 2410,
                           caption: "Весна наступила раньше календаря 🌸", comments: 96, time: "вчера"),
        ]
        for post in posts {
            stack.addArrangedSubview(PhotoPostView(model: post))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
    }

    private func openStories(at index: Int) {
        // Over the navigation bar too: the story takes the whole screen.
        let host: UIView = navigationController?.view ?? view
        let viewer = StoryViewer(in: host, users: stories.users, start: index) { [weak self, weak host] user in
            guard let self, let host else { return .zero }
            return stories.avatarFrame(user, in: host)
        }
        viewer.onSeen = { [weak self] user in self?.stories.markSeen(user) }
    }
}
