import UIKit

final class MTChannelPostCell: UITableViewCell {
    private(set) var postView: ChannelPostView?
    private(set) var messageID: Int?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func height(for post: ChannelPost, channel: ChannelPerson, width: CGFloat) -> CGFloat {
        let card = ChannelPostView(post: post, channel: channel)
        var size = CGSize(width: width, height: 0)
        // Chips wrap using their laid-out width. Resolve that width before the final fitting pass.
        for _ in 0..<3 {
            size = card.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                               withHorizontalFittingPriority: .required,
                                               verticalFittingPriority: .fittingSizeLevel)
            card.bounds.size = size
            card.layoutIfNeeded()
        }
        return ceil(size.height) + 12
    }

    func configure(_ message: MTMessage, channel: ChannelPerson) {
        // Self-sizing can ask for the same row again while its picker or star hold is active.
        // Keep the card and its gesture recognizers alive for that message.
        if messageID == message.id, postView != nil { return }
        postView?.removeFromSuperview()
        messageID = message.id
        guard let post = message.channelPost else { return }
        let card = ChannelPostView(post: post, channel: channel)
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
        postView = card
    }
}
