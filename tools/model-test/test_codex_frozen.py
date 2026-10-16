import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


MODULE = Path(__file__).with_name("codex_frozen.py")
spec = importlib.util.spec_from_file_location("codex_frozen", MODULE)
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)

GUARD_SPEC = importlib.util.spec_from_file_location("codex_guard", Path(__file__).with_name("codex_guard.py"))
guard = importlib.util.module_from_spec(GUARD_SPEC)
GUARD_SPEC.loader.exec_module(guard)

MCP_SPEC = importlib.util.spec_from_file_location("codex_frozen_mcp", Path(__file__).with_name("codex_frozen_mcp.py"))
mcp = importlib.util.module_from_spec(MCP_SPEC)
MCP_SPEC.loader.exec_module(mcp)


class FrozenRootTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "frozen"
        self.root.mkdir()
        (self.root / "nested").mkdir()
        (self.root / "nested" / "fixture.txt").write_text("alpha\nBeta needle\n", encoding="utf-8")
        (self.root / "binary.dat").write_bytes(b"\x00\xff")
        self.fs = cf.FrozenRoot(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_list_read_search_are_rooted(self):
        page = self.fs.read("nested/fixture.txt")
        self.assertEqual(page["text"].replace("\r\n", "\n"), "000001\talpha\n000002\tBeta needle\n")
        self.assertEqual(self.fs.search("needle")["results"][0]["line"], 2)
        self.assertEqual(self.fs.list("nested")[0]["name"], "fixture.txt")

    def test_rejects_traversal_binary_and_oversize(self):
        with self.assertRaises(cf.FrozenAccessError):
            self.fs.read("../outside")
        with self.assertRaises(cf.FrozenAccessError):
            self.fs.read("binary.dat")
        with self.assertRaises(cf.FrozenAccessError):
            self.fs.read("nested/fixture.txt", 2)

    def test_read_supports_bounded_deep_pages(self):
        target = self.root / "deep.txt"
        target.write_text("".join(f"row-{i}\n" for i in range(1, 1001)), encoding="utf-8")
        page = self.fs.read("deep.txt", start_line=997, line_count=3)
        self.assertEqual((page["start_line"], page["end_line"], page["total_lines"]), (997, 999, None))
        self.assertTrue(page["has_more"])
        self.assertIn("000999\trow-999", page["text"])
        last = self.fs.read("deep.txt", start_line=1000, line_count=5)
        self.assertEqual(last["total_lines"], 1000)
        self.assertFalse(last["has_more"])

    def test_read_page_byte_cap_applies_to_returned_page_not_deep_seek(self):
        target = self.root / "deep-large.log"
        target.write_bytes((b"padding-line\n" * 200_000) + b"deep-evidence\nlast-line\n")
        page = self.fs.read("deep-large.log", byte_limit=64, start_line=200_001, line_count=2)
        self.assertIn("deep-evidence", page["text"])
        self.assertEqual((page["start_line"], page["end_line"]), (200001, 200002))

    def test_search_streams_large_logs_and_reports_truncation(self):
        target = self.root / "large.log"
        target.write_bytes((b"ordinary line\n" * 160_000) + b"target evidence\n")
        first = self.fs.search("target evidence", "large.log", byte_budget=1_500_000)
        self.assertTrue(first["truncated"])
        self.assertIsNotNone(first["next_cursor"])
        found = self.fs.search("target evidence", "large.log", byte_budget=1_000_000,
                               **first["next_cursor"])
        self.assertEqual(found["results"][0]["line"], 160001)
        self.assertFalse(found["truncated"])
        partial = self.fs.search("absent", "large.log", byte_budget=1000)
        self.assertTrue(partial["truncated"])
        self.assertLessEqual(partial["bytes_scanned"], 1000)

    def test_search_overlong_unterminated_line_terminates_and_reports_incomplete(self):
        target = self.root / "unterminated.log"
        target.write_bytes(b"x" * (cf.MAX_SEARCH_LINE_BYTES * 3))
        started = time.monotonic()
        result = self.fs.search("missing", "unterminated.log", byte_budget=100_000)
        self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(result["results"], [])
        self.assertTrue(result["incomplete"])
        self.assertGreaterEqual(result["long_lines_skipped"], 1)

    def test_directory_search_has_incremental_tree_budget(self):
        for i in range(20):
            (self.root / f"entry-{i:02d}.txt").write_text("ordinary\n", encoding="utf-8")
        with patch.object(cf, "MAX_SEARCH_TREE_ENTRIES", 4), patch.object(Path, "rglob", side_effect=AssertionError("eager recursive enumeration")):
            result = self.fs.search("never-present", byte_budget=1000)
        self.assertTrue(result["truncated"])
        self.assertLessEqual(result["files_scanned"], 4)

    def test_mcp_stdio_burst_completes_list_read_search_and_fake_sql(self):
        original_root, original_receipts, original_diagnostics = mcp.ROOT, mcp.RECEIPTS, mcp.DIAGNOSTICS
        receipts = self.root.parent / "calls.jsonl"
        diagnostics = self.root.parent / "timings.jsonl"
        mcp.ROOT, mcp.RECEIPTS, mcp.DIAGNOSTICS = self.root, receipts, diagnostics
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "list", "arguments": {"path": "."}}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "read", "arguments": {"path": "nested/fixture.txt"}}},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "search", "arguments": {"query": "never-present", "path": "nested/fixture.txt"}}},
            {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "sql", "arguments": {"query": "SELECT 1"}}},
        ]
        try:
            with patch.object(mcp.FrozenDB, "select", return_value={"columns": ["n"], "rows": [[1]]}):
                output = io.StringIO()
                with patch.object(mcp.sys, "stdout", output):
                    mcp.serve(io.StringIO("".join(json.dumps(req) + "\n" for req in requests)))
            responses = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual({response["id"] for response in responses}, {1, 2, 3, 4})
            self.assertTrue(all(response["result"]["isError"] is False for response in responses))
            entries = [json.loads(line) for line in receipts.read_text(encoding="utf-8").splitlines()]
            self.assertEqual(len(entries), 4)
            self.assertEqual({entry["method"] for entry in entries}, {"list", "read", "search", "sql"})
            events = [json.loads(line) for line in diagnostics.read_text(encoding="utf-8").splitlines()]
            self.assertEqual(sum(event["event"] == "started" for event in events), 4)
            self.assertEqual(sum(event["event"] == "completed" for event in events), 4)
            self.assertTrue(all("elapsed_ms" not in event for event in events if event["event"] == "started"))
            self.assertTrue(all("elapsed_ms" in event for event in events if event["event"] == "completed"))
        finally:
            mcp.ROOT, mcp.RECEIPTS, mcp.DIAGNOSTICS = original_root, original_receipts, original_diagnostics

    def test_mcp_stdio_calls_do_not_head_of_line_block(self):
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "search"}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list"}},
        ]
        def handler(request):
            if request["id"] == 1:
                time.sleep(0.1)
            return {"jsonrpc": "2.0", "id": request["id"], "result": {"isError": False}}
        output = io.StringIO()
        with patch.object(mcp.sys, "stdout", output):
            mcp.serve(io.StringIO("".join(json.dumps(req) + "\n" for req in requests)), response_handler=handler)
        responses = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([response["id"] for response in responses], [2, 1])

    def test_symlink_escape_is_blocked_or_omitted(self):
        outside = Path(self.temp.name) / "secret.txt"
        outside.write_text("secret", encoding="utf-8")
        try:
            (self.root / "escape.txt").symlink_to(outside)
        except (OSError, NotImplementedError):
            self.skipTest("symlink creation unavailable")
        with self.assertRaises(cf.FrozenAccessError):
            self.fs.read("escape.txt")
        self.assertNotIn("escape.txt", [row["name"] for row in self.fs.list()])


