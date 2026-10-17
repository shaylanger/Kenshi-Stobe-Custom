"""Parse and audit a Codex rollout JSONL transcript (stdlib only).

This module deliberately treats incomplete provenance, pricing, and policy evidence
as unknown. It never infers a price or a single-agent configuration from absence.
"""
from __future__ import annotations

import csv
import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

CORE_COLUMNS = ["run", "model", "effort", "prompt", "start_local", "end_local", "wall_s",
                "tool_uses", "input", "output", "cache_read", "cache_create", "token_usd",
                "q5h_before", "q5h_after", "qweek_before", "qweek_after", "report_bytes",
                "headers", "citations", "diff_markers", "violation_flags", "agent",
                "cost_status", "cost_basis", "requested_tier", "served_tier", "invoice_status",
                "price_table_date", "currency", "cost_reason"]
TOKENS = ("input_tokens", "cached_input_tokens", "cache_write_input_tokens",
          "output_tokens", "reasoning_output_tokens", "total_tokens")
MUTATING_NAMES = {"write", "edit", "notebookedit", "apply_patch", "create_file", "delete_file",
                  "move_file", "copy_file", "exec_command_write"}
READ_NAMES = {"read", "read_file", "open_file", "glob", "grep", "search", "list_dir"}
LIVE_MARKERS = ("/var/www/html/stobeserver", "/root/stobe-work", "/root/stobe-src",
                "c:/stobebuild", "d:/steam/steamapps/common/kenshi", "pending-fixes")
MUT_RE = re.compile(r"(?:^|[;&|\s])(?:rm|mv|cp|chmod|chown|tee|git\s+(?:commit|checkout|reset|stash|add|clean|restore|push|apply)|"
                    r"(?:sudo\s+)?(?:apt|apt-get|systemctl|service)\s|(?:curl|wget)\s+.*(?:-X\s*(?:POST|PUT|DELETE)|--data|-d\s)|"
                    r"(?:psql|sqlite3)\s+.*\b(?:insert|update|delete|drop|alter|truncate|create|grant|vacuum)\b|"
                    r"(?:set-content|out-file|add-content|remove-item|move-item|copy-item|new-item|rename-item|clear-content)\b|"
                    r"[^\n]+(?:>|>>)[^=])", re.I)
NESTED_RE = re.compile(r"\b(codex|claude|openai\s+api|anthropic\s+api|responses\.create|chat\.completions\.create)\b", re.I)
INFRA_TOOL_ERROR_RE = re.compile(
    r"\b(?:TimeoutExpired|FrozenDBTimeoutError|timeout|timed out|deadline exceeded|etimedout|connection (?:refused|reset|closed|aborted)|"
    r"(?:service|server|transport) unavailable|transport (?:error|closed|failed)|"
    r"(?:failed|unable) to start|code[- ]mode host is disabled|"
    r"(?:approval|authorization) (?:handler )?(?:unavailable|not available|failed)|"
    r"no approval (?:handler|provider)|(?:authentication|credentials?) (?:failed|unavailable|missing))\b", re.I)


def _walk(obj: Any) -> Iterable[dict]:
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from _walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from _walk(value)


def _tool_calls(obj: dict) -> list[dict]:
    out = []
    # Only the actual response item is authoritative. Do not recurse into prompt
    # text, tool output, or arbitrary nested result data that may resemble a call.
    if str(obj.get("type", "")).lower() == "response_item":
        p = obj.get("payload") or obj.get("item") or {}
        if isinstance(p, dict) and str(p.get("type", "")).lower() in ("function_call", "tool_use", "custom_tool_call"):
            out.append(p)
    elif str(obj.get("type", "")).lower() in ("function_call", "tool_use", "custom_tool_call"):
        out.append(obj)
    # Parent and nested item may identify the same call. De-duplicate by call id.
    result, seen = [], set()
    for call in out:
        key = call.get("call_id") or call.get("id")
        if key and key in seen:
            continue
        if key:
            seen.add(key)
        result.append(call)
    return result


