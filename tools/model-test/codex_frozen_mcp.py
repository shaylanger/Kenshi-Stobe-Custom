"""Minimal stdio MCP gateway for frozen fixture reads only.

Configure the Codex run to expose this server's four tools and no shell or
filesystem tools. Receipts are appended to CODEX_FROZEN_RECEIPTS, which must
name an output path outside the frozen fixture.
"""
from __future__ import annotations

import json
import hashlib
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# `python -I` removes the script directory from sys.path; restore only this
# trusted sibling directory, never cwd or caller-controlled paths.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from codex_frozen import FrozenAccessError, FrozenDB, FrozenRoot, record_call

ROOT = Path(os.environ.get("CODEX_FROZEN_ROOT", r"C:\KenshiTestRuns\invest\frozen-2026-10-14"))
RECEIPTS = Path(os.environ.get("CODEX_FROZEN_RECEIPTS", r"C:\KenshiTestRuns\invest\codex-tool-calls.jsonl"))
DIAGNOSTICS = Path(os.environ.get("CODEX_FROZEN_DIAGNOSTICS", str(RECEIPTS.with_name("codex-frozen-timings.jsonl"))))
_STDOUT_LOCK = threading.Lock()
_DIAGNOSTICS_LOCK = threading.Lock()
MAX_CONCURRENT_CALLS = 4
MAX_QUEUED_CALLS = 8

TOOLS = [
    {"name": "list", "description": "List entries inside the frozen fixture.", "inputSchema": {"type": "object", "properties": {"path": {"type": "string", "default": "."}}, "additionalProperties": False}},
    {"name": "read", "description": "Read a bounded line page of UTF-8 text from the frozen fixture.", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}, "byte_limit": {"type": "integer", "default": 100000}, "start_line": {"type": "integer", "minimum": 1, "default": 1}, "line_count": {"type": "integer", "minimum": 1, "maximum": 500, "default": 200}}, "required": ["path"], "additionalProperties": False}},
    {"name": "search", "description": "Search frozen UTF-8 text with a bounded 30-second scan budget, truncation status, and file cursor for resuming deep logs.", "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}, "path": {"type": "string", "default": "."}, "max_results": {"type": "integer", "default": 50}, "byte_budget": {"type": "integer", "minimum": 1, "maximum": 20000000, "default": 20000000}, "byte_offset": {"type": "integer", "minimum": 0, "default": 0}, "start_line": {"type": "integer", "minimum": 1, "default": 1}}, "required": ["query"], "additionalProperties": False}},
    {"name": "sql", "description": "Run a bounded plain SELECT against stobe_frozen using the configured read-only DB role.", "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"], "additionalProperties": False}},
]

STARTUP_RECEIPTS = os.environ.get("CODEX_BENCH_STARTUP_RECEIPTS")


def _process_identity(pid: int) -> dict:
    if os.name != "nt":
        return {"pid": pid, "query": "unsupported-platform"}
    import ctypes
    from ctypes import wintypes
    handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return {"pid": pid, "query": "unavailable"}
    try:
        image = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(image))
        if not ctypes.windll.kernel32.QueryFullProcessImageNameW(handle, 0, image, ctypes.byref(size)):
            return {"pid": pid, "query": "image-unavailable"}
        created = wintypes.FILETIME(); exited = wintypes.FILETIME()
        kernel = wintypes.FILETIME(); user = wintypes.FILETIME()
        if not ctypes.windll.kernel32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited),
                                                      ctypes.byref(kernel), ctypes.byref(user)):
            return {"pid": pid, "query": "creation-unavailable"}
        ticks = (created.dwHighDateTime << 32) | created.dwLowDateTime
        created_utc = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ticks / 10_000_000 - 11_644_473_600)) + "Z"
        image_path = Path(image.value)
        return {"pid": pid, "image": str(image_path), "image_sha256": hashlib.sha256(image_path.read_bytes()).hexdigest(),
                "created_utc": created_utc}
    finally:
        ctypes.windll.kernel32.CloseHandle(handle)


