"""Offline-only integration probe for the bundled Codex Code Mode host.

The probe talks only to a loopback Responses stub using a disposable CODEX_HOME
and a dummy key. It never contacts a model provider. Phase ``inventory`` only
captures the request's tool names/schema keys and checks SessionStart hooks.
"""
from __future__ import annotations

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any

FROZEN_TOOLS = [
    "mcp__frozen__list", "mcp__frozen__read",
    "mcp__frozen__search", "mcp__frozen__sql",
]
MAX_REQUEST_BYTES = 8_000_000


def _sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def _short_tool_inventory(request: dict[str, Any]) -> tuple[list[str], dict[str, list[str]]]:
    names: list[str] = []
    schema_keys: dict[str, list[str]] = {}
    def visit(items: Any, namespace: str = "") -> None:
        if isinstance(items, dict):
            name = items.get("name")
            is_namespace = items.get("type") == "namespace" or isinstance(items.get("tools"), list)
            if isinstance(name, str) and is_namespace:
                visit(items.get("tools", []), namespace + name + "__")
            elif isinstance(name, str) and (items.get("type") in {"custom", "function"} or
                                             "parameters" in items or "input_schema" in items):
                qualified = name if name.startswith("mcp__") or not namespace else namespace + name
                names.append(qualified)
                schema = items.get("parameters") or items.get("input_schema") or {}
                if isinstance(schema, str):
                    try:
                        schema = json.loads(schema)
                    except json.JSONDecodeError:
                        schema = {}
                props = schema.get("properties", {}) if isinstance(schema, dict) else {}
                schema_keys[qualified] = sorted(k for k in props if isinstance(k, str)) if isinstance(props, dict) else []
            for key in ("tools", "additional_tools", "tool_definitions"):
                value = items.get(key)
                if isinstance(value, (list, dict)):
                    visit(value, namespace)
            for key, value in items.items():
                if key in {"input", "additional_tools", "tool_definitions"} and isinstance(value, (list, dict)):
                    visit(value, namespace)
            return
        if not isinstance(items, list):
            return
        for tool in items:
            if not isinstance(tool, dict):
                continue
            name = tool.get("name")
            if not isinstance(name, str):
                visit(tool, namespace)
                continue
            if tool.get("type") == "namespace" or isinstance(tool.get("tools"), list):
                visit(tool.get("tools"), namespace + name + "__")
                continue
            qualified = name if name.startswith("mcp__") or not namespace else namespace + name
            names.append(qualified)
            schema = tool.get("parameters") or tool.get("input_schema") or {}
            if isinstance(schema, str):
                try:
                    schema = json.loads(schema)
                except json.JSONDecodeError:
                    schema = {}
            props = schema.get("properties", {}) if isinstance(schema, dict) else {}
            schema_keys[qualified] = sorted(k for k in props if isinstance(k, str)) if isinstance(props, dict) else []
    visit(request)
    return sorted(set(names)), schema_keys


def _safe_shape(value: Any, depth: int = 0) -> Any:
    """Keep only JSON structure and discriminator fields; drop all text/body values."""
    if depth >= 8:
        return "depth-limit"
    if isinstance(value, list):
        return {"kind": "array", "count": len(value), "items": [_safe_shape(v, depth + 1) for v in value[:8]]}
    if isinstance(value, dict):
        result: dict[str, Any] = {"kind": "object", "keys": sorted(k for k in value if isinstance(k, str))}
        for key in ("type", "role", "name"):
            v = value.get(key)
            if isinstance(v, str) and len(v) <= 100:
                result[key] = v
        for key in ("tools", "additional_tools", "tool_definitions", "input"):
            if key in value and isinstance(value[key], (list, dict)):
                result[key] = _safe_shape(value[key], depth + 1)
        return result
    return type(value).__name__


def _safe_error_class(stderr: bytes) -> str | None:
    """Classify startup failures without copying any CLI text into receipts."""
    low = stderr.decode("utf-8", "replace").lower()
    rules = [
        (r"unknown (?:config )?(?:key|field)|unrecognized (?:config )?(?:key|field)", "config_unknown_key"),
        (r"failed to parse (?:config|toml)|invalid (?:config|toml)", "config_parse_error"),
        (r"api key|authentication|not logged in|unauthorized", "auth_or_provider_error"),
        (r"model provider|provider .*not found", "provider_config_error"),
        (r"model .*not found|unknown model", "model_catalog_error"),
        (r"access is denied|permission denied|os error 5", "windows_access_denied"),
        (r"usage:|unrecognized option|unexpected argument", "cli_argument_error"),
        (r"code.mode host is disabled", "code_mode_host_disabled"),
    ]
    return next((label for pattern, label in rules if re.search(pattern, low)), "cli_error") if stderr else None


def _safe_event_error_class(item: dict[str, Any]) -> str:
    pieces: list[str] = []
    for key in ("message", "error", "reason", "content"):
        value = item.get(key)
        if isinstance(value, str):
            pieces.append(value)
        elif isinstance(value, dict):
            for nested_key in ("message", "reason", "code"):
                if isinstance(value.get(nested_key), str):
                    pieces.append(value[nested_key])
    low = " ".join(pieces).lower()
    rules = [
        (r"code.mode host.*disabled|code.mode.*unavailable", "code_mode_host_error"),
        (r"hook|pretooluse|sessionstart", "hook_error"),
        (r"mcp|server initialization|server startup", "mcp_server_error"),
        (r"config|toml|unknown field", "config_error"),
        (r"auth|api key|unauthorized", "auth_error"),
    ]
    return next((label for pattern, label in rules if re.search(pattern, low)), "other_error")


