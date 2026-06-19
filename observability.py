"""Structured JSON logs and Prometheus text metrics (stdlib only)."""
import json
import os
import sys
import threading
import time
from datetime import datetime, timezone


def _utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


class Metrics:
    def __init__(self):
        self._lock = threading.Lock()
        self._requests = {}
        self._activity_waits = 0
        self._activity_wakeups = 0
        self._started_at = time.time()

    def inc_request(self, method, path, status):
        key = (method, path, str(status))
        with self._lock:
            self._requests[key] = self._requests.get(key, 0) + 1

    def inc_activity_wait(self):
        with self._lock:
            self._activity_waits += 1

    def inc_activity_wakeup(self):
        with self._lock:
            self._activity_wakeups += 1

    def render_prometheus(self, version):
        lines = []
        uptime = max(0, time.time() - self._started_at)
        lines.append("# HELP pluribusai_up PluribusAI process is running.")
        lines.append("# TYPE pluribusai_up gauge")
        lines.append("pluribusai_up 1")
        lines.append("# HELP pluribusai_uptime_seconds Process uptime.")
        lines.append("# TYPE pluribusai_uptime_seconds gauge")
        lines.append(f"pluribusai_uptime_seconds {uptime:.3f}")
        lines.append("# HELP pluribusai_info Server build info.")
        lines.append("# TYPE pluribusai_info gauge")
        lines.append(f'pluribusai_info{{version="{version}"}} 1')
        lines.append("# HELP pluribusai_http_requests_total HTTP requests.")
        lines.append("# TYPE pluribusai_http_requests_total counter")
        with self._lock:
            for (method, path, status), count in sorted(self._requests.items()):
                lines.append(
                    f'pluribusai_http_requests_total{{method="{method}",'
                    f'path="{path}",status="{status}"}} {count}')
            waits = self._activity_waits
            wakeups = self._activity_wakeups
        lines.append("# HELP pluribusai_activity_longpoll_total Activity long-poll requests.")
        lines.append("# TYPE pluribusai_activity_longpoll_total counter")
        lines.append(f"pluribusai_activity_longpoll_total {waits}")
        lines.append("# HELP pluribusai_activity_wakeups_total Activity hub wakeups.")
        lines.append("# TYPE pluribusai_activity_wakeups_total counter")
        lines.append(f"pluribusai_activity_wakeups_total {wakeups}")
        return "\n".join(lines) + "\n"


def log_event(level, event, **fields):
    fmt = os.environ.get("PLURIBUSAI_LOG_FORMAT", "json").lower()
    fields = {k: v for k, v in fields.items() if v is not None}
    if fmt == "text":
        extra = " ".join(f"{k}={v}" for k, v in fields.items())
        sys.stderr.write(f"{_utc_now()} {level.upper()} {event} {extra}\n")
    else:
        payload = {"ts": _utc_now(), "level": level, "event": event, **fields}
        sys.stderr.write(json.dumps(payload, default=str) + "\n")
    sys.stderr.flush()