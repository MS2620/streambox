"""Tellio backup and feedback service.

Stores encrypted backup files that Tellio uploads (Settings › Backup & restore).
The Apple TV encrypts each backup before sending it, so this only ever holds
unreadable data. Files are deleted 30 days after they were last written.

It also takes feedback sent from the app (Settings › About › Send feedback) and
opens a public GitHub issue for it. The sender's contact details never go on
GitHub; they are kept here and shown only on the password-protected /reports page.

  PUT  /backups/<code>   upload (body = encrypted backup, max 5 MB)      needs the backup password
  GET  /backups/<code>   download                                         needs the backup password
  POST /feedback         JSON {kind, message, contact?, device?}          open to the app, rate limited
  GET  /reports          list of feedback with contact details            needs the reports password
  GET  /health           "ok"

Backups:  Authorization: Bearer <STREAMBOX_BACKUP_PASSWORD>
Reports:  open /reports in a browser; any user name, password = FEEDBACK_PAGE_PASSWORD
"""
import base64
import hmac
import html
import json
import os
import re
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PASSWORD = os.environ.get("STREAMBOX_BACKUP_PASSWORD", "")
DATA_DIR = os.environ.get("DATA_DIR", "/data")
PORT = int(os.environ.get("PORT", "8080"))
MAX_BYTES = 5 * 1024 * 1024
KEEP_SECONDS = 30 * 24 * 3600
CODE = re.compile(r"^[A-Z0-9]{8}$")

# Feedback
GITHUB_TOKEN = os.environ.get("FEEDBACK_GITHUB_TOKEN", "")
GITHUB_REPO = os.environ.get("FEEDBACK_GITHUB_REPO", "MS2620/tellio")
REPORTS_PASSWORD = os.environ.get("FEEDBACK_PAGE_PASSWORD", "")
FEEDBACK_DIR = os.path.join(DATA_DIR, "feedback")   # a subfolder, so backup pruning leaves it alone
KINDS = {"problem": "Problem", "idea": "Idea", "other": "Something else"}
MAX_MESSAGE = 4000
MAX_CONTACT = 200
MAX_DEVICE = 200
PER_SENDER_PER_HOUR = 5
ALL_PER_DAY = 100

_rate_lock = threading.Lock()
_sent_by_sender = {}   # sender -> [timestamps]
_sent_all = []         # timestamps


def prune():
    cutoff = time.time() - KEEP_SECONDS
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
            os.remove(path)


def allowed(sender):
    """True if this sender (and everyone together) is under the limits; records the send."""
    now = time.time()
    with _rate_lock:
        recent = [t for t in _sent_by_sender.get(sender, []) if now - t < 3600]
        _sent_all[:] = [t for t in _sent_all if now - t < 86400]
        if len(recent) >= PER_SENDER_PER_HOUR or len(_sent_all) >= ALL_PER_DAY:
            _sent_by_sender[sender] = recent
            return False
        recent.append(now)
        _sent_by_sender[sender] = recent
        _sent_all.append(now)
        return True


def scrub(text):
    """Issues are public: take out links (addon and stream links carry keys and logins)
    and anything that looks like a login or key."""
    text = re.sub(r"[a-zA-Z][a-zA-Z0-9+.-]*://\S+", "[link removed]", text)
    text = re.sub(r"(?i)\b(user(name)?|pass(word)?|token|key|apikey)\s*[=:]\s*\S+", r"\1=[removed]", text)
    return text


def clean(value, limit):
    if not isinstance(value, str):
        return ""
    value = value.replace("\r", "").strip()
    return value[:limit]


def create_issue(kind, message, device, build):
    label = KINDS[kind]
    first_line = message.splitlines()[0] if message else label
    title = f"[{label}] {first_line[:70]}" + ("…" if len(first_line) > 70 else "")
    body = message + "\n\n---\n"
    if device:
        body += f"Device: {device}\n"
    if build:
        body += f"Tellio build: {build}\n"
    body += "_Sent from Tellio › Send feedback_"
    payload = json.dumps({"title": title, "body": body,
                          "labels": ["feedback", label.lower()]}).encode()
    request = urllib.request.Request(
        f"https://api.github.com/repos/{GITHUB_REPO}/issues", data=payload, method="POST",
        headers={"Authorization": f"Bearer {GITHUB_TOKEN}",
                 "Accept": "application/vnd.github+json",
                 "Content-Type": "application/json",
                 "User-Agent": "TellioFeedback/1"})
    with urllib.request.urlopen(request, timeout=20) as response:
        data = json.loads(response.read())
    return data.get("number"), data.get("html_url")