def _safe_error_summary(item: dict[str, Any]) -> str:
    value = item.get("message")
    if not isinstance(value, str):
        error = item.get("error")
        value = error.get("message") if isinstance(error, dict) else None
    if not isinstance(value, str):
        return "error_without_message"
    value = re.sub(r"(?i)\b(?:OPENAI_API_KEY|CODEX_ACCESS_TOKEN|Authorization)\b\s*[:=]\s*[^\s,;]+", "<REDACTED>", value)
    value = re.sub(r"(?i)https?://[^\s\"']+", "<URL>", value)
    value = re.sub(r"(?i)\b[A-Z]:\\[^\s\"']+", "<PATH>", value)
    value = re.sub(r"(?<![A-Za-z])/(?:[^\s\"']+/)*[^\s\"']+", "<PATH>", value)
    return " ".join(value.split())[:240]


def _safe_stderr_summary(stderr: bytes) -> list[str]:
    """Keep bounded CLI diagnostics, with credentials and local paths removed."""
    lines: list[str] = []
    for raw in stderr.decode("utf-8", "replace").splitlines():
        line = " ".join(raw.split())
        if not line:
            continue
        line = re.sub(r"(?i)\b(?:OPENAI_API_KEY|CODEX_ACCESS_TOKEN|Authorization)\b\s*[:=]\s*[^\s,;]+", "<REDACTED>", line)
        line = re.sub(r"(?i)Bearer\s+[^\s,;]+", "Bearer <REDACTED>", line)
        line = re.sub(r"(?i)https?://[^\s\"']+", "<URL>", line)
        line = re.sub(r"(?i)Bearer\s+[^\s,;]+", "Bearer <REDACTED>", line)
        line = re.sub(r"(?i)\b[A-Z]:\\[^\s\"']+", "<PATH>", line)
        line = re.sub(r"(?<![A-Za-z])/(?:[^\s\"']+/)*[^\s\"']+", "<PATH>", line)
        lines.append(line[:240])
        if len(lines) == 12:
            break
    return lines


def _safe_hook_log_summaries(root: Path) -> list[dict[str, str]]:
    """Extract only bounded hook-specific diagnostics from this disposable profile."""
    result: list[dict[str, str]] = []
    pattern = re.compile(r"(?i)(codex_hooks|hook.{0,60}(dispatch|run|exec|trust|match|error|fail|skip|disabled)|(dispatch|run|exec|trust|match|error|fail|skip|disabled).{0,60}hook)")
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".log", ".jsonl"}:
            continue
        try:
            with path.open("rb") as stream:
                data = stream.read(1_000_000)
            for raw in data.decode("utf-8", "replace").splitlines():
                if not pattern.search(raw):
                    continue
                line = " ".join(raw.split())
                line = re.sub(r"(?i)\b(?:OPENAI_API_KEY|CODEX_ACCESS_TOKEN|Authorization)\b\s*[:=]\s*[^\s,;]+", "<REDACTED>", line)
                line = re.sub(r"(?i)Bearer\s+[^\s,;]+", "Bearer <REDACTED>", line)
                line = re.sub(r"(?i)https?://[^\s\"']+", "<URL>", line)
                line = re.sub(r"(?i)\b[A-Z]:\\[^\s\"']+", "<PATH>", line)
                line = re.sub(r"(?<![A-Za-z])/(?:[^\s\"']+/)*[^\s\"']+", "<PATH>", line)
                result.append({"file": path.name, "line": line[:240]})
                if len(result) >= 20:
                    return result
        except OSError:
            continue
    return result


def _sse_final(response_id: str) -> bytes:
    response = {
        "id": response_id, "object": "response", "status": "completed",
        "output": [{"id": "msg-offline", "type": "message", "status": "completed",
                    "role": "assistant", "content": [{"type": "output_text", "text": "offline probe complete"}]}],
    }
    events = [
        {"type": "response.created", "response": {"id": response_id, "object": "response", "status": "in_progress", "output": []}},
        {"type": "response.output_item.added", "response_id": response_id, "output_index": 0, "item": response["output"][0]},
        {"type": "response.content_part.added", "response_id": response_id, "item_id": "msg-offline", "output_index": 0,
         "content_index": 0, "part": {"type": "output_text", "text": ""}},
        {"type": "response.output_text.delta", "response_id": response_id, "item_id": "msg-offline", "output_index": 0,
         "content_index": 0, "delta": "offline probe complete"},
        {"type": "response.output_text.done", "response_id": response_id, "item_id": "msg-offline", "output_index": 0,
         "content_index": 0, "text": "offline probe complete"},
        {"type": "response.content_part.done", "response_id": response_id, "item_id": "msg-offline", "output_index": 0,
         "content_index": 0, "part": {"type": "output_text", "text": "offline probe complete"}},
        {"type": "response.output_item.done", "response_id": response_id, "output_index": 0, "item": response["output"][0]},
        {"type": "response.completed", "response": response},
    ]
    return b"".join(b"event: " + item["type"].encode() + b"\ndata: " + json.dumps(item, separators=(",", ":")).encode() + b"\n\n" for item in events)


