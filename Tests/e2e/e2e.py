#!/usr/bin/env python3
"""端到端测试：真实的 WATranslate 进程 + 替身聊天应用 + 替身翻译接口。由 run.sh 启动。

会把替身窗口切到前台约半分钟并合成按键、点击；期间别碰键盘鼠标，否则中断（不会误发到别处）。
"""
import json
import os
import subprocess
import sys
import time

WORK, HELPER = sys.argv[1], sys.argv[2]
SENT, MOCK = f"{WORK}/sent.log", f"{WORK}/mock.log"


def drive(*args):
    result = subprocess.run([f"{WORK}/drive", *args], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f"drive {args}: {result.stderr.strip()}")
    return result.stdout.strip()


def lines(path):
    return [json.loads(line) for line in open(path)] if os.path.exists(path) else []


def sent():
    return [entry["text"] for entry in lines(SENT)]


def requests(direction):
    return [entry for entry in lines(MOCK) if entry["direction"] == direction]


def wait(condition, timeout=4.0):
    end = time.time() + timeout
    while time.time() < end:
        if condition():
            return True
        time.sleep(0.05)
    return condition()


results = []


def check(ok, name, detail=""):
    results.append(ok)
    print(("  ok   " if ok else "  失败 ") + name + (f"  [{detail}]" if detail and not ok else ""))


previous_clipboard = subprocess.run(["pbpaste"], capture_output=True).stdout
subprocess.run(["pbcopy"], input=b"CLIP-SENTINEL")
helper = subprocess.Popen([HELPER, "--target", "local.watranslate.fakechat", "--support-dir", f"{WORK}/support"],
                          stdout=open(f"{WORK}/helper.log", "w"), stderr=subprocess.STDOUT,
                          env={**os.environ, "WATRANSLATE_DEBUG": "1"})
try:
    time.sleep(1.0)
    subprocess.run(["open", f"{WORK}/FakeChat.app"])
    time.sleep(1.0)
    drive("front")
    time.sleep(0.5)

    print("收到的消息")
    check(wait(lambda: len(requests("in")) >= 3, 6), "三条外语消息都去翻了")
    time.sleep(0.8)
    texts = sorted(entry["text"][:12] for entry in requests("in"))
    check(texts == sorted(["Bom dia, tud", "Combinado", "Então podemo"]), "只翻别人发的外语：中文、自己发的、无字图片不翻", str(texts))
    check(all(entry["lang"] == "简体中文" for entry in requests("in")), "译成简体中文")
    check(wait(lambda: drive("labels", str(helper.pid)) == "1", 3), "译文层显示在屏幕上")

    print("发送前翻译")
    drive("draft", "我现在有点忙")
    drive("return")
    check(wait(lambda: sent() == ["translated 6"]), "中文草稿按回车后，发出去的是译文", str(sent()))
    out = requests("out")
    check(len(out) == 1 and out[0]["auth"] == "Bearer mock-key" and out[0]["model"] == "mock-model" and out[0]["lang"] == "English",
          "请求带配置里的密钥和模型，目标英文", str(out))
    check(drive("value") == "" and drive("has-send") == "false", "发送后输入框清空", drive("value"))
    time.sleep(0.3)
    check(subprocess.run(["pbpaste"], capture_output=True).stdout == b"CLIP-SENTINEL", "剪贴板内容还原")
    check(wait(lambda: drive("labels", str(helper.pid)) == "1", 3), "发完消息、画面停稳后译文层回来")

    drive("draft", "hello there")
    drive("return")
    check(wait(lambda: sent()[-1:] == ["hello there"]), "英文草稿原样发出")
    drive("draft", "!原文发送")
    drive("return")
    check(wait(lambda: sent()[-1:] == ["!原文发送"]), "! 开头原样发出")
    check(len(requests("out")) == 1, "这两条没有请求翻译")

    count = len(sent())
    drive("draft", "这条会失败")
    drive("return")
    check(wait(lambda: len(requests("out")) == 2), "失败用例发起了请求")
    time.sleep(0.8)
    check(len(sent()) == count and drive("value") == "这条会失败", "翻译失败：不发送，草稿保留", f"{sent()[count:]} / {drive('value')}")

    drive("draft", "这条很慢")
    drive("return")
    time.sleep(0.2)
    drive("return")
    time.sleep(0.2)
    drive("return")
    check(wait(lambda: len(sent()) == count + 1, 6), "等待期间连按回车只发一次", str(sent()[count:]))
    time.sleep(0.8)
    check(sent()[count:] == ["translated 4"], "发出的是译文且没有重复", str(sent()[count:]))

    count = len(sent())
    drive("draft", "这条很慢二")
    drive("return")
    time.sleep(0.4)
    drive("left")
    time.sleep(3.0)
    check(len(sent()) == count and drive("value") == "这条很慢二", "等待期间按了别的键：取消，不发送", f"{sent()[count:]} / {drive('value')}")

    drive("draft", "点按钮发送")
    drive("click-send")
    check(wait(lambda: sent()[count:] == ["translated 5"]), "点发送按钮同样先翻译", str(sent()[count:]))

    count = len(sent())
    drive("draft", "看这个 https://a.b/c?d=1 好吗")
    drive("return")
    check(wait(lambda: len(sent()) == count + 1) and "https://a.b/c?d=1" in sent()[-1] and "WAKEEP" not in sent()[-1], "链接原样保留", str(sent()[count:]))
    check(all("https://" not in entry["text"] for entry in requests("out")), "链接没有发给翻译接口")

    if drive("input-source") == "TISTypeKeyboardInputMode":
        print("输入法选字中")
        count, asked = len(sent()), len(requests("out"))
        drive("draft", "中文草稿")
        drive("keys", "nihao")
        time.sleep(0.6)
        drive("return")
        time.sleep(1.2)
        check(len(requests("out")) == asked and len(sent()) == count, "选字时按回车：不拦截、不翻译、不发送", f"{drive('value')!r} sent={sent()[count:]}")
    else:
        print("当前输入源不是输入法，跳过选字用例")
finally:
    helper.terminate()
    subprocess.run(["pbcopy"], input=previous_clipboard)
print(f"\n{sum(results)}/{len(results)} 通过")
sys.exit(0 if all(results) else 1)