def _tool_output_stats(events: list[dict], calls: list[dict]) -> dict:
    call_ids = {c.get("call_id") or c.get("id") for c in calls if c.get("call_id") or c.get("id")}
    outputs, matched, unmatched = set(), set(), 0
    for event in events:
        if str(event.get("type", "")).lower() != "response_item": continue
        item = event.get("payload") or event.get("item") or {}
        if not isinstance(item, dict) or str(item.get("type", "")).lower() not in ("custom_tool_call_output", "function_call_output"):
            continue
        key = item.get("call_id") or item.get("id")
        if key and key in outputs: continue
        if key: outputs.add(key)
        if key and key in call_ids: matched.add(key)
        else: unmatched += 1
    return {"tool_outputs": len(outputs), "matched_tool_outputs": len(matched),
            "pending_tool_calls": len(call_ids - matched), "unmatched_tool_outputs": unmatched}


def _tool_health(events: list[dict], calls: list[dict]) -> dict:
    """Classify only explicit tool-result metadata; never search returned content."""
    calls_by_id = {c.get("call_id") or c.get("id"): c for c in calls
                   if c.get("call_id") or c.get("id")}
    errors, infrastructure = [], []
    for event in events:
        if str(event.get("type", "")).lower() != "response_item": continue
        item = event.get("payload") or event.get("item") or {}
        if not isinstance(item, dict) or str(item.get("type", "")).lower() not in (
                "custom_tool_call_output", "function_call_output"):
            continue
        call_id = item.get("call_id") or item.get("id")
        call = calls_by_id.get(call_id, {})
        name = str(call.get("name") or call.get("tool_name") or "unknown")
        metadata = [item.get(k) for k in ("error_class", "error_code", "code", "status", "result_class")
                    if isinstance(item.get(k), str)]
        metadata_error = any(v.lower().startswith("error") or
                             v.lower() in ("timeout", "timed_out", "failed", "unavailable")
                             for v in metadata)
        infra_match = next((INFRA_TOOL_ERROR_RE.search(v) for v in metadata
                            if INFRA_TOOL_ERROR_RE.search(v)), None)
        is_error = item.get("isError") is True or metadata_error or infra_match is not None
        if is_error or infra_match:
            classification = "infrastructure" if infra_match else "tool_error"
            summary = {"tool": name, "call_id": call_id if isinstance(call_id, str) else None,
                       "classification": classification}
            errors.append(summary)
            if classification == "infrastructure":
                infrastructure.append({**summary, "error_class": next(
                    (v for v in metadata if INFRA_TOOL_ERROR_RE.search(v)), "transport_failure")})
    return {"status": "FAIL" if infrastructure else "PASS",
            "infrastructure_failures": infrastructure, "tool_error_count": len(errors),
            "noninfrastructure_error_count": len(errors) - len(infrastructure),
            "tool_errors": errors}


def _cli_event_health(path: str | Path | None) -> dict:
    """Inspect only structured MCP failure events, never successful result payloads."""
    if not path:
        return {"status": "UNKNOWN", "infrastructure_failures": [], "source": None}
    failures, malformed = [], 0
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for line in stream:
                try: event = json.loads(line)
                except ValueError:
                    malformed += 1
                    continue
                if not isinstance(event, dict): continue
                item = event.get("item")
                if not isinstance(item, dict) or item.get("type") != "mcp_tool_call" or item.get("status") != "failed":
                    continue
                err = item.get("error")
                message = err.get("message") if isinstance(err, dict) else None
                if not isinstance(message, str): continue
                match = INFRA_TOOL_ERROR_RE.search(message)
                if match:
                    failures.append({"tool": item.get("tool") if isinstance(item.get("tool"), str) else "unknown",
                                     "call_id": item.get("id") if isinstance(item.get("id"), str) else None,
                                     "classification": "infrastructure", "error_class": "transport_failure"})
    except OSError:
        return {"status": "UNKNOWN", "infrastructure_failures": [], "source": str(path)}
    return {"status": "FAIL" if failures else "PASS", "infrastructure_failures": failures,
            "malformed_lines": malformed, "source": str(path)}


def _merge_setup_health(rollout_health: dict, cli_health: dict) -> dict:
    failures = rollout_health.get("infrastructure_failures", []) + cli_health.get("infrastructure_failures", [])
    status = "FAIL" if failures else ("UNKNOWN" if cli_health.get("status") == "UNKNOWN" else "PASS")
    return {"status": status, "infrastructure_failures": failures,
            "tool_error_count": rollout_health.get("tool_error_count", 0),
            "noninfrastructure_error_count": rollout_health.get("noninfrastructure_error_count", 0),
            "cli_events": {"status": cli_health.get("status"), "source": cli_health.get("source"),
                           "malformed_lines": cli_health.get("malformed_lines", 0)}}


