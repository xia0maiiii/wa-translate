import Foundation

// Core 的行为测试：swiftc Sources/Core/*.swift Tests/main.swift 后直接运行，失败即非零退出。
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String, line: UInt = #line) {
    checks += 1
    if !condition() {
        FileHandle.standardError.write("失败（第 \(line) 行）：\(name)\n".data(using: .utf8)!)
        exit(1)
    }
}
let m = "\u{200E}"

// 发送前：只翻含中文的草稿，! ！ / 开头放行
check(TextRules.needsOutgoingTranslation("我现在有点忙"), "中文草稿要翻")
check(TextRules.needsOutgoingTranslation("  ok 我晚点回你"), "中英混排也要翻")
check(!TextRules.needsOutgoingTranslation("see you tomorrow"), "纯英文不翻")
check(!TextRules.needsOutgoingTranslation("!原文发送"), "! 开头按原文发")
check(!TextRules.needsOutgoingTranslation("！原文发送"), "全角 ！ 开头按原文发")
check(!TextRules.needsOutgoingTranslation("/命令"), "/ 开头按原文发")
check(!TextRules.needsOutgoingTranslation("   "), "空草稿不翻")
check(TextRules.pickerLikelyOpen("你好 @jo"), "未完成的 @ 提及说明候选框开着")
check(TextRules.pickerLikelyOpen("好的 :smi"), "未完成的表情短码说明候选框开着")
check(!TextRules.pickerLikelyOpen("你好 @joao 在吗"), "提及后面还有字就不是在选候选")
check(!TextRules.pickerLikelyOpen("时间：下午三点"), "全角冒号不是表情短码")

// 收到的消息：外语才翻
check(TextRules.needsIncomingTranslation("Bom dia, tudo bem?"), "葡语要翻")
check(TextRules.needsIncomingTranslation("ok"), "两个字母的短句也翻")
check(!TextRules.needsIncomingTranslation("今天下午三点开会"), "中文不翻")
check(!TextRules.needsIncomingTranslation("好的 ok 收到了谢谢"), "中文为主的混排不翻")
check(TextRules.needsIncomingTranslation("Vamos fechar o pedido 订单 hoje à tarde"), "外语为主的混排要翻")
check(!TextRules.needsIncomingTranslation("https://example.com/a/b?c=d"), "只有链接不翻")
check(!TextRules.needsIncomingTranslation("👍👍 123"), "只有表情和数字不翻")

// 保护与还原
let guarded = TextRules.protect("看这个 https://a.b/c?d=1 和 `code x` @joao_1 好吗")
check(!guarded.masked.contains("https://") && !guarded.masked.contains("`") && !guarded.masked.contains("@joao"), "链接、代码、提及都换成占位符")
check(guarded.tokens.count == 3, "三处各一个占位符")
check((try? TextRules.restore(guarded.masked, tokens: guarded.tokens)) == "看这个 https://a.b/c?d=1 和 `code x` @joao_1 好吗", "原样还原")
let onlyLink = TextRules.protect("去 https://a.b 看")
let token = onlyLink.tokens.keys.first!
check((try? TextRules.restore("go to \(token) and look", tokens: onlyLink.tokens)) == "go to https://a.b and look", "译文里的占位符换回链接")
check((try? TextRules.restore("go and look", tokens: onlyLink.tokens)) == nil, "译文丢了占位符就作废")
check((try? TextRules.restore("\(token) \(token)", tokens: onlyLink.tokens)) == nil, "占位符重复也作废")

// 气泡描述（结构取自真实 WhatsApp 26.45，内容为虚构）
check(Bubble.body(fromDescription: "\(m)消息, Bom dia, tudo bem?, 下午9:41, \(m)由+ 5 5,4 1,9 9 9 9 9,0 0 0 0发送") == "Bom dia, tudo bem?", "收到的文字，正文里带逗号")
check(Bubble.body(fromDescription: "\(m)你的消息, I can send it tomorrow., 下午9:42, \(m)已发送给+ 5 5,4 1,9 9 9 9 9,0 0 0 0, \(m)已送达") == "I can send it tomorrow.", "自己发的文字")
check(Bubble.body(fromDescription: "\(m)Message, See you at 10:30, ok?, 9:41 PM, \(m)Sent by Ana") == "See you at 10:30, ok?", "正文里的时间不当作消息时间")
check(Bubble.body(fromDescription: "\(m)消息, linha um\nlinha dois, 21:41, \(m)由Ana发送") == "linha um\nlinha dois", "多行正文")
check(Bubble.body(fromDescription: "\(m)你的照片, 下午9:41, \(m)已发送给Ana") == nil, "没有说明文字的图片")
check(Bubble.body(fromDescription: "\(m)照片, Olha o catálogo novo, 下午9:41, \(m)由Ana发送") == "Olha o catálogo novo", "图片的说明文字")
check(Bubble.body(fromDescription: "\(m)消息, \(m)已转发, Promoção só hoje, 下午9:41, \(m)由Ana发送") == "Promoção só hoje", "正文前的标记段去掉")
check(Bubble.body(fromDescription: "\(m)正在回复\(m)你.\n\(m)消息, Combinado, 下午9:41, \(m)由+ 5 5,4 1发送.\n\(m)引用消息.\nEntrego amanhã, pode ser?") == "Combinado", "回复气泡取本条消息而不是被引用的那条")
check(Bubble.body(fromDescription: "\(m)消息, Fechado, 下午9:41") == "Fechado", "没有状态段")
check(Bubble.body(fromDescription: "\(m)消息和通话已进行端到端加密。只有此聊天中的成员可以查看。") == nil, "系统提示不是消息")
check(Bubble.body(fromDescription: "") == nil && Bubble.body(fromDescription: "plain text, 9:41") == nil, "不是 WhatsApp 文案开头的描述不处理")

