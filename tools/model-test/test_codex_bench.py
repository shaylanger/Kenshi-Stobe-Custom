"""Synthetic-only tests for benchmark orchestration; never starts Codex."""
from __future__ import annotations

import csv
import importlib.util
import json
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
            self.assertIn("code_mode = false", private_config)
            self.assertIn("code_mode_host = false", private_config)
            self.assertIn("tool_search = false", private_config)

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


if __name__ == "__main__":
    unittest.main()
