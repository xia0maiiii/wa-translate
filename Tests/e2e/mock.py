#!/usr/bin/env python3
"""翻译接口替身：记录每个请求；原文里有「慢」就拖两秒，有「失败」就回 500。"""
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        system, text = body["messages"][0]["content"], body["messages"][1]["content"]
        direction = "out" if "for a WhatsApp conversation" in system else "in"
        language = re.search(r"into (?:natural )?(.+?)(?: for a WhatsApp|\. )", system).group(1)
        with open(LOG, "a") as log:
            log.write(json.dumps({"direction": direction, "text": text, "auth": self.headers.get("Authorization"),
                                  "model": body["model"], "lang": language}, ensure_ascii=False) + "\n")
        if "慢" in text:
            time.sleep(2.0)
        if "失败" in text:
            self.send_response(500)
            self.end_headers()
            return
        tokens = " ".join(re.findall(r"WAKEEP\w+?END", text))
        reply = f"translated {len(text)} {tokens}".strip() if direction == "out" else f"【译】{text[:60]}"
        data = json.dumps({"choices": [{"message": {"content": reply}, "finish_reason": "stop"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
