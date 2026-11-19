import AppKit
import Carbon.HIToolbox

/// 发送前翻译：在 WhatsApp 输入框里按回车或点发送按钮时，先拦下这次发送，
/// 把草稿译好、替换进输入框，再按 WhatsApp 自己的发送按钮。翻译失败时草稿原样保留。
final class SendInterceptor {
    struct Report {
        enum Kind { case busy, sent, cancelled, failed }
        let kind: Kind
        let message: String
        /// 输入框在屏幕上的位置，用来就近显示提示。
        let anchor: CGRect?
    }

    /// WhatsApp 在前台时返回它，否则为 nil。
    var frontmostChat: () -> ChatApp? = { nil }
    var language: () -> String = { "English" }
    var report: (Report) -> Void = { _ in }

    var isEnabled = false {
        didSet {
            if let tap { CGEvent.tapEnable(tap: tap, enable: isEnabled) }
            if !isEnabled { cancel(nil) }
        }
    }

    private struct Pending {
        let text: String
        let composer: AXUIElement
        let anchor: CGRect?
        let task: URLSessionDataTask?
    }

    private let client: TranslationClient
    private var tap: CFMachPort?
    private var pending: Pending?
    private var generation = 0
    /// 正在往输入框写译文、按发送：这一两秒内 WhatsApp 里的按键和点击都不放行，免得和替换搅在一起。
    private var replacing = false
    private var swallowKeyUp = false
    private var swallowMouseUp = false
    private var inputMethodProcesses: [pid_t: Bool] = [:]

    init(client: TranslationClient) {
        self.client = client
    }

