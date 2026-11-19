#!/bin/sh
# 编译并装到 ~/Applications，登记为登录时启动，然后立刻启动。
cd "$(dirname "$0")" || exit 1
label=com.xiaomai.watranslate
app="$HOME/Applications/WATranslate.app"
agent="$HOME/Library/LaunchAgents/$label.plist"

install() {
  set -e
  command -v swiftc >/dev/null 2>&1 || { echo "需要先安装 Xcode Command Line Tools：xcode-select --install"; return 1; }
  sh build.sh
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
  rm -rf "$app"
  cp -R build/WATranslate.app "$app"
  # 临时签名的程序每次编译指纹都变，旧的辅助功能授权对不上新程序却还显示为已开启。清掉它，让系统重新询问。
  tccutil reset Accessibility "$label" >/dev/null 2>&1 || true
  cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>$app/Contents/MacOS/WATranslate</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/WATranslate.log</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST
  launchctl bootstrap "gui/$(id -u)" "$agent"
  echo
  echo "已安装并启动，菜单栏会出现「WA 译」。"
  echo "系统会弹出授权提示：到 系统设置 › 隐私与安全性 › 辅助功能 把 WATranslate 的开关打开（每次重新安装后都要开一次）。"
}

(install)
result=$?
[ -t 0 ] && { printf "\n按回车关闭窗口…"; read -r _; }
exit "$result"
