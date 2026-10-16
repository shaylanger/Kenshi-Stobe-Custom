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
        outer_tools = sorted(codex_status.OUTER_TOOL_NAMES)
        probe = {
            "kind": "codex_hostprobe", "status": "PASS", "cli_returncode": 0,
            "cli_sha256": "a" * 64, "host_sha256": "b" * 64,
            "config": {"code_mode": True, "code_mode_host": True, "shell_tool": False,
                       "multi_agent": False, "agents_enabled": False, "view_image": False,
                       "hooks_enabled": False, "mcp_tools": frozen,
                       "mcp_default_tools_approval_mode": "approve",
                       "excluded_tool_namespaces": list(codex_status.EXCLUDED_NAMESPACES)},
            "request_tool_names": outer_tools, "request_service_tier": request_tier,
            "provider": {"bound_host": "127.0.0.1", "port_ephemeral": True,
                         "requests": 1, "external_hosts": 0, "credential": "dummy"},
            "host": {"global_names": ["Object", "JSON"], "forbidden_global_names": [],
                     "tool_names": frozen, "tool_namespace_keys": frozen, "direct_callable_tool_names": frozen,
                     "unlisted_callable_names": [], "frozen_list_call": {"isError": False},
                     "list_response_shape": {"isError": False},
                     "unknown_parameter_status": "server_rejected",
                     "unknown_parameter_response_shape": {"isError": True},
                     "agent_api_types": {name: {"global": "undefined", "tool": "undefined"}
                                         for name in codex_status.AGENT_APIS},
                     "constructor_escape_types": {"process": "undefined", "require": "undefined",
                                                  "globalProcess": "undefined"},
                     "dynamic_import_status": {"node:fs": "rejected:Error",
                                               "node:child_process": "rejected:Error",
                                               "node:https": "rejected:Error"}},
            "mcp_calls": [{"tool": "list", "status": "ok", "isError": False, "result_class": "ok"},
                          {"tool": "list", "status": "error:FrozenAccessError", "isError": True,
                           "result_class": "error:FrozenAccessError"}],
            "hook_enforcement": {"status": "UNAVAILABLE", "reason": "hooks disabled"},
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
        self.assertEqual(metrics["code_mode_host"]["hook_enforcement"]["status"], "UNAVAILABLE")
        self.assertNotIn("report", metrics)
        self.assertNotIn("private report content", repr(metrics))

    def test_running_and_missing_tier_are_audit_unknown(self):
        self.receipt["status"] = "running"
        self.records[1].pop("service_tier")
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "UNKNOWN")
        self.assertIsNone(metrics["observed_service_tier"])

    def test_terminal_elapsed_is_stable_and_prefers_recorded_finite_duration(self):
        self.receipt.update({"status": "COMPLETE_UNAUDITED", "elapsed_s": 267.453,
                             "started_utc": (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat(),
                             "ended_utc": (datetime.now(timezone.utc) - timedelta(minutes=55)).isoformat()})
        self.write()
        first = codex_status.live_metrics(self.receipt, None)["elapsed_s"]
        second = codex_status.live_metrics(self.receipt, None)["elapsed_s"]
        self.assertEqual(first, 267.453)
        self.assertEqual(second, 267.453)

    def test_terminal_elapsed_falls_back_to_valid_endpoints_or_unknown(self):
        start = datetime(2026, 10, 16, tzinfo=timezone.utc)
        self.receipt.update({"status": "failed", "started_utc": start.isoformat(),
                             "ended_utc": (start + timedelta(seconds=12.5)).isoformat()})
        self.assertEqual(codex_status._elapsed_seconds(self.receipt), 12.5)
        for invalid in (-1, float("inf"), float("nan")):
            self.receipt["elapsed_s"] = invalid
            self.assertEqual(codex_status._elapsed_seconds(self.receipt), 12.5)
        self.receipt.update({"elapsed_s": -1, "ended_utc": (start - timedelta(seconds=1)).isoformat()})
        self.assertIsNone(codex_status._elapsed_seconds(self.receipt))
        self.receipt.pop("ended_utc")
        self.assertIsNone(codex_status._elapsed_seconds(self.receipt))

    def test_running_elapsed_uses_current_time_not_terminal_duration(self):
        start = datetime.now(timezone.utc) - timedelta(seconds=8)
        duration = codex_status._elapsed_seconds({"status": "running", "started_utc": start.isoformat(),
                                                   "elapsed_s": 9000})
        self.assertGreaterEqual(duration, 8)
        self.assertLess(duration, 10)

    def test_completed_validity_can_pass_while_overall_tier_is_unknown(self):
        self.records[1].pop("service_tier")
        self._write_hostprobe(None)
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "PASS")
        self.assertEqual(metrics["overall_status"], "UNKNOWN")
        self.assertEqual(metrics["requested_tier_proof"], "PASS")
        self.assertEqual(metrics["hostprobe_tier_request_proof"], "UNKNOWN")
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

    def test_code_mode_exec_accepts_hard_boundary_with_unavailable_hooks(self):
        self.records.append({"type": "response_item", "payload": {"type": "custom_tool_call",
                            "call_id": "call-1", "name": "exec", "input": json.dumps({"code": "text(1)"})}})
        self.records.append({"type": "response_item", "payload": {"type": "custom_tool_call_output",
                            "call_id": "call-1", "output": "hidden"}})
        self.receipt["allowed_tools"] = ["exec"]
        self.receipt["hook_verified"] = False
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "PASS")
        self.assertEqual(metrics["code_mode_host"]["hook_enforcement"]["status"], "UNAVAILABLE")

    def test_sanitized_hostprobe_hash_and_guard_binding(self):
        path = Path(self.tmp.name) / "hostprobe.json"
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        self.assertEqual(codex_status._verify_hostprobe(str(path), digest)["status"], "PASS")
        self.assertEqual(codex_status._verify_hostprobe(str(path), "0" * 64)["status"], "FAIL")

    def test_metrics_rechecks_nested_boundary_proof_receipt(self):
        self.records.append({"type": "response_item", "payload": {"role": "assistant",
                            "phase": "final_answer", "content": [{"type": "output_text", "text": "final"}]}})
        path = self.receipt["hostprobe_path"]
        digest = self.receipt["hostprobe_sha256"]
        self.receipt.pop("hostprobe_path")
        self.receipt.pop("hostprobe_sha256")
        self.receipt["code_mode_host_proof"] = {
            "verified": True, "status": "BOUNDARY_VERIFIED",
            "path": path, "sha256": digest,
        }
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        self.assertEqual(metrics["audit"], "PASS")
        self.assertEqual(metrics["code_mode_host"]["status"], "PASS")

    def test_historical_telemetry_is_projected_separately_and_never_aggregated(self):
        telemetry_path = Path(self.tmp.name) / "pilot-attempt02.telemetry.json"
        telemetry = {
            "run_id": "gpt-x-high-p2", "attempt": 2, "classification": "FAIL_SETUP_INVALID_ISOLATION_EVIDENCE",
            "thread_id": "thread-1", "rollout_candidate": "attempt-02/rollout.jsonl",
            "usage": {"input_tokens": 22850, "cached_input_tokens": 11264,
                      "output_tokens": 902, "reasoning_output_tokens": 37},
            "invoice_amount": "UNKNOWN", "served_service_tier": "UNKNOWN",
            "requested_service_tier": "default", "pricing_reference_date": "2026-10-16",
            "conditional_reference_estimate_usd_if_default_was_served": 0.172224,
            "cache_create_rate": "unavailable in published reference table",
            "report": "must not be copied into metrics",
        }
        telemetry_path.write_text(json.dumps(telemetry), encoding="utf-8")
        self.receipt["historical_telemetry_path"] = telemetry_path.name
        self.receipt["suite_dir"] = self.tmp.name
        self.records.append({"type": "event_msg", "payload": {"type": "token_count", "info": {
            "total_token_usage": {"input_tokens": 100, "cached_input_tokens": 5,
                                  "cache_write_input_tokens": 0, "output_tokens": 10,
                                  "reasoning_output_tokens": 2, "total_tokens": 110}}}})
        self.write()
        metrics = codex_status.live_metrics(self.receipt, None)
        historical = metrics["historical_attempt_telemetry"]
        self.assertEqual(historical["status"], "AVAILABLE")
        self.assertEqual(historical["attempt"], 2)
        self.assertEqual(historical["usage"]["input_tokens"], 22850)
        self.assertEqual(historical["reference_cost"]["usd"], 0.172224)
        self.assertEqual(historical["reference_cost"]["status"], "CONDITIONAL_REQUESTED_TIER_ESTIMATE")
        self.assertEqual(metrics["usage"]["input_tokens"], 100)
        self.assertNotIn("must not be copied", repr(metrics))

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

    def test_hostprobe_rejects_nonfrozen_callable_and_missing_strict_mcp_error(self):
        path = Path(self.tmp.name) / "hostprobe.json"
        probe = json.loads(path.read_text(encoding="utf-8"))
        probe["host"]["direct_callable_tool_names"].append("apply_patch")
        raw = json.dumps(probe).encode()
        path.write_bytes(raw)
        self.assertEqual(codex_status._verify_hostprobe(str(path), hashlib.sha256(raw).hexdigest())["status"], "FAIL")
        self._write_hostprobe("default")
        probe = json.loads(path.read_text(encoding="utf-8"))
        probe["mcp_calls"].pop()
        raw = json.dumps(probe).encode()
        path.write_bytes(raw)
        self.assertEqual(codex_status._verify_hostprobe(str(path), hashlib.sha256(raw).hexdigest())["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
