import Foundation

/// 纯文本判断：哪些草稿要翻、哪些收到的消息要翻，以及链接/代码的保护与还原。
enum TextRules {
    /// 发送前翻译只处理含中文的草稿；`!`、`！`、`/` 开头按原文发送。
    static func needsOutgoingTranslation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, !"!！/".contains(first) else { return false }
        return trimmed.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    /// 草稿以未完成的 `@名字` 或 `:表情` 结尾时，回车是在选候选项而不是发送。
    static func pickerLikelyOpen(_ text: String) -> Bool {
        text.range(of: "(^|\\s)(@\\S*|:[A-Za-z_]{2,})$", options: .regularExpression) != nil
    }

    /// 收到的消息：去掉链接、提及后至少有两个字母，且不以中文为主，才值得翻。
    static func needsIncomingTranslation(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: "https?://\\S+|@\\S+", with: " ", options: .regularExpression)
        var letters = 0, han = 0
        for scalar in stripped.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if scalar.properties.isIdeographic { han += 1 }
        }
        return letters >= 2 && han * 10 < letters * 3
    }

    /// 把链接、代码、@ 提及换成占位符，译文回来后再原样放回。
    static func protect(_ text: String) -> (masked: String, tokens: [String: String]) {
        let pattern = "```[\\s\\S]*?```|`[^`\\n]+`|https?://[^\\s<>]+|@[A-Za-z0-9_]+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let source = text as NSString
        let masked = NSMutableString(string: text)
        var tokens: [String: String] = [:]
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        for (number, match) in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed().enumerated() {
            let token = "WAKEEP\(nonce)N\(number)END"
            tokens[token] = source.substring(with: match.range)
            masked.replaceCharacters(in: match.range, with: token)
        }
        return (masked as String, tokens)
    }

    /// 每个占位符必须恰好出现一次，否则宁可不用这份译文。
    static func restore(_ text: String, tokens: [String: String]) throws -> String {
        var result = text
        for (token, original) in tokens {
            guard result.components(separatedBy: token).count == 2 else {
                throw TranslationFailure("译文没有完整保留链接或代码")
            }
            result = result.replacingOccurrences(of: token, with: original)
        }
        return result
    }
}
