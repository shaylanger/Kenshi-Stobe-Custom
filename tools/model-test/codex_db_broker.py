#!/usr/bin/python3
"""Fixed-credential, fixed-database, read-only PostgreSQL broker for frozen MCP.

Invoked only by the Windows MCP gateway using fixed WSL argv. It shells out to
the already-installed psql client with shell=False; no Python DB package or
system dependency installation is needed. The credential path and target are
fixed and the secret is passed only in the child environment.
"""
from __future__ import annotations

import csv
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

from codex_frozen import FrozenAccessError, validate_select

DB_NAME = "stobe_frozen"
DB_USER = "codex_frozen_reader"
CREDENTIALS = Path("/root/.config/kenshi-model-test/frozen-reader.json")
PSQL = "/usr/bin/psql"
MAX_SQL = 20_000
MAX_OUTPUT_BYTES = 4_000_000


def _load_credentials() -> dict:
    if not CREDENTIALS.is_file():
        raise FrozenAccessError("private frozen-reader credential file is missing")
    st = CREDENTIALS.stat()
    if stat.S_IMODE(st.st_mode) != 0o600 or st.st_uid != 0:
        raise FrozenAccessError("private credential file permissions must be root-owned mode 0600")
    config = json.loads(CREDENTIALS.read_text(encoding="utf-8"))
    if set(config) != {"host", "port", "user", "password", "dbname"}:
        raise FrozenAccessError("credential file has unexpected fields")
    if (config["host"] != "127.0.0.1" or int(config["port"]) != 5432 or
            config["user"] != DB_USER or config["dbname"] != DB_NAME or not config["password"]):
        raise FrozenAccessError("credential file is not scoped to codex_frozen_reader/stobe_frozen")
    return config


def _psql(config: dict, select_sql: str) -> tuple[list[str], list[list[str]]]:
    env = os.environ.copy()
    for key in tuple(env):
        if key.startswith("PG"):
            env.pop(key, None)
    env["PGPASSWORD"] = config["password"]
    env["PGCONNECT_TIMEOUT"] = "5"
    env["PGAPPNAME"] = "codex-frozen-mcp"
    command = [PSQL, "-X", "-q", "--csv", "-v", "ON_ERROR_STOP=1", "-h", config["host"],
               "-p", str(config["port"]), "-U", config["user"], "-d", DB_NAME,
               "-c", "BEGIN READ ONLY; SET LOCAL statement_timeout = '5s'; " + select_sql + "; ROLLBACK;"]
    try:
        proc = subprocess.run(command, text=True, encoding="utf-8", stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=15, env=env, shell=False)
    except FileNotFoundError as exc:
        raise FrozenAccessError("fixed /usr/bin/psql client is missing") from exc
    except subprocess.TimeoutExpired as exc:
        raise FrozenAccessError("frozen database query exceeded 15 seconds") from exc
    if proc.returncode:
        # Prefer the bounded PostgreSQL error header over a trailing caret or
        # source-context line. Avoid returning SQL text or any row contents.
        diagnostic = next((line.strip() for line in proc.stderr.splitlines()
                           if line.lstrip().startswith(("ERROR:", "FATAL:", "psql:"))),
                          "psql failed without a diagnostic")
        raise FrozenAccessError("frozen database query failed: " + diagnostic[:300])
    if len(proc.stdout.encode("utf-8")) > MAX_OUTPUT_BYTES:
        raise FrozenAccessError("frozen database query output exceeds 4 MB")
    parsed = list(csv.reader(io.StringIO(proc.stdout)))
    if not parsed:
        raise FrozenAccessError("psql returned no CSV header")
    return parsed[0], parsed[1:]


def handle(request: dict) -> dict:
    config = _load_credentials()
    if request == {"preflight": True}:
        columns, rows = _psql(config, "SELECT current_database() AS database, "
                              "(SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public') AS public_tables, "
                              "(SELECT count(*) FROM pg_foreign_table) AS foreign_tables, "
                              "(SELECT NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls OR rolinherit) "
                              "AND rolconfig @> ARRAY['default_transaction_read_only=on'] "
                              "AND NOT EXISTS (SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid) "
                              "AND NOT has_database_privilege(current_user, 'stobe_frozen', 'CREATE') "
                              "AND NOT has_database_privilege(current_user, 'stobe_frozen', 'TEMP') "
                              "AND NOT has_schema_privilege(current_user, 'public', 'CREATE') "
                              "AND NOT has_schema_privilege(current_user, 'stobe_meta', 'CREATE') "
                              "AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace "
                              "WHERE n.nspname IN ('public','stobe_meta') AND c.relkind IN ('r','p','v','m','f') "
                              "AND (has_table_privilege(current_user, format('%I.%I',n.nspname,c.relname),'INSERT') "
                              "OR has_table_privilege(current_user, format('%I.%I',n.nspname,c.relname),'UPDATE') "
                              "OR has_table_privilege(current_user, format('%I.%I',n.nspname,c.relname),'DELETE') "
                              "OR has_table_privilege(current_user, format('%I.%I',n.nspname,c.relname),'TRUNCATE') "
                              "OR has_table_privilege(current_user, format('%I.%I',n.nspname,c.relname),'REFERENCES') "
                              "OR has_table_privilege(current_user, format('%I.%I',n.nspname,c.relname),'TRIGGER'))) "
                              "FROM pg_roles r WHERE r.rolname=current_user) AS reader_safe")
        if not rows:
            return {"database": None, "public_tables": 0}
        row = dict(zip(columns, rows[0]))
        return {"database": row.get("database"), "public_tables": int(row.get("public_tables") or 0),
                "foreign_tables": int(row.get("foreign_tables") or 0),
                "reader_safe": row.get("reader_safe") == "t"}
    if set(request) - {"sql", "params", "credential_path"}:
        raise FrozenAccessError("unexpected broker request fields")
    if request.get("credential_path", str(CREDENTIALS)) != str(CREDENTIALS):
        raise FrozenAccessError("credential_path is fixed and cannot be overridden")
    sql = request.get("sql")
    params = request.get("params", [])
    if not isinstance(sql, str) or len(sql) > MAX_SQL or params not in ([], None):
        raise FrozenAccessError("invalid SQL request; query parameters are not supported")
    statement = validate_select(sql)
    columns, rows = _psql(config, "SELECT * FROM (" + statement + ") AS __frozen_result LIMIT 501")
    if len(rows) > 500:
        raise FrozenAccessError("query returned more than 500 rows")
    return {"columns": columns, "rows": rows}


def main() -> int:
    try:
        request = json.loads(sys.stdin.readline())
        if not isinstance(request, dict):
            raise FrozenAccessError("request must be a JSON object")
        response = handle(request)
    except Exception as exc:
        if isinstance(exc, FrozenAccessError):
            detail = str(exc)
        else:
            detail = "broker request failed"
        response = {"error": type(exc).__name__ + ": " + detail}
    sys.stdout.write(json.dumps(response, ensure_ascii=False, default=str) + "\n")
    return 0 if "error" not in response else 2


if __name__ == "__main__":
    raise SystemExit(main())
