# WA 翻译

给 Mac 上的原生 WhatsApp 加上和 Discord、Telegram 那两套插件一样的翻译：

- **发送前翻译**：在输入框里写中文，按回车或点发送，先译成英文（可改成葡语、西语）再发出去。翻译失败时草稿原样留着，不会把中文发出去。
- **收到的消息翻译**：别人发来的外语消息，译文显示在气泡右侧，默认译成简体中文。

它是一个菜单栏小程序（`WA 译`），通过系统的辅助功能接口读写 WhatsApp 的界面。**不修改、不重签 WhatsApp.app**，WhatsApp 自动更新不受影响。

当前支持 Apple 芯片 Mac、macOS 13 以上、官网下载版 WhatsApp for Mac（在 26.45 上做的适配）。

## 为什么不是注入

Telegram 那版是往应用里加一个动态库再重新签名。WhatsApp 不能这样做：它跑在沙盒里，聊天数据放在按开发者团队授权的共享容器和钥匙串里，一旦换成本地签名，这些授权就失效，应用起不来，或者起来了读不到账号。所以改成在应用外面做：用辅助功能接口读输入框和消息气泡，用事件拦截接住回车和发送按钮。

## 安装

1. 装好 Xcode Command Line Tools（`xcode-select --install`）。
2. 双击 **安装.command**。它会编译、装到 `~/Applications/WATranslate.app`、登记为登录时启动，并立刻启动。
3. 系统会提示授权：到 **系统设置 › 隐私与安全性 › 辅助功能** 打开 WATranslate。授权后几秒内菜单栏从「WA 待授权」变成「WA 译」。

程序是本机临时签名的，**每次重新安装后要重新授权一次**：在辅助功能列表里把旧的 WATranslate 删掉（选中后点「−」），再打开新的。

卸载双击 **卸载.command**。

## 配置

翻译接口用 OpenAI 兼容的 `chat/completions`。按下面的顺序找配置，找到第一份可用的为止：

1. `~/Library/Application Support/WATranslate/config.json`（格式见 `config.example.json`）
2. TG 发送翻译的 `~/Library/Application Support/TGSendTranslate/config.json`
3. Discord Translator 插件里的 OpenAI 兼容配置

所以装过 Discord 那套插件的电脑不用另外配置。接口地址只接受 `https`；`http` 仅限本机地址（本地模型服务）。配置文件里有密钥，不要提交到仓库。

菜单栏里可以分别开关两个方向、选发送语言。开关和语言存在同目录的 `preferences.json`；阅读语言默认「简体中文」，要改就编辑其中的 `reading_language`，然后重启程序。

## 使用

**发送**

- 草稿里有中文才翻译；纯英文直接发。
- `!`、`！` 或 `/` 开头的消息按原文发送。
- 等译文的一两秒里，输入框上方显示「翻译中…」。这时再按发送会被忽略；按别的键、点别处、切走 WhatsApp 都会取消这次发送，草稿不动。
- 链接、代码和 `@名字` 不会发给翻译接口，也不会被改动。
- 输入法还在选字时的回车、`@` 或表情候选框开着时的回车，不拦截。
- 译文是通过「全选 + 粘贴」写进输入框的，会短暂借用剪贴板，写完立刻还原。

**收到的消息**

- 只翻当前聊天里看得见的、别人发来的消息；中文为主的消息、没有文字的图片不翻。
- 滚动、来新消息时译文先收起，画面停稳后再读消息、摆译文，所以快速滚过的消息不会去翻。译文只缓存在内存里，退出即清空。
- 译文层不接鼠标，不挡 WhatsApp 的任何操作；WhatsApp 不在前台时自动隐藏。

看得见的外语消息会发给你配置的翻译接口，这一点和 Discord 的自动翻译插件相同。

## 已知限制

- 草稿里用选择器插入的 `@提及` 经过翻译后会变成普通文字，不再通知对方。需要提及时用 `!` 开头按原文发，或先关掉发送翻译。
- 只处理普通文字消息的发送。编辑已发送的消息、图片说明文字不翻译，按 WhatsApp 原有方式处理或提示失败。
- 气泡右侧空间不足（窗口很窄）时，译文靠聊天区右边缘显示，会盖住一部分气泡。
- 界面元素是按无障碍标识找的（`ChatBar_ComposerTextView`、`ChatBar_SendButton`、`ChatMessagesTableView`、`WAMessageBubbleTableViewCell`）。WhatsApp 改了这些标识或消息描述的格式，就要更新 `Sources/App/ChatApp.swift` 和 `Sources/Core/Bubble.swift`。

## 源码

```bash
sh build.sh    # 跑 Core 测试，生成 build/WATranslate.app
```

- `Sources/Core/`：不依赖界面的规则——哪些文字要翻、气泡描述怎么取正文、提示词、接口应答、配置读取。`Tests/main.swift` 是它的测试。
- `Sources/App/SendInterceptor.swift`：发送前翻译。
- `Sources/App/IncomingOverlay.swift`：收到的消息翻译。
- `Sources/App/ChatApp.swift`：在 WhatsApp 界面里找元素。
- `Sources/App/AppController.swift`：菜单栏和开关。

开发用的两个启动参数：`--target <bundle id>` 换一个被接入的应用，`--support-dir <目录>` 换配置目录。用它们可以让程序对着一个标识相同的替身应用和本机的假翻译接口做端到端测试，不碰真实聊天。