def _config_proof_summary(config: dict | None) -> dict | None:
    """Keep audit receipts acyclic and omit unrelated paths, prompts, and data."""
    if not isinstance(config, dict): return None
    summary = {}
    for key in ("verified_receipt", "model", "effort", "service_tier", "agents_enabled",
                "multi_agent", "hook_verified", "terminal_verified"):
        value = config.get(key)
        if isinstance(value, (str, int, float, bool)) or value is None:
            if key in config: summary[key] = value
    tools = config.get("allowed_tools")
    if isinstance(tools, list) and all(isinstance(x, str) for x in tools):
        summary["allowed_tools"] = list(tools)
    boundary = config.get("code_mode_host_proof")
    if isinstance(boundary, dict):
        summary["code_mode_host_proof"] = {"verified": boundary.get("verified") is True,
                                           "status": boundary.get("status") if isinstance(boundary.get("status"), str) else None}
    hook_state = config.get("hook_enforcement")
    if isinstance(hook_state, dict):
        summary["hook_enforcement"] = {"status": hook_state.get("status") if isinstance(hook_state.get("status"), str) else "UNKNOWN"}
    return summary


def _count_vector(value: Any) -> dict | None:
    if not isinstance(value, dict): return None
    return {k: value[k] for k in TOKENS if isinstance(value.get(k), (int, float))}


def _usage_data(events: list[dict]) -> tuple[dict | None, list[dict], list[str]]:
    """Return cumulative totals plus request deltas, deduping repeated snapshots."""
    latest = None
    previous = None
    requests, errors, seen = [], [], set()
    for event in events:
        if str(event.get("type", "")).lower() != "event_msg": continue
        payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
        if str(payload.get("type", "")).lower() != "token_count": continue
        info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
        cumulative = _count_vector(info.get("total_token_usage"))
        last = _count_vector(info.get("last_token_usage"))
        if cumulative is None: continue
        signature = tuple(cumulative.get(k) for k in TOKENS)
        if signature in seen: continue
        seen.add(signature)
        if previous is not None and any(cumulative.get(k, 0) < previous.get(k, 0) for k in TOKENS):
            errors.append("cumulative token counter reset/decreased")
            previous = cumulative
            latest = cumulative
            continue
        delta = {k: cumulative.get(k, 0) - (previous.get(k, 0) if previous else 0) for k in TOKENS if k in cumulative or previous and k in previous}
        if last is not None:
            # Prefer provider-reported last request counters, but cross-check them
            # against the cumulative delta when all comparable fields are present.
            comparable = [k for k in last if k in delta]
            if any(last[k] != delta[k] for k in comparable):
                errors.append("last_token_usage does not match cumulative delta")
            else:
                requests.append(last)
        elif delta.get("total_tokens", 0) > 0:
            requests.append(delta)
        latest = cumulative
        previous = cumulative
    if latest is None: return None, [], errors
    latest = dict(latest)
    latest["requests"] = requests
    if errors: latest["request_usage_errors"] = errors
    return latest, requests, errors


def _timestamp(obj: dict) -> str | None:
    for k in ("timestamp", "created_at", "time"):
        v = obj.get(k)
        if isinstance(v, str) and re.match(r"^\d{4}-\d\d-\d\d[T ]", v):
            return v
    return None


