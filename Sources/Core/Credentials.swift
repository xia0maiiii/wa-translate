import Foundation

/// 翻译接口的地址、模型和密钥。
struct Credentials: Equatable {
    let endpoint: URL
    let model: String
    let key: String

    /// 依次找：本插件自己的配置、TG 发送翻译的配置、Discord Translator 插件的配置。
    static func load(supportDirectory: URL, home: URL) -> Credentials? {
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let flat = [supportDirectory.appendingPathComponent("config.json"),
                    appSupport.appendingPathComponent("TGSendTranslate/config.json")]
        for file in flat {
            if let found = parse(json(at: file)) { return found }
        }
        let discord = json(at: appSupport.appendingPathComponent("BetterDiscord/plugins/Translator.config.json"))
        return parse(((discord?["all"] as? [String: Any])?["authKeys"] as? [String: Any])?["oaicompat"] as? [String: Any])
    }

    private static func json(at file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 只接受 https；http 仅限本机回环地址（本地模型服务）。
    static func parse(_ provider: [String: Any]?) -> Credentials? {
        guard let provider,
              let endpoint = (provider["endpoint"] as? String).flatMap(URL.init(string:)),
              let host = endpoint.host,
              endpoint.scheme == "https" || (endpoint.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)),
              let model = provider["model"] as? String, !model.isEmpty,
              let key = provider["key"] as? String, !key.isEmpty
        else { return nil }
        return Credentials(endpoint: endpoint, model: model, key: key)
    }
}
