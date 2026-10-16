"""Synthetic tests for Codex rollout parsing; no model or database calls."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import codex_record as cr


class RecorderTests(unittest.TestCase):
    def fixture(self, records):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        path = Path(td.name) / "rollout.jsonl"
        path.write_text("".join(json.dumps(x) + "\n" for x in records), encoding="utf-8")
        return path

    def test_parse_usage_deduplicates_cumulative_and_extracts_final(self):
        p = self.fixture([
            {"timestamp": "2026-10-16T10:00:00+00:00", "type": "turn_context", "model": "m", "effort": "high", "service_tier": "default", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 100, "cached_input_tokens": 25, "cache_write_input_tokens": 4, "output_tokens": 30, "reasoning_output_tokens": 7, "total_tokens": 130}}}},
            {"timestamp": "2026-10-16T10:00:04+00:00", "type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 200, "cached_input_tokens": 50, "cache_write_input_tokens": 8, "output_tokens": 60, "reasoning_output_tokens": 15, "total_tokens": 260}}}},
            {"type": "response_item", "payload": {"type": "function_call", "call_id": "c1", "name": "Bash", "arguments": "{\"command\":\"echo hi\"}"}},
            {"type": "response_item", "payload": {"role": "assistant", "phase": "final_answer", "content": [{"type": "output_text", "text": "final answer\n"}]}}
        ])
        result = cr.parse_rollout(p, {"verified_receipt": True, "agents_enabled": False, "multi_agent": False,
                                      "hook_verified": True, "terminal_verified": True,
                                      "allowed_tools": ["bash"], "model": "m", "effort": "high",
                                      "service_tier": "standard"})
        self.assertEqual(result["usage"]["total_tokens"], 260)
        self.assertEqual(result["tool_uses"], 1)
        self.assertEqual(result["report"], "final answer\n")
        self.assertEqual(result["wall_s"], 4)
        self.assertEqual(result["audit"]["status"], "PASS")
        self.assertEqual(result["start_local"], "2026-10-16T04:00:00-06:00")

    def test_usage_not_double_counted_and_reasoning_not_added_to_output(self):
        u = {"input_tokens": 100, "cached_input_tokens": 0, "cache_write_input_tokens": 0,
             "output_tokens": 20, "reasoning_output_tokens": 9, "total_tokens": 120}
        result = cr.price_usage(u, "m", "standard", {"date": "2026-01-01", "models": {"m": {"standard": {
            "input": 1, "cache_read": 0.5, "cache_create": 2, "output": 3}}}})
        self.assertEqual(result["parts_usd"]["output"], 20 * 3 / 1_000_000)
        self.assertEqual(result["parts_usd"]["input"], 100 * 1 / 1_000_000)
        self.assertEqual(result["parts_usd"]["cache_read"], 0)
        self.assertNotIn("reasoning", result["parts_usd"])

    def test_audit_reads_actual_inputs_not_prompt_text_and_fails_unknown_config(self):
        safe = [{"type": "response_item", "payload": {"type": "function_call", "name": "Bash", "arguments": "{\"command\":\"echo 'rm -rf'\"}"}}]
        proof = {"verified_receipt": True, "agents_enabled": False, "multi_agent": False,
                 "hook_verified": True, "terminal_verified": True, "allowed_tools": ["bash"]}
        self.assertEqual(cr.audit_rollout(safe, proof)["status"], "PASS")
        self.assertEqual(cr.audit_rollout([], None)["status"], "UNKNOWN")

    def test_audit_flags_mutation_prohibited_read_and_delegation(self):
        events = [{"type": "response_item", "payload": {"type": "function_call", "call_id": "1", "name": "Bash", "arguments": "{\"command\":\"git commit -m x\"}"}},
                  {"type": "response_item", "payload": {"type": "function_call", "call_id": "2", "name": "Read", "arguments": "{\"file_path\":\"C:/StobeBuild/out.dll\"}"}},
                  {"type": "response_item", "payload": {"type": "function_call", "call_id": "3", "name": "collaboration.spawn_agent", "arguments": "{}"}}]
        audit = cr.audit_rollout(events, {"verified_receipt": True, "agents_enabled": False, "multi_agent": False,
                                          "hook_verified": True, "terminal_verified": True,
                                          "allowed_tools": ["bash", "read"]})
        self.assertEqual(audit["status"], "FAIL")
        self.assertTrue(any(x.startswith("mutation:") for x in audit["flags"]))
        self.assertTrue(any(x.startswith("prohibited-read:") for x in audit["flags"]))
        self.assertTrue(any(x.startswith("delegation:") for x in audit["flags"]))

    def test_no_final_answer_and_missing_hook_or_terminal_receipt_fail_closed(self):
        p = self.fixture([{"type": "response_item", "payload": {"role": "assistant", "channel": "commentary",
                                                                      "content": [{"type": "output_text", "text": "not final"}]}}])
        result = cr.parse_rollout(p, {"verified_receipt": True, "agents_enabled": False,
                                      "multi_agent": False, "allowed_tools": ["read"]})
        self.assertIsNone(result["report"])
        self.assertEqual(result["audit"]["status"], "UNKNOWN")

    def test_aggregate_short_long_usage_cost_is_unavailable(self):
        u = {"input_tokens": 500, "cached_input_tokens": 100, "cache_write_input_tokens": 10, "output_tokens": 20}
        table = {"models": {"m": {"standard": {"short": {}, "long": {}}, "threshold_tokens": 1000}}}
        result = cr.price_usage(u, "m", "standard", table)
        self.assertEqual(result["status"], "unavailable")
        self.assertIn("per-request", result["reasons"][0])

    def test_per_request_pricing_applies_threshold_and_uncached_input(self):
        rates = {"input": 1, "cache_read": 0.1, "cache_create": 2, "output": 3}
        usage = {"requests": [
            {"request_id": "r1", "input_tokens": 100, "cached_input_tokens": 20,
             "cache_write_input_tokens": 10, "output_tokens": 5},
            {"request_id": "r2", "input_tokens": 2000, "cached_input_tokens": 100,
             "cache_write_input_tokens": 0, "output_tokens": 10},
        ]}
        table = {"date": "2026-10-16", "models": {"m": {"threshold_tokens": 1000,
                 "standard": {"short": rates, "long": {**rates, "input": 10}}}}}
        result = cr.price_usage(usage, "m", "standard", table)
        self.assertEqual(result["status"], "priced")
        self.assertEqual([r["tier"] for r in result["requests"]], ["short", "long"])
        self.assertAlmostEqual(result["requests"][0]["usd"], (70 + 20 * .1 + 10 * 2 + 5 * 3) / 1_000_000)

    def test_rollout_cumulative_deltas_dedup_and_decrease_invalidate_cost(self):
        def token_event(total):
            return {"type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": total}}}
        base = {"input_tokens": 100, "cached_input_tokens": 10, "cache_write_input_tokens": 5,
                "output_tokens": 20, "reasoning_output_tokens": 3, "total_tokens": 120}
        later = {"input_tokens": 200, "cached_input_tokens": 20, "cache_write_input_tokens": 10,
                 "output_tokens": 40, "reasoning_output_tokens": 8, "total_tokens": 240}
        parsed = cr._usage_data([token_event(base), token_event(base), token_event(later)])
        usage, requests, errors = parsed
        self.assertEqual(len(requests), 2)
        self.assertEqual(requests[1]["input_tokens"], 100)
        self.assertEqual(errors, [])
        decreased = {"input_tokens": 1, "cached_input_tokens": 0, "cache_write_input_tokens": 0,
                     "output_tokens": 1, "total_tokens": 2}
        usage, _, errors = cr._usage_data([token_event(later), token_event(decreased)])
        self.assertTrue(errors)
        self.assertEqual(cr.price_usage(usage, "m", "standard", {"models": {"m": {"standard": {}}}})["status"], "unavailable")

    def test_codex_last_token_usage_and_turn_context_metadata_shape(self):
        p = self.fixture([
            {"type": "turn_context", "timestamp": "2026-10-16T10:00:00Z", "model": "gpt-x", "effort": "high", "service_tier": "priority"},
            {"type": "event_msg", "timestamp": "2026-10-16T10:00:02Z", "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": 120, "cached_input_tokens": 20,
                                      "cache_write_input_tokens": 10, "output_tokens": 25,
                                      "reasoning_output_tokens": 5, "total_tokens": 145},
                "last_token_usage": {"input_tokens": 120, "cached_input_tokens": 20,
                                     "cache_write_input_tokens": 10, "output_tokens": 25,
                                     "reasoning_output_tokens": 5}}}}
        ])
        result = cr.parse_rollout(p, {"verified_receipt": True, "agents_enabled": False,
                                      "multi_agent": False, "hook_verified": True,
                                      "terminal_verified": True, "allowed_tools": [],
                                      "model": "gpt-x", "effort": "high", "service_tier": "fast"})
        self.assertEqual(result["model"], "gpt-x")
        self.assertEqual(result["effort"], "high")
        self.assertEqual(result["usage"]["requests"][0]["input_tokens"], 120)
        self.assertEqual(result["request_usage_errors"], [])

    def test_root_agent_message_is_not_delegation_but_child_metadata_is(self):
        proof = {"verified_receipt": True, "agents_enabled": False, "multi_agent": False,
                 "hook_verified": True, "terminal_verified": True, "allowed_tools": []}
        root_final = [{"type": "event_msg", "payload": {"type": "agent_message", "phase": "final_answer", "message": "done"}}]
        self.assertEqual(cr.audit_rollout(root_final, proof)["status"], "PASS")
        self.assertEqual(cr._final_text({"events": root_final}), "done")
        commentary = [{"type": "event_msg", "payload": {"type": "agent_message", "message": "commentary"}}]
        self.assertIsNone(cr._final_text({"events": commentary}))
        child = [{"type": "turn_context", "child_thread_id": "child-1"}]
        result = cr.audit_rollout(child, proof)
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(any("delegation:" in x for x in result["flags"]))

    def test_runtime_model_effort_missing_mismatch_and_tier_mismatch(self):
        p = self.fixture([{"type": "turn_context", "model": "actual", "effort": "low", "service_tier": "priority"}])
        proof = {"verified_receipt": True, "agents_enabled": False, "multi_agent": False,
                 "hook_verified": True, "terminal_verified": True, "allowed_tools": [],
                 "model": "requested", "effort": "high", "service_tier": "standard"}
        result = cr.parse_rollout(p, proof)
        self.assertEqual(result["audit"]["status"], "FAIL")
        self.assertIn("requested-runtime-model-mismatch", result["audit"]["flags"])
        self.assertIn("requested-runtime-effort-mismatch", result["audit"]["flags"])
        self.assertIn("requested-service-tier-mismatch", result["audit"]["flags"])
        missing = cr.parse_rollout(self.fixture([]), proof)
        self.assertEqual(missing["audit"]["status"], "UNKNOWN")

    def test_pricing_fails_closed_on_missing_long_tier_and_rates(self):
        u = {"input_tokens": 1, "output_tokens": 2}
        self.assertEqual(cr.price_usage(u, "m", "long", {"models": {"m": {"standard": {}}}})["status"], "unavailable")
        self.assertEqual(cr.price_usage(u, "m", "standard", {"models": {"m": {"standard": {"input": 1}}}})["status"], "unavailable")


if __name__ == "__main__":
    unittest.main()
