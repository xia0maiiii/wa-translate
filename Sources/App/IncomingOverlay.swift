import AppKit

/// 收到的消息翻译：轮询当前聊天里看得见的气泡，把外语消息的译文画在气泡右侧。画面滚动时译文先收起，停稳后再摆。
/// WhatsApp 是原生应用，没法往它的界面里加东西，所以译文画在一层盖在聊天区上的透明面板里。
final class IncomingOverlay {
    var language: () -> String = { "简体中文" }
    var failed: (String) -> Void = { _ in }

    private struct Visible {
        struct Item {
            let frame: CGRect
            let text: String
        }
        let area: CGRect
        let bubbles: [Item]
    }

    /// 便宜的一瞥（几次往返）：列表里有哪些气泡、首尾两个在哪、有没有被别的界面盖住。
    /// 滚动、来新消息、切换聊天、挪窗口都会让它变。
    private struct Glance: Equatable {
        let cells: [AXUIElement]
        let first: CGRect?
        let last: CGRect?
        let covered: Bool

        static func == (a: Glance, b: Glance) -> Bool {
            a.first == b.first && a.last == b.last && a.covered == b.covered
                && a.cells.count == b.cells.count && zip(a.cells, b.cells).allSatisfy { CFEqual($0, $1) }
        }
    }

    /// 一次 follow 对应一个 Watch，里面的状态只在轮询队列上读写。
    private final class Watch {
        let app: ChatApp
        var glance: Glance?
        var settled = false
        var lastRead = Date.distantPast
        /// 用来探测遮挡的点：最靠中间的一个气泡的中心。
        var probe: CGPoint?

        init(app: ChatApp) {
            self.app = app
        }
    }

    private enum Step {
        /// 画面在变：先把译文收起来。
        case moving
        /// 画面停稳后完整读了一遍。
        case read(Visible?)
        case unchanged
    }

    private let client: TranslationClient
    private let queue = DispatchQueue(label: "watranslate.poll", qos: .userInitiated)
    private let panel = OverlayPanel()
    private let view = LabelsView()
    private var watch: Watch?
    /// 跟随期间向系统声明「正在干活」。本程序没有常驻窗口，否则会被 App Nap 降速，轮询的定时器一拖就是好几秒。
    private var activity: NSObjectProtocol?
    private var last: Visible?
    private var translations: [String: String] = [:]
    private var inFlight = Set<String>()
    private var retryAfter: [String: Date] = [:]

    init(client: TranslationClient) {
        self.client = client
        panel.contentView = view
    }

