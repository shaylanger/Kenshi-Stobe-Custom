#!/usr/bin/env python3
"""Round 14: DeepInfra cache info in the audit trail (2026-09-30).

Shay's test tally showed 0 cached tokens and no prompt_cache_key, but DeepInfra's own
usage (output_from_llm.log) shows 16 of 18 Malzin chat turns reusing 1.4k-2.6k tokens
after round 13. The audit trail hid it:
  - audit_request.log / the audit_request table kept only prompt/completion/total
    tokens, dropping usage.prompt_tokens_details.cached_tokens;
  - the stored request JSON is cut at 24,000 chars, and messages (~27k) come first, so
    prompt_cache_key and service_tier were always cut off.

Now (audit only, requests unchanged):
  - audit_request.log usage has cached_tokens, plus prompt_cache_key and service_tier;
  - the DB request JSON puts the small fields first and messages last;
  - the DB result JSON gets cached_tokens (no schema change).

Usage: patch_round14_audit_cache.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == 1, f"{rel}: anchor found {t.count(old)}x: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


C = "connector/openaijson.php"
patch(C,
      """    $requestPayload = stobeSerializeAuditPayload($entry['request_payload'] ?? [], 24000);
    $resultPayload = stobeSerializeAuditPayload($entry['result_payload'] ?? '', 24000);""",
      """    // Round 14: keep prompt-cache info in the audit trail.
    $cachedTokens = intval($usage['prompt_tokens_details']['cached_tokens'] ?? ($usage['prompt_cache_hit_tokens'] ?? 0));
    $requestForAudit = $entry['request_payload'] ?? [];
    $promptCacheKey = is_array($requestForAudit) ? strval($requestForAudit['prompt_cache_key'] ?? '') : '';
    $serviceTier = is_array($requestForAudit) ? strval($requestForAudit['service_tier'] ?? '') : '';
    if (is_array($requestForAudit) && array_key_exists('messages', $requestForAudit)) {
        // Small fields first, so the 24,000-char cut drops message text, not prompt_cache_key.
        $messagesForAudit = $requestForAudit['messages'];
        unset($requestForAudit['messages']);
        $requestForAudit['messages'] = $messagesForAudit;
    }
    $resultForAudit = $entry['result_payload'] ?? '';
    if (is_array($resultForAudit) && count($usage) > 0) {
        $resultForAudit['cached_tokens'] = $cachedTokens;
    }
    $requestPayload = stobeSerializeAuditPayload($requestForAudit, 24000);
    $resultPayload = stobeSerializeAuditPayload($resultForAudit, 24000);""")
patch(C,
      """        'usage' => [
            'prompt_tokens' => $promptTokens,
            'completion_tokens' => $completionTokens,
            'total_tokens' => $totalTokens,
        ],""",
      """        'usage' => [
            'prompt_tokens' => $promptTokens,
            'completion_tokens' => $completionTokens,
            'total_tokens' => $totalTokens,
            'cached_tokens' => $cachedTokens,
        ],
        'prompt_cache_key' => $promptCacheKey,
        'service_tier' => $serviceTier,""")
print("round 14 applied to", root)