def _final_text(obj: dict) -> str | None:
    # Standard Codex rollout: response_item with payload role=assistant and
    # content [{type:output_text,text:...}], final when phase/status says final.
    candidates = []
    for d in obj.get("events", []):
        # Codex CLI emits the root assistant answer as event_msg/agent_message.
        # This is a root answer event, not evidence of delegated agents.
        payload = d.get("payload") if isinstance(d.get("payload"), dict) else {}
        if (str(d.get("type", "")).lower() == "event_msg" and
                str(payload.get("type", "")).lower() == "agent_message"):
            value = payload.get("message") or payload.get("text")
            if isinstance(value, str) and (payload.get("phase") == "final_answer" or payload.get("channel") == "final"):
                candidates.append(value)
        if str(d.get("type", "")).lower() == "response_item":
            p = d.get("payload") or d.get("item") or {}
            if isinstance(p, dict) and p.get("role") == "assistant":
                text = "".join(str(b.get("text", "")) for b in p.get("content", [])
                               if isinstance(b, dict) and b.get("type") in ("output_text", "text"))
                if text and (p.get("phase") == "final_answer" or p.get("channel") == "final"):
                    candidates.append(text)
        # Alternate exported shape, only at the top level.
        if d.get("type") == "final_message" and isinstance(d.get("text"), str):
            candidates.append(d["text"])
    return candidates[-1] if candidates else None


def _input(call: dict) -> dict:
    value = call.get("arguments", call.get("input", {}))
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            return {"_raw": value}
    return value if isinstance(value, dict) else {"_raw": value}


def audit_rollout(events: list[dict], config: dict | None) -> dict:
    calls = [c for e in events for c in _tool_calls(e)]
    flags, reasons, delegation = [], [], []
    setup_health = _tool_health(events, calls)
    flags.extend("setup-infrastructure:" + str(e.get("error_class", "transport_failure"))
                 for e in setup_health["infrastructure_failures"])
    if (not isinstance(config, dict) or config.get("verified_receipt") is not True or
            config.get("agents_enabled") is not False or config.get("multi_agent") is not False):
        reasons.append("verified launch receipt must prove agents.enabled=false and multi_agent=false")
    if isinstance(config, dict) and (config.get("agents_enabled") is True or config.get("multi_agent") is True):
        flags.append("delegation-config-enabled")
    # Only explicitly approved read-only tools are permitted. Names are canonical
    # tool names as recorded in function_call payloads.
    allowed = {str(x).lower() for x in config.get("allowed_tools", [])} if isinstance(config, dict) and isinstance(config.get("allowed_tools"), list) else set()
    host_proof = config.get("code_mode_host_proof") if isinstance(config, dict) else None
    verified_transport_boundary = isinstance(host_proof, dict) and host_proof.get("verified") is True
    # The frozen MCP allowlist describes nested data tools. The public Code Mode
    # transport (exec/wait) is separately authorized by the verified host proof.
    transport_allowed = {"exec", "functions.exec", "wait"} if verified_transport_boundary else set()
    if not isinstance(config, dict) or not isinstance(config.get("allowed_tools"), list):
        reasons.append("verified read-only tool allowlist missing")
    for c in calls:
        name = str(c.get("name") or c.get("tool_name") or "").lower()
        args = _input(c)
        serialized = json.dumps(args, ensure_ascii=False, default=str)
        if ("spawn_agent" in name or "collaboration" in name or
                name in ("create_thread", "fork_thread", "resume_agent", "send_input")):
            delegation.append(name or "unknown delegation tool")
        if "child_thread" in serialized.lower() or "agent_id" in serialized.lower() or "thread_id" in serialized.lower() and name in ("spawn_agent", "create_thread"):
            delegation.append("child metadata in tool input")
        if name in MUTATING_NAMES or name in {"bash", "powershell", "exec_command"} and MUT_RE.search(str(args.get("command", args.get("cmd", "")))):
            flags.append("mutation:" + (name or "unknown-tool"))
        if name in READ_NAMES or name in ("bash", "powershell", "exec_command"):
            for k, v in args.items():
                if isinstance(v, str) and any(x in v.lower().replace("\\", "/") for x in LIVE_MARKERS):
                    flags.append("prohibited-read:" + k)
        cmd = str(args.get("command", args.get("cmd", "")))
        if name in ("bash", "powershell", "exec_command") and NESTED_RE.search(cmd):
            flags.append("nested-model-or-api-command")
        if name in ("exec", "functions.exec", "code", "javascript"):
            source = json.dumps(args, ensure_ascii=False, default=str)
            if re.search(r"(?:collaboration\.(?:spawn_agent|followup_task)|spawn_agent\s*\(|mcp__codex_app__(?:create_thread|fork_thread)|send_message_to_thread)", source, re.I):
                delegation.append("code-mode delegation invocation")
            if NESTED_RE.search(source):
                flags.append("nested-model-or-api-command")
        if name not in allowed and name not in transport_allowed:
            flags.append("unallowlisted-tool:" + (name or "unknown"))
        if name in ("exec", "functions.exec") and name in allowed:
            # `exec` is the required public Code Mode transport, not proof that the
            # restricted host actually supplied only the frozen read-only tools.
            if not verified_transport_boundary:
                reasons.append("Code Mode exec host/guard proof missing")
    for e in events:
        # Inspect event metadata only; do not scan arbitrary tool results or prompt text.
        typ = str(e.get("type", "")).lower()
        payload = e.get("payload") if isinstance(e.get("payload"), dict) else {}
        marker = str(payload.get("type", payload.get("kind", ""))).lower()
        if any(x in (typ + " " + marker) for x in ("subagent", "child_thread", "subagent_message", "child_agent")):
            delegation.append("rollout child/agent event:" + (typ + "/" + marker))
        if typ in ("turn_context", "session_context", "provider_metadata"):
            metadata = dict(e)
            metadata.update(payload)
            if any(k in metadata for k in ("child_thread_id", "agent_id", "subagent_id", "child_agents")):
                delegation.append("child/agent metadata in rollout context")
    if isinstance(config, dict) and config.get("hook_verified") is not True:
        host_proof = config.get("code_mode_host_proof")
        hook_state = config.get("hook_enforcement")
        hard_boundary_verified = isinstance(host_proof, dict) and host_proof.get("verified") is True
        hook_unavailable = isinstance(hook_state, dict) and hook_state.get("status") == "UNAVAILABLE"
        if not (hard_boundary_verified and hook_unavailable):
            reasons.append("pre-tool policy hook verification missing and hard-boundary proof unavailable")
    if isinstance(config, dict) and config.get("terminal_verified") is not True:
        reasons.append("complete terminal event not verified")
    if delegation:
        flags.extend("delegation:" + d for d in delegation)
    status = "FAIL" if flags else ("UNKNOWN" if reasons else "PASS")
    return {"status": status, "flags": sorted(set(flags)), "unknown_reasons": reasons,
            "delegation_evidence": delegation, "setup_health": setup_health,
            "config_proof": _config_proof_summary(config)}


