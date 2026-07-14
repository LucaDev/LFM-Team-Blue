#!/usr/bin/env python3
import json
import os
import sys
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


NTFY_BASE_URL = os.environ.get("NTFY_BASE_URL", "http://ntfy").rstrip("/")
NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "").strip()
LISTEN_HOST = os.environ.get("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8088"))


if not NTFY_TOPIC:
    print("NTFY_TOPIC is required", file=sys.stderr)
    sys.exit(1)


def severity_value(alerts, common_labels):
    if common_labels.get("severity"):
        return common_labels["severity"]
    if alerts:
        return alerts[0].get("labels", {}).get("severity", "info")
    return "info"


def priority_for(status, severity):
    if status == "resolved":
        return "2"
    if severity == "critical":
        return "5"
    if severity == "warning":
        return "4"
    return "3"


def tags_for(status, severity):
    if status == "resolved":
        return "white_check_mark"
    if severity == "critical":
        return "rotating_light,warning"
    if severity == "warning":
        return "warning"
    return "information_source"


def title_and_body(payload):
    alerts = payload.get("alerts") or []
    common_labels = payload.get("commonLabels") or {}
    common_annotations = payload.get("commonAnnotations") or {}
    status = payload.get("status", "unknown")
    alertname = common_labels.get("alertname")

    if not alertname and alerts:
        alertname = alerts[0].get("labels", {}).get("alertname", "HomelabAlert")
    if not alertname:
        alertname = "HomelabAlert"

    severity = severity_value(alerts, common_labels)
    title = f"[{status.upper()}] {alertname}"

    lines = []
    summary = common_annotations.get("summary", "").strip()
    description = common_annotations.get("description", "").strip()

    if summary:
        lines.append(summary)
    if description:
        lines.append(description)

    lines.append(f"Severity: {severity}")
    lines.append(f"Alert count: {len(alerts)}")

    for alert in alerts[:5]:
        labels = alert.get("labels", {})
        instance = labels.get("instance") or labels.get("service") or "-"
        job = labels.get("job", "-")
        lines.append(f"- {labels.get('alertname', alertname)} on {instance} ({job})")

    if len(alerts) > 5:
        lines.append(f"... and {len(alerts) - 5} more")

    external_url = payload.get("externalURL", "").strip()
    if external_url:
        lines.append(f"Source: {external_url}")

    return title, "\n".join(lines), priority_for(status, severity), tags_for(status, severity)


def publish_to_ntfy(payload):
    title, body, priority, tags = title_and_body(payload)
    url = f"{NTFY_BASE_URL}/{urllib.parse.quote(NTFY_TOPIC)}"
    request = urllib.request.Request(url, data=body.encode("utf-8"), method="POST")
    request.add_header("Content-Type", "text/plain; charset=utf-8")
    request.add_header("Title", title)
    request.add_header("Priority", priority)
    request.add_header("Tags", tags)
    with urllib.request.urlopen(request, timeout=10) as response:
        response.read()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/healthz":
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"ok\n")

    def do_POST(self):
        if self.path != "/alertmanager":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length)

        try:
            payload = json.loads(raw_body or b"{}")
            publish_to_ntfy(payload)
        except Exception as exc:  # noqa: BLE001
            self.send_response(500)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(f"error: {exc}\n".encode("utf-8"))
            return

        self.send_response(204)
        self.end_headers()

    def log_message(self, format, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), format % args))


def main():
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