// 提示词与请求
check(Prompts.outgoing(language: "English").contains("idk") && !Prompts.outgoing(language: "Brazilian Portuguese").contains("idk"), "英文缩写规则只用于英文")
check(Prompts.outgoing(language: "Brazilian Portuguese").contains("natural Brazilian Portuguese"), "发送语言写进提示词")
check(Prompts.incoming(language: "简体中文").contains("into 简体中文"), "阅读语言写进提示词")
let body = ChatCompletion.body(system: "S", text: "T", model: "M")
check(body["model"] as? String == "M" && (body["messages"] as? [[String: String]])?.map { $0["content"] ?? "" } == ["S", "T"], "请求是系统提示词加一条用户消息")

// 应答
func reply(_ content: Any, _ reason: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content], "finish_reason": reason]]])
}
check((try? ChatCompletion.text(from: reply("  hi there \n", "stop"), status: 200)) == "hi there", "取出译文并去掉首尾空白")
check((try? ChatCompletion.text(from: reply("hi", "length"), status: 200)) == nil, "被截断的译文不用")
check((try? ChatCompletion.text(from: reply("  ", "stop"), status: 200)) == nil, "空译文不用")
check((try? ChatCompletion.text(from: reply("hi", "stop"), status: 500)) == nil, "HTTP 错误不用")
check((try? ChatCompletion.text(from: Data("oops".utf8), status: 200)) == nil, "不是 JSON 不用")

// 配置
let ok = Credentials.parse(["endpoint": "https://api.deepseek.com/chat/completions", "model": "m", "key": "k"])
check(ok?.endpoint.host == "api.deepseek.com" && ok?.model == "m" && ok?.key == "k", "读出完整配置")
check(Credentials.parse(["endpoint": "http://api.example.com/v1", "model": "m", "key": "k"]) == nil, "非本机的 http 不接受")
check(Credentials.parse(["endpoint": "http://127.0.0.1:11434/v1/chat/completions", "model": "m", "key": "k"]) != nil, "本机 http 可以")
check(Credentials.parse(["endpoint": "https://api.deepseek.com/chat/completions", "model": "m", "key": ""]) == nil, "没有密钥不算配置好")

let temp = FileManager.default.temporaryDirectory.appendingPathComponent("watranslate-tests-\(UUID().uuidString)")
let support = temp.appendingPathComponent("Library/Application Support/WATranslate")
let discordDir = temp.appendingPathComponent("Library/Application Support/BetterDiscord/plugins")
try! FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: discordDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
check(Credentials.load(supportDirectory: support, home: temp) == nil, "什么都没配时没有配置")
let discordConfig: [String: Any] = ["all": ["authKeys": ["oaicompat": ["endpoint": "https://api.deepseek.com/chat/completions", "model": "d", "key": "dk"]]]]
try! JSONSerialization.data(withJSONObject: discordConfig).write(to: discordDir.appendingPathComponent("Translator.config.json"))
check(Credentials.load(supportDirectory: support, home: temp)?.key == "dk", "没有独立配置时沿用 Discord 插件的")
try! JSONSerialization.data(withJSONObject: ["endpoint": "https://api.deepseek.com/chat/completions", "model": "w", "key": "wk"]).write(to: support.appendingPathComponent("config.json"))
check(Credentials.load(supportDirectory: support, home: temp)?.key == "wk", "独立配置优先")

// 译文标签的位置。聊天区 x 600…1500、y 100…900；measure 按「每条译文想要 300×高度」模拟。
let pane = CGRect(x: 600, y: 100, width: 900, height: 800)
func layout(_ bubbles: [CGRect], wants heights: [CGFloat]) -> [CGRect] {
    LabelLayout.frames(bubbles: bubbles, area: pane) { index, limit in
        CGSize(width: min(300, limit.width), height: min(heights[index], limit.height))
    }
}
let beside = layout([CGRect(x: 616, y: 300, width: 400, height: 33)], wants: [20])[0]
check(beside.minX == 616 + 400 + 8 - 600 && beside.minY == 200, "译文贴在气泡右侧、与气泡顶对齐")
let scrolledOff = layout([CGRect(x: 616, y: -300, width: 400, height: 640)], wants: [200])[0]
check(scrolledOff.minY == 0 && scrolledOff.maxY <= 800, "气泡顶部滚出可见范围时，译文仍在看得见的地方")
let huge = layout([CGRect(x: 616, y: 300, width: 400, height: 300)], wants: [2500])[0]
check(huge.height == 300, "很长的译文以气泡看得见的高度为限")
let short = layout([CGRect(x: 616, y: 300, width: 400, height: 33)], wants: [2500])[0]
check(short.height == LabelLayout.minimumHeight, "气泡很矮时译文也有最低高度")
let stacked = layout([CGRect(x: 616, y: 300, width: 400, height: 33), CGRect(x: 616, y: 336, width: 400, height: 33)], wants: [60, 20])
check(stacked[1].minY >= stacked[0].maxY, "上一条译文比气泡高时，下一条往下让，不重叠")
let atBottom = layout([CGRect(x: 616, y: 860, width: 400, height: 33)], wants: [100])[0]
check(atBottom.maxY <= 800, "最底下的气泡，译文不伸出可见范围")
let wide = layout([CGRect(x: 616, y: 300, width: 800, height: 33)], wants: [20])[0]
check(wide.maxX == 900 - 12, "气泡右边放不下时，译文靠聊天区右边缘")

print("通过 \(checks) 项检查")
