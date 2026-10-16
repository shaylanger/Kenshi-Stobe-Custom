#!/usr/bin/env python3
"""Prepare and explicitly launch isolated Codex benchmark cells.

Preparation and preflight are offline/read-only. Model execution is possible
only through ``run ... --execute``. No model calls are made by this module at
import time or by the other commands.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_CODEX = Path(r"C:\Users\Shay\AppData\Local\OpenAI\Codex\bin\e78bad9887fa50cf\codex.exe")
DEFAULT_USER_CODEX = Path(r"C:\Users\Shay\.codex")
DEFAULT_FROZEN = Path(r"C:\KenshiTestRuns\invest\frozen-2026-10-14")
MAX_CONCURRENCY = 4
SAFE_ENV = ("PATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "USERPROFILE", "LOCALAPPDATA",
            "APPDATA", "PROGRAMFILES", "PROGRAMFILES(X86)")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*-p[0-9]+$")
LEDGER_MUTEX = threading.Lock()
ACTIVE_LOCK = threading.Lock()
ACTIVE_PROCESSES: set[subprocess.Popen] = set()


class BenchError(RuntimeError):
    pass


def _json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BenchError(f"cannot read {path.name}: {exc}") from exc
    if not isinstance(value, dict):
        raise BenchError(f"{path.name} must contain an object")
    return value


def suite_root(value: str | Path) -> Path:
    root = Path(value).expanduser().resolve()
    if not (root / "suite.json").is_file():
        raise BenchError(f"suite.json not found in {root}")
    return root


def load_suite(root: Path) -> dict[str, Any]:
    cfg = _json(root / "suite.json")
    cells = cfg.get("cells")
    if not isinstance(cells, list) or not cells:
        raise BenchError("suite.json cells must be a non-empty ordered array")
    nums = cfg.get("prompt_numbers", [2, 3])
    prompts = cfg.get("prompts", ["prompt2.txt", "prompt3.txt"])
    if not isinstance(nums, list) or len(nums) != len(prompts) or not all(type(n) is int and n > 0 for n in nums):
        raise BenchError("prompt_numbers must be positive integers matching prompts")
    seen = set()
    for cell in cells:
        if not isinstance(cell, dict) or not all(isinstance(cell.get(k), str) and cell[k] for k in ("slug", "model", "effort", "speed")):
            raise BenchError("each cell requires non-empty slug, model, effort, and speed")
        if cell["speed"] not in ("standard", "fast"):
            raise BenchError(f"unsupported speed tier: {cell['speed']}")
        if cell["slug"] in seen:
            raise BenchError(f"duplicate cell slug: {cell['slug']}")
        seen.add(cell["slug"])
    return cfg


def run_ids(root: Path, cfg: dict[str, Any]) -> list[tuple[str, dict[str, Any], int, str]]:
    nums = cfg.get("prompt_numbers", [2, 3])
    prompts = cfg.get("prompts", ["prompt2.txt", "prompt3.txt"])
    out = []
    for cell in cfg["cells"]:
        for num, name in zip(nums, prompts):
            rid = f"{cell['slug']}-p{num}"
            if not ID_RE.fullmatch(rid):
                raise BenchError(f"unsafe run id: {rid}")
            path = (root / name).resolve()
            if path.parent != root.resolve() or not path.is_file():
                raise BenchError(f"prompt must be an existing file in suite root: {name}")
            out.append((rid, cell, num, name))
    return out


def resolve_launch_mode(root: Path, mode: str | None, cli_value: int | None) -> tuple[str, int]:
    cfg = _json(root / "suite.json")
    policy = cfg.get("concurrency", {})
    configured = policy.get("default", 1) if isinstance(policy, dict) else policy
    hard_cap = policy.get("hard_cap", MAX_CONCURRENCY) if isinstance(policy, dict) else MAX_CONCURRENCY
    if type(hard_cap) is not int or not 1 <= hard_cap <= MAX_CONCURRENCY:
        raise BenchError(f"concurrency hard_cap must be 1..{MAX_CONCURRENCY}")
    if mode not in (None, "sequential", "limited-concurrent"):
        raise BenchError("mode must be sequential or limited-concurrent")
    if mode is None:
        mode = "limited-concurrent" if cli_value is not None and cli_value > 1 else "sequential"
    if mode == "sequential":
        if cli_value is not None and cli_value != 1:
            raise BenchError("sequential mode cannot be combined with --concurrency greater than 1")
        return mode, 1
    default_cap = policy.get("limited_concurrency", 2) if isinstance(policy, dict) else 2
    cap = cli_value if cli_value is not None else default_cap
    if type(cap) is not int or not 1 <= cap <= hard_cap:
        raise BenchError(f"limited-concurrent concurrency must be 1..{hard_cap}")
    return mode, cap


def concurrency(root: Path, cli_value: int | None) -> int:
    """Legacy concurrency resolver retained for prepare/preflight validation."""
    cfg = _json(root / "suite.json")
    policy = cfg.get("concurrency", {})
    configured = policy.get("default", 1) if isinstance(policy, dict) else policy
    hard_cap = policy.get("hard_cap", MAX_CONCURRENCY) if isinstance(policy, dict) else MAX_CONCURRENCY
    n = cli_value if cli_value is not None else configured
    if type(hard_cap) is not int or not 1 <= hard_cap <= MAX_CONCURRENCY or type(n) is not int or not 1 <= n <= hard_cap:
        raise BenchError(f"concurrency must be 1..{hard_cap}")
    return n


def launch_many(ids: list[str], mode: str, cap: int, worker, stop_requested=None,
                paused_boundaries: list[dict[str, Any]] | None = None) -> int:
    """Run a batch in the selected scheduling mode; worker is injected for offline tests."""
    failures = 0
    should_stop = stop_requested or (lambda: False)
    if mode == "sequential":
        completed: list[str] = []
        for index, rid in enumerate(ids):
            if should_stop():
                if paused_boundaries is not None:
                    paused_boundaries.append({"after_run": completed[-1] if completed else None,
                                              "next_run": rid})
                print(f"DISPATCH PAUSED before {rid}")
                break
            try:
                failed = bool(worker(rid))
                failures += failed
            except Exception as exc:
                print(f"run failed: {exc}", file=sys.stderr)
                failures += 1
                failed = True
            if failed:
                break
            completed.append(rid)
            if should_stop():
                next_run = ids[index + 1] if index + 1 < len(ids) else None
                if paused_boundaries is not None:
                    paused_boundaries.append({"after_run": rid, "next_run": next_run})
                print(f"DISPATCH PAUSED after {rid}; next={next_run or 'none'}")
                break
    else:
        if should_stop():
            if paused_boundaries is not None:
                paused_boundaries.append({"after_run": None, "next_run": ids[0] if ids else None})
            print(f"DISPATCH PAUSED before {ids[0] if ids else 'first run'}")
            return 0
        from concurrent.futures import ThreadPoolExecutor, as_completed
        with ThreadPoolExecutor(max_workers=cap) as pool:
            futures = [pool.submit(worker, rid) for rid in ids]
            for future in as_completed(futures):
                try: failures += bool(future.result())
                except Exception as exc:
                    print(f"run failed: {exc}", file=sys.stderr); failures += 1
    return int(failures > 0)


def pending_run_ids(root: Path, entries: list[tuple[str, dict[str, Any], int, str]]) -> list[str]:
    """Skip only audited PASS completions; stop before dispatch on any other terminal state."""
    ledger = root / "runs.tsv"
    recorded = set()
    if ledger.is_file():
        with ledger.open("r", encoding="utf-8", newline="") as stream:
            recorded = {row.get("run", "") for row in csv.DictReader(stream, delimiter="\t")}
    pending: list[str] = []
    for rid, _cell, _number, _prompt in entries:
        run_dir = root / "runs" / rid
        receipt_path = _record_path(run_dir)
        if not receipt_path.is_file():
            raise BenchError(f"run receipt missing before dispatch: {rid}")
        receipt = _json(receipt_path)
        if receipt.get("status") == "PREPARED":
            pending.append(rid)
            continue
        attempt_no = int(receipt.get("attempt", 1))
        attempt = run_dir / f"attempt-{attempt_no:02d}"
        attempt_receipt = _json(attempt / "launch.json")
        completed = (receipt.get("status") in {"RECORDED", "RECHECKED"} and
                     receipt.get("audit", {}).get("status") == "PASS" and
                     attempt_receipt.get("audit", {}).get("status") == "PASS" and
                     attempt_receipt.get("verified_receipt") is True and
                     (run_dir / "report.md").is_file() and rid in recorded)
        if completed:
            continue
        audit_status = receipt.get("audit", {}).get("status", "UNKNOWN")
        raise BenchError(f"{rid} is not an audited PASS completion (status={receipt.get('status')}, audit={audit_status}); inspect or explicitly retry before continuing")
    return pending


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _fast_tier_supported(model: dict[str, Any]) -> bool:
    tiers = model.get("service_tiers") or []
    if isinstance(tiers, dict):
        ids = set(tiers)
    elif isinstance(tiers, list):
        ids = {item if isinstance(item, str) else item.get("id")
               for item in tiers if isinstance(item, (str, dict))}
    else:
        ids = set()
    return bool(model.get("supports_fast", model.get("fast", False)) or "priority" in ids)


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + f".{os.getpid()}.{threading.get_ident()}.tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temp, path)


ATTEMPT_COLUMNS = ["run", "attempt", "status", "model", "effort", "service_tier", "start_local", "end_local",
                   "wall_s", "tool_uses", "input", "output", "cache_read", "cache_create", "token_usd",
                   "report_bytes", "violation_flags", "thread_id", "rollout_path", "events_path", "stderr_path"]


def _append_attempt_row(root: Path, rid: str, receipt: dict[str, Any], result: dict[str, Any] | None) -> None:
    path = root / "attempts.tsv"
    attempt_id = int(receipt.get("attempt", 1))
    usage = (result or {}).get("usage") or {}
    pricing = (result or {}).get("pricing") or {}
    audit = (result or {}).get("audit") or {}
    row = {
        "run": rid, "attempt": attempt_id, "status": receipt.get("status", "UNKNOWN"),
        "model": receipt.get("model", ""), "effort": receipt.get("effort", ""),
        "service_tier": receipt.get("service_tier", ""),
        "start_local": (result or {}).get("start_local", ""), "end_local": (result or {}).get("end_local", ""),
        "wall_s": (result or {}).get("wall_s", receipt.get("elapsed_s", "")),
        "tool_uses": (result or {}).get("tool_uses", ""), "input": usage.get("input_tokens", ""),
        "output": usage.get("output_tokens", ""), "cache_read": usage.get("cached_input_tokens", ""),
        "cache_create": usage.get("cache_write_input_tokens", ""), "token_usd": pricing.get("usd", ""),
        "report_bytes": len(((result or {}).get("report") or "").encode()),
        "violation_flags": ",".join(audit.get("flags", [])) or audit.get("status", "UNKNOWN"),
        "thread_id": receipt.get("thread_id", ""), "rollout_path": receipt.get("rollout_path", ""),
        "events_path": receipt.get("events_path", ""), "stderr_path": receipt.get("stderr_path", ""),
    }
    with LEDGER_MUTEX:
        exists = path.exists() and path.stat().st_size > 0
        if exists:
            with path.open("r", encoding="utf-8", newline="") as f:
                rows = list(csv.DictReader(f, delimiter="\t"))
            if any(r.get("run") == rid and r.get("attempt") == str(attempt_id) for r in rows): return
        with path.open("a", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=ATTEMPT_COLUMNS, delimiter="\t", extrasaction="ignore")
            if not exists: writer.writeheader()
            writer.writerow(row)


def _jsonl(path: Path) -> list[dict[str, Any]]:
    events = []
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                value = json.loads(line)
                if isinstance(value, dict): events.append(value)
            except json.JSONDecodeError:
                continue
    return events


def _thread_id(events: list[dict[str, Any]]) -> str | None:
    for event in events:
        for item in (event, event.get("payload", {}) if isinstance(event.get("payload"), dict) else {}):
            if item.get("type") in {"thread.started", "thread_started"}:
                value = item.get("thread_id") or item.get("id")
                if isinstance(value, str): return value
    return None


def _rollout_id(path: Path) -> str | None:
    for event in _jsonl(path):
        payload = event.get("payload", {}) if isinstance(event.get("payload"), dict) else {}
        if event.get("type") in {"session_meta", "session.started", "thread.started"}:
            for item in (event, payload):
                value = item.get("thread_id") or item.get("session_id") or item.get("id")
                if isinstance(value, str): return value
        for item in (event, payload):
            if item.get("type") in {"session_meta", "session.started", "thread.started"}:
                value = item.get("thread_id") or item.get("session_id") or item.get("id")
                if isinstance(value, str): return value
    return None


def _terminate_process(proc: subprocess.Popen) -> None:
    if proc.poll() is not None: return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True, check=False)
    else:
        import os as _os
        import signal as _signal
        try: _os.killpg(proc.pid, _signal.SIGKILL)
        except ProcessLookupError: pass


def _refresh_live_receipt(receipt: dict[str, Any], root_path: Path, attempt_path: Path,
                          event_path: Path, codex_home: Path) -> None:
    try: events = _jsonl(event_path)
    except OSError: return
    tid = _thread_id(events)
    if not tid: return
    sessions = codex_home / "sessions"
    if not sessions.is_dir(): return
    matches = [p for p in sessions.rglob("*.jsonl") if p.is_file() and _rollout_id(p) == tid]
    if len(matches) == 1:
        receipt["thread_id"] = tid
        receipt["rollout_path"] = str(matches[0])
        _write_json(root_path, receipt)
        _write_json(attempt_path, receipt)


def _private_env(home: Path, extra: dict[str, str] | None = None) -> dict[str, str]:
    env = {k: os.environ[k] for k in SAFE_ENV if k in os.environ}
    # Codex on Windows requires HOME as well as its explicit profile directory.
    env["HOME"] = str(home)
    env["CODEX_HOME"] = str(home / ".codex")
    env["CODEX_FROZEN_ROOT"] = str(DEFAULT_FROZEN)
    env["CODEX_FROZEN_RECEIPTS"] = str(home / "frozen-mcp-receipts.jsonl")
    if extra:
        env.update(extra)
    return env


def _strict_exec_config_probe(cli: Path, env: dict[str, str], cwd: Path) -> None:
    """Ask the installed exec parser to validate config, then stop at empty stdin."""
    result = subprocess.run([str(cli), "exec", "--strict-config", "--json", "--sandbox", "read-only",
                             "--cd", str(cwd), "--skip-git-repo-check"],
                            env=env, input="", capture_output=True, text=True, timeout=30, check=False)
    output = (result.stdout or "") + (result.stderr or "")
    if "Error loading config.toml" in output or "unknown configuration field" in output:
        raise BenchError("strict Codex exec config validation failed: " + output[-1200:])
    if "No prompt provided via stdin." not in output:
        raise BenchError("strict Codex exec config probe did not stop at empty stdin: " + output[-1200:])


def _record_path(run_dir: Path) -> Path:
    return run_dir / "launch.json"


def _stamp_launch_context(attempt_receipt: Path, run_receipt: Path, attempt_dir: Path,
                         launch_mode: str, effective_cap: int, batch_id: str) -> dict[str, Any]:
    receipt = _json(attempt_receipt)
    if receipt.get("status") != "PREPARED":
        raise BenchError("attempt is not untouched PREPARED; refusing relaunch")
    evidence = ("events.jsonl", "stderr.log", "report.md", "rollout.jsonl", "argv.json")
    if any((attempt_dir / name).exists() for name in evidence):
        raise BenchError("attempt evidence already exists; refusing overwrite")
    receipt.update({"launch_mode": launch_mode, "effective_concurrency_cap": effective_cap,
                    "batch_id": batch_id})
    _write_json(attempt_receipt, receipt)
    _write_json(run_receipt, receipt)
    return receipt


def _make_config(run_dir: Path, rid: str, cell: dict[str, Any], attempt_no: int = 1,
                 private_base: Path | None = None,
                 frozen_root_override: Path | None = None) -> tuple[Path, dict[str, Any]]:
    # Active profiles/authentication stay outside the repository.
    local_app = private_base or Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local")))
    suite_key = hashlib.sha256(str(run_dir.resolve().parents[1]).encode()).hexdigest()[:12]
    attempt_name = f"attempt-{attempt_no:02d}"
    home = local_app / "CodexBench" / suite_key / rid / attempt_name / "home"
    codex_home = home / ".codex"
    codex_home.mkdir(parents=True, exist_ok=True)
    (home / "neutral-cwd").mkdir(exist_ok=True)
    frozen_root = frozen_root_override or Path(os.environ.get("CODEX_BENCH_FROZEN_ROOT", str(DEFAULT_FROZEN)))
    receipts = run_dir / attempt_name / "frozen-mcp-receipts.jsonl"
    guard_log = run_dir / attempt_name / "guard-receipts.jsonl"
    python = str(Path(sys.executable))
    mcp_script = str(HERE / "codex_frozen_mcp.py")
    guard_script = str(HERE / "codex_guard.py")
    hook_cmd = f'"{python}" -I "{guard_script}"'
    codex_tier = "priority" if cell["speed"] == "fast" else "default"
    toml = "\n".join([
        f"model = {json.dumps(cell['model'])}",
        f"model_reasoning_effort = {json.dumps(cell['effort'])}",
        f"service_tier = {json.dumps(codex_tier)}",
        'approval_policy = "never"', 'sandbox_mode = "read-only"',
        "project_doc_max_bytes = 0", "web_search = 'disabled'", "",
        "[features]", "multi_agent = false", "multi_agent_v2 = false",
        "multi_agent_v2_dynamic_tools = false", "shell_tool = false", "apps = false", "plugins = false",
        "remote_plugin = false", "goals = false", "computer_use = false",
        "browser_use = false", "in_app_browser = false", "hooks = true",
        "code_mode = true", "code_mode_host = true", "code_mode_tool_search = false", "tool_search = false",
        "view_image = false", "",
        "[agents]", "enabled = false", "max_concurrent_threads_per_session = 1", "",
        "[[hooks.PreToolUse]]", 'matcher = ".*"',
        "[[hooks.PreToolUse.hooks]]", 'type = "command"', f"command = {json.dumps(hook_cmd)}", "timeout = 3", "",
        "[[hooks.SessionStart]]", 'matcher = ".*"',
        "[[hooks.SessionStart.hooks]]", 'type = "command"', f"command = {json.dumps(hook_cmd)}", "timeout = 3", "",
        "[[hooks.SubagentStart]]", 'matcher = ".*"',
        "[[hooks.SubagentStart.hooks]]", 'type = "command"', f"command = {json.dumps(hook_cmd)}", "timeout = 3", "",
        "[[hooks.SessionEnd]]", 'matcher = ".*"',
        "[[hooks.SessionEnd.hooks]]", 'type = "command"', f"command = {json.dumps(hook_cmd)}", "timeout = 3", "",
        "[mcp_servers.frozen]", f"command = {json.dumps(python)}",
        f"args = ['-I', {json.dumps(mcp_script)}]", "enabled = true", "required = true",
        'enabled_tools = ["list", "read", "search", "sql"]',
        f"cwd = {json.dumps(str(home / 'neutral-cwd'))}",
        "startup_timeout_sec = 20", "tool_timeout_sec = 60", "",
        "[mcp_servers.frozen.env]", f"CODEX_FROZEN_ROOT = {json.dumps(str(frozen_root))}",
        f"CODEX_FROZEN_RECEIPTS = {json.dumps(str(receipts))}", "",
    ])
    (codex_home / "config.toml").write_text(toml, encoding="utf-8")
    config = {
        "model": cell["model"], "reasoning_effort": cell["effort"], "service_tier": cell["speed"],
        "multi_agent": False, "multi_agent_v2": False, "multi_agent_v2_dynamic_tools": False,
        "agents_enabled": False, "max_concurrent_threads_per_session": 1,
        "code_mode": True, "code_mode_host": True,
        "sandbox": "read-only", "network": "disabled", "shell_tool": False,
        "apps": False, "plugins": False, "remote_plugin": False, "goals": False,
        "view_image": False, "computer_use": False, "browser_use": False, "in_app_browser": False,
        "memories": False, "web_search": "disabled",
        "hooks_allowlist": ["mcp__frozen__list", "mcp__frozen__read", "mcp__frozen__search", "mcp__frozen__sql"],
        "mcp_command": [python, "-I", mcp_script], "guard_command": [python, "-I", guard_script],
        "guard_log": str(guard_log), "mcp_receipts": str(receipts),
        "private_config": str(codex_home / "config.toml"),
        "private_config_sha256": _sha((codex_home / "config.toml").read_bytes()),
        "prompt_id": rid,
    }
    config["hook_config"] = config["private_config"]
    config["hook_sha256"] = config["private_config_sha256"]
    return codex_home, config


def _write_attempt(root: Path, rid: str, cell: dict[str, Any], rendered_prompt: str, attempt_no: int = 1) -> Path:
    run_dir = root / "runs" / rid
    attempt = run_dir / f"attempt-{attempt_no:02d}"
    if attempt.exists():
        # Never replace evidence from an earlier failed or completed attempt.
        raise BenchError(f"attempt-01 already exists for {rid}; inspect it and use an explicit future attempt workflow")
    attempt.mkdir(parents=True)
    codex_home, run_config = _make_config(run_dir, rid, cell, attempt_no)
    task = root / "runs" / rid / "prompt.md"
    task.parent.mkdir(parents=True, exist_ok=True)
    task.write_text(rendered_prompt, encoding="utf-8", newline="\n")
    (attempt / "requested-config.json").write_text(json.dumps(run_config, indent=2) + "\n", encoding="utf-8")
    # The canonical frozen path is explicit and can be overridden for local test fixtures.
    frozen_root = Path(os.environ.get("CODEX_BENCH_FROZEN_ROOT", str(DEFAULT_FROZEN)))
    private_home = codex_home.parent
    receipt = {
        "run": rid, "model": cell["model"], "effort": cell["effort"], "speed": cell["speed"],
        "service_tier": cell["speed"],
        "prompt_sha256": _sha(task.read_bytes()), "config_sha256": _sha((attempt / "requested-config.json").read_bytes()),
        "cli_path": str(Path(os.environ.get("CODEX_BENCH_CLI", str(DEFAULT_CODEX)))),
        "frozen_root": str(frozen_root), "private_home": str(private_home), "codex_home": str(codex_home),
        "created_utc": datetime.now(timezone.utc).isoformat(), "status": "PREPARED",
        "attempt": attempt_no, "multi_agent": False, "agents_enabled": False,
        "max_concurrent_threads_per_session": 1,
    }
    _write_json(attempt / "launch.json", receipt)
    _write_json(_record_path(run_dir), receipt)
    return run_dir


def _refresh_prepared_prompt(run_dir: Path, rendered: str) -> None:
    """Refresh generated task text only while every attempt is untouched PREPARED."""
    root_receipt = _record_path(run_dir)
    if not root_receipt.is_file():
        raise BenchError("prepared launch receipt is missing; refusing prompt refresh")
    attempts = sorted(run_dir.glob("attempt-[0-9][0-9]"))
    if not attempts:
        raise BenchError("prepared attempt directory is missing; refusing prompt refresh")
    receipts = [root_receipt, *(p / "launch.json" for p in attempts)]
    loaded = [_json(p) for p in receipts]
    if any(item.get("status") != "PREPARED" for item in loaded):
        raise BenchError("prompt refresh is allowed only for untouched PREPARED attempts")
    evidence_names = {"events.jsonl", "stderr.log", "report.md", "rollout.jsonl", "argv.json",
                      "guard-receipts.jsonl", "frozen-mcp-receipts.jsonl"}
    if (run_dir / "report.md").exists() or any((attempt / name).exists() for attempt in attempts for name in evidence_names):
        raise BenchError("attempt evidence exists; refusing to replace prepared prompt")
    for item in loaded:
        codex_home = Path(item.get("codex_home", ""))
        if (codex_home / "auth.json").exists():
            raise BenchError("private profile contains authentication; refusing prompt refresh")
        sessions = codex_home / "sessions"
        if sessions.exists() and any(p.is_file() for p in sessions.rglob("*")):
            raise BenchError("private profile contains session evidence; refusing prompt refresh")
    task = run_dir / "prompt.md"
    task.write_text(rendered, encoding="utf-8", newline="\n")
    digest = _sha(task.read_bytes())
    for path, item in zip(receipts, loaded):
        item["prompt_sha256"] = digest
        _write_json(path, item)


def _refresh_prepared_profile(run_dir: Path, rid: str, cell: dict[str, Any]) -> None:
    """Regenerate only private profile config for untouched PREPARED attempts."""
    root_receipt = _record_path(run_dir)
    attempts = sorted(run_dir.glob("attempt-[0-9][0-9]"))
    if not root_receipt.is_file() or not attempts:
        raise BenchError("prepared receipt/profile is missing; cannot refresh private config")
    receipts = [root_receipt, *(p / "launch.json" for p in attempts)]
    loaded = [_json(p) for p in receipts]
    if any(item.get("status") != "PREPARED" for item in loaded):
        raise BenchError("private config refresh is allowed only for untouched PREPARED attempts")
    evidence_names = {"events.jsonl", "stderr.log", "report.md", "rollout.jsonl", "argv.json",
                      "guard-receipts.jsonl", "frozen-mcp-receipts.jsonl"}
    if (run_dir / "report.md").exists() or any((attempt / name).exists() for attempt in attempts for name in evidence_names):
        raise BenchError("attempt evidence exists; refusing private config refresh")
    for item in loaded:
        codex_home = Path(item.get("codex_home", ""))
        if (codex_home / "auth.json").exists():
            raise BenchError("private profile contains authentication; refusing config refresh")
        sessions = codex_home / "sessions"
        if sessions.exists() and any(p.is_file() for p in sessions.rglob("*")):
            raise BenchError("private profile contains session evidence; refusing config refresh")
    task_digest = _sha((run_dir / "prompt.md").read_bytes())
    for attempt_dir in attempts:
        attempt_no = int(attempt_dir.name.split("-")[-1])
        codex_home, config = _make_config(run_dir, rid, cell, attempt_no)
        legacy_hooks = codex_home / "hooks.json"
        if legacy_hooks.exists():
            legacy_hooks.unlink()
        config_path = attempt_dir / "requested-config.json"
        _write_json(config_path, config)
        receipt_path = attempt_dir / "launch.json"
        receipt = _json(receipt_path)
        receipt.update({"codex_home": str(codex_home), "prompt_sha256": task_digest,
                        "config_sha256": _sha(config_path.read_bytes())})
        _write_json(receipt_path, receipt)
    root_item = _json(root_receipt)
    attempt_item = _json(attempts[-1] / "launch.json")
    root_item.update({"prompt_sha256": task_digest,
                      "codex_home": attempt_item.get("codex_home"),
                      "config_sha256": _sha((attempts[-1] / "requested-config.json").read_bytes())})
    _write_json(root_receipt, root_item)


def _recover_missing_prepared_attempt(run_dir: Path, rid: str, cell: dict[str, Any],
                                     rendered_prompt: str) -> None:
    """Rebuild a missing attempt only when the run is an untouched PREPARED shell."""
    receipt_path = _record_path(run_dir)
    if not receipt_path.is_file():
        raise BenchError("prepared launch receipt is missing; refusing attempt recovery")
    receipt = _json(receipt_path)
    if receipt.get("status") != "PREPARED":
        raise BenchError("attempt recovery is allowed only for untouched PREPARED runs")
    if list(run_dir.glob("attempt-[0-9][0-9]")):
        raise BenchError("attempt directory exists; refusing missing-attempt recovery")
    prompt = run_dir / "prompt.md"
    if not prompt.is_file() or _sha(prompt.read_bytes()) != receipt.get("prompt_sha256"):
        raise BenchError("prepared prompt does not match its receipt; refusing attempt recovery")
    if prompt.read_text(encoding="utf-8") != rendered_prompt:
        raise BenchError("prepared prompt differs from current frozen task; refusing attempt recovery")
    if {p.name for p in run_dir.iterdir()} - {"launch.json", "prompt.md", "legacy-prepared-launch.json"}:
        raise BenchError("run contains attempt evidence; refusing missing-attempt recovery")
    codex_home = Path(receipt.get("codex_home", ""))
    if (codex_home / "auth.json").exists():
        raise BenchError("private profile contains authentication; refusing attempt recovery")
    sessions = codex_home / "sessions"
    if sessions.exists() and any(p.is_file() for p in sessions.rglob("*")):
        raise BenchError("private profile contains session evidence; refusing attempt recovery")
    legacy = run_dir / "legacy-prepared-launch.json"
    old_bytes = receipt_path.read_bytes()
    if legacy.exists() and legacy.read_bytes() != old_bytes:
        raise BenchError("legacy prepared receipt already differs; refusing recovery")
    if not legacy.exists():
        shutil.copy2(receipt_path, legacy)
    _write_attempt(run_dir.parent.parent, rid, cell, rendered_prompt)


def _validate_frozen(path: Path) -> None:
    verify = path / "verify.sh"
    if not verify.is_file():
        raise BenchError(f"frozen verify.sh missing: {path}")
    # Preflight is read-only: run the supplied verifier through WSL only.
    wsl = shutil.which("wsl.exe")
    if not wsl:
        raise BenchError("wsl.exe unavailable; cannot verify frozen fixture")
    rel = "/mnt/" + path.drive[0].lower() + path.as_posix()[2:]
    result = subprocess.run([wsl, "-d", "DwemerAI4Skyrim3", "-u", "root", "--cd", "/", "--", "bash", rel + "/verify.sh"],
                            capture_output=True, text=True, timeout=90, check=False)
    if result.returncode or "FROZEN OK" not in result.stdout.splitlines()[-1:]:
        raise BenchError(f"frozen preflight failed rc={result.returncode}: {(result.stdout + result.stderr)[-1000:]}")


def _probe_mcp(env: dict[str, str]) -> dict[str, Any]:
    script = HERE / "codex_frozen_mcp.py"
    payload = "\n".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "codex-bench-preflight", "version": "1"}}}),
        json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}),
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}), "",
    ])
    result = subprocess.run([sys.executable, "-I", str(script)], input=payload, text=True,
                            capture_output=True, env=env, timeout=30, check=False)
    if result.returncode:
        raise BenchError("frozen MCP startup probe failed: " + result.stderr[-800:])
    responses = []
    for line in result.stdout.splitlines():
        try: responses.append(json.loads(line))
        except json.JSONDecodeError: pass
    listing = next((r.get("result", {}) for r in responses if r.get("id") == 2), {})
    names = sorted(t.get("name") for t in listing.get("tools", []) if isinstance(t, dict))
    expected = ["list", "read", "search", "sql"]
    if names != expected:
        raise BenchError("frozen MCP advertised an unexpected tool surface")
    return {"ready": True, "tools": names}


def prepare(root: Path) -> int:
    cfg = load_suite(root)
    concurrency(root, None)
    if isinstance(cfg.get("concurrency"), dict) and cfg["concurrency"].get("auto_start", False):
        raise BenchError("suite auto_start must be false; launch requires explicit `run --execute`")
    entries = run_ids(root, cfg)
    template_path = (root / cfg.get("template", "task-frozen.tmpl")).resolve()
    if not template_path.is_file():
        raise BenchError(f"suite task template missing: {template_path.name}")
    template = template_path.read_text(encoding="utf-8")
    frozen_value = str(cfg.get("frozen", DEFAULT_FROZEN))
    frozen_path = Path(frozen_value)
    fwsl = f"/mnt/{frozen_path.drive[0].lower()}{frozen_path.as_posix()[2:]}" if frozen_path.drive else frozen_value.replace("\\", "/")
    for index, (rid, cell, _num, prompt_name) in enumerate(entries, 1):
        prompt_source = root / prompt_name
        rendered = (template.replace("{TICKET}", f"BENCH-R{index:03d}")
                    .replace("{PROMPT}", prompt_source.read_text(encoding="utf-8").strip())
                    .replace("{FROZEN_WSL}", fwsl).replace("{FROZEN}", frozen_value))
        target = root / "runs" / rid / "prompt.md"
        receipt_path = _record_path(target.parent)
        if receipt_path.is_file() and not list(target.parent.glob("attempt-[0-9][0-9]")):
            _recover_missing_prepared_attempt(target.parent, rid, cell, rendered)
        if target.exists():
            receipt_path = _record_path(target.parent)
            recorded_hash = _json(receipt_path).get("prompt_sha256") if receipt_path.is_file() else None
            if target.read_text(encoding="utf-8") != rendered or recorded_hash != _sha(target.read_bytes()):
                _refresh_prepared_prompt(target.parent, rendered)
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(rendered, encoding="utf-8", newline="\n")
        # Materialize an explicit launch receipt/config only once per run.
        if not _record_path(target.parent).exists():
            _write_attempt(root, rid, cell, rendered)
        else:
            _refresh_prepared_profile(target.parent, rid, cell)
    print(f"PREPARED {len(entries)} cells; no Codex process started")
    return 0


def _preflight(root: Path) -> int:
    cfg = load_suite(root)
    entries = run_ids(root, cfg)
    template_path = (root / cfg.get("template", "task-frozen.tmpl")).resolve()
    if not template_path.is_file():
        raise BenchError("suite task template missing")
    concurrency(root, None)
    if isinstance(cfg.get("concurrency"), dict) and cfg["concurrency"].get("auto_start", False):
        raise BenchError("suite auto_start must be false")
    cli = Path(os.environ.get("CODEX_BENCH_CLI", str(DEFAULT_CODEX)))
    if not cli.is_file():
        raise BenchError(f"Codex CLI not found: {cli}")
    prepared_prompts: dict[str, str] = {}
    for rid, _cell, _num, _prompt in entries:
        run_dir = root / "runs" / rid
        task = run_dir / "prompt.md"
        launch = _record_path(run_dir)
        if not task.is_file() or not launch.is_file():
            raise BenchError(f"run is not prepared: {rid}; run prepare first")
        receipt = _json(launch)
        attempt_no = int(receipt.get("attempt", 1))
        attempt_config = run_dir / f"attempt-{attempt_no:02d}" / "requested-config.json"
        attempt_receipt = run_dir / f"attempt-{attempt_no:02d}" / "launch.json"
        if not attempt_config.is_file() or not attempt_receipt.is_file():
            raise BenchError(f"latest attempt profile is missing: {rid} attempt-{attempt_no:02d}")
        config = _json(attempt_config)
        codex_home = Path(receipt.get("codex_home", ""))
        if (_sha(task.read_bytes()) != receipt.get("prompt_sha256") or
                not (codex_home / "config.toml").is_file() or
                _sha((codex_home / "config.toml").read_bytes()) != config.get("private_config_sha256") or
                config.get("hook_config") != config.get("private_config") or
                config.get("hook_sha256") != config.get("private_config_sha256")):
            raise BenchError(f"prepared prompt or private isolation profile changed: {rid}")
        if receipt.get("status") == "PREPARED" and (codex_home / "hooks.json").exists():
            raise BenchError(f"duplicate external hooks source remains in prepared profile: {rid}")
        prepared_prompts[rid] = _sha(task.read_bytes())
    frozen = Path(os.environ.get("CODEX_BENCH_FROZEN_ROOT", str(cfg.get("frozen", DEFAULT_FROZEN))))
    _validate_frozen(frozen)
    # The database role/manifest preflight is read-only and uses only stobe_frozen.
    sys.path.insert(0, str(HERE))
    import codex_frozen
    frozen_result = codex_frozen.preflight(frozen, dsn="stobe_frozen", verify=False, db_probe=True)
    # A cached catalog is required to prove model, effort and speed compatibility.
    user_codex = Path(os.environ.get("CODEX_BENCH_CATALOG", str(DEFAULT_USER_CODEX / "models_cache.json")))
    if not user_codex.is_file():
        raise BenchError("Codex model catalog cache is missing; preflight cannot prove model/effort/tier compatibility")
    catalog = _json(user_codex)
    catalog_models = catalog.get("models", catalog.get("data", []))
    if isinstance(catalog_models, dict):
        catalog_models = list(catalog_models.values())
    by_model = {m.get("slug", m.get("id", m.get("model"))): m for m in catalog_models if isinstance(m, dict)}
    for _rid, cell, _n, _p in entries:
        m = by_model.get(cell["model"])
        if not m:
            raise BenchError(f"model missing from current Codex catalog: {cell['model']}")
        levels = m.get("supported_reasoning_levels", m.get("reasoning_levels", []))
        if isinstance(levels, list) and levels and cell["effort"] not in [x if isinstance(x, str) else x.get("effort") for x in levels]:
            raise BenchError(f"effort {cell['effort']} not supported for {cell['model']}")
        if not isinstance(levels, list) or not levels:
            raise BenchError(f"model catalog does not specify reasoning levels for {cell['model']}")
        if cell["speed"] == "fast" and not _fast_tier_supported(m):
            raise BenchError(f"fast service tier not supported for {cell['model']}")
    version_env = _private_env(Path(tempfile.gettempdir()) / "codex-bench-version-home")
    version_env["CODEX_HOME"] = str(Path(tempfile.gettempdir()) / "codex-bench-version-home" / ".codex")
    version = subprocess.run([str(cli), "--version"], env=version_env, capture_output=True, text=True, timeout=15, check=False)
    if version.returncode:
        raise BenchError("Codex CLI version probe failed: " + version.stderr[-500:])
    if "0.163.0-alpha.10.2" not in version.stdout:
        raise BenchError("installed Codex CLI version does not match the pinned benchmark CLI")
    # Validate the current source profile in a disposable auth-free home. A prior
    # failed attempt's profile is immutable and may predate the installed schema.
    probe_cells = {cell["speed"]: cell for _rid, cell, _num, _prompt in entries}
    feature_outputs: list[str] = []
    with tempfile.TemporaryDirectory(prefix="codex-bench-profile-probe-") as tmp:
        private_base = Path(tmp)
        probe_run = private_base / "suite" / "runs" / "profile-probe"
        probe_cwd = None
        for speed, cell in probe_cells.items():
            codex_home, _config = _make_config(probe_run, "profile-probe", cell, private_base=private_base,
                                               frozen_root_override=frozen)
            probe_cwd = codex_home.parent / "neutral-cwd"
            feature_env = _private_env(codex_home.parent, {
                "CODEX_HOME": str(codex_home), "CODEX_FROZEN_ROOT": str(frozen),
                "CODEX_FROZEN_RECEIPTS": str(probe_run / "attempt-01" / "frozen-mcp-receipts.jsonl"),
            })
            config_probe = subprocess.run([str(cli), "mcp", "list"], env=feature_env,
                                          capture_output=True, text=True, timeout=30, check=False)
            if config_probe.returncode:
                raise BenchError("private config rejected by installed Codex CLI: " + (config_probe.stderr or config_probe.stdout)[-1500:])
            features = subprocess.run([str(cli), "features", "list"], env=feature_env,
                                      capture_output=True, text=True, timeout=30, check=False)
            if features.returncode:
                raise BenchError("private Codex feature snapshot failed: " + (features.stderr or features.stdout)[-1000:])
            feature_outputs.append(features.stdout)
            _strict_exec_config_probe(cli, feature_env, probe_cwd)
    # No model turn: initialize the same stdio MCP server and verify only its advertised tool surface.
    # No model turn: initialize the same stdio MCP server and verify only its advertised tool surface.
    mcp_env = _private_env(Path(tempfile.gettempdir()) / "codex-bench-mcp-home", {
        "CODEX_FROZEN_ROOT": str(frozen),
        "CODEX_FROZEN_RECEIPTS": str(root / "mcp-preflight-receipts.jsonl"),
    })
    probe = _probe_mcp(mcp_env)
    materials = [root / "suite.json", template_path, *[root / p for p in cfg.get("prompts", ["prompt2.txt", "prompt3.txt"])]]
    material_hashes = {str(p.resolve()): _sha(p.read_bytes()) for p in materials}
    proof = {"ready": True, "suite_sha256": _sha((root / "suite.json").read_bytes()),
             "frozen": frozen_result, "cli_version": version.stdout.strip(),
             "catalog_sha256": _sha(user_codex.read_bytes()), "cells": len(entries),
             "auth_available": Path(os.environ.get("CODEX_BENCH_AUTH", str(DEFAULT_USER_CODEX / "auth.json"))).is_file(),
             "materials": material_hashes, "prepared_prompts": prepared_prompts,
             "private_features_snapshot_sha256": _sha("\n".join(feature_outputs).encode("utf-8")),
             "cli_config_probe": "strict exec parser (empty stdin) for standard/fast; mcp list", "mcp_probe": probe,
             "checked_utc": datetime.now(timezone.utc).isoformat()}
    _write_json(root / "preflight.json", proof)
    print(f"PREFLIGHT OK {len(entries)} cells; frozen fixture verified; no model call")
    return 0


def _lock(root: Path):
    lock = root / ".codex-bench.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    f = lock.open("a+b")
    try:
        if os.name == "nt":
            import msvcrt
            f.seek(0)
            if f.read(1) == b"": f.write(b"0"); f.flush()
            f.seek(0); msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, BlockingIOError) as exc:
        f.close()
        raise BenchError("another benchmark launcher holds the suite lock") from exc
    return f


def _postflight(root: Path) -> dict[str, Any]:
    cfg = load_suite(root)
    frozen = Path(os.environ.get("CODEX_BENCH_FROZEN_ROOT", str(cfg.get("frozen", DEFAULT_FROZEN))))
    _validate_frozen(frozen)
    sys.path.insert(0, str(HERE))
    import codex_frozen
    result = codex_frozen.preflight(frozen, dsn="stobe_frozen", verify=False, db_probe=True)
    proof = {"ready": True, "frozen": result, "checked_utc": datetime.now(timezone.utc).isoformat()}
    _write_json(root / "postflight.json", proof)
    return proof


def preflight(root: Path) -> int:
    lock = _lock(root)
    try: return _preflight(root)
    finally: lock.close()


def launch_one(root: Path, rid: str, execute: bool, timeout: int, attempt_no: int = 1,
               launch_mode: str = "sequential", effective_cap: int = 1, batch_id: str = "") -> int:
    if not execute:
        raise BenchError("model launch is disabled without the explicit --execute flag")
    cfg = load_suite(root)
    proof_path = root / "preflight.json"
    if not proof_path.is_file():
        raise BenchError("preflight proof missing; run preflight first")
    proof = _json(proof_path)
    if not proof.get("ready") or proof.get("suite_sha256") != _sha((root / "suite.json").read_bytes()):
        raise BenchError("preflight proof is stale or incomplete")
    for material, digest in proof.get("materials", {}).items():
        if not Path(material).is_file() or _sha(Path(material).read_bytes()) != digest:
            raise BenchError("preflight material changed; rerun prepare and preflight")
    item = {x[0]: x[1:] for x in run_ids(root, cfg)}.get(rid)
    if not item:
        raise BenchError(f"unknown run id: {rid}")
    cell, _num, _prompt_name = item
    run_dir = root / "runs" / rid
    receipt_path = _record_path(run_dir)
    if not receipt_path.is_file():
        raise BenchError(f"run not prepared: {rid}; run prepare first")
    if attempt_no < 1:
        raise BenchError("attempt number must be positive")
    attempt = run_dir / f"attempt-{attempt_no:02d}"
    if attempt_no > 1:
        old = sorted(run_dir.glob("attempt-[0-9][0-9]"))
        if attempt.exists() or not old or attempt_no != len(old) + 1:
            raise BenchError("explicit attempts must be new, sequential numbers; no automatic retries are made")
        previous = _json(old[-1] / "launch.json")
        if previous.get("status") not in {"FAILED", "TIMEOUT", "FAILED_IO", "FAILED_START",
                                            "FAILED_NO_ROOT_ROLLOUT", "FAILED_NO_FINAL_REPORT", "COMPLETE_UNAUDITED"}:
            raise BenchError("previous attempt is not terminal")
        _write_attempt(root, rid, cell, (run_dir / "prompt.md").read_text(encoding="utf-8"), attempt_no)
    elif not attempt.is_dir():
        raise BenchError(f"attempt-01 was not prepared: {rid}; run prepare first")
    attempt_receipt = attempt / "launch.json"
    receipt = _json(attempt_receipt)
    if receipt.get("status") != "PREPARED":
        raise BenchError("attempt is not untouched PREPARED; refusing relaunch")
    codex_home = Path(receipt["codex_home"])
    config = _json(attempt / "requested-config.json")
    task = run_dir / "prompt.md"
    if (not task.is_file() or _sha(task.read_bytes()) != receipt.get("prompt_sha256") or
            proof.get("prepared_prompts", {}).get(rid) != receipt.get("prompt_sha256")):
        raise BenchError("prepared participant prompt changed; refusing launch")
    for key, filename in (("private_config_sha256", "config.toml"),):
        private_file = codex_home / filename
        if not private_file.is_file() or _sha(private_file.read_bytes()) != config.get(key):
            raise BenchError(f"isolated {filename} changed after preparation; refusing launch")
    home = codex_home.parent
    prompt = task.read_text(encoding="utf-8")
    # Each process receives a fresh profile and no parent-session prompt context.
    env = _private_env(home, {"CODEX_HOME": str(codex_home), "CODEX_FROZEN_ROOT": receipt["frozen_root"],
                              "CODEX_FROZEN_RECEIPTS": str(attempt / "frozen-mcp-receipts.jsonl"),
                              "CODEX_BENCH_GUARD_LOG": str(attempt / "guard-receipts.jsonl")})
    _strict_exec_config_probe(Path(receipt["cli_path"]), env=env, cwd=home / "neutral-cwd")
    # Do not mark the attempt RUNNING until the exact prepared profile passes
    # the installed CLI's strict parser. A setup rejection stays PREPARED.
    receipt = _stamp_launch_context(attempt_receipt, receipt_path, attempt, launch_mode, effective_cap, batch_id)
    auth_source = Path(os.environ.get("CODEX_BENCH_AUTH", str(DEFAULT_USER_CODEX / "auth.json")))
    if not proof.get("auth_available") or not auth_source.is_file():
        raise BenchError("saved Codex authentication is unavailable; no credentials were copied")
    auth_destination = codex_home / "auth.json"
    if not auth_destination.exists(): shutil.copy2(auth_source, auth_destination)
    cli = receipt["cli_path"]
    log_path = attempt / "events.jsonl"
    stderr_path = attempt / "stderr.log"
    report_path = attempt / "report.md"
    if log_path.exists() or stderr_path.exists() or report_path.exists():
        raise BenchError(f"evidence already exists for {rid}; refusing overwrite")
    # Private config + fixed CLI arguments; nothing is passed via inherited shell state.
    argv = [cli, "--dangerously-bypass-hook-trust", "exec", "--json", "-o", str(report_path), "--ignore-rules",
            "--sandbox", "read-only", "--strict-config", "--cd", str(home / "neutral-cwd"),
            "--skip-git-repo-check",
            "--model", cell["model"], "--config", f"model_reasoning_effort={cell['effort']}",
            "--config", f"service_tier={'priority' if cell['speed'] == 'fast' else 'default'}", "-"]
    (attempt / "argv.json").write_text(json.dumps(argv, indent=2) + "\n", encoding="utf-8")
    receipt.update({"status": "RUNNING", "started_utc": datetime.now(timezone.utc).isoformat(),
                   "requested_config": config, "argv_sha256": _sha(json.dumps(argv).encode())})
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    started = time.monotonic()
    with log_path.open("xb") as out, stderr_path.open("xb") as err:
        popen_args = {"cwd": home / "neutral-cwd", "env": env, "stdin": subprocess.PIPE,
                      "stdout": out, "stderr": err,
                      "creationflags": getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)}
        if os.name != "nt": popen_args["start_new_session"] = True
        try:
            proc = subprocess.Popen(argv, **popen_args)
        except OSError as exc:
            receipt.update({"status": "FAILED_START", "error_type": type(exc).__name__,
                            "ended_utc": datetime.now(timezone.utc).isoformat()})
            _write_json(attempt_receipt, receipt)
            _write_json(receipt_path, receipt)
            print(f"FAILED_START {rid} ({type(exc).__name__})", file=sys.stderr)
            return record(root, rid)
        with ACTIVE_LOCK: ACTIVE_PROCESSES.add(proc)
        try:
            proc.stdin.write(prompt.encode("utf-8")); proc.stdin.flush(); proc.stdin.close()
            while proc.poll() is None:
                _refresh_live_receipt(receipt, receipt_path, attempt_receipt, log_path, codex_home)
                if time.monotonic() - started >= timeout:
                    _terminate_process(proc)
                    receipt["status"] = "TIMEOUT"
                    break
                time.sleep(0.5)
            rc = proc.wait()
        except (BrokenPipeError, OSError) as exc:
            _terminate_process(proc)
            rc = proc.wait()
            receipt.update({"status": "FAILED_IO", "error_type": type(exc).__name__})
        finally:
            with ACTIVE_LOCK: ACTIVE_PROCESSES.discard(proc)
    receipt.update({"returncode": rc, "elapsed_s": round(time.monotonic() - started, 3),
                    "ended_utc": datetime.now(timezone.utc).isoformat(),
                    "events_path": str(log_path), "stderr_path": str(stderr_path),
                    "report_path": str(report_path) if report_path.exists() else None})
    guard_file = attempt / "guard-receipts.jsonl"
    guard_events = []
    if guard_file.is_file():
        for line in guard_file.read_text(encoding="utf-8", errors="replace").splitlines():
            try: guard_events.append(json.loads(line))
            except json.JSONDecodeError: pass
    lifecycle = {e.get("event") for e in guard_events} >= {"SessionStart", "SessionEnd"}
    guard_ok = all((e.get("event") != "PreToolUse" or
                    (e.get("decision") == "allow" and e.get("tool") in config["hooks_allowlist"]))
                   and e.get("event") != "SubagentStart" for e in guard_events)
    mcp_file = attempt / "frozen-mcp-receipts.jsonl"
    mcp_events = _jsonl(mcp_file) if mcp_file.is_file() else []
    mcp_ok = all(e.get("outcome") == "ok" and e.get("method") in {"list", "read", "search", "sql"} for e in mcp_events)
    hook_calls = [e for e in guard_events if e.get("event") == "PreToolUse"]
    import collections
    expected_calls = collections.Counter(("mcp__frozen__" + e.get("method", ""),
                                           _sha(json.dumps(e.get("arguments", {}), sort_keys=True, ensure_ascii=False, default=str).encode("utf-8")))
                                          for e in mcp_events)
    observed_calls = collections.Counter((e.get("tool"), e.get("input_sha256")) for e in hook_calls)
    delegation_detected = any(e.get("event") == "SubagentStart" or
                              (e.get("event") == "PreToolUse" and e.get("decision") == "deny" and
                               any(tag in str(e.get("tool", "")).casefold() for tag in ("agent", "spawn", "delegate")))
                              for e in guard_events)
    receipt.update({"guard_events": len(guard_events), "mcp_events": len(mcp_events),
                    "hook_verified": bool(lifecycle and guard_ok and mcp_ok and observed_calls == expected_calls),
                    "terminal_verified": False, "verified_receipt": False,
                    "delegation_detected": delegation_detected,
                    "allowed_tools": config["hooks_allowlist"], "agents_enabled": False,
                    "multi_agent": False, "max_concurrent_threads_per_session": 1})
    if receipt.get("status") != "TIMEOUT" and rc == 0 and report_path.exists():
        receipt["status"] = "COMPLETE_UNAUDITED"
    elif receipt.get("status") != "TIMEOUT":
        receipt["status"] = "FAILED"
    sessions = codex_home / "sessions"
    candidates = [p for p in sessions.rglob("*.jsonl") if p.is_file()] if sessions.is_dir() else []
    events = _jsonl(log_path)
    requested_thread = _thread_id(events)
    candidate_by_id = {tid: p for p in candidates if (tid := _rollout_id(p))}
    rollouts_dir = attempt / "rollouts"
    child_paths = []
    root_rollout = candidate_by_id.get(requested_thread) if requested_thread else None
    if candidates:
        rollouts_dir.mkdir(exist_ok=True)
        for source in candidates:
            dest = rollouts_dir / (_sha(str(source).encode())[:12] + ".jsonl")
            shutil.copyfile(source, dest)
            if source != root_rollout: child_paths.append(str(dest))
    if root_rollout:
        shutil.copyfile(root_rollout, attempt / "rollout.jsonl")
        receipt["rollout_path"] = str(attempt / "rollout.jsonl")
        receipt["child_rollout_paths"] = child_paths
        receipt["terminal_verified"] = bool(rc == 0 and report_path.is_file() and lifecycle and guard_ok)
        receipt["verified_receipt"] = bool(receipt["hook_verified"] and receipt["terminal_verified"] and not child_paths)
    else:
        receipt["rollout_path"] = None
        receipt["child_rollout_paths"] = child_paths
        receipt["status"] = "FAILED_NO_ROOT_ROLLOUT"
    _write_json(attempt_receipt, receipt)
    _write_json(receipt_path, receipt)
    print(f"{receipt['status']} {rid} rc={rc} elapsed_s={receipt['elapsed_s']}")
    return record(root, rid)


_REQUIRED_HEADERS = ("Summary", "Root cause", "Evidence", "What you ruled out", "Proposed fix",
                     "How to confirm the fix worked", "What is not settled")
_CITATION_RE = re.compile(r"(?im)(?:^|[\s(])(?:[A-Za-z]:\\|/)[^\r\n():]+\.[A-Za-z0-9]{1,8}:\d+(?::\d+)?")


def _required_headers(report: str) -> int:
    found = set()
    for line in report.splitlines():
        text = re.sub(r"^\s{0,3}#{1,6}\s*", "", line).strip()
        text = re.sub(r"[*_`]+", "", text).rstrip(":").strip().casefold()
        for title in _REQUIRED_HEADERS:
            if text == title.casefold():
                found.add(title)
    return len(found)


def record(root: Path, rid: str, recheck: bool = False) -> int:
    run_dir = root / "runs" / rid
    attempt_dirs = sorted(run_dir.glob("attempt-[0-9][0-9]"))
    if not attempt_dirs:
        raise BenchError(f"no attempts recorded for {rid}")
    attempt_dir = attempt_dirs[-1]
    receipt = _json(attempt_dir / "launch.json")
    rollout = attempt_dir / "rollout.jsonl"
    result = None
    codex_record = None
    if rollout.is_file():
        sys.path.insert(0, str(HERE))
        import codex_record
        prices = _json(HERE / "codex_prices.json")
        result = codex_record.parse_rollout(rollout, config={
        "verified_receipt": receipt.get("verified_receipt") is True,
        "agents_enabled": receipt.get("agents_enabled"), "multi_agent": receipt.get("multi_agent"),
        "max_concurrent_threads_per_session": receipt.get("max_concurrent_threads_per_session"),
        "hook_verified": receipt.get("hook_verified") is True,
        "terminal_verified": receipt.get("terminal_verified") is True,
        "allowed_tools": receipt.get("allowed_tools", []),
        "model": receipt.get("model"), "effort": receipt.get("effort"),
        "service_tier": receipt.get("service_tier"),
        "requested_model": receipt.get("model"), "requested_effort": receipt.get("effort"),
        "requested_service_tier": receipt.get("service_tier"),
        "receipt": receipt, "config_digest": receipt.get("config_sha256"),
        }, pricing=prices)
    if result is not None and receipt.get("child_rollout_paths"):
        audit = result["audit"]
        audit["flags"] = sorted(set(audit.get("flags", []) + ["delegation:child-session-rollout-detected"]))
        audit["status"] = "FAIL"
    if result is not None and receipt.get("delegation_detected"):
        audit = result["audit"]
        audit["flags"] = sorted(set(audit.get("flags", []) + ["delegation:guard-evidence-detected"]))
        audit["status"] = "FAIL"
    report = (result or {}).get("report")
    report_path = run_dir / "report.md"
    if report:
        report_bytes = report.encode("utf-8")
        if report_path.exists() and report_path.read_bytes() != report_bytes:
            raise BenchError("saved report differs from rollout; refusing overwrite")
        if not report_path.exists(): report_path.write_bytes(report_bytes)
    usage = (result or {}).get("usage") or {}
    pricing = (result or {}).get("pricing") or {}
    audit = (result or {}).get("audit") or {"status": "UNKNOWN", "flags": ["no-final-report" if rollout.exists() else "no-rollout"]}
    if not report:
        missing_flag = "no-final-report" if rollout.exists() else "no-rollout"
        audit["flags"] = sorted(set(audit.get("flags", []) + [missing_flag]))
        if audit.get("status") != "FAIL": audit["status"] = "UNKNOWN"
    row = {
        "run": rid, "model": receipt.get("model", ""), "effort": receipt.get("effort", ""),
        "prompt": rid.rsplit("-p", 1)[-1], "start_local": (result or {}).get("start_local", ""),
        "end_local": (result or {}).get("end_local", ""), "wall_s": (result or {}).get("wall_s", receipt.get("elapsed_s", "")),
        "tool_uses": (result or {}).get("tool_uses", ""), "input": usage.get("input_tokens", ""),
        "output": usage.get("output_tokens", ""), "cache_read": usage.get("cached_input_tokens", ""),
        "cache_create": usage.get("cache_write_input_tokens", ""), "token_usd": pricing.get("usd", ""),
        "q5h_before": "n/a", "q5h_after": "n/a", "qweek_before": "n/a", "qweek_after": "n/a",
        "report_bytes": len(report.encode("utf-8")) if report else 0,
        "headers": _required_headers(report) if report else 0,
        "citations": len(_CITATION_RE.findall(report)) if report else 0,
        "diff_markers": sum(1 for line in report.splitlines() if line.startswith(("+++", "---", "@@"))) if report else 0,
        "violation_flags": ",".join(audit.get("flags", [])) or audit.get("status", "UNKNOWN"),
        "agent": f"{rid}/attempt-{receipt.get('attempt', 1):02d}",
    }
    _append_attempt_row(root, rid, receipt, result or {"audit": audit, "wall_s": receipt.get("elapsed_s", "")})
    if report and not recheck:
        ledger = root / "runs.tsv"
        with LEDGER_MUTEX:
            if ledger.exists():
                with ledger.open("r", encoding="utf-8", newline="") as f:
                    if any(item.get("run") == rid for item in csv.DictReader(f, delimiter="\t")):
                        raise BenchError(f"run already recorded: {rid}")
            codex_record.append_tsv(ledger, row)
    if result:
        receipt["audit"] = audit
        receipt["runtime"] = {k: result.get(k) for k in ("models", "efforts", "service_tiers", "usage", "pricing")}
    else:
        receipt["audit"] = audit
        if receipt.get("status") in {"RUNNING", "PREPARED"}: receipt["status"] = "FAILED_NO_FINAL_REPORT"
    if report and result: receipt["status"] = "RECORDED" if not recheck else "RECHECKED"
    _write_json(_record_path(run_dir), receipt)
    _write_json(attempt_dirs[-1] / "launch.json", receipt)
    if not report:
        print(f"{receipt.get('status', 'UNKNOWN')} {rid} attempt={receipt.get('attempt', 1)} metadata-only")
        return 1
    print(f"{audit['status']} {rid} report_bytes={len(report.encode())} pricing={pricing.get('status', 'UNKNOWN')}")
    return 0 if audit["status"] == "PASS" else 1


def status(root: Path, metrics: bool = False) -> int:
    cfg = load_suite(root)
    prices = _json(HERE / "codex_prices.json") if metrics else None
    live_metrics = None
    if metrics:
        sys.path.insert(0, str(HERE))
        import codex_status
        live_metrics = codex_status.live_metrics
    for rid, _cell, _num, _prompt in run_ids(root, cfg):
        path = _record_path(root / "runs" / rid)
        if path.exists():
            item = _json(path)
            line = f"{rid}\t{item.get('status','UNKNOWN')}\t{item.get('returncode','')}\t{item.get('audit',{}).get('status','')}\t{item.get('launch_mode','')}\t{item.get('effective_concurrency_cap','')}"
            if metrics:
                line += "\t" + json.dumps(live_metrics(item, prices), sort_keys=True)
            print(line)
        else:
            print(f"{rid}\tUNPREPARED")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "preflight"):
        p = sub.add_parser(name); p.add_argument("suite_dir")
    p = sub.add_parser("status"); p.add_argument("suite_dir"); p.add_argument("--metrics", action="store_true")
    p = sub.add_parser("run"); p.add_argument("suite_dir"); p.add_argument("run_id", nargs="?"); p.add_argument("--all", action="store_true"); p.add_argument("--execute", action="store_true", help="explicitly authorize these paid model launches"); p.add_argument("--mode", choices=("sequential", "limited-concurrent")); p.add_argument("--concurrency", type=int); p.add_argument("--attempt", type=int, default=1); p.add_argument("--timeout", type=int, default=1800)
    for name in ("record", "recheck"):
        p = sub.add_parser(name); p.add_argument("suite_dir"); p.add_argument("run_id")
    args = parser.parse_args(argv)
    try:
        root = suite_root(args.suite_dir)
        if args.command in ("prepare", "preflight"):
            lock = _lock(root)
            try: return prepare(root) if args.command == "prepare" else _preflight(root)
            finally: lock.close()
        if args.command == "status": return status(root, args.metrics)
        if args.command in ("record", "recheck"):
            lock = _lock(root)
            try: return record(root, args.run_id, args.command == "recheck")
            finally: lock.close()
        if args.command == "run":
            if args.all == bool(args.run_id):
                raise BenchError("provide exactly one run_id or --all")
            if not args.execute:
                raise BenchError("refusing any model launch without the explicit --execute action")
            if args.all and args.attempt != 1:
                raise BenchError("--attempt is supported only with a single run_id")
            mode, cap = resolve_launch_mode(root, args.mode, args.concurrency)
            lock = _lock(root)
            try:
                batch_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
                _write_json(root / f"batch-{batch_id}-launch.json", {"batch_id": batch_id,
                            "launch_mode": mode, "effective_concurrency_cap": cap,
                            "started_utc": datetime.now(timezone.utc).isoformat()})
                _preflight(root)
                if not args.all:
                    return launch_one(root, args.run_id, args.execute, args.timeout, args.attempt, mode, cap, batch_id)
                ids = pending_run_ids(root, run_ids(root, load_suite(root)))
                if not ids:
                    print("All cells are audited PASS completions; no model launch needed")
                    return 0
                pause_marker = root / "operator-runtime" / "PAUSE_DISPATCH"
                paused_boundaries: list[dict[str, Any]] = []
                result = launch_many(ids, mode, cap, lambda rid: launch_one(
                    root, rid, args.execute, args.timeout, 1, mode, cap, batch_id),
                    stop_requested=pause_marker.is_file, paused_boundaries=paused_boundaries)
                if paused_boundaries:
                    runtime = root / "operator-runtime"
                    runtime.mkdir(parents=True, exist_ok=True)
                    _write_json(runtime / f"batch-{batch_id}-paused.json", {
                        "batch_id": batch_id, "status": "PAUSED_AT_BOUNDARY",
                        "launch_mode": mode, "effective_concurrency_cap": cap,
                        **paused_boundaries[-1], "paused_utc": datetime.now(timezone.utc).isoformat(),
                    })
                return result
            finally:
                try:
                    _postflight(root)
                except Exception as exc:
                    print(f"POSTFLIGHT FAIL: {exc}", file=sys.stderr)
                    lock.close()
                    raise
                lock.close()
    except (BenchError, OSError, subprocess.SubprocessError, KeyError, ValueError) as exc:
        print(f"codex_bench: {exc}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    def _cancel_active(_signum, _frame):
        with ACTIVE_LOCK:
            active = list(ACTIVE_PROCESSES)
        for process in active: _terminate_process(process)
        raise KeyboardInterrupt
    signal.signal(signal.SIGINT, _cancel_active)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, _cancel_active)
    raise SystemExit(main())