_PROBE_CODE = r'''const globalNames = Object.getOwnPropertyNames(globalThis).sort();
const toolNames = ALL_TOOLS.map(x => x.name).sort();
const toolNamespaceKeys = Object.getOwnPropertyNames(tools).sort();
const directCallableToolNames = toolNamespaceKeys.filter(name => typeof tools[name] === "function");
const forbidden = ["process", "require", "Buffer", "global", "Deno", "Bun", "fetch", "XMLHttpRequest", "WebSocket", "WebSocketStream", "fs", "filesystem", "document", "window", "navigator", "console"];
const forbiddenGlobalNames = forbidden.filter(name => Object.prototype.hasOwnProperty.call(globalThis, name));
const agentApiTypes = Object.fromEntries(["spawn_agent", "delegate", "subagent", "collaboration"].map(name => [name, {global: typeof globalThis[name], tool: typeof tools[name]}]));
const unlistedCallableNames = ["exec_command", "shell_command", "apply_patch", "tool_search", "delegate", "spawn_agent"]
  .filter(name => typeof tools[name] === "function");
const constructorEscapeTypes = {process: Function("return typeof process")(), require: Function("return typeof require")(),
  globalProcess: Function("return typeof globalThis.process")()};
const importStatus = {};
for (const specifier of ["node:fs", "node:child_process", "node:https"]) {
  try { await import(specifier); importStatus[specifier] = "available"; }
  catch (error) { importStatus[specifier] = "rejected:" + (error && error.name || "Error"); }
}
const responseShape = value => {
  let normalized = value;
  if (typeof value === "string") { try { normalized = JSON.parse(value); } catch (_) {} }
  const shape = {type:typeof value, keys:normalized && typeof normalized === "object" ? Object.keys(normalized).sort() : [],
    isError:normalized && typeof normalized === "object" && typeof normalized.isError === "boolean" ? normalized.isError : null};
  if (shape.isError === true && Array.isArray(normalized.content)) {
    const textItem = normalized.content.find(item => item && typeof item.text === "string");
    if (textItem) shape.errorText = textItem.text.slice(0, 240);
  }
  return shape;
};
let frozenListStatus = "call_threw", listShape = null;
try { const value = await tools.mcp__frozen__list({path:"."}); listShape = responseShape(value); frozenListStatus = listShape.isError === false ? "ok" : listShape.isError === true ? "server_error" : "unclassified"; } catch (_) {}
let unknownParameterStatus = "call_threw", unknownShape = null;
try { const value = await tools.mcp__frozen__list({path:".", unknown_probe_parameter:"must_be_rejected"}); unknownShape = responseShape(value); unknownParameterStatus = unknownShape.isError === true ? "server_rejected" : "returned"; } catch (_) {}
text("__CODEX_HOSTPROBE__" + JSON.stringify({globalNames, forbiddenGlobalNames, agentApiTypes, toolNames, toolNamespaceKeys, directCallableToolNames, unlistedCallableNames, constructorEscapeTypes, importStatus, frozenListStatus, listShape, unknownParameterStatus, unknownShape}));'''

_INVENTORY_CODE = r'''const globalNames = Object.getOwnPropertyNames(globalThis).sort();
const toolNames = ALL_TOOLS.map(x => x.name).sort();
const toolNamespaceKeys = Object.getOwnPropertyNames(tools).sort();
const directCallableToolNames = toolNamespaceKeys.filter(name => typeof tools[name] === "function");
const forbidden = ["process", "require", "Buffer", "global", "Deno", "Bun", "fetch", "XMLHttpRequest", "WebSocket", "WebSocketStream", "fs", "filesystem", "document", "window", "navigator", "console"];
const forbiddenGlobalNames = forbidden.filter(name => Object.prototype.hasOwnProperty.call(globalThis, name));
const agentApiTypes = Object.fromEntries(["spawn_agent", "delegate", "subagent", "collaboration"].map(name => [name, {global: typeof globalThis[name], tool: typeof tools[name]}]));
const unlistedCallableNames = ["exec_command", "shell_command", "apply_patch", "tool_search", "delegate", "spawn_agent"]
  .filter(name => typeof tools[name] === "function");
text("__CODEX_HOSTPROBE__" + JSON.stringify({globalNames, forbiddenGlobalNames, agentApiTypes, toolNames, toolNamespaceKeys, directCallableToolNames, unlistedCallableNames, frozenListStatus:"not_called"}));'''

_TRANSPORT_CODE = r'''const responseShape = value => {
  let normalized = value;
  if (typeof value === "string") { try { normalized = JSON.parse(value); } catch (_) {} }
  return {isError:normalized && typeof normalized === "object" ? normalized.isError === true : null};
};
const cases = [
    ["search_server_lib", tools.mcp__frozen__search, {query:"Emperor Tengu", path:"server/lib", max_results:30, byte_budget:20000000}],
    ["search_output_log", tools.mcp__frozen__search, {query:"Tengu", path:"logs/output_from_llm.log", max_results:25, byte_budget:20000000}],
    ["sql_select_readonly", tools.mcp__frozen__sql, {query:"SELECT count(*) FROM public.audit_request"}],
  ["read_manifest", tools.mcp__frozen__read, {path:"MANIFEST-code.txt", byte_limit:512, line_count:2}],
  ["list_root", tools.mcp__frozen__list, {path:"."}],
];
const calls = await Promise.all(cases.map(async ([label, fn, args]) => {
  const started = Date.now();
  try {
    const value = await fn(args);
    const shape = responseShape(value);
    return {label, isError:shape.isError, result_class:shape.isError === true ? "error" : shape.isError === false ? "ok" : "unclassified", elapsed_ms:Date.now()-started};
  } catch (error) {
    return {label, isError:true, result_class:"transport_error:" + (error && error.name || "Error"), elapsed_ms:Date.now()-started};
  }
}));
text("__CODEX_HOSTPROBE__" + JSON.stringify({transportCalls:calls}));'''


def _sse_custom_call(response_id: str, code: str = _PROBE_CODE) -> bytes:
    item = {"id": "item-probe", "type": "custom_tool_call", "status": "completed",
            "call_id": "call-probe", "name": "exec", "input": code}
    response = {"id": response_id, "object": "response", "status": "completed", "output": [item]}
    events = [
        {"type": "response.created", "response": {"id": response_id, "object": "response", "status": "in_progress", "output": []}},
        {"type": "response.output_item.added", "response_id": response_id, "output_index": 0,
         "item": {**item, "input": "", "status": "in_progress"}},
        {"type": "response.custom_tool_call_input.delta", "response_id": response_id,
         "item_id": "item-probe", "output_index": 0, "delta": code},
        {"type": "response.custom_tool_call_input.done", "response_id": response_id,
         "item_id": "item-probe", "output_index": 0, "input": code},
        {"type": "response.output_item.done", "response_id": response_id, "output_index": 0, "item": item},
        {"type": "response.completed", "response": response},
    ]
    return b"".join(b"event: " + item["type"].encode() + b"\ndata: " + json.dumps(item, separators=(",", ":")).encode() + b"\n\n" for item in events)