def _record_startup(method: str) -> None:
    """Record only the real participant CLI's MCP readiness handshake."""
    if not STARTUP_RECEIPTS or not os.environ.get("CODEX_BENCH_EXEC_NONCE"):
        return
    config_path = Path(os.environ.get("CODEX_BENCH_CONFIG_PATH", ""))
    try:
        config_sha = hashlib.sha256(config_path.read_bytes()).hexdigest()
        source_sha = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        row = {"method": method, "utc": time.time(),
               "nonce_sha256": hashlib.sha256(os.environ["CODEX_BENCH_EXEC_NONCE"].encode()).hexdigest(),
               "attempt_id": os.environ.get("CODEX_BENCH_ATTEMPT_ID"),
               "config_sha256": config_sha, "source_sha256": source_sha,
               "server_pid": os.getpid(), "parent_pid": os.getppid(),
               "parent_identity": _process_identity(os.getppid()),
               "tools": [tool["name"] for tool in TOOLS] if method == "tools/list" else []}
        target = Path(STARTUP_RECEIPTS)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(row, sort_keys=True) + "\n")
    except OSError:
        return


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
    readiness_method = None
    params = request.get("params") or {}
    rid = request.get("id")
    if method == "initialize":
        readiness_method = "initialize"
        result = {"protocolVersion": params.get("protocolVersion", "2024-11-05"),
                  "capabilities": {"tools": {}}, "serverInfo": {"name": "codex-frozen-readonly", "version": "1.0.0"}}
    elif method == "notifications/initialized":
        return {}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        readiness_method = "tools/list"
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
    if readiness_method:
        _record_startup(readiness_method)
    return {"jsonrpc": "2.0", "id": rid, "result": result}


def _write_diagnostic(tool: str, event: str, elapsed_ms: int | None = None,
                      status: str | None = None) -> None:
    """Append bounded call timing metadata without request args or results."""
    try:
        target = DIAGNOSTICS.resolve()
        root = ROOT.resolve()
        try:
            target.relative_to(root)
            return
        except ValueError:
            pass
        target.parent.mkdir(parents=True, exist_ok=True)
        entry = {"tool": tool, "stage": "mcp.tools.call." + tool, "event": event}
        if elapsed_ms is not None:
            entry["elapsed_ms"] = max(0, elapsed_ms)
        if status is not None:
            entry["status"] = status
        with _DIAGNOSTICS_LOCK, target.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, sort_keys=True) + "\n")
    except OSError:
        # Diagnostics must not make a read-only tool unavailable.
        return


def _write_response(response: dict) -> None:
    with _STDOUT_LOCK:
        sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def _complete_call(request: dict, tool: str, started: float, handler) -> None:
    try:
        response = handler(request)
        result = response.get("result") if isinstance(response, dict) else None
        status = "error" if isinstance(result, dict) and result.get("isError") is True else "ok"
    except Exception as exc:
        response = {"jsonrpc": "2.0", "id": request.get("id"),
                    "error": {"code": -32603, "message": type(exc).__name__}}
        status = "error"
    elapsed_ms = int((time.monotonic() - started) * 1000)
    _write_diagnostic(tool, "completed", elapsed_ms, status)
    _write_response(response)


def serve(stdin=None, worker_count: int = MAX_CONCURRENT_CALLS, response_handler=None) -> None:
    """Serve MCP JSON-RPC, allowing bounded concurrent tool calls.

    Responses may complete out of order as permitted by JSON-RPC IDs. Keeping
    the stdin reader free means a long search/WSL query cannot block later
    list/read calls behind it.
    """
    source = stdin if stdin is not None else sys.stdin
    handler = response_handler or _response
    with ThreadPoolExecutor(max_workers=worker_count, thread_name_prefix="frozen-mcp") as pool:
        futures = []
        for line in source:
            try:
                request = json.loads(line)
                if not isinstance(request, dict):
                    raise ValueError("request must be an object")
            except Exception as exc:
                _write_response({"jsonrpc": "2.0", "id": None,
                                 "error": {"code": -32700, "message": type(exc).__name__}})
                continue
            if request.get("method") != "tools/call":
                try:
                    response = handler(request)
                    if response:
                        _write_response(response)
                except Exception as exc:
                    _write_response({"jsonrpc": "2.0", "id": request.get("id"),
                                     "error": {"code": -32603, "message": type(exc).__name__}})
                continue
            futures = [future for future in futures if not future.done()]
            if len(futures) >= MAX_QUEUED_CALLS:
                _write_response({"jsonrpc": "2.0", "id": request.get("id"),
                                 "error": {"code": -32000, "message": "frozen MCP server is busy"}})
                continue
            params = request.get("params") if isinstance(request.get("params"), dict) else {}
            tool = params.get("name") if isinstance(params.get("name"), str) else "unknown"
            started = time.monotonic()
            _write_diagnostic(tool, "started")
            future = pool.submit(_complete_call, request, tool, started, handler)
            futures.append(future)
        for future in futures:
            future.result()


def main() -> None:
    # MCP stdio uses newline-delimited JSON-RPC. Never write diagnostics to stdout.
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    serve()


if __name__ == "__main__":
    main()