class SqlGateTests(unittest.TestCase):
    def test_accepts_plain_select_subset(self):
        self.assertEqual(cf.validate_select("SELECT id, name FROM public.npc WHERE id = 4"),
                         "SELECT id, name FROM public.npc WHERE id = 4")

    def test_accepts_useful_readonly_investigation_queries(self):
        for sql in ("SELECT name FROM public.npc WHERE name = 'Tengu'",
                    "SELECT count(*) FROM public.audit_request WHERE request_type IN ('chat', 'memory')",
                    "SELECT lower(name), payload->>'event' FROM public.audit_llm WHERE id = 12 ORDER BY id LIMIT 5",
                    "SELECT coalesce(name, 'unknown') FROM public.npc WHERE name LIKE 'Ten%'",
                    "SELECT id FROM public.audit_request WHERE request_type = 'job update; -- drop'",
                    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND (table_type = 'BASE TABLE' OR table_type = 'VIEW')",
                    "SELECT CAST(id AS bigint) FROM public.audit_request WHERE id = 1",
                    "SELECT id::pg_catalog.int4 FROM public.audit_request"):
            with self.subTest(sql=sql):
                self.assertEqual(cf.validate_select(sql), sql)

    def test_rejects_writes_meta_and_unsafe_functions(self):
        for sql in ("DELETE FROM npc", "SELECT 1; DROP TABLE npc", "SELECT pg_read_file(x)",
                    "SELECT dblink(x)", "SELECT set_config(x,y,z)", "SELECT 1 -- comment",
                    "SELECT public.lower(name) FROM npc", "SELECT nextval('seq') FROM npc",
                    "SELECT id::public.custom_type FROM npc", "SELECT cast(id AS public.custom_type) FROM npc",
                    "SELECT rolname FROM pg_roles",
                    "WITH x AS (SELECT 1) SELECT * FROM x"):
            with self.subTest(sql=sql), self.assertRaises(cf.FrozenAccessError):
                cf.validate_select(sql)

    def test_database_name_is_pinned(self):
        for dsn in ("stobe", "stobe_frozen_backup", "host=x dbname=stobe_frozen user=x"):
            with self.subTest(dsn=dsn), self.assertRaises(cf.FrozenAccessError):
                cf.FrozenDB(dsn)
        self.assertIsInstance(cf.FrozenDB("stobe_frozen"), cf.FrozenDB)