def _extract_probe_result(value: Any) -> dict[str, Any] | None:
    if isinstance(value, str):
        marker = "__CODEX_HOSTPROBE__"
        index = value.find(marker)
        if index >= 0:
            try:
                result = json.loads(value[index + len(marker):].strip())
            except json.JSONDecodeError:
                return None
            for shape_key in ("listShape", "unknownShape"):
                shape = result.get(shape_key)
                if isinstance(shape, dict) and isinstance(shape.get("errorText"), str):
                    summary = shape["errorText"]
                    summary = re.sub(r"(?i)https?://[^\s\"']+", "<URL>", summary)
                    summary = re.sub(r"(?i)Bearer\s+[^\s,;]+", "Bearer <REDACTED>", summary)
                    summary = re.sub(r"(?i)\b[A-Z]:\\[^\s\"']+", "<PATH>", summary)
                    summary = re.sub(r"(?<![A-Za-z])/(?:[^\s\"']+/)*[^\s\"']+", "<PATH>", summary)
                    shape["errorText"] = " ".join(summary.split())[:240]
            return result if isinstance(result, dict) else None
    elif isinstance(value, dict):
        for key in ("input", "output", "content", "text", "result"):
            if key in value:
                result = _extract_probe_result(value[key])
                if result is not None:
                    return result
    elif isinstance(value, list):
        for item in value:
            result = _extract_probe_result(item)
            if result is not None:
                return result
    return None


class _StubState:
    def __init__(self, phase: str = "inventory") -> None:
        self.phase = phase
        self.requests = 0
        self.tool_names: list[str] = []
        self.tool_names_by_request: list[list[str]] = []
        self.schema_keys: dict[str, list[str]] = {}
        self.service_tier: str | None = None
        self.root_keys: list[str] = []
        self.request_input_shape: Any = None
        self.probe_result: dict[str, Any] | None = None
        self.bad_requests = 0
        self.lock = threading.Lock()


def _appserver_hooks(codex: Path, env: dict[str, str], cwd: Path, timeout: float = 8.0) -> tuple[list[dict[str, Any]], str | None, dict[str, Any]]:
    """Read locally registered hooks without starting a model turn."""
    proc = subprocess.Popen([str(codex), "app-server", "--stdio", "--strict-config"], cwd=str(cwd), env=env,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", bufsize=1)
    output: queue.Queue[str | None] = queue.Queue()

    def read_output() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            output.put(line)
        output.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()

    def send(payload: dict[str, Any]) -> None:
        assert proc.stdin is not None
        proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        proc.stdin.flush()

    def response_for(request_id: int) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                line = output.get(timeout=max(0.05, deadline - time.monotonic()))
            except queue.Empty:
                break
            if line is None:
                break
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(message, dict) and message.get("id") == request_id:
                return message
        raise TimeoutError(f"app-server request {request_id} timed out")

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"clientInfo": {"name": "offline-hostprobe", "version": "1"},
                         "capabilities": {"experimentalApi": True}}})
        initialized = response_for(1)
        if "error" in initialized:
            raise RuntimeError("app-server initialize failed")
        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        send({"jsonrpc": "2.0", "id": 2, "method": "hooks/list", "params": {"cwds": [str(cwd)]}})
        reply = response_for(2)
        if "error" in reply:
            return [], "hooks_list_error", {"error_keys": sorted(reply.get("error", {}).keys()) if isinstance(reply.get("error"), dict) else []}
        result = reply.get("result", {})
        records: list[dict[str, Any]] = []
        stack: list[Any] = [result]
        result_keys = sorted(result.keys()) if isinstance(result, dict) else []
        while stack:
            handler = stack.pop()
            if isinstance(handler, dict):
                if isinstance(handler.get("key"), str) and isinstance(handler.get("currentHash"), str):
                    safe: dict[str, Any] = {}
                    for key in ("key", "currentHash", "enabled", "source", "trustStatus", "disabledReason", "event", "matcher"):
                        value = handler.get(key)
                        if isinstance(value, (str, bool, int)) or value is None:
                            safe[key] = value
                    records.append(safe)
                else:
                    stack.extend(handler.values())
            elif isinstance(handler, list):
                stack.extend(handler)
        shape = {"result_type": type(result).__name__, "result_keys": result_keys, "handler_count": len(records)}
        return records, None, shape
    finally:
        try:
            if proc.stdin:
                proc.stdin.close()
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            proc.kill()
            proc.wait(timeout=2)
        reader.join(timeout=1)