def price_usage(usage: dict | None, model: str | None, tier: str | None,
                table: dict | None) -> dict:
    if not usage:
        return {"usd": None, "status": "unavailable", "reasons": ["token usage absent"]}
    if usage.get("request_usage_errors"):
        return {"usd": None, "status": "unavailable", "reasons": list(usage["request_usage_errors"])}
    if not isinstance(table, dict) or not isinstance(table.get("models"), dict):
        return {"usd": None, "status": "unavailable", "reasons": ["dated price table unavailable"]}
    entry = table["models"].get(model or "")
    if not isinstance(entry, dict):
        return {"usd": None, "status": "unavailable", "reasons": ["model price missing"]}
    tier = _normalize_tier(tier or usage.get("service_tier") or entry.get("service_tier"))
    prices = entry.get(tier) if tier else None
    requests = usage.get("requests")
    if isinstance(prices, dict) and "short" in prices and "long" in prices:
        # Long-context thresholds apply per request. Aggregate totals cannot safely
        # establish which rates applied.
        if not isinstance(requests, list) or not requests:
            return {"usd": None, "status": "unavailable", "reasons": ["aggregate usage cannot resolve per-request short/long pricing"]}
        threshold = entry.get("threshold_tokens")
        if not isinstance(threshold, (int, float)):
            return {"usd": None, "status": "unavailable", "reasons": ["long-tier threshold missing"]}
        total = 0.0
        per_request = []
        for req in requests:
            request_in = req.get("input_tokens")
            if not isinstance(request_in, (int, float)):
                return {"usd": None, "status": "unavailable", "reasons": ["request input count missing"]}
            rate = prices["long" if request_in > threshold else "short"]
            cost = _price_counts(req, rate)
            if cost["usd"] is None: return cost
            total += cost["usd"]
            per_request.append({"request_id": req.get("request_id"), "tier": "long" if request_in > threshold else "short", "usd": cost["usd"]})
        return {"usd": total, "status": "priced", "tier": tier, "requests": per_request,
                "price_table_date": table.get("date")}
    if isinstance(prices, dict) and isinstance(prices.get("short"), (int, float)):
        prices = prices["short"]
    return _price_counts(usage, prices, tier=tier, date=table.get("date"))


