#!/usr/bin/env python3
"""Correlate a Stobe chat request across bounded native and backend log tails.

This reports evidence correlation only. Missing reply evidence is PENDING because
backend generation and native delivery can finish after the initial observation
window; this tool never converts a timeout or bounded-tail miss into a product
FAIL. Native timestamps must be converted with the explicit offset for the rig.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Optional

TS_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\]")
RID_RE = re.compile(r'["\']request_id["\']\s*[:=]\s*["\']([^"\']+)["\']|\brequest_id=([A-Za-z0-9_-]+)')


@dataclass
class Tail:
    lines: list[str]
    truncated: bool


def bounded_tail(path: str, max_bytes: int = 64 << 20) -> Tail:
    """Read at most max_bytes from a file's end and discard a partial first line."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        start = max(0, size - max_bytes)
        f.seek(start)
        raw = f.read(max_bytes)
    if start:
        newline = raw.find(b"\n")
        raw = raw[newline + 1:] if newline >= 0 else b""
    return Tail(raw.decode("utf-8", "replace").splitlines(), start > 0)


def timestamp(line: str) -> Optional[dt.datetime]:
    m = TS_RE.match(line)
    if not m:
        return None
    fmt = "%Y-%m-%d %H:%M:%S.%f" if "." in m.group(1) else "%Y-%m-%d %H:%M:%S"
    try:
        return dt.datetime.strptime(m.group(1), fmt)
    except ValueError:
        return None


def request_id(line: str) -> Optional[str]:
    m = RID_RE.search(line)
    return (m.group(1) or m.group(2)) if m else None


def json_payload(line: str) -> dict:
    start = line.find("{")
    if start < 0:
        return {}
    try:
        value, _ = json.JSONDecoder().raw_decode(line[start:])
        return value if isinstance(value, dict) else {}
    except (ValueError, json.JSONDecodeError):
        return {}


def target_in_native_reply(line: str, target: str) -> bool:
    low = line.lower()
    name = re.escape(target.lower())
    return bool(re.search(r"(?:npc_say:\s*|action_exec:\s*say\s*\[)" + name + r"(?:\b|\s*\[)", low))


def correlate(native_path: str, backend_paths: list[str], kah_id: str, target: str,
              utterance: str, native_utc_offset_minutes: int,
              max_bytes: int = 64 << 20,
              observation_until_utc: Optional[dt.datetime] = None) -> dict:
    native = bounded_tail(native_path, max_bytes)
    backend_tails = [bounded_tail(path, max_bytes) for path in backend_paths]
    backend_lines = [line for tail in backend_tails for line in tail.lines]
    backend_truncated = any(tail.truncated for tail in backend_tails)
    offset = dt.timedelta(minutes=native_utc_offset_minutes)

    inbox = None
    inbox_local = None
    native_request = re.compile(r"TEST_INBOX: say id=" + re.escape(kah_id) + r"(?=\s|$)")
    native_target = re.compile(r"\btarget=" + re.escape(target) + r"(?=\s+text=|$)")
    for line in native.lines:
        ts = timestamp(line)
        if native_request.search(line) and native_target.search(line) and "text=" + utterance in line:
            inbox, inbox_local = line, ts
            break
    if not inbox or not inbox_local:
        return {"status": "PENDING", "reason": "matching native request not found in bounded tail",
                "truncated": native.truncated or backend_truncated}
    inbox_utc = inbox_local - offset

    inbound = None
    backend_id = None
    for line in backend_lines:
        ts = timestamp(line)
        payload = json_payload(line)
        logged_target = payload.get("target_npc")
        logged_text = payload.get("message", payload.get("message_preview"))
        if ("Chat input received" not in line or logged_target != target
                or logged_text != utterance or not ts):
            continue
        if abs((ts - inbox_utc).total_seconds()) <= 5:
            inbound, backend_id = line, request_id(line)
            break
    if not inbound or not backend_id:
        return {"status": "PENDING", "reason": "native request found; matching backend ingress/request ID not yet correlated",
                "kah_id": kah_id, "native_local": inbox_local.isoformat(" "),
                "truncated": native.truncated or backend_truncated}

    outcome = None
    outcome_ts = None
    for line in backend_lines:
        ts = timestamp(line)
        if backend_id not in line or not ts:
            continue
        low = line.lower()
        if ("status=ok" in low or '"status":"ok"' in low or '"status": "ok"' in low
                or "http=200" in low or "http 200" in low or '"http_status":200' in low
                or '"http_status": 200' in low):
            outcome, outcome_ts = line, ts
            break
    if not outcome or not outcome_ts:
        return {"status": "PENDING", "reason": "backend request correlated; terminal response not present yet",
                "kah_id": kah_id, "backend_id": backend_id,
                "native_local": inbox_local.isoformat(" "), "truncated": native.truncated or backend_truncated}

    outcome_local = outcome_ts + offset
    replies = []
    for line in native.lines:
        ts = timestamp(line)
        if not ts or not target_in_native_reply(line, target):
            continue
        if ts >= outcome_local and (observation_until_utc is None or ts - offset <= observation_until_utc):
            replies.append((ts, line))
    if not replies:
        status = "PENDING"
        reason = "backend response exists; matching native NPC reply may arrive after this observation window"
        if observation_until_utc and outcome_ts > observation_until_utc:
            reason = "observation window ended before backend response; do not classify as no-response"
        return {"status": status, "reason": reason, "kah_id": kah_id,
                "backend_id": backend_id, "backend_response_utc": outcome_ts.isoformat(" "),
                "truncated": native.truncated or backend_truncated}

    reply_ts, reply = replies[0]
    return {"status": "PASS", "kind": "correlation-only", "kah_id": kah_id,
            "backend_id": backend_id, "native_local": inbox_local.isoformat(" "),
            "backend_response_utc": outcome_ts.isoformat(" "),
            "native_reply_local": reply_ts.isoformat(" "), "reply_line": reply,
            "truncated": native.truncated or backend_truncated}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--native", required=True)
    p.add_argument("--backend", required=True, action="append",
                   help="backend log to scan; repeat for ingress, audit/LLM, and delivery logs")
    p.add_argument("--kah-id", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--utterance", required=True)
    p.add_argument("--native-utc-offset-minutes", type=int, required=True,
                   help="explicit rig-local minus UTC offset (for example -420)")
    p.add_argument("--max-bytes", type=int, default=64 << 20)
    p.add_argument("--observation-until-utc", help="optional YYYY-MM-DD HH:MM:SS cutoff")
    a = p.parse_args()
    until = dt.datetime.strptime(a.observation_until_utc, "%Y-%m-%d %H:%M:%S") if a.observation_until_utc else None
    result = correlate(a.native, a.backend, a.kah_id, a.target, a.utterance,
                       a.native_utc_offset_minutes, a.max_bytes, until)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["status"] in ("PASS", "PENDING") else 1


if __name__ == "__main__":
    raise SystemExit(main())
