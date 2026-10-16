"""Minimal stdio MCP gateway for frozen fixture reads only.

Configure the Codex run to expose this server's four tools and no shell or
filesystem tools. Receipts are appended to CODEX_FROZEN_RECEIPTS, which must
name an output path outside the frozen fixture.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# `python -I` removes the script directory from sys.path; restore only this
# trusted sibling directory, never cwd or caller-controlled paths.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from codex_frozen import FrozenAccessError, FrozenDB, FrozenRoot, record_call

ROOT = Path(os.environ.get("CODEX_FROZEN_ROOT", r"C:\KenshiTestRuns\invest\frozen-2026-10-14"))
RECEIPTS = Path(os.environ.get("CODEX_FROZEN_RECEIPTS", r"C:\KenshiTestRuns\invest\codex-tool-calls.jsonl"))

TOOLS = [
    {"name": "list", "description": "List entries inside the frozen fixture.", "inputSchema": {"type": "object", "properties": {"path": {"type": "string", "default": "."}}, "additionalProperties": False}},
    {"name": "read", "description": "Read a bounded line page of UTF-8 text from the frozen fixture.", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}, "byte_limit": {"type": "integer", "default": 100000}, "start_line": {"type": "integer", "minimum": 1, "default": 1}, "line_count": {"type": "integer", "minimum": 1, "maximum": 500, "default": 200}}, "required": ["path"], "additionalProperties": False}},
    {"name": "search", "description": "Search frozen UTF-8 text with a bounded 30-second scan budget, truncation status, and file cursor for resuming deep logs.", "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}, "path": {"type": "string", "default": "."}, "max_results": {"type": "integer", "default": 50}, "byte_budget": {"type": "integer", "minimum": 1, "maximum": 20000000, "default": 20000000}, "byte_offset": {"type": "integer", "minimum": 0, "default": 0}, "start_line": {"type": "integer", "minimum": 1, "default": 1}}, "required": ["query"], "additionalProperties": False}},
    {"name": "sql", "description": "Run a bounded plain SELECT against stobe_frozen using the configured read-only DB role.", "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"], "additionalProperties": False}},
]


def _call(name: str, args: dict) -> object:
    fs = FrozenRoot(ROOT)
    if name == "list":
        if not set(args) <= {"path"}:
            raise FrozenAccessError("list accepts only path")
        return fs.list(args.get("path", "."))
    if name == "read":
        if set(args) - {"path", "byte_limit", "start_line", "line_count"} or "path" not in args:
            raise FrozenAccessError("read accepts only path, byte_limit, start_line, and line_count")
        return fs.read(args["path"], args.get("byte_limit", 100000),
                       args.get("start_line", 1), args.get("line_count", 200))
    if name == "search":
        if set(args) - {"query", "path", "max_results", "byte_budget", "byte_offset", "start_line"} or "query" not in args:
            raise FrozenAccessError("search accepts only query, path, max_results, byte_budget, byte_offset, and start_line")
        return fs.search(args["query"], args.get("path", "."), args.get("max_results", 50),
                         args.get("byte_budget", 20_000_000), args.get("byte_offset", 0),
                         args.get("start_line", 1))
    if name == "sql":
        if set(args) != {"query"}:
            raise FrozenAccessError("sql accepts only query")
        return FrozenDB("stobe_frozen").select(args["query"])
    raise FrozenAccessError("unknown tool")


def _response(request: dict) -> dict:
    method = request.get("method")
    params = request.get("params") or {}
    rid = request.get("id")
    if method == "initialize":
        result = {"protocolVersion": params.get("protocolVersion", "2024-11-05"),
                  "capabilities": {"tools": {}}, "serverInfo": {"name": "codex-frozen-readonly", "version": "1.0.0"}}
    elif method == "notifications/initialized":
        return {}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        name = params.get("name", "")
        args = params.get("arguments") or {}
        try:
            data = _call(name, args)
            record_call(RECEIPTS, name, args, "ok", ROOT)
            content = json.dumps(data, ensure_ascii=False, default=str)
            result = {"content": [{"type": "text", "text": content}], "isError": False}
        except Exception as exc:
            try:
                record_call(RECEIPTS, name, args, "error:" + type(exc).__name__, ROOT)
            except Exception:
                pass
            result = {"content": [{"type": "text", "text": str(exc)}], "isError": True}
    else:
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "Method not found"}}
    if rid is None:
        return {}
    return {"jsonrpc": "2.0", "id": rid, "result": result}


def main() -> None:
    # MCP stdio uses newline-delimited JSON-RPC. Never write diagnostics to stdout.
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    for line in sys.stdin:
        try:
            req = json.loads(line)
            response = _response(req)
            if response:
                sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
                sys.stdout.flush()
        except Exception as exc:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": None,
                                         "error": {"code": -32700, "message": type(exc).__name__}}) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