def calculated_cost(usage: dict | None, model: str | None, requested_tier: str | None,
                    served_tier: str | None, table: dict | None) -> dict:
    """Return a labeled dated-rate estimate suitable for exported cost columns.

    The estimate is not an invoice amount. When the served tier is unknown, use
    the explicitly requested tier and retain that assumption in the result.
    """
    requested = _normalize_tier(requested_tier)
    served = _normalize_tier(served_tier)
    used_tier = served or requested
    priced = price_usage(usage, model, used_tier, table) if used_tier else {
        "usd": None, "status": "unavailable", "reasons": ["requested service tier missing"]}
    is_observed = bool(served)
    if priced.get("status") == "priced":
        basis = ("recorded per-request token counts × dated reference rates at observed served tier"
                 if is_observed else
                 "recorded per-request token counts × dated reference rates at requested tier; served tier unknown")
        status = ("CALCULATED_OBSERVED_TIER_REFERENCE" if is_observed else
                  "CALCULATED_REQUESTED_TIER_REFERENCE")
        reason = ""
        value: str | float = priced["usd"]
    else:
        basis = "unavailable: required usage, requested tier, or dated rate evidence is missing"
        status = "UNAVAILABLE"
        reason = "; ".join(priced.get("reasons", [])) or "price calculation unavailable"
        value = "N/A"
    return {
        "token_usd": value,
        "cost_status": status,
        "cost_basis": basis,
        "requested_tier": requested or "UNKNOWN",
        "served_tier": served or "UNKNOWN",
        "invoice_status": "UNKNOWN",
        "price_table_date": table.get("date", "UNKNOWN") if isinstance(table, dict) else "UNKNOWN",
        "currency": "USD",
        "cost_reason": reason,
        "status": status,
        "usd": priced.get("usd") if priced.get("status") == "priced" else None,
        "basis": basis,
        "requested_service_tier": requested or "UNKNOWN",
        "served_service_tier": served or "UNKNOWN",
        "price_table_source": (table.get("source", {}).get("title")
                               if isinstance(table, dict) and isinstance(table.get("source"), dict) else None),
    }


def _normalize_tier(value: str | None) -> str | None:
    if value in ("fast", "priority"): return "fast"
    if value in ("standard", "default"): return "standard"
    return value


def _price_counts(usage: dict, prices: dict, tier: str | None = None, date: str | None = None) -> dict:
    if not isinstance(prices, dict):
        return {"usd": None, "status": "unavailable", "reasons": ["service tier price missing"]}
    if not isinstance(prices, dict):
        return {"usd": None, "status": "unavailable", "reasons": ["service tier unresolved"]}
    cached = usage.get("cached_input_tokens", 0)
    created = usage.get("cache_write_input_tokens", 0)
    total_input = usage.get("input_tokens")
    if not all(isinstance(v, (int, float)) for v in (cached, created, total_input)) or cached + created > total_input:
        return {"usd": None, "status": "unavailable", "reasons": ["input/cache token counts missing or inconsistent"]}
    needed = {"input": total_input - cached - created, "cache_read": cached,
              "cache_create": created,
              "output": usage.get("output_tokens")}
    if any(not isinstance(v, (int, float)) for k, v in needed.items() if k in ("input", "output")):
        return {"usd": None, "status": "unavailable", "reasons": ["required token fields missing"]}
    missing = [k for k in needed if needed[k] > 0 and not isinstance(prices.get(k), (int, float))]
    if missing:
        return {"usd": None, "status": "unavailable", "reasons": ["price fields missing: " + ",".join(missing)]}
    parts = {k: needed[k] * (prices.get(k) if isinstance(prices.get(k), (int, float)) else 0) / 1_000_000 for k in needed}
    return {"usd": sum(parts.values()), "status": "priced", "tier": tier, "parts_usd": parts,
            "price_table_date": date}


