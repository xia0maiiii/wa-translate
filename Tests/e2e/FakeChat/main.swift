import UIKit

// WhatsApp 的替身（Mac Catalyst）：同样的无障碍标识、同样的气泡描述格式。
// 发送时只认 textViewDidChange 记下的草稿（真实 WhatsApp 也是这样：直接改无障碍属性不算数），
// 发送按钮不响应无障碍的「按下」，只能回车或真实点击。发出去的内容逐行写进 FAKECHAT_LOG。
// ⌘J 切到另一个聊天：换一个新的消息列表，旧的那个从界面上摘掉但不销毁，仍然答得上无障碍查询。
let mark = "\u{200E}"

struct Message {
    let incoming: Bool
    let text: String
    let description: String
}

final class BubbleCell: UITableViewCell {
    private let bubble = UIView()
    private let label = UILabel()
    private var side: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        bubble.layer.cornerRadius = 10
        bubble.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14)
        contentView.addSubview(bubble)
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.64),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -7),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "WAMessageBubbleTableViewCell"
        accessibilityTraits = .staticText
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ message: Message) {
        NSLayoutConstraint.deactivate(side)
        side = [message.incoming
            ? bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
            : bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)]
        NSLayoutConstraint.activate(side)
        bubble.backgroundColor = message.incoming ? .secondarySystemBackground : UIColor.systemGreen.withAlphaComponent(0.35)
        label.text = message.text
        accessibilityLabel = message.description
    }

    // 和 WhatsApp 一样：无障碍位置是气泡本身，不是整行。
    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(bubble.bounds, in: bubble) }
        set {}
    }
}

final class SendButton: UIButton {
    override func accessibilityActivate() -> Bool { true }
}

final class ChatViewController: UIViewController, UITableViewDataSource, UITextViewDelegate {
    private var table = UITableView()
    /// 切走的聊天的消息列表：留着不销毁。
    private var retired: [UITableView] = []
    private let composer = UITextView()
    private let send = SendButton(type: .system)
    private let voice = UIButton(type: .system)
    private var draft = ""
    private var messages: [Message] = {
        let from = "\(mark)由+ 5 5,4 1,9 9 9 9 9,0 0 0 0发送"
        let long = "Então podemos fechar o pedido hoje à tarde, eu faço o pagamento por Pix assim que você me mandar a chave. Preciso de 120 unidades para entregar antes do dia 30, consegue confirmar o prazo e o valor do frete para São Paulo?"
        return [
            Message(incoming: true, text: "Bom dia, tudo bem? Você ainda tem o produto disponível?",
                    description: "\(mark)消息, Bom dia, tudo bem? Você ainda tem o produto disponível?, 下午9:41, \(from)"),
            Message(incoming: false, text: "yes, still available",
                    description: "\(mark)你的消息, yes, still available, 下午9:42, \(mark)已发送给+ 5 5,4 1,9 9 9 9 9,0 0 0 0, \(mark)已送达"),
            Message(incoming: true, text: "好的，收到", description: "\(mark)消息, 好的，收到, 下午9:43, \(from)"),
            Message(incoming: true, text: "[foto]", description: "\(mark)照片, 下午9:43, \(from)"),
            Message(incoming: true, text: "↩︎ Combinado",
                    description: "\(mark)正在回复\(mark)你.\n\(mark)消息, Combinado, 下午9:44, \(from).\n\(mark)引用消息.\nyes, still available"),
            Message(incoming: true, text: long, description: "\(mark)消息, \(long), 下午9:45, \(from)"),
        ]
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        composer.accessibilityIdentifier = "ChatBar_ComposerTextView"
        composer.font = .systemFont(ofSize: 14)
        composer.layer.borderColor = UIColor.separator.cgColor
        composer.layer.borderWidth = 1
        composer.layer.cornerRadius = 8
        composer.delegate = self
        send.setTitle("发送", for: .normal)
        send.accessibilityIdentifier = "ChatBar_SendButton"
        send.addTarget(self, action: #selector(sendDraft), for: .touchUpInside)
        voice.setTitle("语音", for: .normal)
        voice.accessibilityIdentifier = "ChatBar_VoiceMessageButton"
        for subview in [composer, send, voice] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            composer.heightAnchor.constraint(equalToConstant: 40),
            composer.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
            composer.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -8),
            send.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
            send.centerYAnchor.constraint(equalTo: composer.centerYAnchor),
            send.widthAnchor.constraint(equalToConstant: 56),
            voice.centerXAnchor.constraint(equalTo: send.centerXAnchor),
            voice.centerYAnchor.constraint(equalTo: send.centerYAnchor),
        ])
        installTable()
        updateButtons()
    }

    private func installTable() {
        table.accessibilityIdentifier = "ChatMessagesTableView"
        table.dataSource = self
        table.separatorStyle = .none
        table.register(BubbleCell.self, forCellReuseIdentifier: "bubble")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(table, at: 0)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: guide.topAnchor),
            table.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
        ])
    }

    override var keyCommands: [UIKeyCommand]? {
        let command = UIKeyCommand(input: "j", modifierFlags: .command, action: #selector(switchChat))
        command.wantsPriorityOverSystemBehavior = true
        return [command]
    }

    @objc private func switchChat() {
        table.removeFromSuperview()
        retired.append(table)
        table = UITableView()
        messages = [Message(incoming: true, text: "Obrigado pela compra, volte sempre",
                            description: "\(mark)消息, Obrigado pela compra, volte sempre, 下午9:55, \(mark)由Bia发送")]
        installTable()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        composer.becomeFirstResponder()
    }

    private func updateButtons() {
        send.isHidden = draft.isEmpty
        voice.isHidden = !draft.isEmpty
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bubble", for: indexPath) as! BubbleCell
        cell.show(messages[indexPath.row])
        return cell
    }

    func textViewDidChange(_ textView: UITextView) {
        draft = textView.text
        updateButtons()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text == "\n" else { return true }
        sendDraft()
        return false
    }

    @objc private func sendDraft() {
        guard !draft.isEmpty else { return }
        if let path = ProcessInfo.processInfo.environment["FAKECHAT_LOG"],
           let line = try? JSONSerialization.data(withJSONObject: ["text": draft]) {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(line + Data("\n".utf8))
                handle.closeFile()
            }
        }
        messages.append(Message(incoming: false, text: draft, description: "\(mark)你的消息, \(draft), 下午9:50, \(mark)已发送给Ana, \(mark)已送达"))
        composer.text = ""
        draft = ""
        updateButtons()
        table.reloadData()
        table.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: false)
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ChatViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