class PreflightTests(unittest.TestCase):
    def test_requires_code_and_nonempty_data_manifests_and_database_probe(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "MANIFEST-code.txt").write_text("a" * 64 + "  server/x\n", encoding="utf-8")
            (root / "MANIFEST-data.txt").write_text(
                "# header\nstobeserver.log sha256 | sha256sum frozen/log | abc\n"
                "database stobe_frozen exists | psql -d stobe_frozen | 1\n"
                "table public.npc rows/content md5 | psql -d stobe_frozen | 10/abc\n", encoding="utf-8")
            (root / "logs").mkdir()
            (root / "logs" / "stobeserver.log").write_text("frozen log\n", encoding="utf-8")
            (root / "verify.sh").write_text("#!/bin/sh\necho 'FROZEN OK'\n", encoding="utf-8")
            with self.assertRaisesRegex(cf.FrozenAccessError, "exactly stobe_frozen"):
                cf.preflight(root, dsn="dbname=stobe_frozen", verify=False, db_probe=True)

    def test_db_probe_uses_frozen_broker_only(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "MANIFEST-code.txt").write_text("a" * 64 + "  server/x\n", encoding="utf-8")
            (root / "MANIFEST-data.txt").write_text(
                "stobeserver.log sha256 | sha256sum frozen/log | abc\n"
                "database stobe_frozen exists | psql -d stobe_frozen | 1\n"
                "table public.npc rows/content md5 | psql -d stobe_frozen | 10/abc\n", encoding="utf-8")
            (root / "logs").mkdir()
            (root / "logs" / "stobeserver.log").write_text("log\n", encoding="utf-8")
            result = type("Proc", (), {"returncode": 0, "stdout": '{"database":"stobe_frozen","public_tables":77,"foreign_tables":0,"reader_safe":true}', "stderr": ""})()
            with patch.object(cf.subprocess, "run", return_value=result) as run:
                result = cf.preflight(root, verify=False, db_probe=True)
            self.assertTrue(result["ready"])
            self.assertEqual(result["database"], "stobe_frozen")
            self.assertEqual(run.call_args.args[0][0:7], ["wsl.exe", "-d", "DwemerAI4Skyrim3", "-u", "root", "--cd", "/"])
            unsafe = type("Proc", (), {"returncode": 0, "stdout": '{"database":"stobe_frozen","public_tables":77,"foreign_tables":0,"reader_safe":false}', "stderr": ""})()
            with patch.object(cf.subprocess, "run", return_value=unsafe):
                with self.assertRaisesRegex(cf.FrozenAccessError, "unsafe privileges"):
                    cf.preflight(root, verify=False, db_probe=True)
    def test_missing_data_manifest_fails_before_verify(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "MANIFEST-code.txt").write_text("a" * 64 + "  server/x\n", encoding="utf-8")
            with self.assertRaisesRegex(cf.FrozenAccessError, "MANIFEST-data"):
                cf.preflight(root, verify=False, db_probe=False)

    def test_verify_must_report_code_and_data_checks(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "MANIFEST-code.txt").write_text("a" * 64 + "  server/x\n", encoding="utf-8")
            (root / "MANIFEST-data.txt").write_text(
                "stobeserver.log sha256 | sha256sum frozen/log | abc\n"
                "database stobe_frozen exists | psql -d stobe_frozen | 1\n"
                "table public.npc rows/content md5 | psql -d stobe_frozen | 10/abc\n", encoding="utf-8")
            (root / "logs").mkdir()
            (root / "logs" / "stobeserver.log").write_text("log\n", encoding="utf-8")
            (root / "verify.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            output = "FROZEN OK\n"
            result = type("Proc", (), {"returncode": 0, "stdout": output})()
            with patch.object(cf.subprocess, "run", return_value=result):
                with self.assertRaisesRegex(cf.FrozenAccessError, "FROZEN OK"):
                    cf.preflight(root, dsn="stobe_frozen", verify=True, db_probe=False)

    def test_receipt_path_cannot_be_inside_custom_fixture(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "fixture"
            root.mkdir()
            with self.assertRaises(cf.FrozenAccessError):
                cf.record_call(root / "calls.jsonl", "read", {}, "ok", root)


class GatewayAndGuardTests(unittest.TestCase):
    def test_stdio_gateway_runs_under_isolated_python_and_records_call(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "frozen"
            root.mkdir()
            (root / "sample.txt").write_text("frozen only\n", encoding="utf-8")
            receipts = Path(td) / "calls.jsonl"
            env = os.environ.copy()
            env["CODEX_FROZEN_ROOT"] = str(root)
            env["CODEX_FROZEN_RECEIPTS"] = str(receipts)
            requests = [
                {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05"}},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "list", "arguments": {"path": "."}}},
            ]
            run = subprocess.run([sys.executable, "-I", str(Path(__file__).with_name("codex_frozen_mcp.py"))],
                                 input="\n".join(map(json.dumps, requests)) + "\n", text=True,
                                 capture_output=True, env=env, timeout=10)
            self.assertEqual(run.returncode, 0, run.stderr)
            replies = [json.loads(line) for line in run.stdout.splitlines()]
            self.assertEqual([r["id"] for r in replies], [1, 2, 3])
            names = [t["name"] for t in replies[1]["result"]["tools"]]
            self.assertEqual(names, ["list", "read", "search", "sql"])
            self.assertIn("sample.txt", replies[2]["result"]["content"][0]["text"])
            self.assertEqual(json.loads(receipts.read_text(encoding="utf-8"))["method"], "list")

    def test_guard_allows_only_scoped_frozen_tools_and_requires_receipt(self):
        with tempfile.TemporaryDirectory() as td:
            frozen = Path(td) / "frozen"
            frozen.mkdir()
            receipt = Path(td) / "guard.jsonl"
            env = {"CODEX_FROZEN_ROOT": str(frozen), "CODEX_BENCH_GUARD_LOG": str(receipt)}
            with patch.dict(os.environ, env, clear=False):
                allowed = guard.handle({"hook_event_name": "PreToolUse", "tool_name": "mcp__frozen__read",
                                        "tool_input": {"path": "server/x", "byte_limit": 50,
                                                       "start_line": 4, "line_count": 20}})
                denied = guard.handle({"hook_event_name": "PreToolUse", "tool_name": "shell_command",
                                       "tool_input": {"command": "rm -rf"}})
                malformed = guard.handle({"hook_event_name": "PreToolUse", "tool_name": "mcp__frozen__sql",
                                          "tool_input": {"query": "SELECT 1", "dsn": "secret"}})
            self.assertEqual(allowed["hookSpecificOutput"]["permissionDecision"], "allow")
            self.assertEqual(denied["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(malformed["hookSpecificOutput"]["permissionDecision"], "deny")
            events = [json.loads(line) for line in receipt.read_text(encoding="utf-8").splitlines()]
            self.assertEqual([e["decision"] for e in events], ["allow", "deny", "deny"])
            self.assertNotIn("rm -rf", receipt.read_text(encoding="utf-8"))

    def test_guard_denies_allowed_tool_when_audit_receipt_unavailable(self):
        with tempfile.TemporaryDirectory() as td:
            frozen = Path(td) / "frozen"
            frozen.mkdir()
            with patch.dict(os.environ, {"CODEX_FROZEN_ROOT": str(frozen),
                                        "CODEX_BENCH_GUARD_LOG": str(frozen / "receipt.jsonl")}, clear=False):
                result = guard.handle({"hook_event_name": "PreToolUse", "tool_name": "mcp__frozen__list",
                                       "tool_input": {"path": "."}})
            self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")


if __name__ == "__main__":
    unittest.main(verbosity=2)
