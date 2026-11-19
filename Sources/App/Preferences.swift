import Foundation

/// 菜单里的开关和语言选择，存在配置目录的 preferences.json。
struct Preferences {
    var sendEnabled = true
    var incomingEnabled = true
    /// 写进提示词的语言名。
    var sendLanguage = "English"
    var readingLanguage = "简体中文"

    init(file: URL) {
        guard let data = try? Data(contentsOf: file),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        sendEnabled = json["send_enabled"] as? Bool ?? sendEnabled
        incomingEnabled = json["incoming_enabled"] as? Bool ?? incomingEnabled
        if let language = json["send_language"] as? String, !language.isEmpty { sendLanguage = language }
        if let language = json["reading_language"] as? String, !language.isEmpty { readingLanguage = language }
    }

    func save(to file: URL) {
        let json: [String: Any] = ["send_enabled": sendEnabled, "incoming_enabled": incomingEnabled,
                                   "send_language": sendLanguage, "reading_language": readingLanguage]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