    /// `app` 是在前台的 WhatsApp；不在前台或功能关闭时传 nil，译文层随之隐藏。
    func follow(_ app: ChatApp?) {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = app.map { _ in
            ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "跟随 WhatsApp 聊天画面")
        }
        watch = app.map(Watch.init(app:))
        Debug.log("译文层：\(app == nil ? "停止" : "开始")跟随")
        last = nil
        panel.orderOut(nil)
        if let watch { poll(watch, after: 0) }
    }

    private func poll(_ watch: Watch, after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            let step = Self.step(watch)
            DispatchQueue.main.async {
                guard let self, watch === self.watch else { return }
                var next = 0.3
                switch step {
                case .moving:
                    if self.last != nil { Debug.log("译文层：画面在变，收起") }
                    self.last = nil
                    self.show()
                    next = 0.12
                case .read(let visible):
                    Debug.log("译文层：读到 \(visible.map { "\($0.bubbles.count) 条要翻的消息" } ?? "没有聊天")")
                    self.last = visible
                    self.show()
                case .unchanged:
                    self.show()
                }
                self.poll(watch, after: next)
            }
        }
    }

    /// 读气泡的文字要 WhatsApp 的主线程逐个作答，不便宜。所以平时只瞥一眼；
    /// 画面在变就不读（译文先收起），停稳后读一遍，此后每三秒复查一次。在轮询队列上执行。
    private static func step(_ watch: Watch) -> Step {
        let app = watch.app
        var table = app.messagesTable()
        // 切换聊天后，手里的列表元素可能还答得上话却已不在屏幕上：以屏幕上实际点到的那个为准。
        let point = watch.probe ?? table?.frame.map { CGPoint(x: $0.midX, y: $0.midY) }
        let onScreen = point.flatMap(app.messagesTable(at:))
        if let onScreen, table.map({ !CFEqual($0, onScreen) }) ?? true {
            Debug.log("译文层：换用屏幕上的消息列表（之前\(table == nil ? "没有" : "是另一个")）")
            app.adopt(onScreen)
            table = onScreen
        }
        let cells = table?.children ?? []
        // 探测点上点不到消息列表：上面盖着别的界面（看图、弹窗），这时不画译文。
        let glance = Glance(cells: cells, first: cells.first?.frame, last: cells.last?.frame, covered: point != nil && onScreen == nil)
        if glance != watch.glance {
            if glance.covered != watch.glance?.covered, let point {
                Debug.log("译文层：遮挡判定=\(glance.covered)，探测点命中 \(app.hit(point).map { "\($0.identifier ?? "无标识") \($0.string("AXRole") ?? "")" } ?? "nil")")
            }
            watch.glance = glance
            watch.settled = false
            return .moving
        }
        if watch.settled, Date().timeIntervalSince(watch.lastRead) < 3 { return .unchanged }
        watch.settled = true
        watch.lastRead = Date()
        watch.probe = nil
        guard let table, let area = app.visibleArea(of: table) else {
            app.forgetMessages()
            return .read(nil)
        }

        var bubbles: [Visible.Item] = []
        for cell in cells {
            let values = cell.values(["AXIdentifier", "AXDescription", "AXFrame"])
            guard values[0] as? String == ElementID.bubble, let frame = AX.rect(values[2]), frame.intersects(area) else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if area.contains(center), watch.probe.map({ abs(center.y - area.midY) < abs($0.y - area.midY) }) ?? true { watch.probe = center }
            // 靠左的是别人发的。
            guard frame.minX - area.minX < area.maxX - frame.maxX, let description = values[1] as? String,
                  let body = Bubble.body(fromDescription: description), TextRules.needsIncomingTranslation(body) else { continue }
            bubbles.append(Visible.Item(frame: frame, text: body))
        }
        // 被盖住、或一个气泡也没读到，也可能是手里的列表已经过期：丢掉，下一轮重新找。
        if glance.covered || watch.probe == nil { app.forgetMessages() }
        if glance.covered { bubbles = [] }
        return .read(Visible(area: area, bubbles: bubbles.sorted { $0.frame.minY < $1.frame.minY }))
    }

    /// 按最近一次读到的气泡摆译文；还没译的去请求。
    private func show() {
        guard let visible = last, !visible.bubbles.isEmpty else { return panel.orderOut(nil) }
        var shown: [(frame: CGRect, text: String)] = []
        for bubble in visible.bubbles {
            guard let translated = translations[bubble.text] else {
                request(bubble.text)
                continue
            }
            if translated.caseInsensitiveCompare(bubble.text) != .orderedSame { shown.append((bubble.frame, translated)) }
        }
        let frames = LabelLayout.frames(bubbles: shown.map(\.frame), area: visible.area) { index, limit in
            LabelsView.size(of: shown[index].text, within: limit)
        }
        let labels = zip(frames, shown).map { LabelsView.Label(rect: $0, text: $1.text) }
        if labels.count != view.labels.count { Debug.log("译文层：显示 \(labels.count) 条译文") }
        view.labels = labels
        if labels.isEmpty { return panel.orderOut(nil) }
        panel.place(at: visible.area)
        panel.orderFrontRegardless()
    }

    /// 同时最多三个请求，其余的等前面的回来再发；失败的一分钟后再试。
    private func request(_ text: String) {
        guard !inFlight.contains(text), inFlight.count < 3, retryAfter[text].map({ $0 <= Date() }) ?? true else { return }
        inFlight.insert(text)
        let started = Date()
        client.translate(text, system: Prompts.incoming(language: language())) { [weak self] result in
            guard let self else { return }
            self.inFlight.remove(text)
            Debug.log("译文层：请求结束 \(Int(Date().timeIntervalSince(started) * 1000))ms \(result.map { _ in "成功" })")
            switch result {
            case .success(let translated):
                if self.translations.count >= 4000 { self.translations.removeAll() }
                self.translations[text] = translated
                self.show()
            case .failure(let failure):
                self.retryAfter[text] = Date().addingTimeInterval(60)
                self.failed(failure.message)
            }
        }
    }
}
