"""Synthetic-only tests for benchmark orchestration; never starts Codex."""
from __future__ import annotations

import csv
import importlib.util
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("codex_bench.py")
SPEC = importlib.util.spec_from_file_location("codex_bench_tested", MODULE_PATH)
bench = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(bench)


class BenchTests(unittest.TestCase):
    def test_mcp_receipt_health_accepts_safe_rejection_but_fails_closed(self):
        safe = [{"method": "read", "arguments": {}, "outcome": "ok"},
                {"method": "sql", "arguments": {}, "outcome": "error:FrozenAccessError"}]
        health = bench._classify_mcp_receipts(safe, True)
        self.assertEqual(health["status"], "PASS")
        self.assertEqual(health["safe_rejection_count"], 1)
        self.assertEqual(health["infrastructure_error_count"], 0)
        self.assertEqual(bench._classify_mcp_receipts(
            [{"method": "search", "arguments": {}, "outcome": "error:FileNotFoundError"}], True)["status"], "FAIL")
        self.assertEqual(bench._classify_mcp_receipts(
            [{"method": "search", "arguments": {}, "outcome": "error:TimeoutError"}], True)["status"], "FAIL")
        self.assertEqual(bench._classify_mcp_receipts(
            [{"method": "read", "arguments": {}, "outcome": "error:TimeoutError"}], True)["status"], "FAIL")
        self.assertEqual(bench._classify_mcp_receipts(
            [{"method": "mystery", "arguments": {}, "outcome": "ok"}], True)["integrity"], "FAIL")
        self.assertEqual(bench._classify_mcp_receipts([{"method": "read"}], True)["integrity"], "FAIL")
        self.assertEqual(bench._classify_mcp_receipts([], True)["status"], "FAIL")
        not_used = bench._classify_mcp_receipts([], True, zero_call_ready=True, observed_calls=0)
        self.assertEqual((not_used["status"], not_used["usage"]), ("PASS", "NOT_USED"))
        self.assertEqual(bench._classify_mcp_receipts([], True, zero_call_ready=True,
                                                      observed_calls=1)["status"], "FAIL")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "receipts.jsonl"
            path.write_text('{"method":"read","arguments":{},"outcome":"ok"}\nnot-json\n', encoding="utf-8")
            malformed = bench._mcp_receipt_health(path)
            self.assertEqual(malformed["integrity"], "FAIL")
            self.assertEqual(malformed["malformed_line_count"], 1)

    def test_startup_receipt_is_bound_to_real_execution_and_empty_call_sink(self):
        with tempfile.TemporaryDirectory() as tmp:
            attempt = Path(tmp) / "attempt-01"
            attempt.mkdir()
            calls = attempt / "frozen-mcp-receipts.jsonl"
            calls.touch()  # explicit prelaunch empty sink
            event_path = attempt / "events.jsonl"
            event_path.write_text("\n".join(json.dumps(row) for row in [
                {"type": "thread.started", "thread_id": "thread-1"},
                {"type": "turn.started", "thread_id": "thread-1"},
                {"type": "turn.completed", "thread_id": "thread-1"}]) + "\n", encoding="utf-8")
            event_audit = bench._inspect_cli_event_stream(event_path)
            self.assertEqual(event_audit["status"], "PASS")
            startup_path = attempt / "frozen-mcp-startup.jsonl"
            config = {"private_config_sha256": "c" * 64,
                      "mcp_startup_receipts": str(attempt / "frozen-mcp-startup.jsonl")}
            identity = {"pid": 42, "image": "codex.exe", "image_sha256": "e" * 64,
                        "created_utc": "2026-10-17T00:00:00Z"}
            start = "2026-10-17T00:00:01+00:00"
            end = "2026-10-17T00:00:03+00:00"
            launch = {"run": "model-low-standard-p2", "attempt": 1,
                      "participant_cli_pid": 42, "participant_cli_identity": identity,
                      "mcp_call_sink_primed": True,
                      "mcp_startup_nonce_sha256": "a" * 64,
                      "mcp_startup_config_sha256": "c" * 64,
                      "mcp_startup_source_sha256": "d" * 64,
                      "requested_config": config,
                      "started_utc": start, "ended_utc": end}
            def row(method, stamp, tools):
                return {"method": method, "utc": stamp, "nonce_sha256": "a" * 64,
                        "attempt_id": "model-low-standard-p2/attempt-01",
                        "config_sha256": "c" * 64, "source_sha256": "d" * 64,
                        "server_pid": 73, "parent_pid": 42, "parent_identity": identity, "tools": tools}
            startup_path.write_text("\n".join(json.dumps(x) for x in [
                row("initialize", 1792195202.0, []),
                row("tools/list", 1792195202.2, ["list", "read", "search", "sql"])]) + "\n", encoding="utf-8")
            startup, health = bench._audit_mcp_receipts(attempt, launch, 0, event_audit, "thread-1")
            self.assertEqual(startup["status"], "PASS")
            self.assertEqual((health["status"], health["usage"]), ("PASS", "NOT_USED"))
            _startup, failed_health = bench._audit_mcp_receipts(attempt, launch, 1, event_audit, "thread-1")
            self.assertEqual(failed_health["status"], "FAIL")
            self.assertNotIn("usage", failed_health)
            _startup, mismatched_thread = bench._audit_mcp_receipts(attempt, launch, 0, event_audit, "other-thread")
            self.assertEqual(mismatched_thread["status"], "FAIL")
            startup_path.write_text(startup_path.read_text(encoding="utf-8") + "not-json\n", encoding="utf-8")
            startup, health = bench._audit_mcp_receipts(attempt, launch, 0)
            self.assertEqual(startup["status"], "FAIL")
            self.assertEqual(health["status"], "FAIL")
            startup_path.write_text("\n".join(json.dumps(x) for x in [
                row("initialize", 1792195202.0, []),
                row("tools/list", 1792195202.2, ["list", "read", "search", "sql"])]) + "\n", encoding="utf-8")
            bad = json.loads(startup_path.read_text(encoding="utf-8").splitlines()[1])
            bad["parent_identity"] = {"pid": 42, "image_sha256": "other"}
            startup_path.write_text("\n".join(json.dumps(x) for x in [
                row("initialize", 1792195202.0, []), bad]) + "\n", encoding="utf-8")
            startup, health = bench._audit_mcp_receipts(attempt, launch, 0)
            self.assertEqual(startup["status"], "FAIL")
            self.assertEqual(health["status"], "FAIL")
            tampered_tools = row("tools/list", 1792195202.2, ["list", "read", "search"])
            startup_path.write_text(json.dumps(row("initialize", 1792195202.0, [])) + "\n" +
                                    json.dumps(tampered_tools) + "\n", encoding="utf-8")
            startup, health = bench._audit_mcp_receipts(attempt, launch, 0)
            self.assertEqual(startup["status"], "FAIL")
            self.assertEqual(health["status"], "FAIL")
            wrong_nonce = row("initialize", 1792195202.0, [])
            wrong_nonce["nonce_sha256"] = "stale-preflight-nonce"
            startup_path.write_text(json.dumps(wrong_nonce) + "\n" + json.dumps(
                row("tools/list", 1792195202.2, ["list", "read", "search", "sql"])) + "\n", encoding="utf-8")
            startup, health = bench._audit_mcp_receipts(attempt, launch, 0)
            self.assertEqual(startup["status"], "FAIL")
            self.assertEqual(health["status"], "FAIL")
            for key in ("mcp_startup_nonce_sha256", "mcp_startup_source_sha256"):
                incomplete = dict(launch)
                incomplete.pop(key)
                startup, _health = bench._audit_mcp_receipts(attempt, incomplete, 0)
                self.assertEqual(startup["status"], "FAIL")
            incomplete = dict(launch)
            incomplete["requested_config"] = {"mcp_startup_receipts": str(startup_path)}
            startup, _health = bench._audit_mcp_receipts(attempt, incomplete, 0)
            self.assertEqual(startup["status"], "FAIL")
            incomplete = dict(launch)
            incomplete["participant_cli_identity"] = {"pid": 42, "query": "unavailable"}
            startup, _health = bench._audit_mcp_receipts(attempt, incomplete, 0)
            self.assertEqual(startup["status"], "FAIL")
            incomplete = dict(launch)
            incomplete["participant_cli_identity"] = {"pid": 42, "image": "codex.exe",
                                                      "created_utc": "2026-10-17T00:00:00Z"}
            startup, _health = bench._audit_mcp_receipts(attempt, incomplete, 0)
            self.assertEqual(startup["status"], "FAIL")
            incomplete = dict(launch)
            incomplete["participant_cli_identity"] = {**identity, "pid": 41}
            startup, _health = bench._audit_mcp_receipts(attempt, incomplete, 0)
            self.assertEqual(startup["status"], "FAIL")
            incomplete = dict(launch)
            incomplete["participant_cli_identity"] = {**identity, "created_utc": ""}
            startup, _health = bench._audit_mcp_receipts(attempt, incomplete, 0)
            self.assertEqual(startup["status"], "FAIL")
            startup_path.write_text("{malformed\n", encoding="utf-8")
            startup, health = bench._audit_mcp_receipts(attempt, launch, 0)
            self.assertEqual(startup["status"], "FAIL")
            self.assertEqual(health["status"], "FAIL")

    def test_structural_frozen_call_without_receipt_fails_empty_sink(self):
        with tempfile.TemporaryDirectory() as tmp:
            attempt = Path(tmp) / "attempt-01"
            attempt.mkdir()
            (attempt / "frozen-mcp-receipts.jsonl").touch()
            calls = [{"type": "item.completed", "item": {"type": "mcp_tool_call",
                      "server": "frozen", "name": "read"}}]
            self.assertEqual(bench._count_frozen_tool_calls(calls), 1)
            _startup, health = bench._audit_mcp_receipts(attempt, {}, 1)
            self.assertEqual(health["status"], "FAIL")

    def test_zero_call_event_stream_must_be_complete_well_formed_and_root_bound(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "events.jsonl"
            complete = [{"type": "thread.started", "thread_id": "thread-a"},
                        {"type": "turn.started", "thread_id": "thread-a"},
                        {"type": "turn.completed", "thread_id": "thread-a"}]
            path.write_text("\n".join(json.dumps(row) for row in complete) + "\n", encoding="utf-8")
            audit = bench._inspect_cli_event_stream(path)
            self.assertEqual((audit["status"], audit["tool_call_count"], audit["thread_id"]),
                             ("PASS", 0, "thread-a"))
            path.write_text("\n".join(json.dumps(row) for row in complete[:2]) + "\n", encoding="utf-8")
            self.assertEqual(bench._inspect_cli_event_stream(path)["status"], "FAIL")
            mismatched = [dict(row) for row in complete]
            mismatched[1]["thread_id"] = "thread-b"
            path.write_text("\n".join(json.dumps(row) for row in mismatched) + "\n", encoding="utf-8")
            self.assertEqual(bench._inspect_cli_event_stream(path)["status"], "FAIL")
            path.write_text("\n".join(json.dumps(row) for row in complete) + "\nnot-json\n", encoding="utf-8")
            self.assertEqual(bench._inspect_cli_event_stream(path)["status"], "FAIL")
            path.unlink()
            self.assertEqual(bench._inspect_cli_event_stream(path)["status"], "FAIL")

    def test_record_quarantines_failed_attempt_then_promotes_valid_retry_once(self):
        import sys
        sys.path.insert(0, str(MODULE_PATH.parent))
        import codex_status
        import codex_record
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_id = "model-low-standard-p2"
            run_dir = root / "runs" / run_id
            run_dir.mkdir(parents=True)
            report_failed = "synthetic failed-attempt report"
            report_valid = "synthetic valid-attempt report"

            def add_attempt(number):
                attempt = run_dir / f"attempt-{number:02d}"
                attempt.mkdir()
                (attempt / "rollout.jsonl").write_text("{}\n", encoding="utf-8")
                (attempt / "argv.json").write_text(json.dumps({"argv": ["--model", "model", "--reasoning-effort", "low", "--service-tier", "default"]}))
                (attempt / "requested-config.json").write_text("{}")
                receipt = {"run": run_id, "attempt": number, "status": "COMPLETE_UNAUDITED",
                           "model": "model", "effort": "low", "service_tier": "standard",
                           "returncode": 0, "execution_boundary_status": "BOUNDARY_VERIFIED",
                           "report_path": str(attempt / "report.md"),
                           "verified_receipt": True, "terminal_verified": True,
                           "code_mode_host_proof": {"path": "probe.json", "sha256": "digest"},
                           "requested_config": {}, "config_sha256": "config", "argv_sha256": "argv",
                           "attempt_dir": str(attempt)}
                (attempt / "launch.json").write_text(json.dumps(receipt), encoding="utf-8")
                (attempt / "frozen-mcp-receipts.jsonl").write_text(
                    json.dumps({"method": "read", "arguments": {}, "outcome": "ok"}) + "\n", encoding="utf-8")
                (attempt / "report.md").write_text("synthetic report", encoding="utf-8")
                bench._write_json(run_dir / "launch.json", receipt)
                return attempt

            failed_attempt = add_attempt(1)
            failed_result = {"report": report_failed, "audit": {"status": "FAIL", "flags": ["mcp-transport-timeout"],
                             "setup_health": {"status": "FAIL", "infrastructure_failures": ["timeout"]}},
                             "usage": {"input_tokens": 10, "output_tokens": 2},
                             "pricing": {"usd": 0.01, "status": "priced"}, "wall_s": 1,
                             "tool_uses": 1, "models": ["model"], "efforts": ["low"], "service_tiers": ["default"]}
            with mock.patch.object(codex_status, "_verify_hostprobe", return_value={"status": "PASS"}), \
                 mock.patch.object(codex_status, "_verify_requested_modes", return_value={"status": "PASS"}), \
                 mock.patch.object(codex_record, "parse_rollout", return_value=failed_result):
                self.assertEqual(bench.record(root, run_id), 1)
            self.assertFalse((root / "runs.tsv").exists())
            self.assertFalse((run_dir / "report.md").exists())
            self.assertEqual((failed_attempt / "launch.json").read_bytes(), (run_dir / "launch.json").read_bytes())

            valid_attempt = add_attempt(2)
            valid_result = {**failed_result, "report": report_valid,
                            "audit": {"status": "PASS", "flags": [], "setup_health": {"status": "PASS", "infrastructure_failures": []}}}
            with mock.patch.object(codex_status, "_verify_hostprobe", return_value={"status": "PASS"}), \
                 mock.patch.object(codex_status, "_verify_requested_modes", return_value={"status": "PASS"}), \
                 mock.patch.object(codex_record, "parse_rollout", return_value=valid_result):
                self.assertEqual(bench.record(root, run_id), 0)
            with (root / "runs.tsv").open("r", encoding="utf-8", newline="") as stream:
                rows = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([row["agent"] for row in rows], [f"{run_id}/attempt-02"])
            self.assertEqual((run_dir / "report.md").read_text(encoding="utf-8"), report_valid)
            with (root / "attempts.tsv").open("r", encoding="utf-8", newline="") as stream:
                attempts = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([row["attempt"] for row in attempts], ["1", "2"])
            self.assertTrue((valid_attempt / "launch.json").is_file())

            # Simulate a crash after canonical row/report promotion but before final receipts.
            stale = json.loads((valid_attempt / "launch.json").read_text(encoding="utf-8"))
            stale["status"] = "COMPLETE_UNAUDITED"
            stale.pop("audit", None)
            (valid_attempt / "launch.json").write_text(json.dumps(stale), encoding="utf-8")
            bench._write_json(run_dir / "launch.json", stale)
            with mock.patch.object(codex_status, "_verify_hostprobe", return_value={"status": "PASS"}), \
                 mock.patch.object(codex_status, "_verify_requested_modes", return_value={"status": "PASS"}), \
                 mock.patch.object(codex_record, "parse_rollout", return_value=valid_result):
                self.assertEqual(bench.record(root, run_id), 0)
            with (root / "runs.tsv").open("r", encoding="utf-8", newline="") as stream:
                self.assertEqual(len(list(csv.DictReader(stream, delimiter="\t"))), 1)
            with (root / "attempts.tsv").open("r", encoding="utf-8", newline="") as stream:
                self.assertEqual(len(list(csv.DictReader(stream, delimiter="\t"))), 2)
            finalized = json.loads((valid_attempt / "launch.json").read_text(encoding="utf-8"))
            self.assertEqual((finalized.get("status"), finalized.get("audit", {}).get("status")), ("RECORDED", "PASS"))

    def test_concurrency_obeys_configured_hard_cap(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "suite.json").write_text(json.dumps({"concurrency": {"default": 2, "hard_cap": 3}}))
            self.assertEqual(bench.concurrency(root, None), 2)
            self.assertEqual(bench.concurrency(root, 3), 3)
            with self.assertRaises(bench.BenchError):
                bench.concurrency(root, 4)

    def test_named_launch_modes_resolve_defaults_and_reject_contradictions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite = root / "suite.json"
            suite.write_text(json.dumps({"concurrency": {"default": 1, "limited_concurrency": 2, "hard_cap": 4}}))
            self.assertEqual(bench.resolve_launch_mode(root, None, None), ("sequential", 1))
            self.assertEqual(bench.resolve_launch_mode(root, "sequential", 1), ("sequential", 1))
            self.assertEqual(bench.resolve_launch_mode(root, "limited-concurrent", None), ("limited-concurrent", 2))
            self.assertEqual(bench.resolve_launch_mode(root, "limited-concurrent", 3), ("limited-concurrent", 3))
            self.assertEqual(bench.resolve_launch_mode(root, None, 3), ("limited-concurrent", 3))
            with self.assertRaises(bench.BenchError):
                bench.resolve_launch_mode(root, "sequential", 2)
            with self.assertRaises(bench.BenchError):
                bench.resolve_launch_mode(root, "limited-concurrent", 5)

    def test_synthetic_scheduler_respects_sequential_and_concurrent_caps(self):
        import threading
        import time

        def peak_for(mode, cap):
            guard = threading.Lock()
            active = peak = 0
            def worker(_rid):
                nonlocal active, peak
                with guard:
                    active += 1
                    peak = max(peak, active)
                time.sleep(0.02)
                with guard:
                    active -= 1
                return 0
            self.assertEqual(bench.launch_many([str(n) for n in range(8)], mode, cap, worker), 0)
            return peak

        self.assertEqual(peak_for("sequential", 1), 1)
        self.assertEqual(peak_for("limited-concurrent", 2), 2)
        self.assertLessEqual(peak_for("limited-concurrent", 3), 3)

    def test_sequential_scheduler_stops_after_first_failed_cell(self):
        calls = []
        def worker(rid):
            calls.append(rid)
            return 1 if rid == "first" else 0
        self.assertEqual(bench.launch_many(["first", "second", "third"], "sequential", 1, worker), 1)
        self.assertEqual(calls, ["first"])

    def test_sequential_scheduler_pauses_after_current_cell(self):
        calls = []
        stop = False
        boundaries = []
        def worker(rid):
            nonlocal stop
            calls.append(rid)
            stop = True
            return 0
        self.assertEqual(bench.launch_many(["first", "second"], "sequential", 1, worker,
                                           stop_requested=lambda: stop,
                                           paused_boundaries=boundaries), 0)
        self.assertEqual(calls, ["first"])
        self.assertEqual(boundaries, [{"after_run": "first", "next_run": "second"}])

    def test_pending_run_ids_skips_only_audited_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            entries = []
            (root / "runs.tsv").write_text("run\tviolation_flags\nfinished\tPASS\n")
            for rid, status, audit in (("finished", "RECORDED", "PASS"), ("pending", "PREPARED", "")):
                run_dir = root / "runs" / rid
                run_dir.mkdir(parents=True)
                entries.append((rid, {}, 2, "prompt2.txt"))
                (run_dir / "launch.json").write_text(json.dumps({
                    "run": rid, "status": status, "attempt": 1, "audit": {"status": audit},
                }))
                if status == "RECORDED":
                    attempt = run_dir / "attempt-01"
                    attempt.mkdir()
                    (run_dir / "report.md").write_text("report")
                    (attempt / "launch.json").write_text(json.dumps({
                        "status": "RECORDED", "verified_receipt": True, "rollout_path": "rollout.jsonl",
                        "audit": {"status": "PASS"},
                    }))
            self.assertEqual(bench.pending_run_ids(root, entries), ["pending"])
            (root / "runs" / "finished" / "launch.json").write_text(json.dumps({
                "run": "finished", "status": "RECORDED", "attempt": 1, "audit": {"status": "UNKNOWN"},
            }))
            with self.assertRaises(bench.BenchError):
                bench.pending_run_ids(root, entries)

    def test_relaunch_context_cannot_mutate_completed_attempt_receipts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            attempt = root / "attempt-01"
            attempt.mkdir()
            original = {"status": "RECORDED", "launch_mode": "sequential",
                        "effective_concurrency_cap": 1, "batch_id": "old"}
            (attempt / "launch.json").write_text(json.dumps(original))
            run_receipt = root / "launch.json"
            run_receipt.write_text(json.dumps(original))
            with self.assertRaises(bench.BenchError):
                bench._stamp_launch_context(attempt / "launch.json", run_receipt, attempt,
                                            "limited-concurrent", 2, "new")
            self.assertEqual(json.loads((attempt / "launch.json").read_text()), original)
            self.assertEqual(json.loads(run_receipt.read_text()), original)

    def test_catalog_fast_tier_object_schema_is_supported_and_fail_closed(self):
        self.assertTrue(bench._fast_tier_supported({"service_tiers": [{"id": "priority", "name": "Fast"}]}))
        self.assertTrue(bench._fast_tier_supported({"service_tiers": {"priority": {}}}))
        self.assertFalse(bench._fast_tier_supported({"service_tiers": [{"id": "default"}]}))

    def test_required_headers_and_windows_citations(self):
        report = """# Summary
## Root cause:
**Evidence**
What you ruled out
### Proposed fix
How to confirm the fix worked
What is not settled
See C:\\KenshiModding\\src\\module.py:42
"""
        self.assertEqual(bench._required_headers(report), 7)
        self.assertEqual(len(bench._CITATION_RE.findall(report)), 1)

    def test_record_without_rollout_preserves_metadata_not_fake_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            attempt = root / "runs" / "gpt61sol-high-standard-p2" / "attempt-01"
            attempt.mkdir(parents=True)
            receipt = {"run": "gpt61sol-high-standard-p2", "attempt": 1, "status": "FAILED",
                       "model": "gpt-6.1-sol", "effort": "high", "service_tier": "standard",
                       "elapsed_s": 1.25, "events_path": "events.jsonl", "stderr_path": "stderr.log"}
            (attempt / "launch.json").write_text(json.dumps(receipt))
            rc = bench.record(root, receipt["run"])
            self.assertEqual(rc, 1)
            self.assertFalse((attempt.parent / "report.md").exists())
            with (root / "attempts.tsv").open(encoding="utf-8", newline="") as stream:
                row = next(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual(row["status"], "FAILED")
            self.assertEqual(row["wall_s"], "1.25")
            self.assertEqual(row["report_bytes"], "0")
            self.assertIn("no-rollout", row["violation_flags"])

    def test_prepare_uses_opaque_ticket_and_never_copies_auth_or_launches(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "suite"
            root.mkdir()
            (root / "suite.json").write_text(json.dumps({
                "cells": [{"slug": "secret-model-high-standard", "model": "secret-model", "effort": "high", "speed": "standard"}],
                "prompts": ["prompt2.txt"], "prompt_numbers": [2],
                "template": "task-frozen.tmpl", "concurrency": {"default": 1, "hard_cap": 4, "auto_start": False},
            }))
            (root / "prompt2.txt").write_text("Review the frozen source.")
            (root / "task-frozen.tmpl").write_text("Ticket {TICKET}\n{PROMPT}\n{FROZEN}\n{FROZEN_WSL}\n")
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(Path(tmp) / "local")}), \
                 mock.patch.object(bench.subprocess, "Popen", side_effect=AssertionError("must not launch")):
                self.assertEqual(bench.prepare(root), 0)
            prompt = (root / "runs" / "secret-model-high-standard-p2" / "prompt.md").read_text()
            self.assertIn("BENCH-R001", prompt)
            self.assertNotIn("secret-model", prompt)
            self.assertFalse(list((Path(tmp) / "local").rglob("auth.json")))
            private_config = next((Path(tmp) / "local").rglob("config.toml")).read_text()
            self.assertIn("multi_agent_v2 = false", private_config)
            self.assertIn("multi_agent_v2_dynamic_tools = false", private_config)
            self.assertIn("[features.code_mode]", private_config)
            self.assertIn("enabled = true", private_config)
            self.assertIn('excluded_tool_namespaces = ["functions", "clock", "mcp__codex_apps", "mcp__plugins"]', private_config)
            self.assertIn("code_mode_host = true", private_config)
            self.assertIn("tool_search = false", private_config)
            self.assertIn("view_image = false", private_config)
            self.assertIn('enabled_tools = ["list", "read", "search", "sql"]', private_config)
            self.assertIn('default_tools_approval_mode = "approve"', private_config)
            self.assertIn("hooks = false", private_config)
            self.assertNotIn("[[hooks.", private_config)
            self.assertFalse(list((Path(tmp) / "local").rglob("hooks.json")))
            prepared = next((root / "runs").glob("*/attempt-01/requested-config.json"))
            self.assertFalse(bench._json(prepared).get("hooks_enabled"))
            self.assertNotIn("[tools]", private_config)

    def test_private_profile_path_is_stable_for_relative_and_absolute_run_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_dir = base / "suite" / "runs" / "opaque-p2"
            relative = Path(__import__("os").path.relpath(run_dir, Path.cwd()))
            cell = {"model": "secret-model", "effort": "high", "speed": "standard"}
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(base / "local")}):
                first, first_config = bench._make_config(run_dir, "opaque-p2", cell)
                second, second_config = bench._make_config(relative, "opaque-p2", cell)
            self.assertEqual(first, second)
            expected = str((run_dir / "attempt-01" / "frozen-mcp-receipts.jsonl").resolve())
            self.assertEqual(first_config["mcp_receipts"], expected)
            self.assertEqual(second_config["mcp_receipts"], expected)
            self.assertTrue(Path(second_config["mcp_receipts"]).is_absolute())

    def test_preparation_and_retry_bind_absolute_mcp_receipts_outside_neutral_cwd(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "suite"
            root.mkdir()
            (root / "suite.json").write_text(json.dumps({
                "cells": [{"slug": "x-high-standard", "model": "x", "effort": "high", "speed": "standard"}],
                "prompts": ["prompt2.txt"], "prompt_numbers": [2], "template": "task-frozen.tmpl",
            }))
            (root / "prompt2.txt").write_text("p2")
            (root / "task-frozen.tmpl").write_text("{TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
            relative_root = Path(os.path.relpath(root, Path.cwd()))
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(base / "local")}):
                bench.prepare(relative_root)
                run_dir = root / "runs" / "x-high-standard-p2"
                attempt = run_dir / "attempt-01"
                launch = bench._json(attempt / "launch.json")
                config = bench._json(attempt / "requested-config.json")
                expected = str((attempt / "frozen-mcp-receipts.jsonl").resolve())
                self.assertEqual(config["mcp_receipts"], expected)
                self.assertEqual(launch["mcp_receipts_path"], expected)
                bench._validate_mcp_receipt_binding(config, attempt, launch)
                neutral = Path(launch["codex_home"]).parent / "neutral-cwd"
                self.assertNotEqual((neutral / "docs" / "model-test" / "frozen-mcp-receipts.jsonl").resolve(),
                                    Path(config["mcp_receipts"]))
                launch["status"] = "FAILED_SETUP"
                bench._write_json(attempt / "launch.json", launch)
                bench._write_json(run_dir / "launch.json", launch)
                bench._prepare_retry_attempt(relative_root, "x-high-standard-p2", 2)
                retry = run_dir / "attempt-02"
                retry_launch = bench._json(retry / "launch.json")
                retry_config = bench._json(retry / "requested-config.json")
                retry_expected = str((retry / "frozen-mcp-receipts.jsonl").resolve())
                self.assertEqual(retry_config["mcp_receipts"], retry_expected)
                self.assertEqual(retry_launch["mcp_receipts_path"], retry_expected)
                bench._validate_mcp_receipt_binding(retry_config, retry, retry_launch)

    def test_mcp_receipt_binding_rejects_relative_or_mismatched_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            attempt = Path(tmp) / "suite" / "runs" / "opaque-p2" / "attempt-01"
            attempt.mkdir(parents=True)
            _, config = bench._make_config(attempt.parent, "opaque-p2",
                                           {"model": "x", "effort": "high", "speed": "standard"},
                                           private_base=Path(tmp) / "private")
            launch = {"mcp_receipts_path": config["mcp_receipts"]}
            self.assertEqual(bench._validate_mcp_receipt_binding(config, attempt, launch),
                             attempt.resolve() / "frozen-mcp-receipts.jsonl")
            bad = dict(config, mcp_receipts="relative\\frozen-mcp-receipts.jsonl")
            with self.assertRaisesRegex(bench.BenchError, "absolute canonical"):
                bench._validate_mcp_receipt_binding(bad, attempt, launch)
            with self.assertRaisesRegex(bench.BenchError, "does not claim"):
                bench._validate_mcp_receipt_binding(config, attempt, {"mcp_receipts_path": "wrong"})

    def test_cli_relative_suite_path_retry_keeps_receipt_out_of_neutral_cwd(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "suite"
            root.mkdir()
            (root / "suite.json").write_text(json.dumps({
                "cells": [{"slug": "x-high-standard", "model": "x", "effort": "high", "speed": "standard"}],
                "prompts": ["prompt2.txt"], "prompt_numbers": [2], "template": "task-frozen.tmpl",
                "concurrency": {"default": 1, "hard_cap": 1, "auto_start": False},
            }))
            (root / "prompt2.txt").write_text("p2")
            (root / "task-frozen.tmpl").write_text("{TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
            relative_root = Path(os.path.relpath(root, Path.cwd()))
            env = {"LOCALAPPDATA": str(base / "local")}
            with mock.patch.dict(bench.os.environ, env):
                self.assertEqual(bench.main(["prepare", str(relative_root)]), 0)
                run_dir = root / "runs" / "x-high-standard-p2"
                attempt01 = run_dir / "attempt-01" / "launch.json"
                failed = bench._json(attempt01)
                failed["status"] = "FAILED_SETUP"
                bench._write_json(attempt01, failed)
                bench._write_json(run_dir / "launch.json", failed)

                def intercepted_launcher(suite_root, run_id, execute, timeout, attempt_no,
                                         launch_mode, effective_cap, batch_id):
                    self.assertTrue(execute)
                    self.assertEqual(run_id, "x-high-standard-p2")
                    self.assertEqual(attempt_no, 2)
                    attempt02 = run_dir / "attempt-02"
                    launch = bench._json(attempt02 / "launch.json")
                    config = bench._json(attempt02 / "requested-config.json")
                    expected = str((attempt02 / "frozen-mcp-receipts.jsonl").resolve())
                    self.assertEqual(config["mcp_receipts"], expected)
                    self.assertEqual(launch["mcp_receipts_path"], expected)
                    bench._validate_mcp_receipt_binding(config, attempt02, launch)
                    neutral = Path(launch["codex_home"]).parent / "neutral-cwd"
                    self.assertFalse((neutral / config["mcp_receipts"]).exists())
                    return 0

                with mock.patch.object(bench, "_preflight", return_value=0), \
                     mock.patch.object(bench, "_postflight", return_value={"ready": True}), \
                     mock.patch.object(bench, "launch_one", side_effect=intercepted_launcher) as launch_mock:
                    self.assertEqual(bench.main(["run", str(relative_root), "x-high-standard-p2",
                                                 "--execute", "--attempt", "2"]), 0)
                launch_mock.assert_called_once()
                self.assertTrue((run_dir / "attempt-02" / "launch.json").is_file())

    def test_preflight_refreshes_stale_prepared_profile_but_preserves_terminal_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "suite"
            root.mkdir()
            (root / "suite.json").write_text(json.dumps({
                "cells": [
                    {"slug": "stale-high-standard", "model": "x", "effort": "high", "speed": "standard"},
                    {"slug": "done-high-standard", "model": "x", "effort": "high", "speed": "standard"},
                ],
                "prompts": ["prompt2.txt"], "prompt_numbers": [2], "template": "task-frozen.tmpl",
            }))
            (root / "prompt2.txt").write_text("p2")
            (root / "task-frozen.tmpl").write_text("{TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
            cli = base / "codex.exe"
            cli.write_bytes(b"fixture")
            with mock.patch.dict(bench.os.environ, {
                "LOCALAPPDATA": str(base / "local"), "CODEX_BENCH_CLI": str(cli),
            }):
                bench.prepare(root)
                stale_dir = root / "runs" / "stale-high-standard-p2"
                stale_config_path = stale_dir / "attempt-01" / "requested-config.json"
                stale_config = bench._json(stale_config_path)
                stale_config["profile_version"] = 5
                stale_config_path.write_text(json.dumps(stale_config), encoding="utf-8")

                done_dir = root / "runs" / "done-high-standard-p2"
                done_attempt = done_dir / "attempt-01"
                done_launch_path = done_attempt / "launch.json"
                done_launch = bench._json(done_launch_path)
                done_launch["status"] = "RECORDED"
                done_launch.pop("mcp_receipts_path", None)
                bench._write_json(done_launch_path, done_launch)
                bench._write_json(done_dir / "launch.json", done_launch)
                done_config_path = done_attempt / "requested-config.json"
                done_config = bench._json(done_config_path)
                done_config["profile_version"] = 5
                done_config["mcp_receipts"] = "relative\\legacy-receipts.jsonl"
                done_config_path.write_text(json.dumps(done_config), encoding="utf-8")
                private_path = Path(done_config["private_config"])
                private_lines = private_path.read_text(encoding="utf-8").splitlines()
                for index, line in enumerate(private_lines):
                    if line.startswith("CODEX_FROZEN_RECEIPTS = "):
                        private_lines[index] = 'CODEX_FROZEN_RECEIPTS = "relative\\\\legacy-receipts.jsonl"'
                        break
                private_path.write_text("\n".join(private_lines) + "\n", encoding="utf-8")
                terminal_preimages = (done_launch_path.read_bytes(), done_config_path.read_bytes(),
                                      private_path.read_bytes())

                class StopBeforeExternalPreflight(Exception):
                    pass

                with mock.patch.object(bench, "_appserver_hook_rows", return_value=[]), \
                     mock.patch.object(bench, "_validate_frozen", side_effect=StopBeforeExternalPreflight):
                    with self.assertRaises(StopBeforeExternalPreflight):
                        bench._preflight(root)

                stale_launch = bench._json(stale_dir / "attempt-01" / "launch.json")
                refreshed = bench._json(stale_config_path)
                expected = str((stale_dir / "attempt-01" / "frozen-mcp-receipts.jsonl").resolve())
                self.assertEqual(refreshed["profile_version"], bench.PROFILE_VERSION)
                self.assertEqual(refreshed["mcp_receipts"], expected)
                self.assertEqual(stale_launch["mcp_receipts_path"], expected)
                bench._validate_mcp_receipt_binding(refreshed, stale_dir / "attempt-01", stale_launch)
                self.assertEqual((done_launch_path.read_bytes(), done_config_path.read_bytes(),
                                  private_path.read_bytes()), terminal_preimages)

    def test_strict_exec_config_probe_stops_before_any_prompt(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = mock.Mock(returncode=1, stdout="Reading prompt from stdin...\nNo prompt provided via stdin.\n", stderr="")
            with mock.patch.object(bench.subprocess, "run", return_value=result) as run:
                bench._strict_exec_config_probe(Path("codex.exe"), {}, Path(tmp))
            self.assertIn("--strict-config", run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs["input"], "")
            bad = mock.Mock(returncode=2, stdout="Error loading config.toml: unknown configuration field `tools.view_image`", stderr="")
            with mock.patch.object(bench.subprocess, "run", return_value=bad):
                with self.assertRaises(bench.BenchError):
                    bench._strict_exec_config_probe(Path("codex.exe"), {}, Path(tmp))

    def test_exact_profile_probe_failure_leaves_attempt_prepared(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "suite"
            root.mkdir()
            suite = {"cells": [{"slug": "opaque-high-standard", "model": "model-x", "effort": "high", "speed": "standard"}],
                     "prompts": ["prompt2.txt"], "prompt_numbers": [2],
                     "template": "task-frozen.tmpl", "concurrency": {"default": 1, "hard_cap": 1, "auto_start": False}}
            (root / "suite.json").write_text(json.dumps(suite), encoding="utf-8")
            (root / "prompt2.txt").write_text("Review the frozen source.", encoding="utf-8")
            template = root / "task-frozen.tmpl"
            template.write_text("Ticket {TICKET}\n{PROMPT}\n{FROZEN}\n{FROZEN_WSL}\n", encoding="utf-8")
            local = Path(tmp) / "local"
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(local)}):
                self.assertEqual(bench.prepare(root), 0)
                rid = "opaque-high-standard-p2"
                receipt = bench._json(root / "runs" / rid / "launch.json")
                proof = {"ready": True, "suite_sha256": bench._sha((root / "suite.json").read_bytes()),
                         "materials": {str(p.resolve()): bench._sha(p.read_bytes())
                                       for p in (root / "suite.json", template, root / "prompt2.txt",
                                                 *bench._transport_source_paths())},
                         "prepared_prompts": {rid: receipt["prompt_sha256"]},
                         "private_profiles": {rid: {
                             "config_sha256": bench._json(root / "runs" / rid / "attempt-01" / "requested-config.json")["private_config_sha256"],
                             "execution_contract_sha256": bench._json(root / "runs" / rid / "attempt-01" / "requested-config.json")["execution_contract_sha256"]}},
                         "auth_available": True}
                bench._write_json(root / "preflight.json", proof)
                mcp_source = next(p for p in bench._transport_source_paths() if p.name == "codex_frozen_mcp.py")
                proof["materials"][str(mcp_source)] = "0" * 64
                bench._write_json(root / "preflight.json", proof)
                with mock.patch.object(bench, "_verify_offline_hostprobe"):
                    with self.assertRaisesRegex(bench.BenchError, "preflight material changed"):
                        bench.launch_one(root, rid, execute=True, timeout=10)
                proof["materials"][str(mcp_source)] = bench._sha(mcp_source.read_bytes())
                bench._write_json(root / "preflight.json", proof)
                with mock.patch.object(bench, "_verify_offline_hostprobe"), \
                     mock.patch.object(bench, "_strict_exec_config_probe", side_effect=bench.BenchError("invalid exact profile")):
                    with self.assertRaisesRegex(bench.BenchError, "invalid exact profile"):
                        bench.launch_one(root, rid, execute=True, timeout=10)
                self.assertEqual(bench._json(root / "runs" / rid / "launch.json")["status"], "PREPARED")
                self.assertEqual(bench._json(root / "runs" / rid / "attempt-01" / "launch.json")["status"], "PREPARED")
                self.assertFalse((Path(receipt["codex_home"]) / "auth.json").exists())

    def test_hook_trust_is_bound_to_exact_registered_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            home = base / "home"
            codex_home = home / ".codex"
            neutral = home / "neutral-cwd"
            codex_home.mkdir(parents=True)
            neutral.mkdir()
            config_path = codex_home / "config.toml"
            config_path.write_text("[hooks]\nenabled = true\n", encoding="utf-8")
            run_dir = base / "run"
            run_dir.mkdir()
            attempt_config = run_dir / "requested-config.json"
            launch_receipt = run_dir / "attempt-launch.json"
            run_receipt = run_dir / "launch.json"
            config = {"private_config": str(config_path), "private_config_sha256": bench._sha(config_path.read_bytes()),
                      "hook_sha256": bench._sha(config_path.read_bytes()), "guard_log": str(run_dir / "guard.jsonl")}
            bench._write_json(attempt_config, config)
            bench._write_json(launch_receipt, {"status": "PREPARED"})
            bench._write_json(run_receipt, {"status": "PREPARED"})
            keys = ["session_start", "pre_tool_use", "subagent_start", "session_end"]
            rows = [{"key": f"{config_path}:event:0:0:{index}", "currentHash": f"sha256:{index:064x}",
                     "source": "user", "enabled": True, "trustStatus": status}
                    for index, status in enumerate(keys)]
            with mock.patch.object(bench, "_appserver_hook_rows", side_effect=[rows, [dict(row, trustStatus="trusted") for row in rows]]):
                result = bench._establish_exact_hook_trust(Path("codex.exe"), codex_home, Path("C:/frozen"),
                                                            config_path, config, attempt_config, launch_receipt, run_receipt)
            self.assertTrue(result["trusted"])
            persisted = config_path.read_text(encoding="utf-8")
            self.assertEqual(persisted.count("trusted_hash = "), 4)
            self.assertEqual(bench._json(launch_receipt)["config_sha256"], bench._sha(attempt_config.read_bytes()))

    def test_retry_profile_is_prepared_before_preflight_without_touching_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "suite"
            root.mkdir()
            suite = {"cells": [{"slug": "opaque-high-standard", "model": "model-x", "effort": "high", "speed": "standard"}],
                     "prompts": ["prompt2.txt"], "prompt_numbers": [2],
                     "template": "task-frozen.tmpl", "concurrency": {"default": 1, "hard_cap": 1, "auto_start": False}}
            (root / "suite.json").write_text(json.dumps(suite), encoding="utf-8")
            (root / "prompt2.txt").write_text("Review the frozen source.", encoding="utf-8")
            (root / "task-frozen.tmpl").write_text("Ticket {TICKET}\n{PROMPT}\n{FROZEN}\n{FROZEN_WSL}\n", encoding="utf-8")
            rid = "opaque-high-standard-p2"
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(Path(tmp) / "local")}):
                self.assertEqual(bench.prepare(root), 0)
                run_dir = root / "runs" / rid
                old_attempt = run_dir / "attempt-01" / "launch.json"
                failed = bench._json(old_attempt)
                failed["status"] = "FAILED_SETUP"
                bench._write_json(old_attempt, failed)
                bench._write_json(run_dir / "launch.json", failed)
                original_bytes = old_attempt.read_bytes()
                self.assertIn("FAILED_SETUP", bench.RETRYABLE_TERMINAL_STATUSES)
                (run_dir / "attempt-02").mkdir()
                bench._prepare_retry_attempt(root, rid, 2)
                self.assertEqual(old_attempt.read_bytes(), original_bytes)
                new = run_dir / "attempt-02"
                self.assertEqual(bench._json(new / "launch.json")["status"], "PREPARED")
                self.assertFalse((Path(bench._json(new / "launch.json")["codex_home"]) / "auth.json").exists())
                failed_config = (run_dir / "attempt-01" / "requested-config.json").read_bytes()
                bench._refresh_prepared_profile(run_dir, rid, {"model": "model-x", "effort": "high", "speed": "standard"})
                self.assertEqual((run_dir / "attempt-01" / "launch.json").read_bytes(), original_bytes)
                self.assertEqual((run_dir / "attempt-01" / "requested-config.json").read_bytes(), failed_config)
                refreshed = bench._json(new / "requested-config.json")
                self.assertEqual(refreshed["profile_version"], bench.PROFILE_VERSION)
                self.assertFalse(refreshed["hooks_enabled"])

    def test_rollout_id_reads_session_meta_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            rollout = Path(tmp) / "rollout.jsonl"
            rollout.write_text(json.dumps({
                "type": "session_meta",
                "payload": {"id": "thread-123", "session_id": "thread-123"},
            }) + "\n", encoding="utf-8")
            self.assertEqual(bench._rollout_id(rollout), "thread-123")

    def test_prepare_refreshes_untouched_prompt_and_receipts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "suite"
            root.mkdir()
            (root / "suite.json").write_text(json.dumps({
                "cells": [{"slug": "x-high-standard", "model": "x", "effort": "high", "speed": "standard"}],
                "prompts": ["prompt2.txt"], "prompt_numbers": [2], "template": "task-frozen.tmpl",
            }))
            (root / "prompt2.txt").write_text("p2")
            template = root / "task-frozen.tmpl"
            template.write_text("old {TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(Path(tmp) / "local")}):
                bench.prepare(root)
                template.write_text("new pagination {TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
                bench.prepare(root)
            run_dir = root / "runs" / "x-high-standard-p2"
            prompt = run_dir / "prompt.md"
            self.assertIn("new pagination", prompt.read_text())
            digest = bench._sha(prompt.read_bytes())
            self.assertEqual(bench._json(run_dir / "launch.json")["prompt_sha256"], digest)
            self.assertEqual(bench._json(run_dir / "attempt-01" / "launch.json")["prompt_sha256"], digest)

    def test_prepare_recovers_only_missing_untouched_prepared_attempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "suite"
            root.mkdir()
            (root / "suite.json").write_text(json.dumps({
                "cells": [{"slug": "x-high-standard", "model": "x", "effort": "high", "speed": "standard"}],
                "prompts": ["prompt2.txt"], "prompt_numbers": [2], "template": "task-frozen.tmpl",
            }))
            (root / "prompt2.txt").write_text("p2")
            (root / "task-frozen.tmpl").write_text("{TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
            env = {"LOCALAPPDATA": str(Path(tmp) / "local")}
            with mock.patch.dict(bench.os.environ, env):
                bench.prepare(root)
                run_dir = root / "runs" / "x-high-standard-p2"
                old_receipt = (run_dir / "launch.json").read_bytes()
                shutil.rmtree(run_dir / "attempt-01")
                bench.prepare(root)
            self.assertEqual((run_dir / "legacy-prepared-launch.json").read_bytes(), old_receipt)
            self.assertTrue((run_dir / "attempt-01" / "requested-config.json").is_file())
            self.assertEqual(bench._json(run_dir / "launch.json")["status"], "PREPARED")

    def test_prepare_refuses_refresh_after_report_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "suite"
            root.mkdir()
            (root / "suite.json").write_text(json.dumps({
                "cells": [{"slug": "x-high-standard", "model": "x", "effort": "high", "speed": "standard"}],
                "prompts": ["prompt2.txt"], "prompt_numbers": [2], "template": "task-frozen.tmpl",
            }))
            (root / "prompt2.txt").write_text("p2")
            template = root / "task-frozen.tmpl"
            template.write_text("old {TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(Path(tmp) / "local")}):
                bench.prepare(root)
                run_dir = root / "runs" / "x-high-standard-p2"
                (run_dir / "report.md").write_text("preserved")
                template.write_text("new {TICKET} {PROMPT} {FROZEN} {FROZEN_WSL}")
                with self.assertRaises(bench.BenchError):
                    bench.prepare(root)
                self.assertEqual((run_dir / "report.md").read_text(), "preserved")

    def test_run_without_execute_refuses_before_preflight_or_launch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "suite.json").write_text(json.dumps({"cells": [{"slug": "x-high-standard", "model": "x", "effort": "high", "speed": "standard"}]}))
            with mock.patch.object(bench, "_preflight", side_effect=AssertionError("preflight must not run")):
                self.assertEqual(bench.main(["run", str(root), "x-high-standard-p2"]), 2)

    def test_missing_execute_with_named_mode_still_refuses_before_preflight(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "suite.json").write_text(json.dumps({"cells": [{"slug": "x-high-standard", "model": "x", "effort": "high", "speed": "standard"}]}))
            with mock.patch.object(bench, "_preflight", side_effect=AssertionError("preflight must not run")):
                self.assertEqual(bench.main(["run", str(root), "x-high-standard-p2", "--mode", "limited-concurrent"]), 2)


if __name__ == "__main__":
    unittest.main()
