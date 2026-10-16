"""Codex PreToolUse/SessionStart/SubagentStart/SessionEnd guard hook.

Configure this program as the isolated run's hook for those events. PreToolUse
allows only the four frozen MCP tools. SubagentStart is auditable but Codex
hooks cannot reliably veto delegation; features.multi_agent=false must also be
set. Receipts contain hashes and decision metadata, never tool arguments.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import sys
from datetime import datetime, timezone

ALLOW = {"mcp__frozen__list", "mcp__frozen__read", "mcp__frozen__search", "mcp__frozen__sql"}
FROZEN_ROOT = Path(os.environ.get("CODEX_FROZEN_ROOT", r"C:\KenshiTestRuns\invest\frozen-2026-10-14"))
LOG_ENV = "CODEX_BENCH_GUARD_LOG"


def _receipt(event: dict, decision: str, reason: str = "") -> bool:
    path_text = os.environ.get(LOG_ENV)
    if not path_text:
        return False
    path = Path(path_text).resolve()
    root = Path(os.environ.get("CODEX_FROZEN_ROOT", str(FROZEN_ROOT))).resolve()
    try:
        path.relative_to(root)
    except ValueError:
        pass
    else:
        return False
    raw = json.dumps(event.get("tool_input", {}), sort_keys=True, ensure_ascii=False, default=str).encode("utf-8")
    line = {"time_utc": datetime.now(timezone.utc).isoformat(),
            "event": event.get("hook_event_name"), "tool": event.get("tool_name"),
            "session_id": event.get("session_id"), "decision": decision,
            "reason": reason, "input_sha256": hashlib.sha256(raw).hexdigest()}
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(line, sort_keys=True) + "\n")
        return True
    except OSError:
        # A missing audit receipt is itself not a PASS; caller audits log count.
        return False


def handle(event: dict) -> dict:
    kind = event.get("hook_event_name")
    tool = event.get("tool_name", "")
    if kind == "PreToolUse":
        args = event.get("tool_input")
        allowed = tool in ALLOW and isinstance(args, dict)
        if allowed:
            allowed_keys = {"mcp__frozen__list": {"path"},
                            "mcp__frozen__read": {"path", "byte_limit", "start_line", "line_count"},
                            "mcp__frozen__search": {"query", "path", "max_results", "byte_budget", "byte_offset", "start_line"},
                            "mcp__frozen__sql": {"query"}}[tool]
            allowed = set(args) <= allowed_keys
        decision = "allow" if allowed else "deny"
        reason = "" if allowed else "Frozen investigation only; delegation prohibited including Ultra"
        if not _receipt(event, decision, reason):
            decision = "deny"
            reason = "Guard audit receipt unavailable; frozen tool call denied"
        return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                       "permissionDecision": decision,
                                       "permissionDecisionReason": reason}}
    if kind == "SubagentStart":
        _receipt(event, "failure", "SubagentStart is auditable but cannot be blocked by this hook")
        return {}
    if kind in {"SessionStart", "SessionEnd"}:
        _receipt(event, "baseline" if kind == "SessionStart" else "session_end")
        return {}
    _receipt(event, "deny", "unsupported hook event")
    return {}


def main() -> int:
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    try:
        event = json.loads(sys.stdin.read())
        if not isinstance(event, dict):
            raise ValueError("hook input must be an object")
        result = handle(event)
    except Exception as exc:
        result = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                         "permissionDecision": "deny",
                                         "permissionDecisionReason": "Invalid guard input: " + type(exc).__name__}}
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
