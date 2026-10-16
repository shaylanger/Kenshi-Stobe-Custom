"""Read-only live metrics for a single Codex rollout named by a run receipt."""
from __future__ import annotations

import json
import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import codex_record

FROZEN_TOOLS = {"mcp__frozen__list", "mcp__frozen__read", "mcp__frozen__search", "mcp__frozen__sql"}
FORBIDDEN_GLOBALS = {"process", "require", "buffer", "global", "deno", "bun", "fetch",
                    "xmlhttprequest", "websocket", "fs"}


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


def _verify_hostprobe(path: Any, expected_sha256: Any) -> dict:
    """Verify the sanitized isolated-host receipt; never read credentials or logs."""
    if not isinstance(path, str) or not path:
        return {"status": "UNKNOWN", "reason": "hostprobe path missing"}
    try:
        content = Path(path).read_bytes()
    except OSError:
        return {"status": "UNKNOWN", "reason": "hostprobe unavailable"}
    actual = hashlib.sha256(content).hexdigest()
    if not isinstance(expected_sha256, str) or not expected_sha256:
        return {"status": "UNKNOWN", "reason": "hostprobe digest missing"}
    if actual.lower() != expected_sha256.lower():
        return {"status": "FAIL", "reason": "hostprobe digest mismatch"}
    try:
        probe = json.loads(content.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return {"status": "UNKNOWN", "reason": "hostprobe invalid JSON"}
    if not isinstance(probe, dict) or probe.get("kind") != "codex_hostprobe":
        return {"status": "UNKNOWN", "reason": "hostprobe schema missing"}
    if probe.get("status") == "FAIL" or probe.get("cli_returncode") not in (0,):
        return {"status": "FAIL", "reason": "hostprobe reported failure"}
    config = probe.get("config") if isinstance(probe.get("config"), dict) else {}
    provider = probe.get("provider") if isinstance(probe.get("provider"), dict) else {}
    host = probe.get("host") if isinstance(probe.get("host"), dict) else {}
    hooks = probe.get("hooks") if isinstance(probe.get("hooks"), dict) else {}
    required_true = (config.get("code_mode") is True, config.get("code_mode_host") is True)
    required_false = (config.get("shell_tool") is False, config.get("multi_agent") is False,
                      config.get("agents_enabled") is False, config.get("view_image") is False)
    enabled = set(config.get("enabled_tools", [])) if isinstance(config.get("enabled_tools"), list) else set()
    requested = set(probe.get("request_tool_names", [])) if isinstance(probe.get("request_tool_names"), list) else set()
    hosttools = set(host.get("tool_names", [])) if isinstance(host.get("tool_names"), list) else set()
    globals_seen = {str(x).lower() for x in host.get("global_names", [])} if isinstance(host.get("global_names"), list) else None
    forbidden = {str(x).lower() for x in host.get("global_forbidden_names", [])} if isinstance(host.get("global_forbidden_names"), list) else None
    if not all(required_true + required_false):
        return {"status": "UNKNOWN", "reason": "hostprobe config proof incomplete"}
    if enabled != FROZEN_TOOLS | {"exec"} or requested != FROZEN_TOOLS | {"exec"} or hosttools != FROZEN_TOOLS:
        return {"status": "FAIL", "reason": "hostprobe tool allowlist mismatch"}
    if host.get("frozen_list_call") != "ok":
        return {"status": "UNKNOWN", "reason": "frozen list call proof missing"}
    if globals_seen is None or forbidden is None:
        return {"status": "UNKNOWN", "reason": "host global isolation proof missing"}
    if forbidden or globals_seen & FORBIDDEN_GLOBALS:
        return {"status": "FAIL", "reason": "host exposes forbidden globals"}
    hook_counts = (hooks.get("session_start_receipts"), hooks.get("pretool_allowed_frozen"),
                   hooks.get("pretool_denied_nonfrozen"))
    if not all(isinstance(n, int) and n >= 1 for n in hook_counts):
        return {"status": "UNKNOWN", "reason": "guard hook allow/deny receipts incomplete"}
    if (provider.get("bound_host") != "127.0.0.1" or
            not isinstance(provider.get("port_ephemeral"), int) or provider.get("port_ephemeral") <= 0 or
            not isinstance(provider.get("requests_n"), int) or provider.get("requests_n") < 1 or
            provider.get("external_hosts_attempted") != 0 or provider.get("auth") != "dummy"):
        return {"status": "UNKNOWN", "reason": "isolated provider proof incomplete"}
    if not probe.get("cli_sha256") or not probe.get("code_mode_host_sha256"):
        return {"status": "UNKNOWN", "reason": "CLI/host binary identity missing"}
    if probe.get("status") != "PASS":
        return {"status": "UNKNOWN", "reason": "hostprobe did not pass"}
    provider_request = probe.get("provider_request") if isinstance(probe.get("provider_request"), dict) else {}
    requested_tier = probe.get("request_service_tier") or provider_request.get("service_tier")
    return {"status": "PASS", "sha256": actual, "request_service_tier": requested_tier}


def _verify_requested_modes(receipt: dict, rollout_path: str | Path) -> dict:
    """Bind requested model/effort/speed to hashed launch metadata and argv."""
    attempt_dir = Path(receipt.get("attempt_dir") or Path(rollout_path).parent).resolve()
    argv_path = Path(receipt.get("argv_path") or attempt_dir / "argv.json").resolve()
    config_path = Path(receipt.get("requested_config_path") or attempt_dir / "requested-config.json").resolve()
    if argv_path.parent != attempt_dir or config_path.parent != attempt_dir:
        return {"status": "FAIL", "reason": "launch metadata path escaped attempt directory"}
    try:
        argv_bytes = argv_path.read_bytes()
        config_bytes = config_path.read_bytes()
    except OSError:
        return {"status": "UNKNOWN", "reason": "launch metadata unavailable"}
    if hashlib.sha256(config_bytes).hexdigest().lower() != str(receipt.get("config_sha256", "")).lower():
        return {"status": "FAIL", "reason": "requested config digest mismatch"}
    try:
        requested_config = json.loads(config_bytes.decode("utf-8"))
        argv_obj = json.loads(argv_bytes.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return {"status": "UNKNOWN", "reason": "launch metadata invalid JSON"}
    if isinstance(receipt.get("requested_config"), dict) and requested_config != receipt["requested_config"]:
        return {"status": "FAIL", "reason": "requested config copy mismatch"}
    argv = argv_obj.get("argv") if isinstance(argv_obj, dict) else argv_obj
    if not isinstance(argv, list) or not all(isinstance(x, str) for x in argv):
        return {"status": "UNKNOWN", "reason": "argv array missing"}
    argv_digest = hashlib.sha256(json.dumps(argv).encode("utf-8")).hexdigest()
    if argv_digest.lower() != str(receipt.get("argv_sha256", "")).lower():
        return {"status": "FAIL", "reason": "argv digest mismatch"}
    found = {"model": [], "effort": [], "service_tier": []}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--model", "--reasoning-effort", "--service-tier") and i + 1 < len(argv):
            key = {"--model": "model", "--reasoning-effort": "effort", "--service-tier": "service_tier"}[arg]
            found[key].append(argv[i + 1])
            i += 2
            continue
        if arg.startswith("--model="): found["model"].append(arg.split("=", 1)[1])
        elif arg.startswith("--reasoning-effort="): found["effort"].append(arg.split("=", 1)[1])
        elif arg.startswith("--service-tier="): found["service_tier"].append(arg.split("=", 1)[1])
        elif arg == "--config" and i + 1 < len(argv):
            value = argv[i + 1]
            if value.startswith("model_reasoning_effort="): found["effort"].append(value.split("=", 1)[1])
            elif value.startswith("service_tier="): found["service_tier"].append(value.split("=", 1)[1])
            i += 2
            continue
        elif arg.startswith("--config="):
            value = arg.split("=", 1)[1]
            if value.startswith("model_reasoning_effort="): found["effort"].append(value.split("=", 1)[1])
            elif value.startswith("service_tier="): found["service_tier"].append(value.split("=", 1)[1])
        i += 1
    expected = {"model": receipt.get("model"), "effort": receipt.get("effort"),
                "service_tier": receipt.get("service_tier", receipt.get("speed"))}
    missing = [k for k in expected if not expected[k] or not found[k]]
    if missing: return {"status": "UNKNOWN", "reason": "requested launch values missing: " + ",".join(missing)}
    normalized = {k: [codex_record._normalize_tier(v) if k == "service_tier" else v for v in vals]
                  for k, vals in found.items()}
    expected["service_tier"] = codex_record._normalize_tier(expected["service_tier"])
    for key, value in expected.items():
        if len(set(normalized[key])) != 1 or normalized[key][0] != value:
            return {"status": "FAIL", "reason": "requested launch value mismatch: " + key}
    return {"status": "PASS", "config_sha256": hashlib.sha256(config_bytes).hexdigest(),
            "argv_sha256": argv_digest, "model": expected["model"], "effort": expected["effort"],
            "service_tier": expected["service_tier"]}


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
    launch_modes = _verify_requested_modes(receipt, rollout)
    hostprobe = _verify_hostprobe(receipt.get("hostprobe_path"), receipt.get("hostprobe_sha256"))
    config["code_mode_host_proof"] = {"verified": hostprobe["status"] == "PASS"}
    try:
        parsed = codex_record.parse_rollout(rollout, config, prices, include_report=False)
    except OSError as exc:
        return {"run": receipt.get("run"), "status": receipt.get("status", "unknown"),
                "elapsed_s": elapsed, "audit": "UNKNOWN", "reason": "rollout unavailable: " + str(exc)}
    threads = _rollout_threads(rollout)
    in_progress = str(receipt.get("status", "")).lower() in ("running", "in_progress", "started")
    audit_status = parsed["audit"]["status"]
    overall_status = parsed["audit"].get("overall_status", audit_status)
    if in_progress:
        audit_status = "UNKNOWN"
        overall_status = "UNKNOWN"
    if threads["provenance"] in ("child", "ambiguous"):
        audit_status = "FAIL"
        overall_status = "FAIL"
    elif threads["provenance"] == "unknown" and not in_progress:
        overall_status = "UNKNOWN"
    uses_code_mode = any(str(t.get("name", "")).lower() in ("exec", "functions.exec")
                         for t in parsed.get("tools", []))
    if uses_code_mode and hostprobe["status"] != "PASS":
        if hostprobe["status"] == "FAIL": audit_status, overall_status = "FAIL", "FAIL"
        elif audit_status != "FAIL": audit_status, overall_status = "UNKNOWN", "UNKNOWN"
    usage = parsed.get("usage") or {}
    transport_calls = sum(str(t.get("name", "")).lower() in ("exec", "functions.exec", "wait")
                          for t in parsed.get("tools", []))
    direct_tool_calls = parsed.get("tool_uses", 0) - transport_calls
    mcp_receipts_verified = receipt.get("frozen_mcp_call_receipts_verified") is True
    frozen_mcp_calls = receipt.get("frozen_mcp_calls") if mcp_receipts_verified else None
    if not isinstance(frozen_mcp_calls, int) or frozen_mcp_calls < 0:
        frozen_mcp_calls = None
        mcp_receipts_verified = False
    requested_tier = codex_record._normalize_tier(config.get("service_tier"))
    hostprobe_tier = codex_record._normalize_tier(hostprobe.get("request_service_tier"))
    tier_request_status = "UNKNOWN"
    if launch_modes["status"] == "FAIL":
        tier_request_status = "FAIL"
    elif launch_modes["status"] == "PASS" and requested_tier and hostprobe_tier:
        tier_request_status = "PASS" if requested_tier == hostprobe_tier else "FAIL"
    elif launch_modes["status"] == "PASS" and requested_tier and hostprobe_tier is None:
        tier_request_status = "UNKNOWN"
    if launch_modes["status"] == "FAIL" or tier_request_status == "FAIL":
        audit_status, overall_status = "FAIL", "FAIL"
    elif launch_modes["status"] != "PASS" or tier_request_status != "PASS":
        if audit_status != "FAIL": audit_status = "UNKNOWN"
        if overall_status != "FAIL": overall_status = "UNKNOWN"
    return {
        "run": receipt.get("run"), "status": receipt.get("status", "unknown"),
        "elapsed_s": elapsed, "model": parsed.get("model"), "effort": parsed.get("effort"),
        "requested_model": receipt.get("model"), "requested_effort": receipt.get("effort"),
        "requested_service_tier": config.get("service_tier"),
        "hostprobe_requested_service_tier": hostprobe.get("request_service_tier"),
        "requested_tier_proof": tier_request_status,
        "launch_mode_proof": launch_modes,
        "observed_service_tier": parsed.get("observed_service_tier"),
        "usage": {k: usage.get(k) for k in codex_record.TOKENS},
        "tool_uses": parsed.get("tool_uses", 0),
        "transport_calls": transport_calls,
        "direct_tool_calls": direct_tool_calls,
        "frozen_mcp_calls": frozen_mcp_calls,
        "frozen_mcp_call_receipts_verified": mcp_receipts_verified,
        "tool_outputs": parsed.get("tool_outputs", 0),
        "matched_tool_outputs": parsed.get("matched_tool_outputs", 0),
        "pending_tool_calls": parsed.get("pending_tool_calls", 0),
        "unmatched_tool_outputs": parsed.get("unmatched_tool_outputs", 0),
        "cost": parsed.get("pricing"), "audit": audit_status, "overall_status": overall_status,
        "audit_flags": parsed["audit"].get("flags", []),
        "audit_unknown_reasons": parsed["audit"].get("unknown_reasons", []),
        "audit_dimensions": {**parsed["audit"].get("dimensions", {}),
                             "launch_mode": launch_modes["status"],
                             "requested_service_tier": tier_request_status},
        "thread": threads, "code_mode_host": hostprobe,
    }
