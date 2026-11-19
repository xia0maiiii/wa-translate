#!/bin/sh
# 跑 Core 测试，然后编出 build/WATranslate.app（本机临时签名）。
set -eu
cd "$(dirname "$0")"
app=build/WATranslate.app
rm -rf build
mkdir -p "$app/Contents/MacOS"
flags="-swift-version 5 -target arm64-apple-macos13.0 -warnings-as-errors"
swiftc $flags Sources/Core/*.swift Tests/main.swift -o build/core-tests
./build/core-tests
swiftc -O $flags Sources/Core/*.swift Sources/App/*.swift -o "$app/Contents/MacOS/WATranslate"
sed "s/__VERSION__/$(cat VERSION)/" Info.plist > "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "已生成 $app"