def parse_rollout(path: str | Path, config: dict | None = None,
                  pricing: dict | None = None, include_report: bool = True) -> dict:
    events, times, models, efforts, tiers = [], [], set(), set(), set()
    malformed = 0
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                event = json.loads(line)
            except ValueError:
                malformed += 1
                continue
            if not isinstance(event, dict):
                continue
            events.append(event)
            ts = _timestamp(event)
            if ts: times.append(ts)
            # Read model/effort/tier only from explicit session context/provider
            # metadata records. Never interpret arbitrary tool inputs as metadata.
            payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
            etype = str(event.get("type", "")).lower()
            if etype in ("turn_context", "session_context", "provider_metadata") or str(payload.get("type", "")).lower() in ("turn_context", "session_context", "provider_metadata"):
                for source in (event, payload, payload.get("model_info", {})):
                    if not isinstance(source, dict): continue
                    for key, bucket in (("model", models), ("effort", efforts), ("service_tier", tiers)):
                        if isinstance(source.get(key), str): bucket.add(source[key])
    usage, request_usage, usage_errors = _usage_data(events)
    calls = [c for e in events for c in _tool_calls(e)]
    # Dedup calls across duplicate wrapper events by call id.
    dedup, seen = [], set()
    for c in calls:
        key = c.get("call_id") or c.get("id")
        if key and key in seen: continue
        if key: seen.add(key)
        dedup.append(c)
    output_stats = _tool_output_stats(events, dedup)
    model = next(iter(models)) if len(models) == 1 else None
    tier = next(iter(tiers)) if len(tiers) == 1 else None
    observed_tier = _normalize_tier(tier)
    requested_tier = _normalize_tier(config.get("service_tier")) if isinstance(config, dict) else None
    tier = observed_tier
    audit_config = dict(config) if isinstance(config, dict) else None
    if audit_config is not None and (malformed or usage_errors):
        audit_config["terminal_verified"] = False
    audit = audit_rollout(events, audit_config)
    cli_event_path = audit_config.get("events_path") if isinstance(audit_config, dict) else None
    if not cli_event_path and isinstance(audit_config, dict):
        cli_event_path = audit_config.get("receipt", {}).get("events_path") if isinstance(audit_config.get("receipt"), dict) else None
    if not cli_event_path:
        sibling = Path(path).with_name("events.jsonl")
        if sibling.is_file(): cli_event_path = str(sibling)
    cli_health = _cli_event_health(cli_event_path)
    audit["setup_health"] = _merge_setup_health(audit.get("setup_health", {}), cli_health)
    if audit["setup_health"]["status"] == "FAIL":
        audit["flags"].append("setup-infrastructure:transport_failure")
        audit["status"] = "FAIL"
    policy_status = audit["status"]
    runtime_status = "PASS"
    tier_status = "PASS"
    if not models:
        runtime_status = "UNKNOWN"
        audit["unknown_reasons"].append("runtime model metadata missing")
        if audit["status"] == "PASS": audit["status"] = "UNKNOWN"
    if len(models) > 1:
        runtime_status = "FAIL"
        audit["flags"].append("multiple-runtime-models")
        audit["status"] = "FAIL"
    if not efforts:
        runtime_status = "UNKNOWN" if runtime_status == "PASS" else runtime_status
        audit["unknown_reasons"].append("runtime effort metadata missing")
        if audit["status"] == "PASS": audit["status"] = "UNKNOWN"
    if len(efforts) > 1:
        runtime_status = "FAIL"
        audit["flags"].append("multiple-runtime-efforts")
        audit["status"] = "FAIL"
    if isinstance(config, dict) and config.get("verified_receipt") is True:
        expected_model = config.get("model")
        expected_effort = config.get("effort")
        if not expected_model:
            runtime_status = "UNKNOWN" if runtime_status == "PASS" else runtime_status
            audit["unknown_reasons"].append("requested model missing from verified receipt")
        if not expected_effort:
            runtime_status = "UNKNOWN" if runtime_status == "PASS" else runtime_status
            audit["unknown_reasons"].append("requested effort missing from verified receipt")
        if audit["status"] == "PASS" and (not expected_model or not expected_effort): audit["status"] = "UNKNOWN"
        if expected_model and model and expected_model != model:
            runtime_status = "FAIL"
            audit["flags"].append("requested-runtime-model-mismatch")
            audit["status"] = "FAIL"
        if expected_effort and next(iter(efforts), None) and expected_effort != next(iter(efforts)):
            runtime_status = "FAIL"
            audit["flags"].append("requested-runtime-effort-mismatch")
            audit["status"] = "FAIL"
    if observed_tier is None:
        tier_status = "UNKNOWN"
    elif requested_tier and observed_tier != requested_tier:
        tier_status = "FAIL"
        audit["flags"].append("requested-service-tier-mismatch")
        audit["status"] = "FAIL"
    report = _final_text({"events": events}) if include_report else None
    cost = price_usage(usage, model, tier, pricing)
    reference_cost = price_usage(usage, model, requested_tier, pricing) if requested_tier and tier_status == "UNKNOWN" else None
    if tier_status == "UNKNOWN":
        cost = {"usd": None, "status": "unavailable", "invoice_status": "UNKNOWN",
                "reasons": ["served service tier is unobserved"]}
        if reference_cost and reference_cost.get("status") == "priced":
            cost["requested_tier_reference_estimate"] = {
                "usd": reference_cost["usd"], "status": "CONDITIONAL_REQUESTED_TIER_ESTIMATE",
                "tier": requested_tier, "price_table_date": reference_cost.get("price_table_date")}
    else:
        cost = {**cost, "invoice_status": "UNKNOWN",
                "rate_estimate_status": "OBSERVED_TIER_RATE_ESTIMATE" if cost.get("status") == "priced" else cost.get("status")}
    if audit["status"] == "PASS" and policy_status != "PASS": policy_status = audit["status"]
    audit["dimensions"] = {"policy": policy_status, "runtime_model_effort": runtime_status,
                            "service_tier": tier_status, "cost": cost.get("status", "unavailable")}
    audit["dimensions"]["setup_health"] = audit["setup_health"]["status"]
    audit["overall_status"] = ("FAIL" if audit["status"] == "FAIL" or runtime_status == "FAIL" or tier_status == "FAIL"
                               else "UNKNOWN" if audit["status"] == "UNKNOWN" or runtime_status == "UNKNOWN" or tier_status == "UNKNOWN" or cost.get("status") != "priced"
                               else "PASS")
    return {"path": str(path), "start_local": _local_timestamp(times[0]) if times else None,
            "end_local": _local_timestamp(times[-1]) if times else None, "wall_s": _wall_seconds(times),
            "tool_uses": len(dedup), "tools": [{"name": c.get("name", c.get("tool_name")), "input": _input(c)} for c in dedup],
            "setup_health": audit.get("setup_health"),
            **output_stats,
            "models": sorted(models), "model": model, "efforts": sorted(efforts),
            "effort": next(iter(efforts)) if len(efforts) == 1 else None,
            "service_tiers": sorted(tiers), "requested_service_tier": requested_tier,
            "observed_service_tier": observed_tier, "usage": usage, "report": report,
            "audit": audit, "pricing": cost, "malformed_lines": malformed,
            "request_usage_errors": usage_errors}


