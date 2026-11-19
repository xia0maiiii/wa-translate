import Foundation

/// 排查用日志：设了环境变量 WATRANSLATE_DEBUG 才往标准错误写。只写数量、耗时和状态，不写消息内容。
enum Debug {
    private static let enabled = ProcessInfo.processInfo.environment["WATRANSLATE_DEBUG"] != nil
    private static let started = Date()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(String(format: "%8.2f %@\n", Date().timeIntervalSince(started), message()).utf8))
    }
}
