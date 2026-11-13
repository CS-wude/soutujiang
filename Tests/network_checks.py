#!/usr/bin/env python3
"""Real local HTTP boundary checks. No internet or third-party Python modules."""
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import json

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="feishu-image-tests-") as folder:
    env = dict(os.environ, IMAGE_HELPER_FIXTURE_DIRECTORY=folder)
    subprocess.run(["swift", "run", "CoreChecks"], cwd=ROOT, env=env, check=True)

    class Handler(http.server.BaseHTTPRequestHandler):
        meme_counts = {}
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.path.startswith("/meme-"):
                self.meme_counts[self.path] = self.meme_counts.get(self.path, 0) + 1
                count = self.meme_counts[self.path]
                image = {"title_zh": f"reply {count}", "url": "https://images.example/test.gif", "kind": "gif"}
                body = {"data": [image]}
                status = 200
                if self.path == "/meme-rate":
                    status, body = 429, {"error": "rate_limited"}
                elif self.path == "/meme-credit":
                    status, body = 402, {"error": "insufficient_credits"}
                elif self.path == "/meme-invalid":
                    body = {"data": "wrong shape"}
                elif self.path == "/meme-empty" and count == 1:
                    body = {"data": []}
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if self.path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/png")
                self.end_headers()
                return
            if self.path in ("/png", "/gif"):
                data = (Path(folder) / ("test" + self.path.replace("/", "."))).read_bytes()
                content_type = "image/" + self.path[1:]
                status = 200
            elif self.path == "/oversize":
                data = b"x" * 32768
                content_type = "image/png"
                status = 200
            else:
                data = b"<html>not an image</html>"
                content_type = "text/html"
                status = 403 if self.path == "/forbidden" else 200
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(26 * 1024 * 1024 if self.path == "/oversize" else len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
                if self.path == "/oversize":
                    for _ in range(832):
                        self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        env["IMAGE_HELPER_TEST_BASE_URL"] = f"http://127.0.0.1:{server.server_port}"
        subprocess.run(["swift", "run", "CoreChecks"], cwd=ROOT, env=env, check=True)
    finally:
        server.shutdown()
        server.server_close()
