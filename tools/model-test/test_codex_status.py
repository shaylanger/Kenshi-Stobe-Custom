"""Synthetic file based tests for read-only Codex live metrics."""
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import codex_status


class LiveMetricsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "rollout.jsonl"
        self.receipt = {
            "run": "gpt-x-high-p2", "model": "gpt-x", "effort": "high", "speed": "standard",
            "service_tier": "standard", "started_utc": (datetime.now(timezone.utc) - timedelta(seconds=30)).isoformat(),
            "status": "completed", "agents_enabled": False, "multi_agent": False,
            "verified_receipt": True, "hook_verified": True, "terminal_verified": True,
            "allowed_tools": [],
        }
        self.records = [
            {"type": "thread.started", "thread_id": "root-1"},
            {"type": "turn_context", "model": "gpt-x", "effort": "high", "service_tier": "default"},
        ]

    def write(self):
        self.path.write_text("".join(json.dumps(x) + "\n" for x in self.records), encoding="utf-8")
        self.receipt["rollout_path"] = str(self.path)

    def test_complete_metrics_are_compact_and_do_not_include_message_text(self):
        self.records.append({"type": "event_msg", "payload": {"type": "agent_message", "phase": "final_answer", "message": "private report content"}})
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "PASS")
        self.assertEqual(metrics["thread"], {"root_thread_id": "root-1", "provenance": "root", "malformed_lines": 0})
        self.assertEqual(metrics["model"], "gpt-x")
        self.assertEqual(metrics["observed_service_tier"], "standard")
        self.assertNotIn("report", metrics)
        self.assertNotIn("private report content", repr(metrics))

    def test_running_and_missing_tier_are_audit_unknown(self):
        self.receipt["status"] = "running"
        self.records[1].pop("service_tier")
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "UNKNOWN")
        self.assertIsNone(metrics["observed_service_tier"])

    def test_child_and_ambiguous_thread_origins_fail(self):
        self.records[0]["parent_thread_id"] = "parent-0"
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "FAIL")
        self.assertEqual(metrics["thread"]["provenance"], "child")
        self.records[0].pop("parent_thread_id")
        self.records.append({"type": "thread.started", "thread_id": "root-2"})
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "FAIL")
        self.assertEqual(metrics["thread"]["provenance"], "ambiguous")

    def test_receipt_without_rollout_fails_closed_without_searching(self):
        metrics = codex_status.live_metrics({"status": "running"}, None)
        self.assertEqual(metrics["audit"], "UNKNOWN")
        self.assertEqual(metrics["reason"], "rollout path missing")


if __name__ == "__main__":
    unittest.main()
