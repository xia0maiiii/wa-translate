#!/bin/sh
# 端到端测试：编出替身应用和驱动，起一个假翻译接口，然后跑 e2e.py。先运行仓库根目录的 build.sh。
# 需要终端有辅助功能权限。会占用前台约半分钟。
set -eu
cd "$(dirname "$0")"
root=$(cd ../.. && pwd)
work="$root/build/e2e"
helper="$root/build/WATranslate.app/Contents/MacOS/WATranslate"
[ -x "$helper" ] || { echo "先运行 build.sh"; exit 1; }
sdk=$(xcrun --show-sdk-path)
rm -rf "$work"
mkdir -p "$work/FakeChat.app/Contents/MacOS" "$work/support"
swiftc -swift-version 5 -target arm64-apple-ios17.0-macabi -sdk "$sdk" \
  -Fsystem "$sdk/System/iOSSupport/System/Library/Frameworks" \
  -I "$sdk/System/iOSSupport/usr/lib/swift" -L "$sdk/System/iOSSupport/usr/lib/swift" \
  FakeChat/main.swift -o "$work/FakeChat.app/Contents/MacOS/FakeChat"
cp FakeChat/Info.plist "$work/FakeChat.app/Contents/Info.plist"
codesign --force --sign - "$work/FakeChat.app" 2>/dev/null
swiftc -O -swift-version 5 drive/main.swift -o "$work/drive"
printf '{"endpoint": "http://127.0.0.1:18765/chat/completions", "model": "mock-model", "key": "mock-key"}\n' > "$work/support/config.json"

python3 mock.py 18765 "$work/mock.log" &
mock=$!
trap 'kill $mock 2>/dev/null; pkill -f "$work/FakeChat.app/Contents/MacOS/FakeChat" 2>/dev/null || true' EXIT
open -g -n "$work/FakeChat.app" --env "FAKECHAT_LOG=$work/sent.log"
sleep 2
python3 e2e.py "$work" "$helper"
