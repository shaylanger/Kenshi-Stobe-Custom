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
import argparse
import re
import time
from pathlib import Path
import sys
from datetime import datetime, timezone

ALLOW = {"mcp__frozen__list", "mcp__frozen__read", "mcp__frozen__search", "mcp__frozen__sql"}
FROZEN_ROOT = Path(os.environ.get("CODEX_FROZEN_ROOT", r"C:\KenshiTestRuns\invest\frozen-2026-10-14"))
LOG_ENV = "CODEX_BENCH_GUARD_LOG"
_LOG_OVERRIDE: Path | None = None
_ROOT_OVERRIDE: Path | None = None


def _receipt(event: dict, decision: str, reason: str = "") -> bool:
    path_text = str(_LOG_OVERRIDE) if _LOG_OVERRIDE is not None else os.environ.get(LOG_ENV)
    if not path_text:
        return False
    path = Path(path_text).resolve()
    root = (_ROOT_OVERRIDE or Path(os.environ.get("CODEX_FROZEN_ROOT", str(FROZEN_ROOT)))).resolve()
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


def _input_failure(exc: Exception) -> None:
    """Record input framing failures separately from real hook receipts."""
    path_text = str(_LOG_OVERRIDE) if _LOG_OVERRIDE is not None else os.environ.get(LOG_ENV)
    if not path_text:
        return
    try:
        path = Path(path_text).resolve()
        entry = {"time_utc": datetime.now(timezone.utc).isoformat(),
                 "event": "HookInputError", "error_type": type(exc).__name__}
        for attr, field in (("hook_stage", "stage"), ("hook_bytes_received", "bytes_received"),
                            ("hook_stdin_type", "stdin_type"), ("hook_pipe_available", "pipe_available"),
                            ("hook_errno", "errno"), ("hook_winerror", "winerror")):
            value = getattr(exc, attr, None)
            if value is not None:
                entry[field] = value
        if isinstance(exc, OSError) and exc.winerror is not None:
            entry["winerror"] = exc.winerror
        if os.environ.get("CODEX_GUARD_DEBUG_INPUT") == "1":
            sample = getattr(exc, "hook_sample", b"")
            if isinstance(sample, bytes):
                entry["sample_hex"] = sample[:16].hex()
            entry["parent_pid"] = os.getppid()
            entry["parent_image"] = _parent_image_name()
            entry["hook_input_env_names"] = sorted(
                key for key in os.environ
                if re.search(r"(?i)(CODEX_HOOK|HOOK.*INPUT|INPUT.*HOOK)", key)
            )[:32]
        with path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(entry) + "\n")
    except OSError:
        return


def _parent_image_name() -> str | None:
    if os.name != "nt":
        return None
    try:
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.QueryFullProcessImageNameW.argtypes = (wintypes.HANDLE, wintypes.DWORD,
                                                       wintypes.LPWSTR, wintypes.LPDWORD)
        kernel.QueryFullProcessImageNameW.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
        handle = kernel.OpenProcess(0x1000, False, os.getppid())
        if not handle:
            return None
        try:
            buffer = ctypes.create_unicode_buffer(32768)
            size = wintypes.DWORD(len(buffer))
            if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
                return None
            return Path(buffer.value).name
        finally:
            kernel.CloseHandle(handle)
    except Exception:
        return None


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


def _read_hook_event(limit: int = 1024 * 1024, timeout: float = 3.0) -> dict:
    """Read one complete hook JSON object without requiring stdin EOF."""
    if os.name != "nt":
        raw = sys.stdin.buffer.read1(limit + 1)
        if not raw or len(raw) > limit:
            raise ValueError("hook input missing or too large")
        value = json.loads(raw.decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("hook input must be an object")
        return value

    import ctypes
    import msvcrt
    from ctypes import wintypes

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    peek = kernel.PeekNamedPipe
    peek.argtypes = (wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD,
                     wintypes.LPDWORD, wintypes.LPDWORD, wintypes.LPDWORD)
    peek.restype = wintypes.BOOL
    read_file = kernel.ReadFile
    read_file.argtypes = (wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD,
                          wintypes.LPDWORD, wintypes.LPVOID)
    read_file.restype = wintypes.BOOL
    stage = "get_handle"
    buffer = bytearray()
    available = wintypes.DWORD()
    file_type: int | None = None
    decoder = json.JSONDecoder()
    deadline = time.monotonic() + timeout
    try:
        handle = wintypes.HANDLE(msvcrt.get_osfhandle(sys.stdin.fileno()))
        get_file_type = kernel.GetFileType
        get_file_type.argtypes = (wintypes.HANDLE,)
        get_file_type.restype = wintypes.DWORD
        file_type = int(get_file_type(handle))
        while time.monotonic() < deadline:
            stage = "peek"
            if not peek(handle, None, 0, None, ctypes.byref(available), None):
                raise OSError(ctypes.get_last_error(), "hook stdin is not a readable pipe")
            if available.value:
                stage = "read"
                chunk_size = min(available.value, 65536)
                chunk_buffer = ctypes.create_string_buffer(chunk_size)
                read_count = wintypes.DWORD()
                if not read_file(handle, chunk_buffer, chunk_size, ctypes.byref(read_count), None):
                    raise OSError(ctypes.get_last_error(), "unable to read hook input pipe")
                chunk = chunk_buffer.raw[:read_count.value]
                buffer.extend(chunk)
                if len(buffer) > limit:
                    raise ValueError("hook input too large")
                stage = "decode"
                try:
                    decoded = buffer.decode("utf-8")
                    start = len(decoded) - len(decoded.lstrip())
                    value, end = decoder.raw_decode(decoded, start)
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                if decoded[end:].strip():
                    raise ValueError("trailing data after hook input")
                if not isinstance(value, dict):
                    raise ValueError("hook input must be an object")
                return value
            time.sleep(0.01)
        raise TimeoutError("hook input was not delivered")
    except Exception as exc:
        exc.hook_stage = stage
        exc.hook_bytes_received = len(buffer)
        exc.hook_stdin_type = file_type
        exc.hook_pipe_available = available.value
        exc.hook_errno = getattr(exc, "errno", None)
        exc.hook_winerror = getattr(exc, "winerror", None)
        exc.hook_sample = bytes(buffer)
        raise


def main() -> int:
    global _LOG_OVERRIDE, _ROOT_OVERRIDE
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--frozen-root", type=Path)
    args, _ = parser.parse_known_args()
    _LOG_OVERRIDE = args.log
    _ROOT_OVERRIDE = args.frozen_root
    sys.stdout.reconfigure(encoding="utf-8")
    try:
        # Hook runners keep stdin open for the lifetime of the child process.
        # Consume one complete bounded JSON object, then return immediately.
        event = _read_hook_event()
        result = handle(event)
    except Exception as exc:
        _input_failure(exc)
        sys.stderr.write("codex_guard input failure: " + type(exc).__name__ + "\n")
        result = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                         "permissionDecision": "deny",
                                         "permissionDecisionReason": "Invalid guard input: " + type(exc).__name__}}
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
