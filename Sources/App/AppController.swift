import AppKit

/// 菜单栏图标、开关，以及「WhatsApp 在不在、在不在前台」的跟踪。
final class AppController: NSObject, NSApplicationDelegate {
    private static let sendLanguages = [("English", "English"), ("Português (Brasil)", "Brazilian Portuguese"), ("Español", "Spanish")]

    private let targetBundleID: String
    private let supportDirectory: URL
    private var preferences: Preferences
    private let interceptor: SendInterceptor
    private let overlay: IncomingOverlay
    private let toast = Toast()

    private var chat: ChatApp?
    private var chatIsFrontmost = false
    private var trusted = false
    private var busy = false
    private var state = "" { didSet { stateItem.title = state } }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let sendItem = NSMenuItem(title: "", action: #selector(toggleSend), keyEquivalent: "")
    private let incomingItem = NSMenuItem(title: "", action: #selector(toggleIncoming), keyEquivalent: "")
    private let languageMenu = NSMenu()

    private var preferencesFile: URL { supportDirectory.appendingPathComponent("preferences.json") }

    init(targetBundleID: String, supportDirectory: URL) {
        self.targetBundleID = targetBundleID
        self.supportDirectory = supportDirectory
        preferences = Preferences(file: supportDirectory.appendingPathComponent("preferences.json"))
        let client = TranslationClient(supportDirectory: supportDirectory)
        interceptor = SendInterceptor(client: client)
        overlay = IncomingOverlay(client: client)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        interceptor.frontmostChat = { [weak self] in self?.chatIsFrontmost == true ? self?.chat : nil }
        interceptor.language = { [weak self] in self?.preferences.sendLanguage ?? "English" }
        interceptor.report = { [weak self] in self?.handle($0) }
        overlay.language = { [weak self] in self?.preferences.readingLanguage ?? "简体中文" }
        overlay.failed = { [weak self] message in self?.state = "收到的消息翻译失败：\(message)" }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        waitForPermission(prompt: true)
    }

    /// 读输入框、拦回车都要辅助功能权限。没有时弹系统引导，然后每两秒看一次。
    private func waitForPermission(prompt: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), interceptor.install() {
            trusted = true
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.4)
            state = "准备就绪"
            return workspaceChanged(nil)
        }
        state = "请在 系统设置 › 隐私与安全性 › 辅助功能 里打开 WATranslate"
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.waitForPermission(prompt: false) }
    }

    @objc private func workspaceChanged(_ notification: Notification?) {
        let terminated = notification?.name == NSWorkspace.didTerminateApplicationNotification
            ? (notification?.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier : nil
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first { $0.processIdentifier != terminated }
        if running?.processIdentifier != chat?.pid {
            chat = running.map { ChatApp(pid: $0.processIdentifier) }
            // 菜单栏第一次遍历要一百多毫秒，先在后台做掉，别卡在第一次发送上。
            if let chat { DispatchQueue.global(qos: .utility).async { _ = chat.menuItem(commandKey: "V") } }
        }
        let wasFrontmost = chatIsFrontmost
        chatIsFrontmost = chat != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == chat?.pid
        if wasFrontmost && !chatIsFrontmost {
            interceptor.chatDeactivated()
            toast.hide()
        }
        if wasFrontmost != chatIsFrontmost || notification == nil { apply() }
        refresh()
    }

    private func apply() {
        interceptor.isEnabled = trusted && preferences.sendEnabled
        overlay.follow(trusted && preferences.incomingEnabled && chatIsFrontmost ? chat : nil)
    }

    private func handle(_ report: SendInterceptor.Report) {
        busy = report.kind == .busy
        state = report.message
        switch report.kind {
        case .busy: toast.show("翻译中…", above: report.anchor, duration: nil)
        case .sent: toast.hide()
        case .cancelled: toast.show(report.message, above: report.anchor, duration: 2.5)
        case .failed:
            NSSound.beep()
            toast.show(report.message, above: report.anchor, isError: true, duration: 5)
        }
        refresh()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(.separator())
        for item in [sendItem, incomingItem] {
            item.target = self
            menu.addItem(item)
        }
        let languages = NSMenuItem(title: "发送语言", action: nil, keyEquivalent: "")
        var choices = Self.sendLanguages
        if !choices.contains(where: { $0.1 == preferences.sendLanguage }) { choices.append((preferences.sendLanguage, preferences.sendLanguage)) }
        for (title, language) in choices {
            let item = NSMenuItem(title: title, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language
            languageMenu.addItem(item)
        }
        languages.submenu = languageMenu
        menu.addItem(languages)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "含中文的草稿才翻译 · ! 或 / 开头按原文发送", action: nil, keyEquivalent: ""))
        let folder = NSMenuItem(title: "打开配置目录", action: #selector(openSupportDirectory), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
        menu.addItem(NSMenuItem(title: "退出 WATranslate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = menu
        refresh()
    }

    private func refresh() {
        let languageTitle = Self.sendLanguages.first { $0.1 == preferences.sendLanguage }?.0 ?? preferences.sendLanguage
        sendItem.title = "发送前翻译成 \(languageTitle)"
        sendItem.state = preferences.sendEnabled ? .on : .off
        incomingItem.title = "把收到的消息译成\(preferences.readingLanguage)"
        incomingItem.state = preferences.incomingEnabled ? .on : .off
        for item in languageMenu.items {
            item.state = item.representedObject as? String == preferences.sendLanguage ? .on : .off
        }
        let title: String
        if !trusted { title = "WA 待授权" } else if busy { title = "WA 译…" } else if preferences.sendEnabled || preferences.incomingEnabled { title = "WA 译" } else { title = "WA 译关" }
        statusItem.button?.title = title
    }

    private func preferencesChanged() {
        preferences.save(to: preferencesFile)
        apply()
        refresh()
    }

    @objc private func toggleSend() {
        preferences.sendEnabled.toggle()
        state = preferences.sendEnabled ? "准备就绪" : "发送前翻译已关闭"
        preferencesChanged()
    }

    @objc private func toggleIncoming() {
        preferences.incomingEnabled.toggle()
        preferencesChanged()
    }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else { return }
        preferences.sendLanguage = language
        preferencesChanged()
    }

    @objc private func openSupportDirectory() {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(supportDirectory)
    }
}