def _appserver_probe(codex: Path, env: dict[str, str], cwd: Path, timeout: float) -> tuple[int, list[dict[str, Any]], list[str]]:
    """Run one scripted no-inference turn through local app-server and the loopback stub."""
    proc = subprocess.Popen([str(codex), "app-server", "--stdio", "--strict-config"], cwd=str(cwd), env=env,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", bufsize=1)
    output: queue.Queue[str | None] = queue.Queue()
    diagnostics: list[dict[str, Any]] = []

    def read_output() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            output.put(line)
        output.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()

    def send(payload: dict[str, Any]) -> None:
        assert proc.stdin is not None
        proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        proc.stdin.flush()

    def read_until(predicate: Any, deadline: float) -> dict[str, Any]:
        while time.monotonic() < deadline:
            try:
                line = output.get(timeout=max(0.05, deadline - time.monotonic()))
            except queue.Empty:
                break
            if line is None:
                break
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(message, dict):
                continue
            method = message.get("method")
            params = message.get("params", {})
            if isinstance(method, str):
                record: dict[str, Any] = {"method": method}
                if isinstance(params, dict):
                    for key in ("threadId", "turnId", "status"):
                        if isinstance(params.get(key), (str, bool)):
                            record[key] = params[key]
                    item = params.get("item")
                    if isinstance(item, dict):
                        if isinstance(item.get("type"), str):
                            record["item_type"] = item["type"]
                        if isinstance(item.get("name"), str):
                            record["item_name"] = item["name"]
                diagnostics.append(record)
            if predicate(message):
                return message
        raise TimeoutError("app-server scripted turn timed out")

    deadline = time.monotonic() + timeout
    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"clientInfo": {"name": "offline-hostprobe", "version": "1"},
                         "capabilities": {"experimentalApi": True}}})
        init = read_until(lambda m: m.get("id") == 1, deadline)
        if "error" in init:
            return 2, diagnostics, ["initialize_error"]
        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        send({"jsonrpc": "2.0", "id": 2, "method": "thread/start", "params": {
            "model": "gpt-6-astra", "modelProvider": "offline_probe", "cwd": str(cwd),
            "approvalPolicy": "never", "sandbox": "read-only", "ephemeral": True}})
        started = read_until(lambda m: m.get("id") == 2, deadline)
        if "error" in started:
            return 2, diagnostics, ["thread_start_error"]
        thread = started.get("result", {}).get("thread", {})
        thread_id = thread.get("id") if isinstance(thread, dict) else None
        if not isinstance(thread_id, str):
            return 2, diagnostics, ["thread_id_missing"]
        send({"jsonrpc": "2.0", "id": 3, "method": "turn/start", "params": {
            "threadId": thread_id, "input": [{"type": "text", "text": "Run the fixed offline host probe."}],
            "cwd": str(cwd), "approvalPolicy": "never", "sandboxPolicy": {"type": "readOnly", "networkAccess": False},
            "serviceTierForTurn": "default"}})
        turn_start = read_until(lambda m: m.get("id") == 3, deadline)
        if "error" in turn_start:
            return 2, diagnostics, ["turn_start_error"]
        complete = read_until(lambda m: m.get("method") == "turn/completed", deadline)
        params = complete.get("params", {})
        if isinstance(params, dict) and isinstance(params.get("turnId"), str):
            diagnostics.append({"method": "turn/completed"})
        return 0, diagnostics[:40], []
    except TimeoutError:
        return 124, diagnostics[:40], ["turn_timeout"]
    finally:
        try:
            if proc.stdin:
                proc.stdin.close()
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            proc.kill()
            proc.wait(timeout=2)
        reader.join(timeout=1)


class _Handler(BaseHTTPRequestHandler):
    server_version = "CodexOfflineProbe/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, *_: object) -> None:
        return

    def do_POST(self) -> None:
        state: _StubState = self.server.probe_state  # type: ignore[attr-defined]
        host = self.headers.get("Host", "").lower()
        if self.path not in {"/v1/responses", "/responses"} or not host.startswith(("127.0.0.1:", "localhost:")):
            with state.lock:
                state.bad_requests += 1
            self.send_error(403)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 1 or size > MAX_REQUEST_BYTES:
                raise ValueError("request size out of bounds")
            request = json.loads(self.rfile.read(size))
            if not isinstance(request, dict):
                raise ValueError("request must be object")
        except Exception:
            with state.lock:
                state.bad_requests += 1
            self.send_error(400)
            return
        names, schema_keys = _short_tool_inventory(request)
        with state.lock:
            state.requests += 1
            state.tool_names_by_request.append(names)
            if state.requests == 1:
                state.tool_names = names
                state.schema_keys = schema_keys
                state.service_tier = request.get("service_tier") if isinstance(request.get("service_tier"), str) else None
                state.root_keys = sorted(k for k in request if isinstance(k, str))
                state.request_input_shape = _safe_shape(request.get("input"))
            if state.phase in {"exec", "host_inventory", "appserver_exec", "transport"} and state.requests > 1:
                state.probe_result = _extract_probe_result(request.get("input"))
        code = (_INVENTORY_CODE if state.phase == "host_inventory" else
                _TRANSPORT_CODE if state.phase == "transport" else _PROBE_CODE)
        payload = (_sse_custom_call(f"resp-offline-{state.requests}", code)
                   if state.phase in {"exec", "host_inventory", "appserver_exec", "transport"} and state.requests == 1 and "functions__exec" in names
                   else _sse_final(f"resp-offline-{state.requests}"))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        self.wfile.flush()


