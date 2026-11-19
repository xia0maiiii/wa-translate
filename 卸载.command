#!/bin/sh
# 停掉并移除 WATranslate。配置目录保留。
label=com.xiaomai.watranslate
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$HOME/Applications/WATranslate.app"
echo "已卸载。配置仍在 ~/Library/Application Support/WATranslate，不需要可以手动删除。"
[ -t 0 ] && { printf "\n按回车关闭窗口…"; read -r _; }
exit 0
