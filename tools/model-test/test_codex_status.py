"""Synthetic file based tests for read-only Codex live metrics."""
import json
import hashlib
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
        self._write_launch_proofs()
        self.records = [
            {"type": "thread.started", "thread_id": "root-1"},
            {"type": "turn_context", "model": "gpt-x", "effort": "high", "service_tier": "default"},
        ]

    def write(self):
        self.path.write_text("".join(json.dumps(x) + "\n" for x in self.records), encoding="utf-8")
        self.receipt["rollout_path"] = str(self.path)

    def _write_launch_proofs(self):
        cfg = {"private_config_sha256": "c" * 64}
        cfg_bytes = (json.dumps(cfg, indent=2) + "\n").encode()
        cfg_path = Path(self.tmp.name) / "requested-config.json"
        cfg_path.write_bytes(cfg_bytes)
        argv = ["--model", "gpt-x", "--config", "model_reasoning_effort=high", "--service-tier", "default"]
        argv_path = Path(self.tmp.name) / "argv.json"
        argv_path.write_text(json.dumps(argv, indent=2) + "\n", encoding="utf-8")
        self.receipt.update({"requested_config": cfg, "config_sha256": hashlib.sha256(cfg_bytes).hexdigest(),
                             "argv_sha256": hashlib.sha256(json.dumps(argv).encode()).hexdigest(),
                             "attempt_dir": self.tmp.name})
        self._write_hostprobe("default")

    def _write_hostprobe(self, request_tier):
        frozen = sorted(codex_status.FROZEN_TOOLS)
        probe = {
            "kind": "codex_hostprobe", "status": "PASS", "cli_returncode": 0,
            "cli_sha256": "a" * 64, "code_mode_host_sha256": "b" * 64,
            "config": {"code_mode": True, "code_mode_host": True, "shell_tool": False,
                       "multi_agent": False, "agents_enabled": False, "view_image": False,
                       "enabled_tools": frozen + ["exec"]},
            "request_tool_names": frozen + ["exec"], "request_service_tier": request_tier,
            "provider": {"bound_host": "127.0.0.1", "port_ephemeral": 54321,
                         "requests_n": 1, "external_hosts_attempted": 0, "auth": "dummy"},
            "host": {"global_names": ["Object", "JSON"], "global_forbidden_names": [],
                     "tool_names": frozen, "frozen_list_call": "ok"},
            "hooks": {"session_start_receipts": 1, "pretool_allowed_frozen": 1,
                      "pretool_denied_nonfrozen": 1},
        }
        raw = json.dumps(probe).encode()
        path = Path(self.tmp.name) / "hostprobe.json"
        path.write_bytes(raw)
        self.receipt.update({"hostprobe_path": str(path), "hostprobe_sha256": hashlib.sha256(raw).hexdigest()})

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

    def test_completed_validity_can_pass_while_overall_tier_is_unknown(self):
        self.records[1].pop("service_tier")
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "PASS")
        self.assertEqual(metrics["overall_status"], "UNKNOWN")
        self.assertEqual(metrics["audit_dimensions"]["service_tier"], "UNKNOWN")

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

    def test_code_mode_exec_without_hostproof_stays_unknown_and_counts_once(self):
        self.records.append({"type": "response_item", "payload": {"type": "custom_tool_call",
                            "call_id": "call-1", "name": "exec", "input": "{}"}})
        self.records.append({"type": "response_item", "payload": {"type": "custom_tool_call_output",
                            "call_id": "call-1", "output": "hidden"}})
        self.receipt["allowed_tools"] = ["exec"]
        self.receipt.pop("hostprobe_path")
        self.receipt.pop("hostprobe_sha256")
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["tool_uses"], 1)
        self.assertEqual(metrics["audit"], "UNKNOWN")
        self.assertEqual(metrics["code_mode_host"]["status"], "UNKNOWN")

    def test_sanitized_hostprobe_hash_and_guard_binding(self):
        path = Path(self.tmp.name) / "hostprobe.json"
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        self.assertEqual(codex_status._verify_hostprobe(str(path), digest)["status"], "PASS")
        self.assertEqual(codex_status._verify_hostprobe(str(path), "0" * 64)["status"], "FAIL")

    def test_hostprobe_failure_and_incomplete_proof_never_pass(self):
        path = Path(self.tmp.name) / "hostprobe.json"
        probe = json.loads(path.read_text(encoding="utf-8"))
        probe.update({"status": "FAIL", "phase": "exec"})
        raw = json.dumps(probe).encode()
        path.write_bytes(raw)
        digest = hashlib.sha256(raw).hexdigest()
        self.assertEqual(codex_status._verify_hostprobe(str(path), digest)["status"], "FAIL")

        probe.pop("status")
        probe.pop("cli_returncode")
        raw = json.dumps(probe).encode()
        path.write_bytes(raw)
        digest = hashlib.sha256(raw).hexdigest()
        result = codex_status._verify_hostprobe(str(path), digest)
        self.assertEqual(result["status"], "UNKNOWN")

    def test_hostprobe_forbidden_global_inventory_is_sufficient(self):
        path = Path(self.tmp.name) / "hostprobe.json"
        probe = json.loads(path.read_text(encoding="utf-8"))
        probe["host"].pop("global_names")
        raw = json.dumps(probe).encode()
        path.write_bytes(raw)
        result = codex_status._verify_hostprobe(str(path), hashlib.sha256(raw).hexdigest())
        self.assertEqual(result["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