def run_inventory(codex: Path, model_cache: Path, output: Path, frozen_root: Path,
                  timeout: int = 30, phase: str = "inventory", private_parent: Path | None = None,
                  exclude_native_host_tools: bool = False) -> dict[str, Any]:
    if phase not in {"inventory", "exec", "host_inventory", "appserver_exec", "transport"}:
        raise ValueError("phase must be inventory, exec, host_inventory, appserver_exec, or transport")
    codex = codex.resolve(strict=True)
    model_cache = model_cache.resolve(strict=True)
    frozen_root = frozen_root.resolve(strict=True)
    if codex.name.casefold() != "codex.exe":
        raise ValueError("codex must be the installed codex.exe path")
    if model_cache.name.casefold() != "models_cache.json":
        raise ValueError("model cache must be models_cache.json")
    cache = json.loads(model_cache.read_text(encoding="utf-8"))
    cache_models = cache.get("models", [])
    target = next((m for m in cache_models if m.get("slug") == "gpt-6-astra" and m.get("tool_mode") == "code_mode_only"), None)
    if target is None:
        raise ValueError("model cache does not contain the expected Code Mode catalog entry")

    state = _StubState(phase)
    server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    server.daemon_threads = True
    server.probe_state = state  # type: ignore[attr-defined]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    status = "FAIL"
    cli_rc: int | None = None
    cli_err_class: str | None = None
    guard_events: list[dict[str, Any]] = []
    mcp_events: list[dict[str, Any]] = []
    cli_event_summary: list[dict[str, Any]] = []
    cli_error_classes: list[str] = []
    cli_error_summaries: list[str] = []
    version = "unknown"
    marker_start = marker_pretool = False
    hooks_before_trust: list[dict[str, Any]] = []
    hooks_after_trust: list[dict[str, Any]] = []
    hooks_list_shape: dict[str, Any] = {}
    hooks_list_error: str | None = None
    hook_trust_verified = False
    hook_log_summaries: list[dict[str, str]] = []
    try:
        version_run = subprocess.run([str(codex), "--version"], capture_output=True, text=True, timeout=10, check=False)
        version = version_run.stdout.strip()[:100]
        temp_kwargs: dict[str, Any] = {"prefix": "offline-hostprobe-"}
        if private_parent is not None:
            parent = private_parent.resolve(strict=True)
            if not parent.is_dir():
                raise ValueError("private parent must be an existing directory")
            temp_kwargs["dir"] = str(parent)
        with tempfile.TemporaryDirectory(**temp_kwargs) as raw_tmp:
            tmp = Path(raw_tmp)
            home = tmp / "home"
            codex_home = home / ".codex"
            neutral = tmp / "neutral"
            codex_home.mkdir(parents=True)
            neutral.mkdir()
            shutil.copyfile(model_cache, codex_home / "models_cache.json")
            mcp_receipts = codex_home / "mcp.jsonl"
            mcp_diagnostics = codex_home / "mcp-diagnostics.jsonl"
            guard_log = codex_home / "guard.jsonl"
            mcp_script = Path(__file__).resolve().with_name("codex_frozen_mcp.py")
            python = Path(sys.executable).resolve()
            start_marker = codex_home / "session-start.marker"
            pretool_marker = codex_home / "pretool.marker"
            config_lines = [
                'model = "gpt-6-astra"', 'model_provider = "offline_probe"',
                f"model_catalog_json = {json.dumps(str(codex_home / 'models_cache.json'))}",
                'approval_policy = "never"', 'sandbox_mode = "read-only"',
                "project_doc_max_bytes = 0", "web_search = 'disabled'",
                "[model_providers.offline_probe]", 'name = "Offline probe"',
                f'base_url = "http://127.0.0.1:{port}/v1"', 'wire_api = "responses"',
                'env_key = "OPENAI_API_KEY"',
                "[features]", "hooks = false", "code_mode_host = true",
                "code_mode_tool_search = false", "tool_search = false", "shell_tool = false",
                "multi_agent = false", "multi_agent_v2 = false", "multi_agent_v2_dynamic_tools = false",
                "apps = false", "plugins = false", "remote_plugin = false",
                "goals = false", "view_image = false", "computer_use = false", "browser_use = false",
                "in_app_browser = false", "memories = false", "web_search = false",
                "[agents]", "enabled = false", "max_concurrent_threads_per_session = 1",
                "[features.code_mode]", "enabled = true",
                'excluded_tool_namespaces = ' + json.dumps(((["functions", "clock"] if exclude_native_host_tools else []) + ["mcp__codex_apps", "mcp__plugins"])),
                "[mcp_servers.frozen]", f"command = {json.dumps(str(python))}",
                f"args = ['-I', {json.dumps(str(mcp_script))}]", "enabled = true", "required = true",
                'default_tools_approval_mode = "approve"',
                'enabled_tools = ["list", "read", "search", "sql"]', f"cwd = {json.dumps(str(neutral))}",
                "startup_timeout_sec = 10", "tool_timeout_sec = 20",
                "[mcp_servers.frozen.env]", f"CODEX_FROZEN_ROOT = {json.dumps(str(frozen_root))}",
                f"CODEX_FROZEN_RECEIPTS = {json.dumps(str(mcp_receipts))}",
                f"CODEX_FROZEN_DIAGNOSTICS = {json.dumps(str(mcp_diagnostics))}",
            ]
            config_path = codex_home / "config.toml"
            config_path.write_text("\n".join(config_lines) + "\n", encoding="utf-8")
            env = {k: os.environ[k] for k in ("PATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP") if k in os.environ}
            env.update({"CODEX_HOME": str(codex_home), "HOME": str(home), "USERPROFILE": str(home),
                        "OPENAI_API_KEY": "offline-probe-only",
                        "CODEX_FROZEN_ROOT": str(frozen_root), "CODEX_FROZEN_RECEIPTS": str(mcp_receipts),
                        "CODEX_FROZEN_DIAGNOSTICS": str(mcp_diagnostics),
                        "RUST_LOG": "codex_core=debug"})
            hooks_list_error = "native hooks disabled: Windows command-hook stdin is a character handle without payload"
            prompt = "Reply with the fixed offline probe completion message. Do not call tools."
            if phase == "appserver_exec":
                cli_rc, cli_event_summary, cli_error_summaries = _appserver_probe(codex, env, neutral, timeout)
                stdout, stderr = b"", b""
            else:
                proc = subprocess.Popen(
                    [str(codex), "exec", "--json", "--strict-config",
                     "--sandbox", "read-only", "--cd", str(neutral),
                     "--skip-git-repo-check", "--model", "gpt-6-astra", prompt],
                    cwd=str(neutral), env=env, stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
                try:
                    stdout, stderr = proc.communicate(timeout=timeout)
                    cli_rc = proc.returncode
                except subprocess.TimeoutExpired:
                    proc.kill()
                    stdout, stderr = proc.communicate()
                    cli_rc = proc.returncode
                cli_err_class = _safe_error_class(stderr)
            marker_start = start_marker.exists()
            marker_pretool = pretool_marker.exists()
            hook_log_summaries = _safe_hook_log_summaries(codex_home)
            for line in stdout.decode("utf-8", "replace").splitlines():
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(event, dict):
                    item = event.get("item") if isinstance(event.get("item"), dict) else {}
                    summarized = {"type": event.get("type")}
                    if isinstance(item.get("type"), str):
                        summarized["item_type"] = item["type"]
                    if isinstance(item.get("name"), str):
                        summarized["item_name"] = item["name"]
                    if item.get("type") == "error":
                        error_class = _safe_event_error_class(item)
                        cli_error_classes.append(error_class)
                        summarized["error_class"] = error_class
                        if len(cli_error_summaries) < 12:
                            cli_error_summaries.append(_safe_error_summary(item))
                    if len(cli_event_summary) < 40:
                        cli_event_summary.append(summarized)
            # Only summarize hook-specific diagnostics in logs; never retain transcript/output content.
            if guard_log.exists():
                for line in guard_log.read_text(encoding="utf-8").splitlines():
                    try:
                        guard_events.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
            if mcp_receipts.exists():
                for line in mcp_receipts.read_text(encoding="utf-8").splitlines():
                    try:
                        entry = json.loads(line)
                        # codex_frozen.record_call deliberately writes the
                        # compact names `method` and `outcome`; retain no args
                        # or returned content in the hostprobe receipt.
                        outcome = entry.get("outcome")
                        is_error = isinstance(outcome, str) and outcome.startswith("error:")
                        result_class = outcome if isinstance(outcome, str) else "unknown"
                        method = entry.get("method")
                        canonical_tool = "mcp__frozen__" + method if isinstance(method, str) else None
                        mcp_events.append({"tool": canonical_tool, "status": outcome,
                                           "isError": is_error, "result_class": result_class})
                    except json.JSONDecodeError:
                        continue
            mcp_timing_events: list[dict[str, Any]] = []
            if mcp_diagnostics.exists():
                for line in mcp_diagnostics.read_text(encoding="utf-8").splitlines():
                    try:
                        item = json.loads(line)
                        if isinstance(item, dict):
                            mcp_timing_events.append({key: item[key] for key in ("tool", "stage", "event", "elapsed_ms", "status") if key in item})
                    except json.JSONDecodeError:
                        continue
            start_hooks = sum(e.get("event") == "SessionStart" and e.get("decision") == "baseline" for e in guard_events)
            tool_names = list(state.tool_names)
            expected_request = "functions__exec" in tool_names and set(tool_names) <= {
                "functions__exec", "functions__wait", "functions__request_user_input",
                "functions__request_user_input_async", "clock__sleep", *FROZEN_TOOLS,
            }
            if phase in {"exec", "host_inventory", "appserver_exec"}:
                tool_names_expected = set(state.probe_result.get("toolNames", [])) == set(FROZEN_TOOLS) if state.probe_result else False
                agent_apis = state.probe_result.get("agentApiTypes", {}) if state.probe_result else {}
                agents_off = bool(agent_apis) and all(
                    isinstance(v, dict) and v.get("global") == "undefined" and v.get("tool") == "undefined"
                    for v in agent_apis.values()
                )
                globals_ok = bool(state.probe_result) and not state.probe_result.get("forbiddenGlobalNames") and not state.probe_result.get("unlistedCallableNames") and agents_off
                escapes_ok = bool(state.probe_result) and all(
                    value == "undefined" for value in state.probe_result.get("constructorEscapeTypes", {}).values()
                ) and set(state.probe_result.get("importStatus", {}).keys()) == {"node:fs", "node:child_process", "node:https"} and all(
                    str(value).startswith("rejected:") for value in state.probe_result.get("importStatus", {}).values()
                )
                frozen_call = state.probe_result.get("frozenListStatus") == "ok" if state.probe_result else False
                pretool = sum(e.get("event") == "PreToolUse" and e.get("decision") == "allow" and e.get("tool", "").startswith("mcp__frozen__") for e in guard_events)
                denied_canary = sum(e.get("event") == "PreToolUse" and e.get("decision") == "deny" and e.get("tool") == "mcp__frozen__list" for e in guard_events)
                hook_input_error = any(e.get("event") == "HookInputError" for e in guard_events)
                if phase == "host_inventory":
                    status = "OBSERVED" if cli_rc == 0 and state.requests >= 2 and state.bad_requests == 0 and expected_request and state.probe_result else "FAIL"
                else:
                    tool_receipts_ok = len(mcp_events) == 2 and mcp_events[0].get("status") == "ok" and str(mcp_events[1].get("status", "")).startswith("error:")
                    independent_boundary_ok = (
                        cli_rc == 0 and state.requests >= 2 and state.bad_requests == 0 and expected_request
                        and tool_names_expected and globals_ok and escapes_ok and frozen_call
                        and state.probe_result.get("unknownParameterStatus") == "server_rejected"
                        and tool_receipts_ok and exclude_native_host_tools
                    )
                    status = "PASS" if independent_boundary_ok else "FAIL"
            elif phase == "transport":
                transport_calls = state.probe_result.get("transportCalls", []) if state.probe_result else []
                transport_labels = {call.get("label") for call in transport_calls if isinstance(call, dict)}
                transport_ok = (
                    len(transport_calls) == 5 and
                    transport_labels == {"search_server_lib", "search_output_log", "sql_select_readonly", "read_manifest", "list_root"} and
                    all(call.get("isError") is False and call.get("result_class") == "ok" and
                        isinstance(call.get("elapsed_ms"), int) and 0 <= call["elapsed_ms"] < 55_000
                        for call in transport_calls)
                )
                status = "PASS" if (cli_rc == 0 and state.requests >= 2 and state.bad_requests == 0 and
                                     expected_request and transport_ok and len(mcp_events) == 5 and
                                     all(event.get("status") == "ok" for event in mcp_events)) else "FAIL"
            else:
                status = "PASS" if cli_rc == 0 and state.requests >= 1 and state.bad_requests == 0 and expected_request else "FAIL"
            receipt = {
                "schema_version": 1, "kind": "codex_hostprobe", "phase": phase,
                "status": status, "cli_version": version, "cli_sha256": _sha(codex),
                "host_binary": str(codex.with_name("codex-code-mode-host.exe")),
                "host_sha256": _sha(codex.with_name("codex-code-mode-host.exe")) if codex.with_name("codex-code-mode-host.exe").is_file() else None,
                "provider": {"bound_host": "127.0.0.1", "port_ephemeral": True,
                             "requests": state.requests, "bad_requests": state.bad_requests, "external_hosts": 0,
                             "credential": "dummy"},
                "config": {"code_mode": True, "code_mode_host": True, "shell_tool": False,
                           "multi_agent": False, "agents_enabled": False, "view_image": False, "hooks_enabled": False,
                           "mcp_default_tools_approval_mode": "approve",
                           "excluded_tool_namespaces": ((["functions", "clock"] if exclude_native_host_tools else []) + ["mcp__codex_apps", "mcp__plugins"]),
                           "mcp_tools": FROZEN_TOOLS},
                "request_tool_names": tool_names, "request_tool_names_by_request": state.tool_names_by_request,
                "request_tool_schema_keys": state.schema_keys,
                "request_root_keys": state.root_keys, "request_service_tier": state.service_tier,
                "request_input_shape": state.request_input_shape,
                "host": ({"global_names": state.probe_result.get("globalNames", []),
                          "forbidden_global_names": state.probe_result.get("forbiddenGlobalNames", []),
                          "agent_api_types": state.probe_result.get("agentApiTypes", {}),
                          "constructor_escape_types": state.probe_result.get("constructorEscapeTypes", {}),
                          "dynamic_import_status": state.probe_result.get("importStatus", {}),
                          "tool_names": state.probe_result.get("toolNames", []),
                          "tool_namespace_keys": state.probe_result.get("toolNamespaceKeys", []),
                          "callable_names": state.probe_result.get("directCallableToolNames", []),
                          "direct_callable_tool_names": state.probe_result.get("directCallableToolNames", []),
                          "unlisted_callable_names": state.probe_result.get("unlistedCallableNames", []),
                          "frozen_list_call": state.probe_result.get("frozenListStatus"),
                          "list_response_shape": state.probe_result.get("listShape"),
                          "unknown_parameter_status": state.probe_result.get("unknownParameterStatus"),
                          "unknown_parameter_isError": (state.probe_result.get("unknownShape", {}).get("isError") is True),
                          "unknown_parameter_response_shape": state.probe_result.get("unknownShape")}
                         if phase in {"exec", "host_inventory", "appserver_exec"} and state.probe_result else None),
                "transport_calls": (state.probe_result.get("transportCalls", [])
                                    if phase == "transport" and state.probe_result else None),
                "hooks": {"session_start_receipts": start_hooks,
                          "session_start_marker": marker_start,
                          "pretool_marker": marker_pretool,
                          "listed_before_trust": hooks_before_trust,
                          "listed_after_trust": hooks_after_trust,
                          "hooks_list_shape": hooks_list_shape,
                          "hooks_list_error": hooks_list_error,
                          "private_trust_verified": hook_trust_verified,
                          "hook_log_summaries": hook_log_summaries,
                          "pretool_allow_frozen": sum(e.get("event") == "PreToolUse" and e.get("decision") == "allow" for e in guard_events),
                          "pretool_deny_other": sum(e.get("event") == "PreToolUse" and e.get("decision") == "deny" for e in guard_events),
                          "pretool_deny_unknown_parameter": sum(e.get("event") == "PreToolUse" and e.get("decision") == "deny" and e.get("tool") == "mcp__frozen__list" for e in guard_events),
                          "input_error_types": sorted({e.get("error_type") for e in guard_events if e.get("event") == "HookInputError" and isinstance(e.get("error_type"), str)}),
                          "input_errors": [{
                              "type": e.get("error_type"), "winerror": e.get("winerror"),
                              "stage": e.get("stage"), "bytes_received": e.get("bytes_received"),
                              "stdin_type": e.get("stdin_type"), "pipe_available": e.get("pipe_available"),
                              "errno": e.get("errno"), "sample_hex": e.get("sample_hex"),
                              "parent_pid": e.get("parent_pid"), "parent_image": e.get("parent_image"),
                              "hook_input_env_names": e.get("hook_input_env_names", []),
                          } for e in guard_events if e.get("event") == "HookInputError"][:8]},
                "hook_enforcement": {
                    "status": "UNAVAILABLE",
                    "reason": "Hooks disabled in this profile; separate stdin diagnostic found FILE_TYPE_CHAR with zero payload bytes.",
                    "diagnostic_receipt": "offline-hostprobe-input-contract.json",
                },
                "mcp_calls": mcp_events, "mcp_timing_events": mcp_timing_events,
                "cli_returncode": cli_rc,
                "cli_error_class": cli_err_class,
                "cli_event_summary": cli_event_summary,
                "cli_error_classes": cli_error_classes,
                "cli_error_summaries": cli_error_summaries,
                "cli_stderr_summaries": _safe_stderr_summary(stderr),
            }
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description="Run an offline, loopback-only Codex Code Mode startup probe.")
    parser.add_argument("--codex", required=True, type=Path, help="absolute path to installed codex.exe")
    parser.add_argument("--model-cache", required=True, type=Path, help="non-secret models_cache.json with code_mode_only model metadata")
    parser.add_argument("--frozen-root", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--phase", choices=("inventory", "exec", "host_inventory", "appserver_exec", "transport"), default="inventory")
    parser.add_argument("--private-parent", type=Path, help="existing private parent for fresh non-TEMP probe home")
    parser.add_argument("--exclude-native-host-tools", action="store_true", help="offline-only candidate excluding functions and clock from nested host")
    args = parser.parse_args()
    try:
        result = run_inventory(args.codex, args.model_cache, args.receipt, args.frozen_root, args.timeout, args.phase, args.private_parent, args.exclude_native_host_tools)
    except Exception as exc:
        if args.receipt.is_file():
            try:
                receipt = json.loads(args.receipt.read_text(encoding="utf-8"))
                receipt["cleanup_error"] = {"type": type(exc).__name__, "message": str(exc)[:300]}
                args.receipt.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
            except Exception:
                pass
        print(f"hostprobe setup failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(f"HOSTPROBE {result['status']} phase={result['phase']} requests={result['provider']['requests']} session_start_hooks={result['hooks']['session_start_receipts']} markers={int(result['hooks']['session_start_marker'])}/{int(result['hooks']['pretool_marker'])} tool_names={','.join(result['request_tool_names'])}")
    return 0 if result["status"] in {"PASS", "OBSERVED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
