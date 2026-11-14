"""StreamBox backup service.

Stores encrypted backup files that StreamBox uploads (Settings › Backup & restore).
The Apple TV encrypts each backup before sending it, so this only ever holds
unreadable data. Files are deleted 30 days after they were last written.

  PUT /backups/<code>   upload (body = encrypted backup, max 5 MB)
  GET /backups/<code>   download
  GET /health           "ok"

Every request except /health needs:  Authorization: Bearer <STREAMBOX_BACKUP_PASSWORD>
"""
import hmac
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PASSWORD = os.environ.get("STREAMBOX_BACKUP_PASSWORD", "")
DATA_DIR = os.environ.get("DATA_DIR", "/data")
PORT = int(os.environ.get("PORT", "8080"))
MAX_BYTES = 5 * 1024 * 1024
KEEP_SECONDS = 30 * 24 * 3600
CODE = re.compile(r"^[A-Z0-9]{8}$")


def prune():
    cutoff = time.time() - KEEP_SECONDS
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
            os.remove(path)


class Handler(BaseHTTPRequestHandler):
    server_version = "StreamBoxBackup/1"

    def _reply(self, status, body=b"", content_type="text/plain"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorised(self):
        given = self.headers.get("Authorization", "")
        return bool(PASSWORD) and hmac.compare_digest(given, f"Bearer {PASSWORD}")

    def _path_for_code(self):
        match = re.fullmatch(r"/backups/([A-Za-z0-9]+)", self.path)
        if not match or not CODE.match(match.group(1).upper()):
            return None
        return os.path.join(DATA_DIR, match.group(1).upper() + ".bin")

    def do_GET(self):
        if self.path == "/health":
            return self._reply(200, b"ok")
        if not self._authorised():
            return self._reply(401, b"wrong password")
        path = self._path_for_code()
        if not path:
            return self._reply(400, b"bad code")
        prune()
        if not os.path.exists(path):
            return self._reply(404, b"no backup with that code")
        with open(path, "rb") as f:
            return self._reply(200, f.read(), "application/octet-stream")

    def do_PUT(self):
        if not self._authorised():
            return self._reply(401, b"wrong password")
        path = self._path_for_code()
        if not path:
            return self._reply(400, b"bad code")
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BYTES:
            return self._reply(413, b"backup too large")
        body = self.rfile.read(length)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(body)
        os.replace(tmp, path)
        prune()
        return self._reply(201, b"saved")

    def log_message(self, fmt, *args):
        # Codes stay out of the logs.
        print(f"{self.command} {re.sub(r'/backups/[A-Za-z0-9]+', '/backups/<code>', self.path)} {args[1] if len(args) > 1 else ''}")


if __name__ == "__main__":
    if not PASSWORD:
        raise SystemExit("Set STREAMBOX_BACKUP_PASSWORD")
    os.makedirs(DATA_DIR, exist_ok=True)
    print(f"StreamBox backup service on port {PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