    /// 装上键盘/鼠标事件拦截。需要辅助功能权限；拿不到时返回 false。
    func install() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<SendInterceptor>.fromOpaque(context).takeUnretainedValue()
            return interceptor.receive(type, event) ? Unmanaged.passUnretained(event) : nil
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: isEnabled)
        return true
    }

    /// WhatsApp 离开前台：等待中的翻译作废，不会在用户看不到的时候发出去。
    func chatDeactivated() {
        if pending != nil { cancel("WhatsApp 已离开前台，本次没有发送") }
    }

    private func cancel(_ message: String?) {
        generation += 1
        let anchor = pending?.anchor
        pending?.task?.cancel()
        pending = nil
        if let message { report(Report(kind: .cancelled, message: message, anchor: anchor)) }
    }

    /// 返回 true 放行事件，false 吞掉。
    private func receive(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isEnabled, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .keyUp:
            guard swallowKeyUp, Self.isReturn(event) else { return true }
            swallowKeyUp = false
            return false
        case .leftMouseUp:
            guard swallowMouseUp else { return true }
            swallowMouseUp = false
            return false
        case .keyDown, .leftMouseDown:
            guard let app = frontmostChat() else { return true }
            return decide(isKey: type == .keyDown, event, app)
        default:
            return true
        }
    }

    private func decide(isKey: Bool, _ event: CGEvent, _ app: ChatApp) -> Bool {
        func swallow() -> Bool {
            if !isKey { swallowMouseUp = true } else if Self.isReturn(event) { swallowKeyUp = true }
            return false
        }
        if replacing { return swallow() }
        let composer = isKey ? keyTrigger(event, app) : mouseTrigger(event, app)
        if let pending {
            // 同一份草稿重复按发送：忽略。其他任何按键或点击都视为用户改了主意。
            if let composer, composer.value == pending.text { return swallow() }
            cancel("操作或草稿已变化，本次没有发送")
        }
        guard let composer, let text = composer.value, TextRules.needsOutgoingTranslation(text) else { return true }
        let anchor = composer.frame
        // 输入法还在选字、或 @/表情 候选框开着时，回车不是发送。
        if isKey, TextRules.pickerLikelyOpen(text) || inputMethodIsComposing(near: anchor) { return true }
        if text.contains("\u{FFFC}") {
            report(Report(kind: .failed, message: "草稿里有嵌入对象，没有翻译也没有发送", anchor: anchor))
            return swallow()
        }
        begin(text: text, composer: composer, anchor: anchor, app: app)
        return swallow()
    }

    /// 不带修饰键的回车，且焦点在消息输入框。
    private func keyTrigger(_ event: CGEvent, _ app: ChatApp) -> AXUIElement? {
        guard Self.isReturn(event), event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty else { return nil }
        return app.focusedComposer()
    }

    private func mouseTrigger(_ event: CGEvent, _ app: ChatApp) -> AXUIElement? {
        guard let button = app.sendButton(at: event.location) else { return nil }
        return app.sibling(of: button, id: ElementID.composer)
    }

    private static func isReturn(_ event: CGEvent) -> Bool {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        return code == kVK_Return || code == kVK_ANSI_KeypadEnter
    }

    private func begin(text: String, composer: AXUIElement, anchor: CGRect?, app: ChatApp) {
        generation += 1
        let current = generation
        report(Report(kind: .busy, message: "正在翻译…", anchor: anchor))
        let task = client.translate(text, system: Prompts.outgoing(language: language())) { [weak self] result in
            guard let self, current == self.generation, let pending = self.pending else { return }
            self.pending = nil
            switch result {
            case .failure(let failure):
                self.report(Report(kind: .failed, message: "\(failure.message)，原文还在输入框，没有发送", anchor: anchor))
            case .success(let translated):
                self.deliver(translated, pending, app)
            }
        }
        pending = Pending(text: text, composer: composer, anchor: anchor, task: task)
    }

    /// 全选草稿 → 粘贴译文 → 按发送按钮。写入走「粘贴」是因为直接改无障碍属性 WhatsApp 不认：
    /// 文字变了，但它记着的草稿没变。
    private func deliver(_ translated: String, _ pending: Pending, _ app: ChatApp) {
        let composer = pending.composer
        func fail(_ message: String) {
            report(Report(kind: .failed, message: message, anchor: pending.anchor))
        }
        guard frontmostChat()?.pid == app.pid, composer.value == pending.text else {
            report(Report(kind: .cancelled, message: "聊天或草稿已变化，本次没有发送", anchor: pending.anchor))
            return
        }
        guard let paste = app.menuItem(commandKey: "V") else { return fail("找不到“粘贴”菜单项，原文还在输入框") }
        composer.set("AXFocused", kCFBooleanTrue)
        let length = (pending.text as NSString).length
        composer.set("AXSelectedTextRange", AX.range(0, length))
        guard let selected = composer.selectedRange, selected.location == 0, selected.length == length else {
            return fail("没能选中草稿，原文还在输入框")
        }
        replacing = true
        let clipboard = Clipboard()
        clipboard.put(translated)
        paste.press()
        wait(until: { composer.value == translated }, timeout: 1.2) { [weak self] replaced in
            clipboard.restore()
            guard let self else { return }
            guard replaced else {
                self.replacing = false
                return fail("译文没能写进输入框，请检查草稿")
            }
            guard let button = app.sibling(of: composer, id: ElementID.sendButton) else {
                self.replacing = false
                return fail("找不到发送按钮，译文已在输入框，可以手动发送")
            }
            button.press()
            self.wait(until: { composer.value != translated }, timeout: 1.5) { sent in
                self.replacing = false
                if sent {
                    self.report(Report(kind: .sent, message: "译文已发送", anchor: pending.anchor))
                } else {
                    fail("发送按钮没有响应，译文已在输入框，可以手动发送")
                }
            }
        }
    }

    private func wait(until condition: @escaping () -> Bool, timeout: TimeInterval, then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() { return then(true) }
            if Date() >= deadline { return then(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
        }
        poll()
    }

    /// 输入法的候选窗贴在输入框旁边，就说明还在选字。
    private func inputMethodIsComposing(near frame: CGRect?) -> Bool {
        guard let frame, Self.inputSourceIsInputMethod(),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let area = frame.insetBy(dx: -60, dy: -100)
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, isInputMethod(pid),
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.intersects(area)
        }
    }

    private static func inputSourceIsInputMethod() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        return Unmanaged<CFString>.fromOpaque(type).takeUnretainedValue() == kTISTypeKeyboardInputMode
    }

    private func isInputMethod(_ pid: pid_t) -> Bool {
        if let known = inputMethodProcesses[pid] { return known }
        let app = NSRunningApplication(processIdentifier: pid)
        let result = app?.bundleURL?.path.contains("/Input Methods/") == true || app?.bundleIdentifier?.contains("inputmethod") == true
        inputMethodProcesses[pid] = result
        return result
    }
}

/// 借用剪贴板粘贴译文，用完把原来的内容放回去。
private final class Clipboard {
    private let board = NSPasteboard.general
    private let saved: [[NSPasteboard.PasteboardType: Data]]

    init() {
        saved = (board.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    func put(_ text: String) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // 让剪贴板管理器别把这条临时内容记进历史。
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        board.writeObjects([item])
    }

    func restore() {
        board.clearContents()
        board.writeObjects(saved.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        })
    }
}
