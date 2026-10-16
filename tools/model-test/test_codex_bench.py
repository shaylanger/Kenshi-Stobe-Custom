"""Synthetic-only tests for benchmark orchestration; never starts Codex."""
from __future__ import annotations

import csv
import importlib.util
import json
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
            self.assertIn("code_mode = true", private_config)
            self.assertIn("code_mode_host = true", private_config)
            self.assertIn("tool_search = false", private_config)
            self.assertIn("view_image = false", private_config)
            self.assertIn('enabled_tools = ["list", "read", "search", "sql"]', private_config)
            self.assertIn("[[hooks.PreToolUse]]", private_config)
            self.assertIn("[[hooks.SessionStart]]", private_config)
            self.assertIn("[[hooks.SubagentStart]]", private_config)
            self.assertIn("[[hooks.SessionEnd]]", private_config)
            self.assertFalse(list((Path(tmp) / "local").rglob("hooks.json")))
            self.assertNotIn("[tools]", private_config)

    def test_private_profile_path_is_stable_for_relative_and_absolute_run_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_dir = base / "suite" / "runs" / "opaque-p2"
            relative = Path(__import__("os").path.relpath(run_dir, Path.cwd()))
            cell = {"model": "secret-model", "effort": "high", "speed": "standard"}
            with mock.patch.dict(bench.os.environ, {"LOCALAPPDATA": str(base / "local")}):
                first, _ = bench._make_config(run_dir, "opaque-p2", cell)
                second, _ = bench._make_config(relative, "opaque-p2", cell)
            self.assertEqual(first, second)

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
                                       for p in (root / "suite.json", template, root / "prompt2.txt")},
                         "prepared_prompts": {rid: receipt["prompt_sha256"]}, "auth_available": True}
                bench._write_json(root / "preflight.json", proof)
                with mock.patch.object(bench, "_strict_exec_config_probe", side_effect=bench.BenchError("invalid exact profile")):
                    with self.assertRaisesRegex(bench.BenchError, "invalid exact profile"):
                        bench.launch_one(root, rid, execute=True, timeout=10)
                self.assertEqual(bench._json(root / "runs" / rid / "launch.json")["status"], "PREPARED")
                self.assertEqual(bench._json(root / "runs" / rid / "attempt-01" / "launch.json")["status"], "PREPARED")
                self.assertFalse((Path(receipt["codex_home"]) / "auth.json").exists())

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
