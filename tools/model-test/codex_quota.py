#!/usr/bin/env python3
"""Read Codex account rate-limit metadata without creating a thread or model turn.

Snapshots are account-wide. They must not be treated as per-run cost attribution.
The app-server response is reduced to an allowlist before it is returned or stored.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import json
import os
from pathlib import Path
import queue
import re
import hashlib
import math
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from typing import Any

DEFAULT_CODEX = Path(r"C:\Users\Shay\AppData\Local\OpenAI\Codex\bin\e78bad9887fa50cf\codex.exe")
DEFAULT_CODEX_HOME = Path(r"C:\Users\Shay\.codex")
POLL_MIN_SECONDS = 10
POLL_DEFAULT_SECONDS = 30
RPC_TIMEOUT_SECONDS = 15
_SAFE_RATE_FIELDS = {"usedPercent", "windowDurationMins", "resetsAt", "limitId"}
_SAFE_CREDIT_FIELDS = {"balance", "hasCredits", "unlimited"}
_SAFE_PLAN_FIELDS = {"type", "name", "planType"}
_SAFE_ENV_KEYS = {"PATH", "SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "TEMP", "TMP",
                  "APPDATA", "LOCALAPPDATA", "HOMEDRIVE", "HOMEPATH"}
_MCP_ID_RE = re.compile(r"[A-Za-z0-9_.@:-]+\Z")
_PLUGIN_ID_RE = re.compile(r"[A-Za-z0-9_.@:-]+\Z")
_KNOWN_LIMIT_IDS = {"codex", "codex_cli", "primary", "secondary", "weekly", "daily"}
_UNKNOWN_CONFIG_FIELD = re.compile(rb"unknown field `([A-Za-z0-9_]+)`", re.IGNORECASE)
_SAFE_ENV_IDENTIFIER = re.compile(rb"\b(?:CODEX|OPENAI)_[A-Z0-9_]{1,80}\b")
_SAFE_CLI_IDENTIFIER = re.compile(rb"--[A-Za-z][A-Za-z0-9-]{1,60}")
_SAFE_CONFIG_IDENTIFIER = re.compile(rb"\b(?:mcp_servers|plugins|profiles)\.[A-Za-z0-9_.-]{1,100}\b")
_SAFE_TRANSPORT_SCHEME = re.compile(rb"\b(?:stdio|ws|wss|unix|https?)://")
_SAFE_ERROR_WORDS = {"error", "failed", "failure", "fatal", "warning", "could", "not", "find", "home",
                     "directory", "path", "alias", "aliases", "create", "initialize", "initialization",
                     "server", "stdio", "transport", "process", "closed", "before", "response", "unknown",
                     "field", "config", "configuration", "invalid", "unsupported", "missing", "required",
                     "unexpected", "argument", "option", "flag", "expected", "value", "type", "parse",
                     "permission", "denied", "access", "authentication", "credentials", "unable", "start",
                     "network", "socket", "connection", "refused", "timeout", "timed", "out", "disabled",
                     "enabled", "method", "request", "account", "rate", "limits", "initialized", "notifier",
                     "protocol", "version", "handshake", "complete", "in", "mcp", "http", "sse", "websocket",
                     "stdio", "stdio_transport", "listen", "uri", "url", "streamable", "or", "and", "to", "for", "the", "a",
                     "an", "is", "was", "were", "with", "on", "in", "from", "by", "at", "of", "as",
                     "after", "while", "when", "than", "please", "try", "again"}


class AppServerExited(RuntimeError):
    """The app-server closed stdout before replying to a bounded RPC."""


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _process_creation_utc(pid: int) -> str | None:
    """Read only the child process creation timestamp, never its command or environment."""
    if os.name != "nt":
        return None

    class FileTime(ctypes.Structure):
        _fields_ = [("low", ctypes.c_uint32), ("high", ctypes.c_uint32)]

    handle = None
    try:
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        handle = kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return None
        created, exited, kernel_time, user_time = FileTime(), FileTime(), FileTime(), FileTime()
        if not kernel.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited),
                                      ctypes.byref(kernel_time), ctypes.byref(user_time)):
            return None
        ticks = (created.high << 32) | created.low
        instant = dt.datetime(1601, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(microseconds=ticks / 10)
        return instant.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    except (AttributeError, OSError, OverflowError, ValueError):
        return None
    finally:
        if handle:
            try:
                ctypes.WinDLL("kernel32", use_last_error=True).CloseHandle(handle)
            except (AttributeError, OSError):
                pass


def _safe_error_summary(line: str) -> str:
    """Retain only common error vocabulary after removing paths and quoted values."""
    def quote_value(match: re.Match[str]) -> str:
        value = match.group(0)[1:-1].strip().lower()
        scheme = re.fullmatch(r"(stdio|ws|wss|unix|https?)://", value)
        if scheme:
            return f" {scheme.group(1)}_transport "
        return " stdio_transport " if value in {"stdio", "stdio_transport"} else " <redacted-value> "

    scrubbed = re.sub(r"(?i)stdio://", " stdio_transport ", line)
    scrubbed = re.sub(r"(?i)https?://[^\s\"'`]+", " <redacted-url> ", scrubbed)
    scrubbed = re.sub(r"(?i)\b[A-Z]:\\[^\s\"'`]+", " <redacted-path> ", scrubbed)
    scrubbed = re.sub(r"(?<![A-Za-z])/(?:[^\s/]+/)*[^\s]+", " <redacted-path> ", scrubbed)
    scrubbed = re.sub(r"(?i)\b[^\s@]+@[^\s@]+\.[^\s@]+\b", " <redacted-email> ", scrubbed)
    scrubbed = re.sub(r"`[^`]*`|\"[^\"]*\"|'[^']*'", quote_value, scrubbed)
    tokens = re.findall(r"[A-Za-z][A-Za-z_-]{0,23}", scrubbed.lower())
    safe = [token if token in _SAFE_ERROR_WORDS else "<other>" for token in tokens[:40]]
    return " ".join(safe[:24])


def _safe_error_identifiers(data: bytes) -> dict[str, list[str]]:
    """Return only identifier names/schemes; never include assignment values or URLs."""
    def unique(matches: list[bytes]) -> list[str]:
        return sorted({item.decode("ascii", "ignore") for item in matches})[:16]

    schemes = {item.decode("ascii").split(":", 1)[0] + "://"
               for item in _SAFE_TRANSPORT_SCHEME.findall(data)}
    return {
        "environmentNames": unique(_SAFE_ENV_IDENTIFIER.findall(data)),
        "cliFlags": unique(_SAFE_CLI_IDENTIFIER.findall(data)),
        "configFieldNames": unique(_SAFE_CONFIG_IDENTIFIER.findall(data)),
        "transportSchemes": sorted(schemes),
    }


def _safe_scalar(value: Any) -> str | int | float | bool | None:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return None


def _rate_rows(value: Any) -> list[dict[str, Any]]:
    """Extract stable limit/window metadata without retaining unknown identifiers."""
    rows: list[dict[str, Any]] = []
    if isinstance(value, dict):
        # Current schema puts the map at the response root. Each limit has windows.
        by_id = value.get("rateLimitsByLimitId")
        if not isinstance(by_id, dict):
            nested = value.get("rateLimits")
            by_id = nested.get("rateLimitsByLimitId") if isinstance(nested, dict) else None
        if isinstance(by_id, dict):
            for limit_id, bucket in by_id.items():
                raw_id = str(limit_id)
                safe_id = raw_id if raw_id in _KNOWN_LIMIT_IDS else "unknown:" + hashlib.sha256(raw_id.encode("utf-8", "replace")).hexdigest()[:12]
                if isinstance(bucket, dict):
                    windows = [(key, bucket[key]) for key in ("primary", "secondary") if key in bucket]
                    if windows:
                        for window_id, window in windows:
                            row = {"limitId": safe_id, "windowId": window_id}
                            if isinstance(window, dict):
                                for key in _SAFE_RATE_FIELDS - {"limitId"}:
                                    row[key] = _safe_scalar(window.get(key))
                            else:
                                row.update({"usedPercent": None, "windowDurationMins": None, "resetsAt": None})
                            rows.append(row)
                    elif all(key in bucket for key in ("usedPercent", "windowDurationMins", "resetsAt")):
                        # Some protocol versions document a flat bucket representation.
                        row = {"limitId": safe_id, "windowId": "flat"}
                        for key in _SAFE_RATE_FIELDS - {"limitId"}:
                            row[key] = _safe_scalar(bucket.get(key))
                        rows.append(row)
        else:
            # Legacy rateLimits.primary / secondary, including explicit nulls.
            limits = value.get("rateLimits") if isinstance(value.get("rateLimits"), dict) else value
            for key in ("primary", "secondary"):
                bucket = limits.get(key)
                if key in limits:
                    row = {"limitId": key, "windowId": key}
                    if isinstance(bucket, dict):
                        for field in _SAFE_RATE_FIELDS - {"limitId"}:
                            row[field] = _safe_scalar(bucket.get(field))
                    else:
                        row.update({"usedPercent": None, "windowDurationMins": None, "resetsAt": None})
                    rows.append(row)
    return rows


def normalize_snapshot(result: Any) -> dict[str, Any]:
    """Return only approved rate-limit, credit, and plan metadata."""
    result = result if isinstance(result, dict) else {}
    limits = result.get("rateLimits") if isinstance(result.get("rateLimits"), dict) else result
    buckets = _rate_rows(result)
    credits = result.get("credits", limits.get("credits"))
    plan = result.get("plan", result.get("planType", limits.get("planType", limits.get("plan"))))
    safe_credits = ({key: _safe_scalar(credits.get(key)) for key in _SAFE_CREDIT_FIELDS if key in credits}
                    if isinstance(credits, dict) else None)
    safe_plan = ({key: _safe_scalar(plan.get(key)) for key in _SAFE_PLAN_FIELDS if key in plan}
                 if isinstance(plan, dict) else _safe_scalar(plan))
    weekly_candidates = [row for row in buckets if row.get("windowDurationMins") == 10080]
    known_codex_weekly = next((row for wanted in ("codex", "codex_cli")
                               for row in weekly_candidates if row.get("limitId") == wanted), None)
    if known_codex_weekly is not None:
        weekly = known_codex_weekly
        weekly_selection = "known_codex_limit"
    elif len(weekly_candidates) == 1:
        weekly = weekly_candidates[0]
        weekly_selection = "single_weekly_window"
    elif weekly_candidates:
        weekly = None
        weekly_selection = "ambiguous_weekly_windows"
    else:
        weekly = None
        weekly_selection = "weekly_window_missing"
    used = weekly.get("usedPercent") if weekly else None
    reset = weekly.get("resetsAt") if weekly else None
    window_mins = weekly.get("windowDurationMins") if weekly else None
    fresh_weekly = (isinstance(used, (int, float)) and not isinstance(used, bool)
                    and math.isfinite(used) and 0 <= used <= 100
                    and isinstance(window_mins, int) and not isinstance(window_mins, bool)
                    and window_mins == 10080
                    and isinstance(reset, int) and not isinstance(reset, bool) and reset > 0) if weekly else False
    now = _utc_now()
    return {"sample_id": uuid.uuid4().hex, "sampled_at_utc": now,
            "observedAt": now, "status": "ok" if fresh_weekly else "unknown",
            "freshness": "fresh" if fresh_weekly else "unknown",
            "buckets": buckets, "windows": buckets, "weekly": weekly,
            "weeklySelection": weekly_selection,
            "credits": safe_credits, "plan": safe_plan,
            "scope": "account-wide", "perRunAttribution": "unavailable"}


def _quoted_dotted_key(key: str) -> str:
    """Return a simple dotted override key; nested/quoted IDs are unsupported."""
    if not _MCP_ID_RE.fullmatch(key) or "." in key:
        raise ValueError("unsupported Codex config identifier")
    return key


def effective_config_overrides(codex_home: Path = DEFAULT_CODEX_HOME) -> tuple[list[str], list[str], list[str]]:
    """Read section headers only and build per-process MCP/plugin disable overrides.

    Values, including MCP environment values and account credentials, are never parsed,
    returned, or printed. Profile layers are rejected until their effective merge order
    is explicitly supported.
    """
    config = codex_home / "config.toml"
    mcp_names: set[str] = set()
    plugin_names: set[str] = set()
    try:
        with config.open("r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line.startswith("["):
                    # Reject any selector key without inspecting or retaining its value.
                    if "=" in line and line.partition("=")[0].strip() == "profile":
                        raise ValueError("Codex profile selector detected; effective profile is unverified")
                    continue
                if line.startswith("[["):
                    if line.startswith("[[mcp_servers") or line.startswith("[[plugins") or line.startswith("[[profiles"):
                        raise ValueError("unsupported array-table header in Codex config")
                    continue
                match = re.fullmatch(r"\[([^\]]+)\]\s*(?:#.*)?", line)
                if not match:
                    if line.startswith(("[mcp_servers", "[plugins", "[profiles", "[profile")):
                        raise ValueError("ambiguous Codex config section header")
                    continue
                section = match.group(1).strip()
                if section == "profiles" or section.startswith("profiles.") or section == "profile" or section.startswith("profile."):
                    raise ValueError("Codex profile layer detected; effective profile is unverified")
                if section == "mcp_servers" or section.startswith("mcp_servers."):
                    server_match = re.fullmatch(r'mcp_servers\.([A-Za-z0-9_-]+)(?:\.env)?', section)
                    quoted_match = re.fullmatch(r'mcp_servers\."([^"\\]+)"(?:\.env)?', section)
                    found = server_match or quoted_match
                    if not found or not _MCP_ID_RE.fullmatch(found.group(1)):
                        raise ValueError("unsupported or ambiguous MCP config header")
                    if not section.endswith(".env"):
                        mcp_names.add(found.group(1))
                elif section == "plugins" or section.startswith("plugins."):
                    plugin_match = re.fullmatch(r'plugins\."([^"\\]+)"', section)
                    if not plugin_match or not _PLUGIN_ID_RE.fullmatch(plugin_match.group(1)):
                        raise ValueError("unsupported or ambiguous plugin config header")
                    plugin_names.add(plugin_match.group(1))
    except OSError as exc:
        raise RuntimeError("canonical Codex config headers unavailable") from exc

    overrides = [f"mcp_servers.{_quoted_dotted_key(name)}.enabled=false" for name in sorted(mcp_names)]
    overrides.extend(f"plugins.{_quoted_dotted_key(name)}.enabled=false" for name in sorted(plugin_names))
    return sorted(mcp_names), sorted(plugin_names), overrides


def _telemetry_environment(source: dict[str, str] | None = None,
                           codex_home: Path = DEFAULT_CODEX_HOME) -> dict[str, str]:
    """Construct an allowlisted child environment without copying credential variables."""
    keys = set(source) if source is not None else set(os.environ)
    if "CODEX_PROFILE" in keys:
        raise RuntimeError("CODEX_PROFILE environment selection is unsupported; effective profile is unverified")
    safe: dict[str, str] = {}
    for key in _SAFE_ENV_KEYS & keys:
        # Only allowlisted OS/runtime path values are read; credential-like variables are untouched.
        value = source[key] if source is not None else os.environ[key]
        safe[key] = value
    profile_root = str(codex_home.parent)
    safe["USERPROFILE"] = profile_root
    safe["HOME"] = profile_root
    safe["CODEX_HOME"] = str(codex_home)
    return safe


def build_appserver_argv(cli: Path = DEFAULT_CODEX,
                         codex_home: Path = DEFAULT_CODEX_HOME) -> tuple[list[str], list[str], list[str]]:
    """Build exact app-server argv and return discovered config header names."""
    mcp_names, plugin_names, overrides = effective_config_overrides(codex_home)
    argv = [str(cli), "app-server", "--listen", "stdio://", "--strict-config"]
    for override in overrides:
        argv.extend(("-c", override))
    return argv, mcp_names, plugin_names


class QuotaSampler:
    """Persistent account-only app-server connection shared by one batch observer."""

    def __init__(self, cli: Path = DEFAULT_CODEX, runtime_dir: Path | None = None,
                 interval: int = POLL_DEFAULT_SECONDS, cwd: Path | None = None,
                 env: dict[str, str] | None = None, timeout: float = RPC_TIMEOUT_SECONDS,
                 codex_home: Path = DEFAULT_CODEX_HOME) -> None:
        self.cli, self.runtime_dir, self.interval = Path(cli), runtime_dir, interval
        self.cwd, self.env, self.timeout, self.codex_home = cwd, env, timeout, Path(codex_home)
        self.proc: subprocess.Popen[str] | None = None
        self.output: queue.Queue[str | None] = queue.Queue()
        self.counter = 1
        self._tmp: tempfile.TemporaryDirectory[str] | None = None
        self._reader: threading.Thread | None = None
        self.previous_reset: Any = None
        self._lock_path: Path | None = None
        self._lock_token: str | None = None
        self.phase = "startup"
        self.spawned_monotonic: float | None = None
        self.child_pid: int | None = None
        self.child_created_utc: str | None = None
        self.child_exit_code: int | None = None
        self.rpc_error_code: int | None = None
        self.stderr_bytes = 0
        self.stderr_digest = hashlib.sha256()
        self.stderr_categories: set[str] = set()
        self.stderr_safe_summary: list[str] = []
        self.stderr_safe_identifiers: dict[str, set[str]] = {
            "environmentNames": set(), "cliFlags": set(),
            "configFieldNames": set(), "transportSchemes": set(),
        }
        self.unknown_config_fields: set[str] = set()
        self._stderr_thread: threading.Thread | None = None
        self._diagnostic_lock = threading.Lock()

    def _diagnostics(self) -> dict[str, Any]:
        proc = self.proc
        if proc is not None:
            code = proc.poll()
            if code is not None:
                self.child_exit_code = code
        if self._stderr_thread is not None and self.child_exit_code is not None:
            self._stderr_thread.join(timeout=0.25)
        with self._diagnostic_lock:
            stderr_hash = self.stderr_digest.hexdigest()
            categories = sorted(self.stderr_categories)
            unknown_fields = sorted(self.unknown_config_fields)
            stderr_bytes = self.stderr_bytes
            stderr_summary = self.stderr_safe_summary[:8]
            safe_identifiers = {key: sorted(values)[:16]
                                for key, values in self.stderr_safe_identifiers.items()}
        elapsed = (time.monotonic() - self.spawned_monotonic) if self.spawned_monotonic is not None else None
        return {"phase": self.phase, "childPid": self.child_pid,
                "childCreatedAtUtc": self.child_created_utc,
                "childExitCode": self.child_exit_code,
                "childElapsedSeconds": round(elapsed, 3) if elapsed is not None else None,
                "stderrByteCount": stderr_bytes, "stderrSha256": stderr_hash,
                "stderrCategories": categories, "stderrSafeSummary": stderr_summary,
                "stderrSafeIdentifiers": safe_identifiers,
                "unknownConfigFieldNames": unknown_fields}

    def _unknown(self, reason: str, *, rpc_error_code: int | None = None) -> dict[str, Any]:
        now = _utc_now()
        return {"sample_id": uuid.uuid4().hex, "sampled_at_utc": now,
                "observedAt": now, "status": "unknown", "reason": reason,
                "freshness": "unknown",
                "buckets": [], "windows": [], "weekly": None, "credits": None, "plan": None,
                "scope": "account-wide", "perRunAttribution": "unavailable",
                "rpcErrorCode": rpc_error_code if rpc_error_code is not None else self.rpc_error_code,
                "diagnostics": self._diagnostics()}

    def start(self) -> "QuotaSampler":
        if self.proc is not None:
            return self
        if not self.cli.is_file():
            raise FileNotFoundError("pinned Codex CLI is unavailable")
        if self.runtime_dir is not None:
            self.runtime_dir.mkdir(parents=True, exist_ok=True)
            self._lock_path = self.runtime_dir / "quota-sampler.lock"
            self._lock_token = uuid.uuid4().hex
            try:
                lock_fd = os.open(self._lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            except FileExistsError as exc:
                self._lock_path = None
                self._lock_token = None
                raise RuntimeError("quota sampler lock exists, possibly stale; verify owner before cleanup") from exc
            with os.fdopen(lock_fd, "w", encoding="utf-8") as handle:
                json.dump({"pid": os.getpid(), "createdAt": _utc_now(), "token": self._lock_token}, handle)
        self._tmp = tempfile.TemporaryDirectory(prefix="codex-quota-") if self.cwd is None else None
        cwd = self.cwd if self.cwd is not None else Path(self._tmp.name)
        # Neutral cwd and strict config avoid project-level instructions/MCP discovery.
        try:
            argv, self.mcp_headers, self.plugin_headers = build_appserver_argv(self.cli, self.codex_home)
            child_env = _telemetry_environment(self.env, self.codex_home)
        except Exception:
            self.stop()
            raise
        try:
            self.proc = subprocess.Popen(argv,
                                         cwd=str(cwd), env=child_env,
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, text=True, encoding="utf-8",
                                         errors="replace", bufsize=1)
        except OSError:
            self.stop()
            raise
        self.spawned_monotonic = time.monotonic()
        self.child_pid = self.proc.pid
        self.child_created_utc = _process_creation_utc(self.proc.pid)

        def pump() -> None:
            assert self.proc is not None and self.proc.stdout is not None
            for line in self.proc.stdout:
                self.output.put(line)
            self.output.put(None)

        def pump_stderr() -> None:
            assert self.proc is not None and self.proc.stderr is not None
            for line in self.proc.stderr:
                data = line.encode("utf-8", "replace")
                with self._diagnostic_lock:
                    self.stderr_bytes += len(data)
                    self.stderr_digest.update(data)
                    lowered = data.lower()
                    line_categories: set[str] = set()
                    safe_summary = _safe_error_summary(line)
                    safe_identifiers = _safe_error_identifiers(data)
                    for key, values in safe_identifiers.items():
                        self.stderr_safe_identifiers[key].update(values)
                    fields = _UNKNOWN_CONFIG_FIELD.findall(data)
                    for field in fields[:32]:
                        self.unknown_config_fields.add(field.decode("ascii"))
                    if fields:
                        line_categories.add("unknown_config_field")
                    if b"error loading config" in lowered:
                        line_categories.add("config_load_error")
                    if b"could not find home directory" in lowered:
                        line_categories.add("home_directory_unavailable")
                    if b"path aliases" in lowered and b"could not create" in lowered:
                        line_categories.add("path_alias_initialization_warning")
                    if b"permission denied" in lowered or b"access is denied" in lowered:
                        line_categories.add("access_denied")
                    if b"no such file" in lowered or b"cannot find the path" in lowered:
                        line_categories.add("file_not_found")
                    if b"invalid config" in lowered or b"config.toml" in lowered:
                        line_categories.add("config_validation_error")
                    if b"failed to initialize" in lowered or b"initialization failed" in lowered:
                        line_categories.add("initialization_error")
                    if b"panic" in lowered:
                        line_categories.add("runtime_panic")
                    if b"unknown field" in lowered and not fields:
                        line_categories.add("unknown_config_field_format_unrecognized")
                    if {"path_alias_initialization_warning", "access_denied"}.issubset(line_categories):
                        line_categories.add("path_alias_creation_access_denied")
                    if lowered.lstrip().startswith((b"error:", b"error ")) and not line_categories:
                        line_categories.add("error_prefix_unclassified")
                    if data.strip() and not line_categories:
                        line_categories.add("other_stderr")
                    self.stderr_categories.update(line_categories)
                    if safe_summary and safe_summary not in self.stderr_safe_summary and len(self.stderr_safe_summary) < 8:
                        self.stderr_safe_summary.append(safe_summary)

        self._reader = threading.Thread(target=pump, daemon=True)
        self._reader.start()
        self._stderr_thread = threading.Thread(target=pump_stderr, daemon=True)
        self._stderr_thread.start()
        self.phase = "initialize"
        self._send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"clientInfo": {"name": "codex-quota-observer", "version": "1"},
                               "capabilities": {"experimentalApi": True}}})
        try:
            init = self._response(1, time.monotonic() + self.timeout)
            if "error" in init:
                error = init.get("error")
                self.rpc_error_code = error.get("code") if isinstance(error, dict) and isinstance(error.get("code"), int) else None
                raise RuntimeError("app-server initialize failed")
        except Exception:
            self.stop()
            raise
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        self.phase = "initialized"
        return self

    def _send(self, payload: dict[str, Any]) -> None:
        if not self.proc or not self.proc.stdin:
            raise OSError("app-server is not running")
        self.proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def _response(self, request_id: int, deadline: float) -> dict[str, Any]:
        while time.monotonic() < deadline:
            try:
                line = self.output.get(timeout=max(0.05, deadline - time.monotonic()))
            except queue.Empty:
                break
            if line is None:
                if self.proc is not None:
                    try:
                        self.proc.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
                    self.child_exit_code = self.proc.poll()
                raise AppServerExited("app-server stdout closed before response")
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(msg, dict) and msg.get("id") == request_id:
                return msg
        raise TimeoutError

    def snapshot(self) -> dict[str, Any]:
        try:
            if self.proc is None:
                self.start()
            self.counter += 1
            request_id = self.counter
            self.phase = "account_read"
            self._send({"jsonrpc": "2.0", "id": request_id,
                        "method": "account/rateLimits/read", "params": {}})
            reply = self._response(request_id, time.monotonic() + self.timeout)
            if "error" in reply:
                error = reply.get("error")
                code = error.get("code") if isinstance(error, dict) and isinstance(error.get("code"), int) else None
                return self._unknown("rpc_error", rpc_error_code=code)
            result = normalize_snapshot(reply.get("result"))
            reset = result.get("weekly", {}).get("resetsAt") if result.get("weekly") else None
            result["weeklyResetChanged"] = (self.previous_reset is not None and reset != self.previous_reset)
            result["deltaAcrossReset"] = None
            result["diagnostics"] = self._diagnostics()
            self.previous_reset = reset
            return result
        except AppServerExited:
            return self._unknown("process_exited_before_response")
        except TimeoutError:
            return self._unknown("rpc_timeout")
        except (OSError, RuntimeError, FileNotFoundError):
            return self._unknown("rpc_unavailable")

    def stop(self) -> None:
        proc, self.proc = self.proc, None
        if proc is not None:
            self.child_exit_code = proc.poll()
            try:
                if self.child_exit_code is None:
                    if proc.stdin:
                        proc.stdin.close()
                    proc.terminate()
                    proc.wait(timeout=2)
            except (OSError, subprocess.TimeoutExpired):
                proc.kill()
                proc.wait(timeout=2)
            self.child_exit_code = proc.poll()
            if self._stderr_thread is not None:
                self._stderr_thread.join(timeout=0.5)
        if self._tmp is not None:
            self._tmp.cleanup()
            self._tmp = None
        if self._lock_path is not None and self._lock_token is not None:
            try:
                lock = json.loads(self._lock_path.read_text(encoding="utf-8"))
                if lock.get("pid") == os.getpid() and lock.get("token") == self._lock_token:
                    self._lock_path.unlink()
            except (OSError, json.JSONDecodeError):
                pass
            self._lock_path = None
            self._lock_token = None


def read_snapshot(codex: Path = DEFAULT_CODEX, timeout: float = RPC_TIMEOUT_SECONDS) -> dict[str, Any]:
    """Read one account-wide quota snapshot through the pinned app-server."""
    sampler = QuotaSampler(codex, timeout=timeout)
    try:
        return sampler.snapshot()
    finally:
        sampler.stop()


def startup_diagnostic(codex: Path = DEFAULT_CODEX, codex_home: Path = DEFAULT_CODEX_HOME) -> dict[str, Any]:
    """Initialize the local app-server and stop without sending any account RPC."""
    sampler = QuotaSampler(codex, codex_home=codex_home)
    try:
        sampler.start()
        return {"status": "initialized", "diagnostics": sampler._diagnostics(),
                "mcpHeadersDisabled": sampler.mcp_headers,
                "pluginHeadersDisabled": sampler.plugin_headers,
                "rpcMethodsSent": ["initialize", "notifications/initialized"]}
    except AppServerExited:
        return {"status": "unknown", "reason": "process_exited_before_initialize_response",
                "diagnostics": sampler._diagnostics(),
                "mcpHeadersDisabled": getattr(sampler, "mcp_headers", []),
                "pluginHeadersDisabled": getattr(sampler, "plugin_headers", []),
                "rpcMethodsSent": ["initialize"]}
    except TimeoutError:
        return {"status": "unknown", "reason": "initialize_timeout",
                "diagnostics": sampler._diagnostics(),
                "mcpHeadersDisabled": getattr(sampler, "mcp_headers", []),
                "pluginHeadersDisabled": getattr(sampler, "plugin_headers", []),
                "rpcMethodsSent": ["initialize"]}
    except (OSError, RuntimeError, ValueError):
        return {"status": "unknown", "reason": "startup_failed",
                "diagnostics": sampler._diagnostics(),
                "mcpHeadersDisabled": getattr(sampler, "mcp_headers", []),
                "pluginHeadersDisabled": getattr(sampler, "plugin_headers", []),
                "rpcMethodsSent": []}
    finally:
        sampler.stop()


def watch(out: Path, interval: int, codex: Path) -> int:
    """Bounded single-owner sampler; one process per output directory."""
    out.mkdir(parents=True, exist_ok=True)
    lock = out / "quota-observer.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        print("quota observer already owns this output directory", file=sys.stderr)
        return 2
    identity = {"pid": os.getpid(), "createdAt": _utc_now()}
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(identity, handle)
    history = out / "quota-snapshots.jsonl"
    try:
        sampler = QuotaSampler(codex, runtime_dir=out, interval=interval).start()
        while True:
            snapshot = sampler.snapshot()
            line = json.dumps(snapshot, separators=(",", ":"), ensure_ascii=True)
            tmp = out / "quota-snapshot.json.tmp"
            tmp.write_text(line + "\n", encoding="utf-8")
            os.replace(tmp, out / "quota-snapshot.json")
            with history.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
            print(f"QUOTA {snapshot['status']} {snapshot.get('weekly')}", flush=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        return 0
    finally:
        if "sampler" in locals():
            sampler.stop()
        try:
            if json.loads(lock.read_text(encoding="utf-8")) == identity:
                lock.unlink()
        except (OSError, json.JSONDecodeError):
            pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    snap = sub.add_parser("snapshot", help="read one account-wide quota snapshot")
    snap.add_argument("--codex", type=Path, default=DEFAULT_CODEX)
    startup = sub.add_parser("diagnose-start", help="initialize app-server without an account read")
    startup.add_argument("--codex", type=Path, default=DEFAULT_CODEX)
    watch_parser = sub.add_parser("watch", help="sample account quota metadata until stopped")
    watch_parser.add_argument("--codex", type=Path, default=DEFAULT_CODEX)
    watch_parser.add_argument("--out", type=Path, required=True)
    watch_parser.add_argument("--interval", type=int, default=POLL_DEFAULT_SECONDS)
    args = parser.parse_args(argv)
    if args.command == "snapshot":
        snapshot = read_snapshot(args.codex)
        print(json.dumps(snapshot, indent=2, ensure_ascii=True))
        return 0 if snapshot.get("status") == "ok" else 2
    if args.command == "diagnose-start":
        result = startup_diagnostic(args.codex)
        print(json.dumps(result, indent=2, ensure_ascii=True))
        return 0 if result.get("status") == "initialized" else 2
    if args.interval < POLL_MIN_SECONDS:
        parser.error(f"--interval must be at least {POLL_MIN_SECONDS} seconds")
    return watch(args.out, args.interval, args.codex)


if __name__ == "__main__":
    raise SystemExit(main())
