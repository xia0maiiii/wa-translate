import ApplicationServices
import Foundation

/// 辅助功能（AX）接口的薄封装：读属性、写属性、按按钮。
enum AX {
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    static func range(_ location: Int, _ length: Int) -> AXValue {
        var range = CFRange(location: location, length: length)
        return AXValueCreate(.cfRange, &range)!
    }
}

extension AXUIElement {
    func raw(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success ? value : nil
    }

    func string(_ name: String) -> String? { raw(name) as? String }
    func element(_ name: String) -> AXUIElement? { AX.element(raw(name)) }

    var identifier: String? { string("AXIdentifier") }
    var value: String? { string("AXValue") }
    var frame: CGRect? { AX.rect(raw("AXFrame")) }
    var parent: AXUIElement? { element("AXParent") }
    var children: [AXUIElement] { (raw("AXChildren") as? [AXUIElement]) ?? [] }

    var selectedRange: CFRange? {
        guard let value = raw("AXSelectedTextRange"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    /// 一次往返取多个属性；取不到的那一项为 nil。
    func values(_ names: [String]) -> [CFTypeRef?] {
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(self, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result) == .success,
              let values = result as? [CFTypeRef], values.count == names.count
        else { return Array(repeating: nil, count: names.count) }
        return values.map { value in
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { return nil }
            return value
        }
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    func press() {
        AXUIElementPerformAction(self, "AXPress" as CFString)
    }
}
