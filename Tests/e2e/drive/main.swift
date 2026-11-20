import AppKit
import ApplicationServices
import Carbon.HIToolbox

// 测试驱动：像用户一样操作替身应用。合成的按键和点击会落到当前前台应用，所以发出前都确认前台是替身。
func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { (attribute(element, "AXChildren") as? [AXUIElement]) ?? [] }
func find(_ element: AXUIElement, _ id: String, depth: Int = 0) -> AXUIElement? {
    if attribute(element, "AXIdentifier") as? String == id { return element }
    if depth > 14 { return nil }
    for child in children(element) {
        if let found = find(child, id, depth: depth + 1) { return found }
    }
    return nil
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
func frame(_ element: AXUIElement) -> CGRect {
    var rect = CGRect.zero
    if let value = attribute(element, "AXFrame") { AXValueGetValue(value as! AXValue, .cgRect, &rect) }
    return rect
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "local.watranslate.fakechat").first else { fail("替身应用没在运行") }
let axApp = AXUIElementCreateApplication(app.processIdentifier)
func window() -> AXUIElement { (attribute(axApp, "AXWindows") as? [AXUIElement])?.first ?? { fail("没有窗口") }() }
func composer() -> AXUIElement { find(window(), "ChatBar_ComposerTextView") ?? { fail("没有输入框") }() }
// 每条命令都是新进程，NSWorkspace 在启动时取到的前台应用是新的。
func isFrontmost() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
func requireFrontmost() { if !isFrontmost() { fail("替身应用不在前台，放弃合成输入") } }
func key(_ code: Int, flags: CGEventFlags = []) {
    requireFrontmost()
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: keyDown)!
        event.flags = flags
        event.post(tap: .cghidEventTap)
        usleep(15_000)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first ?? "" {
case "front":
    app.activate(options: [.activateAllWindows])
    print("activated")
case "draft":   // 用 ⌘V 写草稿，走正常输入路径
    requireFrontmost()
    let field = composer()
    let board = NSPasteboard.general
    let previous = board.string(forType: .string)
    AXUIElementSetAttributeValue(field, "AXFocused" as CFString, kCFBooleanTrue)
    var all = CFRange(location: 0, length: ((attribute(field, "AXValue") as? String ?? "") as NSString).length)
    AXUIElementSetAttributeValue(field, "AXSelectedTextRange" as CFString, AXValueCreate(.cfRange, &all)!)
    board.clearContents()
    board.setString(arguments[1], forType: .string)
    key(kVK_ANSI_V, flags: .maskCommand)
    usleep(300_000)
    board.clearContents()
    if let previous { board.setString(previous, forType: .string) }
case "return": key(kVK_Return)
case "left": key(kVK_LeftArrow)
case "switch-chat": key(kVK_ANSI_J, flags: .maskCommand)
case "keys":
    let codes: [Character: Int] = ["n": kVK_ANSI_N, "i": kVK_ANSI_I, "h": kVK_ANSI_H, "a": kVK_ANSI_A, "o": kVK_ANSI_O]
    for character in arguments[1] { key(codes[character] ?? { fail("没有键位 \(character)") }()) }
case "click-send":
    requireFrontmost()
    guard let button = find(window(), "ChatBar_SendButton") else { fail("没有发送按钮") }
    let point = CGPoint(x: frame(button).midX, y: frame(button).midY)
    let cursor = CGEvent(source: nil)!.location
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cursor, mouseButton: .left)!.post(tap: .cghidEventTap)
case "value": print(attribute(composer(), "AXValue") as? String ?? "")
case "has-send": print(find(window(), "ChatBar_SendButton") != nil)
case "input-source":
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    print(Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceType)).takeUnretainedValue() as String)
case "labels":   // 译文层此刻在屏幕上的窗口数（参数是 WATranslate 的 pid）
    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    print(windows.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid_t(arguments[1]) }.count)
default: fail("未知命令")
}
