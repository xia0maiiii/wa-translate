#!/bin/sh
# 编译并装到 ~/Applications，登记为登录时启动，然后立刻启动。
cd "$(dirname "$0")" || exit 1
label=com.xiaomai.watranslate
app="$HOME/Applications/WATranslate.app"
agent="$HOME/Library/LaunchAgents/$label.plist"
# 本机签名证书：辅助功能授权认的是「标识 + 签名证书」。临时签名每次编译都变，授权就得重开；
# 用一张固定的证书签，只需授权一次，以后重装、升级都沿用。
signing="$HOME/Library/Application Support/WATranslate/signing"
keychain="$signing/signing.keychain-db"
identity="WATranslate Local Signing"

create_identity() {
  mkdir -p "$signing"
  chmod 700 "$signing"
  tmp=$(mktemp -d)
  cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $identity
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$identity" \
    -out "$tmp/identity.p12" -passout pass:watranslate
  # 单独一个钥匙串文件，不进登录钥匙串，也不加入钥匙串搜索列表。
  security create-keychain -p "" "$keychain"
  security set-keychain-settings "$keychain"
  security unlock-keychain -p "" "$keychain"
  security import "$tmp/identity.p12" -k "$keychain" -P watranslate -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "" "$keychain" >/dev/null
  rm -rf "$tmp"
}

install() {
  set -e
  command -v swiftc >/dev/null 2>&1 || { echo "需要先安装 Xcode Command Line Tools：xcode-select --install"; return 1; }
  sh build.sh
  fresh=0
  if [ ! -f "$keychain" ]; then
    create_identity
    fresh=1
  fi
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
  rm -rf "$app"
  cp -R build/WATranslate.app "$app"
  security unlock-keychain -p "" "$keychain"
  codesign --force --keychain "$keychain" --sign "$identity" "$app"
  # 刚换成这张证书：旧的授权记录对不上新签名却还显示为已开启。清掉它，让系统重新询问。
  [ "$fresh" -eq 1 ] && tccutil reset Accessibility "$label" >/dev/null 2>&1 || true
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
  if [ "$fresh" -eq 1 ]; then
    echo "第一次用本机证书签名：到 系统设置 › 隐私与安全性 › 辅助功能 把 WATranslate 的开关打开。以后重新安装不用再开。"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  fi
}

(install)
result=$?
[ -t 0 ] && { printf "\n按回车关闭窗口…"; read -r _; }
exit "$result"
