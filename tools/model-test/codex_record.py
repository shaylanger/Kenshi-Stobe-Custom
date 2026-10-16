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
                "headers", "citations", "diff_markers", "violation_flags", "agent"]
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
        if isinstance(p, dict) and str(p.get("type", "")).lower() in ("function_call", "tool_use"):
            out.append(p)
    elif str(obj.get("type", "")).lower() in ("function_call", "tool_use"):
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
    if (not isinstance(config, dict) or config.get("verified_receipt") is not True or
            config.get("agents_enabled") is not False or config.get("multi_agent") is not False):
        reasons.append("verified launch receipt must prove agents.enabled=false and multi_agent=false")
    if isinstance(config, dict) and (config.get("agents_enabled") is True or config.get("multi_agent") is True):
        flags.append("delegation-config-enabled")
    # Only explicitly approved read-only tools are permitted. Names are canonical
    # tool names as recorded in function_call payloads.
    allowed = {str(x).lower() for x in config.get("allowed_tools", [])} if isinstance(config, dict) and isinstance(config.get("allowed_tools"), list) else set()
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
        if name not in allowed:
            flags.append("unallowlisted-tool:" + (name or "unknown"))
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
        reasons.append("pre-tool policy hook verification missing")
    if isinstance(config, dict) and config.get("terminal_verified") is not True:
        reasons.append("complete terminal event not verified")
    if delegation:
        flags.extend("delegation:" + d for d in delegation)
    status = "FAIL" if flags else ("UNKNOWN" if reasons else "PASS")
    return {"status": status, "flags": sorted(set(flags)), "unknown_reasons": reasons,
            "delegation_evidence": delegation, "config_proof": config if isinstance(config, dict) else None}


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
    missing = [k for k in needed if not isinstance(prices.get(k), (int, float))]
    if missing:
        return {"usd": None, "status": "unavailable", "reasons": ["price fields missing: " + ",".join(missing)]}
    parts = {k: needed[k] * prices[k] / 1_000_000 for k in needed}
    return {"usd": sum(parts.values()), "status": "priced", "tier": tier, "parts_usd": parts,
            "price_table_date": date}


def parse_rollout(path: str | Path, config: dict | None = None,
                  pricing: dict | None = None) -> dict:
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
    model = next(iter(models)) if len(models) == 1 else None
    tier = next(iter(tiers)) if len(tiers) == 1 else None
    observed_tier = _normalize_tier(tier)
    requested_tier = _normalize_tier(config.get("service_tier")) if isinstance(config, dict) else None
    tier = observed_tier
    audit_config = dict(config) if isinstance(config, dict) else None
    if audit_config is not None and (malformed or usage_errors):
        audit_config["terminal_verified"] = False
    audit = audit_rollout(events, audit_config)
    if not models:
        audit["unknown_reasons"].append("runtime model metadata missing")
        if audit["status"] == "PASS": audit["status"] = "UNKNOWN"
    if len(models) > 1:
        audit["flags"].append("multiple-runtime-models")
        audit["status"] = "FAIL"
    if not efforts:
        audit["unknown_reasons"].append("runtime effort metadata missing")
        if audit["status"] == "PASS": audit["status"] = "UNKNOWN"
    if len(efforts) > 1:
        audit["flags"].append("multiple-runtime-efforts")
        audit["status"] = "FAIL"
    if isinstance(config, dict) and config.get("verified_receipt") is True:
        expected_model = config.get("model")
        expected_effort = config.get("effort")
        if not expected_model:
            audit["unknown_reasons"].append("requested model missing from verified receipt")
        if not expected_effort:
            audit["unknown_reasons"].append("requested effort missing from verified receipt")
        if audit["status"] == "PASS" and (not expected_model or not expected_effort): audit["status"] = "UNKNOWN"
        if expected_model and model and expected_model != model:
            audit["flags"].append("requested-runtime-model-mismatch")
            audit["status"] = "FAIL"
        if expected_effort and next(iter(efforts), None) and expected_effort != next(iter(efforts)):
            audit["flags"].append("requested-runtime-effort-mismatch")
            audit["status"] = "FAIL"
    if observed_tier is None:
        audit["unknown_reasons"].append("delivered service tier metadata missing")
        if audit["status"] == "PASS": audit["status"] = "UNKNOWN"
    elif requested_tier and observed_tier != requested_tier:
        audit["flags"].append("requested-service-tier-mismatch")
        audit["status"] = "FAIL"
    report = _final_text({"events": events})
    cost = price_usage(usage, model, tier, pricing)
    return {"path": str(path), "start_local": _local_timestamp(times[0]) if times else None,
            "end_local": _local_timestamp(times[-1]) if times else None, "wall_s": _wall_seconds(times),
            "tool_uses": len(dedup), "tools": [{"name": c.get("name", c.get("tool_name")), "input": _input(c)} for c in dedup],
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
    with p.open("a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=CORE_COLUMNS, delimiter="\t", extrasaction="ignore")
        if not exists: writer.writeheader()
        writer.writerow({k: row.get(k, "") for k in CORE_COLUMNS})