class Handler(BaseHTTPRequestHandler):
    server_version = "TellioBackup/1"

    def _reply(self, status, body=b"", content_type="text/plain", headers=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status, obj):
        return self._reply(status, json.dumps(obj).encode(), "application/json")

    def _authorised(self):
        given = self.headers.get("Authorization", "")
        return bool(PASSWORD) and hmac.compare_digest(given, f"Bearer {PASSWORD}")

    def _reports_authorised(self):
        if not REPORTS_PASSWORD:
            return False
        given = self.headers.get("Authorization", "")
        if not given.startswith("Basic "):
            return False
        try:
            _, _, password = base64.b64decode(given[6:]).decode().partition(":")
        except Exception:
            return False
        return hmac.compare_digest(password, REPORTS_PASSWORD)

    def _sender(self):
        # Behind the Cloudflare Tunnel the real address is in this header. Only used for
        # rate limiting, in memory; never stored.
        return self.headers.get("CF-Connecting-IP") or self.client_address[0]

    def _path_for_code(self):
        match = re.fullmatch(r"/backups/([A-Za-z0-9]+)", self.path)
        if not match or not CODE.match(match.group(1).upper()):
            return None
        return os.path.join(DATA_DIR, match.group(1).upper() + ".bin")

    def do_GET(self):
        if self.path == "/health":
            return self._reply(200, b"ok")
        if self.path.split("?")[0] == "/reports":
            return self._reports()
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

    def do_POST(self):
        if self.path != "/feedback":
            return self._reply(404, b"not found")
        if not GITHUB_TOKEN:
            return self._json(503, {"error": "Feedback isn't set up on this server."})
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 20000:
            return self._json(413, {"error": "Message too long."})
        try:
            data = json.loads(self.rfile.read(length))
        except Exception:
            return self._json(400, {"error": "Couldn't read the message."})
        kind = data.get("kind") if data.get("kind") in KINDS else "other"
        message = scrub(clean(data.get("message"), MAX_MESSAGE))
        contact = clean(data.get("contact"), MAX_CONTACT)
        device = scrub(clean(data.get("device"), MAX_DEVICE))
        build = clean(str(data.get("build", "")), 20)
        if len(message) < 3:
            return self._json(400, {"error": "Please write a message first."})
        if not allowed(self._sender()):
            return self._json(429, {"error": "Too many messages for now. Please try again later."})
        try:
            number, url = create_issue(kind, message, device, build)
        except urllib.error.HTTPError as error:
            print(f"GitHub refused the issue: {error.code}")
            return self._json(502, {"error": "Couldn't send it right now. Please try again later."})
        except Exception as error:
            print(f"GitHub unreachable: {type(error).__name__}")
            return self._json(502, {"error": "Couldn't send it right now. Please try again later."})
        os.makedirs(FEEDBACK_DIR, exist_ok=True)
        record = {"number": number, "url": url, "kind": KINDS[kind], "message": message,
                  "contact": contact, "device": device, "build": build, "time": int(time.time())}
        with open(os.path.join(FEEDBACK_DIR, f"{number}.json"), "w") as f:
            json.dump(record, f)
        return self._json(201, {"number": number, "url": url})

    def _reports(self):
        if not self._reports_authorised():
            return self._reply(401, b"password needed", headers={
                "WWW-Authenticate": 'Basic realm="Tellio feedback", charset="UTF-8"'})
        records = []
        if os.path.isdir(FEEDBACK_DIR):
            for name in os.listdir(FEEDBACK_DIR):
                try:
                    with open(os.path.join(FEEDBACK_DIR, name)) as f:
                        records.append(json.load(f))
                except Exception:
                    pass
        records.sort(key=lambda r: r.get("time", 0), reverse=True)
        rows = []
        for r in records:
            when = time.strftime("%d %b %Y %H:%M", time.gmtime(r.get("time", 0)))
            contact = html.escape(r.get("contact") or "") or "<span class=dim>none</span>"
            rows.append(
                f"<tr><td><a href='{html.escape(r.get('url') or '#')}'>#{r.get('number')}</a></td>"
                f"<td>{when}</td><td>{html.escape(r.get('kind', ''))}</td>"
                f"<td class=msg>{html.escape(r.get('message', ''))}</td><td>{contact}</td>"
                f"<td class=dim>{html.escape(r.get('device') or '')} {html.escape(r.get('build') or '')}</td></tr>")
        page = f"""<!doctype html><html><head><meta charset=utf-8><meta name=viewport content="width=device-width">
<meta name=robots content=noindex><title>Tellio feedback</title><style>
body{{font:15px system-ui,sans-serif;background:#111418;color:#eee;margin:24px}}
table{{border-collapse:collapse;width:100%}}td,th{{padding:8px 10px;border-bottom:1px solid #2a2f37;vertical-align:top;text-align:left}}
a{{color:#9cc4ff}}.msg{{white-space:pre-wrap;max-width:560px}}.dim{{color:#8a919c}}</style></head><body>
<h1>Tellio feedback</h1><p class=dim>{len(records)} messages. Contact details are only shown here, never on GitHub.</p>
<table><tr><th>Issue</th><th>Sent (UTC)</th><th>Type</th><th>Message</th><th>Contact</th><th>Device</th></tr>
{''.join(rows) or '<tr><td colspan=6 class=dim>Nothing yet.</td></tr>'}</table></body></html>"""
        return self._reply(200, page.encode(), "text/html; charset=utf-8",
                           headers={"Cache-Control": "no-store"})

    def log_message(self, fmt, *args):
        # Codes stay out of the logs.
        print(f"{self.command} {re.sub(r'/backups/[A-Za-z0-9]+', '/backups/<code>', self.path)} {args[1] if len(args) > 1 else ''}")


if __name__ == "__main__":
    if not PASSWORD:
        raise SystemExit("Set STREAMBOX_BACKUP_PASSWORD")
    os.makedirs(DATA_DIR, exist_ok=True)
    print(f"Tellio backup service on port {PORT}")
    print("Feedback: " + ("on" if GITHUB_TOKEN else "off (set FEEDBACK_GITHUB_TOKEN)")
          + ", reports page: " + ("on" if REPORTS_PASSWORD else "off (set FEEDBACK_PAGE_PASSWORD)"))
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
