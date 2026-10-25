import UIKit

final class QuickReplyDemoViewController: UITableViewController {
    private let senders: [(name: String, message: String)] = [
        ("Anna", "Are we still on for tonight?"), ("Max", "Can you send me the deck?"),
        ("Mom", "Call me when you land ❤️"), ("Team", "Standup moved to 10:30"),
    ]
    private var replies: [String] = []

    init() {
        super.init(style: .insetGrouped)
        title = "Quick Reply"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Incoming" : "Sent replies"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Tap a message, then tap the toast: it flows into a reply field. Send shoots it back into the island." : nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? senders.count : replies.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = senders[indexPath.row].name
            content.secondaryText = senders[indexPath.row].message
            content.image = UIImage(systemName: "message.fill")
        } else {
            content.text = replies[indexPath.row]
            content.image = UIImage(systemName: "arrowshape.turn.up.left.fill")
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0, let window = view.window else { return }
        let sender = senders[indexPath.row]
        LiquidIslandToast.show(in: window, title: sender.name, message: sender.message, symbol: "message.fill",
                               onReply: { [weak self] text in
            guard let self else { return }
            self.replies.insert("To \(sender.name): \(text)", at: 0)
            self.tableView.insertRows(at: [IndexPath(row: 0, section: 1)], with: .top)
        })
    }
}

