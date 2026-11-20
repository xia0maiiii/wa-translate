import ApplicationServices
import Foundation

/// WhatsApp 界面元素的无障碍标识（取自 WhatsApp for Mac 26.45）。
enum ElementID {
    static let composer = "ChatBar_ComposerTextView"
    static let sendButton = "ChatBar_SendButton"
    static let messagesTable = "ChatMessagesTableView"
    static let bubble = "WAMessageBubbleTableViewCell"
    static let chatList = "ChatListView_TableView"
    static let header = "WDSNavigationBar"
}

/// 一个正在运行的 WhatsApp 进程，以及在它界面里找元素的办法。
final class ChatApp {
    let pid: pid_t
    private let element: AXUIElement
    private let lock = NSLock()
    private var menuItems: [String: AXUIElement] = [:]
    private var table: AXUIElement?
    private var header: AXUIElement?
    private var composer: AXUIElement?
    private var nextSearch = Date.distantPast

    init(pid: pid_t) {
        self.pid = pid
        element = AXUIElementCreateApplication(pid)
    }

    /// 键盘焦点在消息输入框时返回它。
    func focusedComposer() -> AXUIElement? {
        guard let focused = element.element("AXFocusedUIElement"), focused.identifier == ElementID.composer else { return nil }
        return focused
    }

    func hit(_ point: CGPoint) -> AXUIElement? {
        var found: AXUIElement?
        return AXUIElementCopyElementAtPosition(element, Float(point.x), Float(point.y), &found) == .success ? found : nil
    }

    /// 屏幕上这一点是发送按钮（或它里面的图标）时返回按钮。
    func sendButton(at point: CGPoint) -> AXUIElement? {
        var candidate = hit(point)
        for _ in 0..<3 {
            guard let current = candidate else { return nil }
            if current.identifier == ElementID.sendButton { return current }
            candidate = current.parent
        }
        return nil
    }

    /// 输入框、发送按钮、消息列表在界面里是兄弟节点。
    func sibling(of element: AXUIElement, id: String) -> AXUIElement? {
        element.parent?.children.first { $0.identifier == id }
    }

    /// 按快捷键字母找菜单项（如 "V" 是粘贴），不依赖界面语言。第一次查找要遍历菜单栏，之后走缓存。
    func menuItem(commandKey: String) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = menuItems[commandKey], cached.raw("AXEnabled") != nil { return cached }
        guard let bar = element.element("AXMenuBar") else { return nil }
        for title in bar.children {
            for menu in title.children {
                for item in menu.children where item.string("AXMenuItemCmdChar") == commandKey && (item.raw("AXMenuItemCmdModifiers") as? Int) == 0 {
                    menuItems[commandKey] = item
                    return item
                }
            }
        }
        return nil
    }

    /// 当前聊天的消息列表；没有打开聊天时为 nil。只在轮询队列上调用。
    /// 找一次要遍历半个窗口，所以找到后一直用着；找不到时隔两秒再找。
    /// 切换聊天后手里的元素可能还答得上话、却已不在屏幕上，调用方要用 `messagesTable(at:)` 核对。
    func messagesTable() -> AXUIElement? {
        if let table { return table }
        guard Date() >= nextSearch else { return nil }
        let window = element.element("AXFocusedWindow") ?? element.element("AXMainWindow") ?? (element.raw("AXWindows") as? [AXUIElement])?.first
        adopt(window.flatMap { Self.find(ElementID.messagesTable, in: $0, depth: 12) })
        if table == nil { nextSearch = Date().addingTimeInterval(2) }
        return table
    }

    /// 屏幕上这一点（气泡或列表空白处）属于哪个消息列表；上面盖着别的界面时为 nil。
    func messagesTable(at point: CGPoint) -> AXUIElement? {
        var candidate = hit(point)
        for _ in 0..<3 {
            guard let current = candidate else { return nil }
            if current.identifier == ElementID.messagesTable { return current }
            candidate = current.parent
        }
        return nil
    }

    /// 改用这个消息列表（连同它旁边的标题栏和输入框）。
    func adopt(_ found: AXUIElement?) {
        table = found
        header = found.flatMap(Self.header(above:))
        composer = found.flatMap { sibling(of: $0, id: ElementID.composer) }
    }

    /// 列表里真正看得见的那一段：列表本身一直延伸到标题栏和输入栏的下面。
    func visibleArea(of table: AXUIElement) -> CGRect? {
        guard let area = table.frame else { return nil }
        let top = max(area.minY, header?.frame?.maxY ?? area.minY)
        let bottom = min(area.maxY, composer?.frame.map { $0.minY - 12 } ?? area.maxY)
        guard bottom > top else { return nil }
        return CGRect(x: area.minX, y: top, width: area.width, height: bottom - top)
    }

    /// 手里的列表读不出东西时丢掉，下次重新找。
    func forgetMessages() {
        table = nil
    }

    /// 聊天标题栏挂在消息列表的某一层祖先下面。
    private static func header(above table: AXUIElement) -> AXUIElement? {
        var node = table
        for _ in 0..<4 {
            guard let parent = node.parent else { return nil }
            if let bar = parent.children.first(where: { $0.identifier == ElementID.header }) { return bar }
            node = parent
        }
        return nil
    }

    private static func find(_ id: String, in root: AXUIElement, depth: Int) -> AXUIElement? {
        for child in root.children {
            let childID = child.identifier
            if childID == id { return child }
            if childID == ElementID.chatList || depth == 0 { continue }
            if let found = find(id, in: child, depth: depth - 1) { return found }
        }
        return nil
    }
}
