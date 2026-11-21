import Foundation

/// 从 WhatsApp 消息气泡的无障碍描述里取出正文。
///
/// 描述的形状（界面语言不同，文字不同，结构相同；`‎` 是 U+200E，WhatsApp 自己的文案都以它开头）：
///
///     ‎消息, 正文, 下午9:41, ‎由张三发送
///     ‎你的消息, 正文, 下午9:41, ‎已发送给张三, ‎已送达
///     ‎正在回复张三.\n‎你的消息, 正文, 下午9:41, ‎已发送给张三, ‎已读.\n‎引用消息.\n被引用的原文
enum Bubble {
    private static let mark: Character = "\u{200E}"
    // WhatsApp 中文描述里的旧消息时间可带日期，年份数字有时为空。
    private static let date = "(?:(?:\\d{4})?年)?\\d{1,2}月\\d{1,2}日"
    private static let time = "(?:\(date)\\h*)?[^\\d,\\n]{0,8}\\d{1,2}[:.]\\d{2}[^\\d,\\n]{0,8}"
    /// 时间段后面跟着状态段；没有状态段时退而取最后一个位于行尾的时间。
    private static let timeBeforeStatus = try! NSRegularExpression(pattern: ", \(time)(?=, \u{200E})")
    private static let timeAtLineEnd = try! NSRegularExpression(pattern: ", \(time)(?=\\.?(\\n|$))")

    static func body(fromDescription description: String) -> String? {
        var text = Substring(description)
        guard text.first == mark else { return nil }
        if let newline = text.firstIndex(of: "\n"), !text[..<newline].contains(", ") {
            text = text[text.index(after: newline)...]
            guard text.first == mark else { return nil }
        }
        guard let label = text.range(of: ", ") else { return nil }
        let tail = String(text[label.lowerBound...])
        let whole = NSRange(location: 0, length: (tail as NSString).length)
        guard let match = timeBeforeStatus.firstMatch(in: tail, range: whole) ?? timeAtLineEnd.matches(in: tail, range: whole).last,
              match.range.location >= 2 else { return nil }
        var body = Substring((tail as NSString).substring(with: NSRange(location: 2, length: match.range.location - 2)))
        // 正文前可能还有「已转发」之类的标记段。
        while body.first == mark {
            guard let next = body.range(of: ", ") else { return nil }
            body = body[next.upperBound...]
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
