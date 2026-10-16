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
EXCLUDED_NAMESPACES = ["functions", "clock", "mcp__codex_apps", "mcp__plugins"]
OUTER_TOOL_NAMES = {"functions__exec", "functions__wait", "functions__request_user_input",
                    "functions__request_user_input_async", "clock__sleep"}
AGENT_APIS = {"spawn_agent", "delegate", "subagent", "collaboration"}
FORBIDDEN_GLOBALS = {"process", "require", "buffer", "global", "deno", "bun", "fetch",
                    "xmlhttprequest", "websocket", "webtransport", "eventsource", "navigator",
                    "filesystem", "fs", "child_process"}


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
    """Verify the sanitized hard-boundary receipt; hook status is metadata only."""
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
    if probe.get("status") == "FAIL":
        return {"status": "FAIL", "reason": "hostprobe reported failure"}
    if probe.get("status") == "FAIL" or isinstance(probe.get("cli_returncode"), int) and probe["cli_returncode"] != 0:
        return {"status": "FAIL", "reason": "hostprobe reported failure"}
    if probe.get("status") is None or probe.get("cli_returncode") is None:
        return {"status": "UNKNOWN", "reason": "hostprobe completion proof missing"}
    config = probe.get("config") if isinstance(probe.get("config"), dict) else {}
    provider = probe.get("provider") if isinstance(probe.get("provider"), dict) else {}
    host = probe.get("host") if isinstance(probe.get("host"), dict) else {}
    true_keys = ("code_mode", "code_mode_host")
    false_keys = ("shell_tool", "multi_agent", "agents_enabled", "view_image", "hooks_enabled")
    if any(k in config and config[k] is not True for k in true_keys) or any(k in config and config[k] is not False for k in false_keys):
        return {"status": "FAIL", "reason": "hostprobe contains unsafe configuration"}
    required_true = all(config.get(k) is True for k in true_keys)
    required_false = all(config.get(k) is False for k in false_keys)
    if not required_true or not required_false:
        return {"status": "UNKNOWN", "reason": "hostprobe config proof incomplete"}
    configured_tools = config.get("mcp_tools")
    excluded_namespaces = config.get("excluded_tool_namespaces")
    request_tools = probe.get("request_tool_names")
    if not isinstance(configured_tools, list) or not isinstance(excluded_namespaces, list):
        return {"status": "UNKNOWN", "reason": "hostprobe MCP boundary config missing"}
    if configured_tools != sorted(FROZEN_TOOLS) or excluded_namespaces != EXCLUDED_NAMESPACES:
        return {"status": "FAIL", "reason": "hostprobe MCP/native namespace boundary mismatch"}
    if not isinstance(request_tools, list):
        return {"status": "UNKNOWN", "reason": "outer transport tool list missing"}
    normalized_request = {str(x).replace(".", "__") for x in request_tools}
    normalized_request.discard("exec")
    if not normalized_request or not normalized_request <= OUTER_TOOL_NAMES or "functions__exec" not in normalized_request:
        return {"status": "FAIL", "reason": "outer transport tool allowlist mismatch"}
    tool_fields = ("tool_names", "tool_namespace_keys", "callable_names")
    if any(not isinstance(host.get(k), list) for k in tool_fields):
        return {"status": "UNKNOWN", "reason": "nested callable inventory incomplete"}
    if any(set(host[k]) != FROZEN_TOOLS or len(host[k]) != len(FROZEN_TOOLS) for k in tool_fields):
        return {"status": "FAIL", "reason": "nested callable inventory contains unlisted tools"}
    if not isinstance(host.get("unlisted_callable_names"), list):
        return {"status": "UNKNOWN", "reason": "unlisted callable proof missing"}
    if host.get("unlisted_callable_names"):
        return {"status": "FAIL", "reason": "host exposes unlisted callables"}
    forbidden_value = host.get("forbidden_global_names")
    if not isinstance(forbidden_value, list):
        return {"status": "UNKNOWN", "reason": "host global isolation proof missing"}
    forbidden = {str(x).lower() for x in forbidden_value}
    globals_seen = host.get("global_names")
    if forbidden or (isinstance(globals_seen, list) and {str(x).lower() for x in globals_seen} & FORBIDDEN_GLOBALS):
        return {"status": "FAIL", "reason": "host exposes forbidden globals"}
    agent_types = host.get("agent_api_types")
    if not isinstance(agent_types, dict) or not AGENT_APIS <= set(agent_types):
        return {"status": "UNKNOWN", "reason": "agent API isolation proof incomplete"}
    for api in AGENT_APIS:
        values = agent_types[api]
        if isinstance(values, dict):
            if values.get("global") not in ("undefined", False) or values.get("tool") not in ("undefined", False):
                return {"status": "FAIL", "reason": "agent API is exposed"}
        elif values not in ("undefined", False):
            return {"status": "FAIL", "reason": "agent API is exposed"}
    list_result = host.get("frozen_list_call")
    if isinstance(list_result, dict): list_ok = list_result.get("isError") is False
    else: list_ok = list_result == "ok"
    unknown_status = host.get("unknown_parameter_status")
    unknown_error = host.get("unknown_parameter_isError")
    strict_reject = unknown_status == "server_rejected" and unknown_error is True
    mcp_calls = probe.get("mcp_calls")
    if not isinstance(mcp_calls, list):
        return {"status": "UNKNOWN", "reason": "MCP call receipts missing"}
    list_receipt = any(isinstance(c, dict) and c.get("tool") == "mcp__frozen__list" and
                       c.get("isError") is False and c.get("result_class") == "ok" for c in mcp_calls)
    error_receipt = any(isinstance(c, dict) and c.get("tool") == "mcp__frozen__list" and
                        c.get("isError") is True and isinstance(c.get("result_class"), str) and
                        c["result_class"].startswith("error:") for c in mcp_calls)
    if not list_ok or not list_receipt or not strict_reject or not error_receipt:
        return {"status": "FAIL" if mcp_calls else "UNKNOWN",
                "reason": "strict MCP success/error proof missing"}
    external_hosts = provider.get("external_hosts_attempted", provider.get("external_hosts"))
    auth_mode = provider.get("auth", provider.get("credential"))
    if (("bound_host" in provider and provider.get("bound_host") != "127.0.0.1") or
            (external_hosts is not None and external_hosts != 0) or
            (auth_mode is not None and auth_mode not in ("dummy", "dummy_credentials"))):
        return {"status": "FAIL", "reason": "isolated provider constraints violated"}
    request_count = provider.get("requests_n", provider.get("requests"))
    ephemeral = provider.get("port_ephemeral") is True or (isinstance(provider.get("port_ephemeral"), int) and
                 not isinstance(provider.get("port_ephemeral"), bool) and provider.get("port_ephemeral") > 0)
    if (provider.get("bound_host") != "127.0.0.1" or not ephemeral or
            not isinstance(request_count, int) or request_count < 1 or
            external_hosts != 0 or auth_mode not in ("dummy", "dummy_credentials")):
        return {"status": "UNKNOWN", "reason": "isolated provider proof incomplete"}
    host_hash = probe.get("code_mode_host_sha256", probe.get("host_sha256"))
    if not isinstance(probe.get("cli_sha256"), str) or not probe["cli_sha256"] or not isinstance(host_hash, str) or not host_hash:
        return {"status": "UNKNOWN", "reason": "CLI/host binary identity missing"}
    hook_enforcement = probe.get("hook_enforcement") if isinstance(probe.get("hook_enforcement"), dict) else {}
    hook_status = hook_enforcement.get("status", "UNKNOWN")
    if hook_status == "UNAVAILABLE" and (hook_enforcement.get("stdin_type") != 2 or
            hook_enforcement.get("bytes_received") != 0 or hook_enforcement.get("errno") in (None, 0)):
        hook_status = "UNKNOWN"
    if hook_status not in ("UNAVAILABLE", "PASS", "UNKNOWN"):
        return {"status": "FAIL", "reason": "hook evidence reports failure"}
    if probe.get("status") != "PASS":
        return {"status": "UNKNOWN", "reason": "hostprobe did not pass"}
    provider_request = probe.get("provider_request") if isinstance(probe.get("provider_request"), dict) else {}
    requested_tier = probe.get("request_service_tier") or provider_request.get("service_tier")
    return {"status": "PASS", "sha256": actual, "request_service_tier": requested_tier,
            "hook_enforcement": {"status": hook_status,
                                 "stdin_type": hook_enforcement.get("stdin_type"),
                                 "bytes_received": hook_enforcement.get("bytes_received"),
                                 "errno": hook_enforcement.get("errno")}}


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
    config_digest = receipt.get("config_sha256")
    argv_expected_digest = receipt.get("argv_sha256")
    if not isinstance(config_digest, str) or not config_digest or not isinstance(argv_expected_digest, str) or not argv_expected_digest:
        return {"status": "UNKNOWN", "reason": "launch metadata digest missing"}
    if hashlib.sha256(config_bytes).hexdigest().lower() != config_digest.lower():
        return {"status": "FAIL", "reason": "requested config digest mismatch"}
    try:
        requested_config = json.loads(config_bytes.decode("utf-8"))
        argv_obj = json.loads(argv_bytes.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return {"status": "UNKNOWN", "reason": "launch metadata invalid JSON"}
    if not isinstance(receipt.get("requested_config"), dict):
        return {"status": "UNKNOWN", "reason": "requested config receipt copy missing"}
    if requested_config != receipt["requested_config"]:
        return {"status": "FAIL", "reason": "requested config copy mismatch"}
    argv = argv_obj.get("argv") if isinstance(argv_obj, dict) else argv_obj
    if not isinstance(argv, list) or not all(isinstance(x, str) for x in argv):
        return {"status": "UNKNOWN", "reason": "argv array missing"}
    argv_digest = hashlib.sha256(json.dumps(argv).encode("utf-8")).hexdigest()
    if argv_digest.lower() != argv_expected_digest.lower():
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
    boundary_receipt = receipt.get("code_mode_host_proof") if isinstance(receipt.get("code_mode_host_proof"), dict) else {}
    hostprobe_path = (receipt.get("hostprobe_path") or boundary_receipt.get("path") or
                      receipt.get("execution_boundary_path"))
    hostprobe_sha256 = (receipt.get("hostprobe_sha256") or boundary_receipt.get("sha256") or
                        receipt.get("execution_boundary_sha256"))
    hostprobe = _verify_hostprobe(hostprobe_path, hostprobe_sha256)
    config["code_mode_host_proof"] = {"verified": hostprobe["status"] == "PASS"}
    config["hook_enforcement"] = hostprobe.get("hook_enforcement", {"status": "UNKNOWN"})
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
    requested_tier_status = launch_modes["status"] if requested_tier else "UNKNOWN"
    hostprobe_tier_status = "UNKNOWN"
    if hostprobe_tier is not None and requested_tier is not None:
        hostprobe_tier_status = "PASS" if requested_tier == hostprobe_tier else "FAIL"
    if launch_modes["status"] == "FAIL" or hostprobe_tier_status == "FAIL":
        audit_status, overall_status = "FAIL", "FAIL"
    elif launch_modes["status"] != "PASS":
        if audit_status != "FAIL": audit_status = "UNKNOWN"
        if overall_status != "FAIL": overall_status = "UNKNOWN"
    elif hostprobe_tier_status == "UNKNOWN" and overall_status != "FAIL":
        overall_status = "UNKNOWN"
    return {
        "run": receipt.get("run"), "status": receipt.get("status", "unknown"),
        "elapsed_s": elapsed, "model": parsed.get("model"), "effort": parsed.get("effort"),
        "requested_model": receipt.get("model"), "requested_effort": receipt.get("effort"),
        "requested_service_tier": config.get("service_tier"),
        "hostprobe_requested_service_tier": hostprobe.get("request_service_tier"),
        "requested_tier_proof": requested_tier_status,
        "hostprobe_tier_request_proof": hostprobe_tier_status,
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
                             "requested_service_tier": requested_tier_status,
                             "hostprobe_service_tier_request": hostprobe_tier_status},
        "thread": threads, "code_mode_host": hostprobe,
    }