def _wall_seconds(times: list[str]) -> float | None:
    if len(times) < 2: return None
    try:
        a, b = (datetime.fromisoformat(x.replace("Z", "+00:00")) for x in (times[0], times[-1]))
        return max(0.0, (b - a).total_seconds())
    except ValueError:
        return None


def _local_timestamp(value: str | None) -> str | None:
    if not value: return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None: dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone(timedelta(hours=-6))).isoformat()
    except ValueError:
        return None


def append_tsv(path: str | Path, row: dict) -> None:
    """Append one brief-compatible row; creates the exact core header when empty."""
    p = Path(path)
    exists = p.exists() and p.stat().st_size > 0
    if exists:
        with p.open("r", encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f, delimiter="\t")
            fields = reader.fieldnames or []
            rows = list(reader)
        upgraded = fields + [key for key in CORE_COLUMNS if key not in fields]
        if upgraded != fields:
            temp = p.with_name(p.name + ".schema.tmp")
            with temp.open("w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=upgraded, delimiter="\t", extrasaction="ignore")
                writer.writeheader()
                writer.writerows(rows)
            temp.replace(p)
            fields = upgraded
        else:
            fields = fields or CORE_COLUMNS
    else:
        fields = CORE_COLUMNS
    with p.open("a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, delimiter="\t", extrasaction="ignore")
        if not exists: writer.writeheader()
        writer.writerow({k: row.get(k, "") for k in fields})
