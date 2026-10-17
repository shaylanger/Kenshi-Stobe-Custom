"""Read-only access primitives for the frozen Codex investigation fixture.

This module deliberately provides no general filesystem or SQL interface. The
only database connection it accepts is an explicitly configured frozen DB DSN.
For model runs, expose these operations through the companion stdio MCP server
and disable shell/file tools in the run's tool policy; Python checks cannot
constrain a model that also has an unrestricted shell.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time
from typing import Any

DEFAULT_ROOT = Path(r"C:\KenshiTestRuns\invest\frozen-2026-10-14")
MAX_READ_BYTES = 1_000_000
MAX_READ_LINES = 500
MAX_READ_SKIP_BYTES = 200_000_000
MAX_SEARCH_RESULTS = 200
MAX_SEARCH_BYTES = 20_000_000
MAX_SEARCH_LINE_BYTES = 64_000
MAX_SEARCH_SECONDS = 20
MAX_SEARCH_TREE_ENTRIES = 50_000
MAX_SEARCH_FILES = 10_000
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")
_LIVE_PATH = re.compile(r"(?i)(?:/var/www/html/StobeServer|/root/stobe-work|/root/STOBE-src|C:[\\/]StobeBuild|D:[\\/]Steam[\\/]steamapps[\\/]common[\\/]Kenshi|pending-fixes|\bstobe\b(?!_frozen))")


class FrozenAccessError(ValueError):
    """A request is outside the frozen read-only surface."""


_RECEIPT_LOCK = threading.Lock()


class FrozenRoot:
    def __init__(self, root: Path | str = DEFAULT_ROOT):
        self.root = Path(root).resolve(strict=True)
        if not self.root.is_dir():
            raise FrozenAccessError("frozen root is not a directory")

    def _resolve(self, relative: str) -> Path:
        rel = Path(relative)
        if rel.is_absolute() or ".." in rel.parts or not relative or "\x00" in relative:
            raise FrozenAccessError("path must be a nonempty relative frozen path")
        try:
            target = (self.root / rel).resolve(strict=True)
        except FileNotFoundError as exc:
            # A missing requested target inside a live fixture is a safe,
            # typed access rejection. A missing fixture root remains raw
            # infrastructure failure, including loss after initialization.
            if not self.root.is_dir():
                raise
            raise FrozenAccessError("requested frozen target does not exist") from exc
        try:
            target.relative_to(self.root)
        except ValueError as exc:
            raise FrozenAccessError("path escapes frozen root") from exc
        return target

    def list(self, relative: str = ".") -> list[dict[str, Any]]:
        target = self.root if relative == "." else self._resolve(relative)
        if not target.is_dir():
            raise FrozenAccessError("list target is not a directory")
        entries = []
        for p in sorted(target.iterdir(), key=lambda x: x.name.casefold()):
            try:
                resolved = p.resolve(strict=True)
                resolved.relative_to(self.root)
            except (OSError, ValueError):
                continue  # broken or escaping symlinks are not exposed
            st = resolved.stat()
            entries.append({"name": p.name, "type": "directory" if resolved.is_dir() else "file",
                            "size": st.st_size if resolved.is_file() else None})
        return entries

    def read(self, relative: str, byte_limit: int = 100_000, start_line: int = 1,
             line_count: int = 200) -> dict[str, Any]:
        if not 1 <= byte_limit <= MAX_READ_BYTES:
            raise FrozenAccessError(f"byte_limit must be between 1 and {MAX_READ_BYTES}")
        if not isinstance(start_line, int) or isinstance(start_line, bool) or start_line < 1:
            raise FrozenAccessError("start_line must be an integer >= 1")
        if not isinstance(line_count, int) or isinstance(line_count, bool) or not 1 <= line_count <= MAX_READ_LINES:
            raise FrozenAccessError(f"line_count must be between 1 and {MAX_READ_LINES}")
        p = self._resolve(relative)
        if not p.is_file():
            raise FrozenAccessError("read target is not a regular file")
        selected: list[str] = []
        page_bytes = 0
        skipped_bytes = 0
        total_lines: int | None = None
        has_more = False
        with p.open("rb") as handle:
            deadline = time.monotonic() + 30
            line_no = 1
            partial_skipped_line = False
            while line_no < start_line:
                if time.monotonic() >= deadline or skipped_bytes >= MAX_READ_SKIP_BYTES:
                    raise FrozenAccessError("requested start_line exceeds bounded scan budget")
                chunk = handle.readline(min(65_536, MAX_READ_SKIP_BYTES - skipped_bytes + 1))
                if not chunk:
                    total_lines = line_no if partial_skipped_line else line_no - 1
                    break
                skipped_bytes += len(chunk)
                if skipped_bytes > MAX_READ_SKIP_BYTES:
                    raise FrozenAccessError("requested start_line exceeds bounded scan budget")
                if b"\x00" in chunk:
                    raise FrozenAccessError("binary files cannot be read as text")
                partial_skipped_line = True
                if chunk.endswith(b"\n"):
                    line_no += 1
                    partial_skipped_line = False
            else:
                while len(selected) < line_count:
                    raw = handle.readline(byte_limit - page_bytes + 1)
                    if not raw:
                        total_lines = line_no - 1
                        break
                    page_bytes += len(raw)
                    if page_bytes > byte_limit:
                        raise FrozenAccessError("requested line page exceeds byte limit")
                    if b"\x00" in raw:
                        raise FrozenAccessError("binary files cannot be read as text")
                    try:
                        selected.append(raw.decode("utf-8"))
                    except UnicodeDecodeError as exc:
                        raise FrozenAccessError("file is not UTF-8 text") from exc
                    line_no += 1
                if len(selected) == line_count:
                    has_more = bool(handle.read(1))
                    if not has_more:
                        total_lines = line_no - 1
        end_line = start_line + len(selected) - 1
        numbered = "".join(f"{start_line + i:06d}\t{line}" for i, line in enumerate(selected))
        return {"path": Path(relative).as_posix(), "start_line": start_line,
                "end_line": end_line, "total_lines": total_lines, "has_more": has_more,
                "text": numbered}

    def search(self, query: str, relative: str = ".", max_results: int = 50,
               byte_budget: int = MAX_SEARCH_BYTES, byte_offset: int = 0,
               start_line: int = 1) -> dict[str, Any]:
        deadline = time.monotonic() + MAX_SEARCH_SECONDS
        if (not query or len(query) > 500 or not 1 <= max_results <= MAX_SEARCH_RESULTS or
                not 1 <= byte_budget <= MAX_SEARCH_BYTES or not isinstance(byte_offset, int) or
                isinstance(byte_offset, bool) or byte_offset < 0 or not isinstance(start_line, int) or
                isinstance(start_line, bool) or start_line < 1):
            raise FrozenAccessError("invalid query or max_results")
        try:
            start = self.root if relative == "." else self._resolve(relative)
        except FileNotFoundError as exc:
            # Keep root loss fail-closed even if it happens after __init__.
            if not self.root.is_dir():
                raise
            raise FrozenAccessError("search target does not exist") from exc
        if time.monotonic() >= deadline:
            raise FrozenAccessError("search exceeded its time budget resolving the path")
        if (byte_offset or start_line != 1) and not start.is_file():
            raise FrozenAccessError("search cursors require a single file path")
        if start.is_file() and byte_offset > start.stat().st_size:
            raise FrozenAccessError("search cursor is beyond end of file")
        walk_state = {"truncated": False}
        files = [start] if start.is_file() else self._iter_search_files(start, deadline, walk_state)
        result: list[dict[str, Any]] = []
        bytes_scanned = 0
        files_scanned = 0
        truncated = False
        long_lines_skipped = 0
        next_cursor: dict[str, int] | None = None
        for p in files:
            if time.monotonic() >= deadline:
                truncated = True
                break
            try:
                resolved = p.resolve(strict=True)
                resolved.relative_to(self.root)
                if not resolved.is_file():
                    continue
                files_scanned += 1
                with resolved.open("rb") as handle:
                    offset = byte_offset if resolved == start else 0
                    line_no = start_line - 1 if resolved == start else 0
                    handle.seek(offset)
                    while bytes_scanned < byte_budget:
                        if time.monotonic() >= deadline:
                            truncated = True
                            break
                        remaining = byte_budget - bytes_scanned
                        raw = handle.readline(min(MAX_SEARCH_LINE_BYTES + 1, remaining))
                        if not raw:
                            break
                        bytes_scanned += len(raw)
                        if bytes_scanned > byte_budget:
                            truncated = True
                            break
                        if bytes_scanned == byte_budget and not raw.endswith(b"\n"):
                            # Do not report a possible match from a partial final line.
                            truncated = True
                            break
                        if len(raw) > MAX_SEARCH_LINE_BYTES:
                            line_no += 1
                            # Long lines are deliberately omitted from matching, but drain
                            # them with EOF and time checks so a final unterminated record
                            # cannot pin the single-threaded MCP server forever.
                            long_lines_skipped += 1
                            while not raw.endswith(b"\n") and bytes_scanned < byte_budget:
                                if time.monotonic() >= deadline:
                                    truncated = True
                                    break
                                raw = handle.readline(min(MAX_SEARCH_LINE_BYTES + 1, byte_budget - bytes_scanned))
                                if not raw:
                                    break
                                bytes_scanned += len(raw)
                                if bytes_scanned > byte_budget:
                                    truncated = True
                                    break
                            if truncated:
                                break
                            next_cursor = {"byte_offset": handle.tell(), "start_line": line_no + 1}
                            continue
                        if b"\x00" in raw:
                            break
                        try:
                            line = raw.decode("utf-8").rstrip("\r\n")
                        except UnicodeDecodeError:
                            break
                        line_no += 1
                        if raw.endswith(b"\n"):
                            next_cursor = {"byte_offset": handle.tell(), "start_line": line_no + 1}
                        if query.casefold() in line.casefold():
                            result.append({"path": resolved.relative_to(self.root).as_posix(),
                                           "line": line_no, "text": line[:2000]})
                            if len(result) >= max_results:
                                return {"results": result, "truncated": True,
                                        "bytes_scanned": bytes_scanned, "files_scanned": files_scanned,
                                        "long_lines_skipped": long_lines_skipped,
                                        "incomplete": long_lines_skipped > 0,
                                        "next_cursor": next_cursor if start.is_file() else None}
                    if bytes_scanned >= byte_budget:
                        truncated = True
                if truncated:
                    break
            except (OSError, ValueError):
                continue
        if walk_state["truncated"]:
            truncated = True
        return {"results": result, "truncated": truncated,
                "bytes_scanned": bytes_scanned, "files_scanned": files_scanned,
                "long_lines_skipped": long_lines_skipped,
                "incomplete": long_lines_skipped > 0,
                "next_cursor": next_cursor if truncated and start.is_file() else None}

    def _iter_search_files(self, start: Path, deadline: float, state: dict[str, bool]):
        """Yield in-root regular files without eager recursive enumeration."""
        stack = [start]
        entries_seen = 0
        files_seen = 0
        while stack:
            if time.monotonic() >= deadline or entries_seen >= MAX_SEARCH_TREE_ENTRIES:
                state["truncated"] = True
                return
            directory = stack.pop()
            subdirectories: list[Path] = []
            try:
                with os.scandir(directory) as entries:
                    for entry in entries:
                        if time.monotonic() >= deadline or entries_seen >= MAX_SEARCH_TREE_ENTRIES:
                            state["truncated"] = True
                            return
                        entries_seen += 1
                        try:
                            if entry.is_symlink() or _is_reparse_point(entry):
                                continue
                            if entry.is_dir(follow_symlinks=False):
                                subdirectories.append(Path(entry.path))
                            elif entry.is_file(follow_symlinks=False):
                                files_seen += 1
                                if files_seen > MAX_SEARCH_FILES:
                                    state["truncated"] = True
                                    return
                                yield Path(entry.path)
                        except OSError:
                            continue
            except OSError:
                continue
            subdirectories.sort(key=lambda path: path.name.casefold())
            stack.extend(reversed(subdirectories))


def _parse_manifest(path: Path) -> list[tuple[str, str]]:
    if not path.is_file() or path.stat().st_size == 0:
        raise FrozenAccessError(f"missing or empty {path.name}")
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if m:
            out.append((m.group(1), m.group(2)))
        elif " | " in line:
            # Data checks have description | command | expected-output format.
            parts = line.split(" | ", 2)
            if len(parts) != 3 or not parts[0].strip() or not parts[1].strip() or not parts[2].strip():
                raise FrozenAccessError(f"malformed data-manifest check in {path.name}")
            out.append((parts[0], parts[2]))
    if not out:
        raise FrozenAccessError(f"{path.name} contains no checks")
    return out


def preflight(root: Path | str = DEFAULT_ROOT, dsn: str | None = None,
              verify: bool = True, db_probe: bool = True) -> dict[str, Any]:
    """Require integrity manifests, completed log+DB checks, and frozen DB access.

    verify.sh is a read-only setup check only. The database probe goes through
    the fixed WSL broker, which connects with the dedicated frozen-reader role.
    """
    frozen = FrozenRoot(root)
    code = _parse_manifest(frozen.root / "MANIFEST-code.txt")
    data = _parse_manifest(frozen.root / "MANIFEST-data.txt")
    data_lines = [line for line in (frozen.root / "MANIFEST-data.txt").read_text(encoding="utf-8").splitlines()
                  if line.strip() and not line.lstrip().startswith("#") and " | " in line]
    descriptions = [line.split(" | ", 2)[0].casefold() for line in data_lines]
    labels = "\n".join(data_lines).casefold()
    log_path = frozen.root / "logs" / "stobeserver.log"
    if not any("stobeserver.log sha256" in x for x in descriptions) or not log_path.is_file() or log_path.stat().st_size == 0:
        raise FrozenAccessError("data manifest lacks a nonempty frozen stobeserver.log check")
    if "database stobe_frozen exists" not in descriptions or not any(x.startswith("table public.") for x in descriptions):
        raise FrozenAccessError("data manifest lacks both completed frozen log and database checks")
    verify_output = None
    if verify:
        script = frozen.root / "verify.sh"
        if not script.is_file():
            raise FrozenAccessError("verify.sh is missing")
        # `bash verify.sh` creates only its own temp directory; it never edits the fixture.
        proc = subprocess.run(["wsl.exe", "-d", "DwemerAI4Skyrim3", "-u", "root", "--cd", "/", "--", "bash",
                               "/mnt/c/KenshiTestRuns/invest/frozen-2026-10-14/verify.sh"], text=True, encoding="utf-8",
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
        verify_output = proc.stdout[-4000:]
        code_ok = re.search(r"(?m)^code manifest: all \d+ hashes match\s*$", proc.stdout)
        data_match = re.search(r"(?m)^data manifest: (\d+) checks\s*$", proc.stdout)
        if (proc.returncode or not re.search(r"(?m)^FROZEN OK\s*$", proc.stdout) or not code_ok or
                not data_match or int(data_match.group(1)) != len(data_lines)):
            raise FrozenAccessError("frozen verify.sh did not finish with FROZEN OK")
    if db_probe:
        if dsn not in (None, "stobe_frozen"):
            raise FrozenAccessError("database selector must be exactly stobe_frozen")
        if not os.environ.get("CODEX_FROZEN_DB_BROKER", "1") == "1":
            raise FrozenAccessError("frozen DB broker is disabled")
        proc = subprocess.run(["wsl.exe", "-d", "DwemerAI4Skyrim3", "-u", "root", "--cd", "/", "--",
                               "/usr/bin/python3", "/mnt/c/KenshiModding/tools/model-test/codex_db_broker.py"],
                               input=json.dumps({"preflight": True}),
                              text=True, encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        if proc.returncode:
            try:
                error = json.loads(proc.stdout).get("error", "broker error")
            except (json.JSONDecodeError, AttributeError):
                error = "broker returned no structured error"
            raise FrozenAccessError("frozen DB broker preflight failed: " + str(error))
        try:
            db_result = json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            raise FrozenAccessError("frozen DB broker returned invalid preflight data") from exc
        if (db_result.get("database") != "stobe_frozen" or not db_result.get("public_tables") or
                db_result.get("foreign_tables") != 0 or db_result.get("reader_safe") is not True):
            raise FrozenAccessError("stobe_frozen reader role is missing or has unsafe privileges")
    return {"ready": True, "code_checks": len(code), "data_checks": len(data),
            "database": "stobe_frozen" if db_probe else "not probed",
            "verify_tail": verify_output}


_FORBIDDEN_WORDS = re.compile(r"(?i)\b(?:insert|update|delete|merge|upsert|create|alter|drop|truncate|grant|revoke|copy|call|do|execute|prepare|deallocate|vacuum|analyze|refresh|cluster|comment|set|reset|discard|listen|notify|lock|begin|commit|rollback|savepoint|release|explain|show|values|table|into|with|listen|notify)\b")
_SAFE_FUNCTIONS = {"abs", "avg", "btrim", "cast", "ceil", "ceiling", "char_length", "coalesce",
                   "concat", "concat_ws", "count", "current_database", "current_schema", "current_user",
                   "date_part", "date_trunc", "extract", "floor", "json_array_length", "json_build_array",
                   "json_build_object", "json_extract_path", "json_extract_path_text", "json_typeof",
                   "jsonb_array_length", "jsonb_build_array", "jsonb_build_object", "jsonb_extract_path",
                   "jsonb_extract_path_text", "jsonb_typeof", "length", "lower", "ltrim", "max", "min",
                   "mod", "nullif", "now", "position", "replace", "round", "rtrim", "string_agg",
                   "substr", "substring", "sum", "to_char", "to_json", "to_jsonb", "trim", "upper"}
_PAREN_SYNTAX = {"all", "and", "any", "exists", "filter", "from", "in", "not", "or", "over", "select", "some"}
_SAFE_TYPES = {"bigint", "bool", "boolean", "bytea", "char", "date", "decimal", "double", "float4",
               "float8", "int", "int2", "int4", "int8", "integer", "interval", "json", "jsonb",
               "numeric", "real", "smallint", "text", "time", "timestamp", "timestamptz", "uuid",
               "varchar"}
_SAFE_OPERATORS = {"!~", "!~*", "!=", "#>", "#>>", "%", "&", "*", "+", "-", "->", "->>", "/",
                   "<", "<@", "<=", "<>", "=", ">", ">=", "?", "?&", "?|", "@>", "^", "::",
                   "||", "~", "~*"}


def _mask_sql_literals(sql: str) -> str:
    """Blank standard SQL string literals while detecting unterminated/escape forms."""
    chars = list(sql)
    i = 0
    while i < len(sql):
        if sql[i] != "'":
            i += 1
            continue
        if i > 0 and sql[i - 1] in "eE" and (i < 2 or not (sql[i - 2].isalnum() or sql[i - 2] == "_")):
            raise FrozenAccessError("escape strings are unavailable")
        start = i
        i += 1
        while i < len(sql):
            if sql[i] == "'":
                if i + 1 < len(sql) and sql[i + 1] == "'":
                    i += 2
                    continue
                i += 1
                break
            if sql[i] == "\\":
                raise FrozenAccessError("backslash escapes are unavailable")
            i += 1
        else:
            raise FrozenAccessError("unterminated SQL string literal")
        for j in range(start, i):
            if chars[j] not in "\r\n":
                chars[j] = " "
    return "".join(chars)


def validate_select(sql: str) -> str:
    """Single SELECT with literals and an explicit safe built-in function set.

    The broker also applies a dedicated role and READ ONLY transaction. Public
    user functions and user-defined casts are excluded by this allowlist.
    """
    sql = sql.strip()
    if not sql or len(sql) > 20_000 or not re.match(r"(?is)^select\b", sql):
        raise FrozenAccessError("only one bounded SELECT statement is allowed")
    masked = _mask_sql_literals(sql)
    if any(mark in masked for mark in (";", "--", "/*", "*/", "\\", '"', "$") ):
        raise FrozenAccessError("SQL comments, statement separators, and quoted identifiers are unavailable")
    if _FORBIDDEN_WORDS.search(masked):
        raise FrozenAccessError("SQL contains a forbidden statement or clause")
    if not re.fullmatch(r"(?is)select\s+[A-Za-z0-9_.,*\s=<>!+/%:|&#^@\[\]()\-]+", masked):
        raise FrozenAccessError("SQL is outside the supported SELECT syntax subset")
    operator_pattern = re.compile(r"#>>|->>|!~\*|~\*|!~|<=|>=|<>|!=|\|\||\?\||\?&|@>|<@|::|#>|->|[+*/%=<>^?&~\-]")
    for operator in operator_pattern.findall(masked):
        if operator not in _SAFE_OPERATORS:
            raise FrozenAccessError("SQL operator is not in the built-in allowlist")
    # Calls may only be unqualified built-ins or pg_catalog built-ins. This
    # blocks arbitrary user functions, including dblink and file/lo functions.
    for match in re.finditer(r"(?i)(?:(?P<schema>[a-z_][a-z0-9_$]*)\s*\.\s*)?(?P<name>[a-z_][a-z0-9_$]*)\s*\(", masked):
        name, schema = match.group("name").casefold(), match.group("schema")
        if name in _PAREN_SYNTAX and schema is None:
            continue
        if name not in _SAFE_FUNCTIONS or (schema and schema.casefold() != "pg_catalog"):
            raise FrozenAccessError("SQL function is not in the safe built-in allowlist")
    for match in re.finditer(r"(?i)::\s*(?:(?P<schema>[a-z_][a-z0-9_$]*)\s*\.\s*)?(?P<type>[a-z_][a-z0-9_$]*)", masked):
        typ, schema = match.group("type").casefold(), match.group("schema")
        if typ not in _SAFE_TYPES or (schema and schema.casefold() != "pg_catalog"):
            raise FrozenAccessError("SQL cast type is not in the built-in allowlist")
    for match in re.finditer(r"(?is)\bcast\s*\([^)]*\bas\s+(?:(?P<schema>[a-z_][a-z0-9_$]*)\s*\.\s*)?(?P<type>[a-z_][a-z0-9_$]*)", masked):
        typ, schema = match.group("type").casefold(), match.group("schema")
        if typ not in _SAFE_TYPES or (schema and schema.casefold() != "pg_catalog"):
            raise FrozenAccessError("SQL cast type is not in the built-in allowlist")
    # Deny direct operational/statistics catalogs; information_schema remains
    # available for permitted fixture schema discovery.
    safe_catalog_names = "|".join(sorted(_SAFE_FUNCTIONS | _SAFE_TYPES))
    catalog_stripped = re.sub(r"(?i)\bpg_catalog\s*\.\s*(?:" + safe_catalog_names + r")\b", "", masked)
    if re.search(r"(?i)\bpg_[a-z0-9_]*\b", catalog_stripped):
        raise FrozenAccessError("PostgreSQL catalog relations are unavailable; use information_schema")
    return sql


class FrozenDB:
    def __init__(self, dsn: str):
        # The value is deliberately only a logical selector; no client may
        # supply host, user, password, or arbitrary connection parameters.
        if dsn != "stobe_frozen":
            raise FrozenAccessError("database selector must be exactly stobe_frozen")

    def select(self, sql: str) -> dict[str, Any]:
        statement = validate_select(sql)
        proc = subprocess.run(["wsl.exe", "-d", "DwemerAI4Skyrim3", "-u", "root", "--cd", "/", "--",
                               "/usr/bin/python3", "/mnt/c/KenshiModding/tools/model-test/codex_db_broker.py"],
                              input=json.dumps({"sql": statement, "params": []}), text=True, encoding="utf-8",
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        if proc.returncode:
            try:
                error = json.loads(proc.stdout).get("error", "broker error")
            except (json.JSONDecodeError, AttributeError):
                error = "broker returned no structured error"
            raise FrozenAccessError("frozen DB broker failed: " + str(error))
        try:
            result = json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            raise FrozenAccessError("frozen DB broker returned invalid data") from exc
        if result.get("error"):
            raise FrozenAccessError("frozen DB query denied: " + str(result["error"]))
        return {"columns": result.get("columns", []), "rows": result.get("rows", [])}


def record_call(path: Path | str, method: str, arguments: dict[str, Any], outcome: str,
                root: Path | str = DEFAULT_ROOT) -> None:
    """Append a compact tool receipt outside the frozen fixture."""
    target = Path(path).resolve()
    frozen = Path(root).resolve()
    try:
        target.relative_to(frozen)
    except ValueError:
        pass
    else:
        raise FrozenAccessError("call recorder must be outside the frozen fixture")
    target.parent.mkdir(parents=True, exist_ok=True)
    record = {"method": method, "arguments": arguments, "outcome": outcome}
    with _RECEIPT_LOCK:
        with target.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def _is_reparse_point(entry: os.DirEntry) -> bool:
    """Recognize symlinks, junctions, and other Windows reparse entries."""
    try:
        is_junction = getattr(entry, "is_junction", None)
        if callable(is_junction) and is_junction():
            return True
        attributes = getattr(entry.stat(follow_symlinks=False), "st_file_attributes", 0)
        # FILE_ATTRIBUTE_REPARSE_POINT; do not follow directory junctions.
        return bool(attributes & 0x400)
    except OSError:
        return True
