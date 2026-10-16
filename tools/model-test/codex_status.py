"""Read-only live metrics for a single Codex rollout named by a run receipt."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import codex_record


def _dt(value: Any) -> datetime | None:
    if not isinstance(value, str): return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None: parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return None


def _rollout_threads(path: str | Path) -> dict:
    """Read only explicit thread lifecycle metadata, never message contents."""
    ids, child_seen, malformed = set(), False, 0
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for line in stream:
                try: event = json.loads(line)
                except ValueError:
                    malformed += 1
                    continue
                if not isinstance(event, dict): continue
                payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
                if (str(event.get("type", "")).lower() != "thread.started" and
                        str(payload.get("type", "")).lower() != "thread.started"):
                    continue
                thread_id = event.get("thread_id") or event.get("id") or payload.get("thread_id") or payload.get("id")
                if isinstance(thread_id, str) and thread_id: ids.add(thread_id)
                if (event.get("parent_thread_id") or event.get("parent_id") or
                        payload.get("parent_thread_id") or payload.get("parent_id")):
                    child_seen = True
    except OSError as exc:
        return {"root_thread_id": None, "provenance": "unavailable", "reason": str(exc),
                "malformed_lines": malformed}
    if child_seen: state = "child"
    elif len(ids) > 1: state = "ambiguous"
    elif len(ids) == 1: state = "root"
    else: state = "unknown"
    return {"root_thread_id": next(iter(ids)) if state == "root" else None,
            "provenance": state, "malformed_lines": malformed}


def live_metrics(receipt: dict, prices: dict | None) -> dict:
    """Return bounded live metrics without exposing prompt or report text.

    The receipt is the sole source of the rollout path and launch proof. No
    CODEX_HOME, authentication, settings, prompt, or report files are inspected.
    """
    if not isinstance(receipt, dict):
        return {"status": "unknown", "audit": "UNKNOWN", "reason": "receipt missing"}
    started = _dt(receipt.get("started_utc"))
    now = datetime.now(timezone.utc)
    elapsed = max(0.0, (now - started).total_seconds()) if started else None
    rollout = receipt.get("rollout_path")
    if not isinstance(rollout, str) or not rollout:
        return {"run": receipt.get("run"), "status": receipt.get("status", "unknown"),
                "elapsed_s": elapsed, "audit": "UNKNOWN", "reason": "rollout path missing"}
    config = dict(receipt)
    config["service_tier"] = receipt.get("service_tier", receipt.get("speed"))
    try:
        parsed = codex_record.parse_rollout(rollout, config, prices)
    except OSError as exc:
        return {"run": receipt.get("run"), "status": receipt.get("status", "unknown"),
                "elapsed_s": elapsed, "audit": "UNKNOWN", "reason": "rollout unavailable: " + str(exc)}
    threads = _rollout_threads(rollout)
    in_progress = str(receipt.get("status", "")).lower() in ("running", "in_progress", "started")
    audit_status = parsed["audit"]["status"]
    if in_progress:
        audit_status = "UNKNOWN"
    if threads["provenance"] in ("child", "ambiguous"):
        audit_status = "FAIL"
    elif threads["provenance"] == "unknown" and not in_progress:
        audit_status = "UNKNOWN"
    usage = parsed.get("usage") or {}
    return {
        "run": receipt.get("run"), "status": receipt.get("status", "unknown"),
        "elapsed_s": elapsed, "model": parsed.get("model"), "effort": parsed.get("effort"),
        "requested_model": receipt.get("model"), "requested_effort": receipt.get("effort"),
        "requested_service_tier": config.get("service_tier"),
        "observed_service_tier": parsed.get("observed_service_tier"),
        "usage": {k: usage.get(k) for k in codex_record.TOKENS},
        "tool_uses": parsed.get("tool_uses", 0),
        "cost": parsed.get("pricing"), "audit": audit_status,
        "audit_flags": parsed["audit"].get("flags", []),
        "audit_unknown_reasons": parsed["audit"].get("unknown_reasons", []),
        "thread": threads,
    }
