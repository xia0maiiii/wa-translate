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
3. 安装脚本会打开辅助功能设置页：把 WATranslate 的开关打开。授权后几秒内菜单栏从「WA 待授权」变成「WA 译」。

第一次安装时，脚本会生成一张本机签名证书，放在 `~/Library/Application Support/WATranslate/signing/`（单独的钥匙串文件，不进登录钥匙串）。辅助功能授权认的是「程序标识 + 签名证书」，所以**只需授权一次**，以后重新安装、升级都沿用。删掉这个目录后再安装会换一张新证书，需要重新授权。持有这张证书的人可以签出同样被授权的程序，所以不要把这个目录拷给别人。

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
- 译文是通过「全选 + 粘贴」写进输入框的，会短暂借用剪贴板，写完立刻还原；随后程序替你再按一次回车把它发出去。

**收到的消息**

- 只翻当前聊天里看得见的、别人发来的消息；中文为主的消息、没有文字的图片不翻。
- 滚动、来新消息时译文先收起，画面停稳后再读消息、摆译文，所以快速滚过的消息不会去翻。译文只缓存在内存里，退出即清空。
- 译文层不接鼠标，不挡 WhatsApp 的任何操作；WhatsApp 不在前台时自动隐藏。

看得见的外语消息会发给你配置的翻译接口，这一点和 Discord 的自动翻译插件相同。

## 已知限制

- 草稿里用选择器插入的 `@提及` 经过翻译后会变成普通文字，不再通知对方。需要提及时用 `!` 开头按原文发，或先关掉发送翻译。
- 只处理普通文字消息的发送。编辑已发送的消息、图片说明文字不翻译，按 WhatsApp 原有方式处理或提示失败。
- 气泡右侧空间不足（窗口很窄）时，译文靠聊天区右边缘显示，会盖住一部分气泡。
- 译文的高度以气泡看得见的部分为限（最少约七行），放不下的以省略号收尾。带大图的长消息滚动一下，让气泡多露出一些，就能看到更多。
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

端到端测试在 `Tests/e2e/`：一个无障碍标识和 WhatsApp 相同的替身聊天应用、一个假翻译接口、一个模拟按键和点击的驱动。

```bash
sh build.sh && sh Tests/e2e/run.sh    # 占用前台约半分钟，期间别碰键盘鼠标
```

它靠两个开发用的启动参数让程序对着替身而不是真实聊天：`--target <bundle id>` 换被接入的应用，`--support-dir <目录>` 换配置目录。

## 排查

译文不出来、发送没反应时，先看菜单第一行的状态。还看不出原因就打开日志（只记数量、耗时和状态，不记消息内容）：

```bash
launchctl setenv WATRANSLATE_DEBUG 1
launchctl kickstart -k "gui/$(id -u)/com.xiaomai.watranslate"
tail -f ~/Library/Logs/WATranslate.log
```

查完执行 `launchctl unsetenv WATRANSLATE_DEBUG` 再 `kickstart` 一次关掉。
