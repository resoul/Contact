import UIKit

/// A compact grid of folder icons, opened from the smiley in the name field.
final class FolderEmojiPickerViewController: UICollectionViewController {
    private static let emoji = [
        "📁", "💬", "👤", "👥", "📢", "🤖", "⭐️", "❤️", "🏠", "💼", "🎓", "🎮",
        "🎵", "🎨", "📚", "✈️", "🏝️", "🍕", "☕️", "⚽️", "🏋️", "💰", "📈", "🛒",
        "🐱", "🐶", "🌿", "🔥", "⚡️", "🔔", "🔒", "🧪", "💡", "🛠️", "🚗", "🎉",
    ]

    private let selected: String?
    private let onPick: (String?) -> Void

    init(selected: String?, onPick: @escaping (String?) -> Void) {
        self.selected = selected
        self.onPick = onPick
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 52, height: 52)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)
        super.init(collectionViewLayout: layout)
        title = "Folder Icon"
    }

    required init?(coder: NSCoder) { fatalError("Use init(selected:onPick:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = Palette.grouped
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "emoji")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "No Icon", style: .plain, target: self, action: #selector(clear))
        navigationItem.leftBarButtonItem?.isEnabled = selected != nil
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
    }

    @objc private func clear() { pick(nil) }
    @objc private func close() { dismiss(animated: true) }

    private func pick(_ emoji: String?) {
        onPick(emoji)
        dismiss(animated: true)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Self.emoji.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath)
        let emoji = Self.emoji[indexPath.item]
        var content = UIListContentConfiguration.cell()
        content.image = FolderIcons.emoji(emoji, size: 36)
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        cell.contentConfiguration = content
        var background = UIBackgroundConfiguration.clear()
        background.cornerRadius = 14
        background.backgroundColor = emoji == selected ? Palette.accent.withAlphaComponent(0.22) : Palette.cell
        cell.backgroundConfiguration = background
        cell.accessibilityLabel = emoji
        cell.accessibilityTraits = emoji == selected ? [.button, .selected] : .button
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        pick(Self.emoji[indexPath.item])
    }
}
