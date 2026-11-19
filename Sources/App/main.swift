import AppKit

// 两个开发用参数：--target 换一个被接入的应用（用替身应用做端到端测试），--support-dir 换配置目录。
func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let target = option("--target")
// 同一个 WhatsApp 上只能有一个实例在拦截发送。
if target == nil, let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
    exit(0)
}

let supportDirectory = option("--support-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WATranslate", isDirectory: true)
let controller = AppController(targetBundleID: target ?? "net.whatsapp.WhatsApp", supportDirectory: supportDirectory)
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = controller
application.run()
