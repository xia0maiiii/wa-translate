import Foundation

/// 调翻译接口。完成回调总在主线程、总是异步。
final class TranslationClient: NSObject, URLSessionTaskDelegate {
    private let supportDirectory: URL
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 35
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    @discardableResult
    func translate(_ text: String, system: String, completion: @escaping (Result<String, TranslationFailure>) -> Void) -> URLSessionDataTask? {
        guard let credentials = Credentials.load(supportDirectory: supportDirectory, home: FileManager.default.homeDirectoryForCurrentUser) else {
            DispatchQueue.main.async { completion(.failure(TranslationFailure("没有找到翻译接口配置"))) }
            return nil
        }
        let guarded = TextRules.protect(text)
        var request = URLRequest(url: credentials.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + credentials.key, forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ChatCompletion.body(system: system, text: guarded.masked, model: credentials.model))
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<String, TranslationFailure>
            if error != nil {
                result = .failure(TranslationFailure("无法连接翻译服务"))
            } else {
                do {
                    let translated = try ChatCompletion.text(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
                    result = .success(try TextRules.restore(translated, tokens: guarded.tokens))
                } catch {
                    result = .failure(error as? TranslationFailure ?? TranslationFailure("翻译失败"))
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    /// 不跟随重定向：密钥只发给配置里写的那个地址。
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
