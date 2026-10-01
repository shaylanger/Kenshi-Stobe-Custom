#!/usr/bin/env python3
"""Round 12 (latency), deployed 2026-09-30 17:02. Not the same as patch_round12.py (bugs 28-31).

1. MiniMe topic extraction made up to WORLD_KNOWLEDGE_AMOUNT (default 2) sequential
   topic calls, but world-knowledge retrieval only uses topics[0]; topic #2 only went
   to the audit row. Now one call (~90-100 ms saved per turn). The setting still
   limits how many knowledge entries go into the prompt (knowledgeLimit), unchanged.

2. stobeRefreshNpcDataForTraderInventory() polled 8 x 100 ms for trader inventory
   whenever the message merely looked like trade ("cats", "price", ...). The DLL only
   fills that inventory for real traders (isATrader) on chat-open, so for a normal NPC
   like Malzin it never shows up: 43 of 43 trade-word turns in the logs waited the full
   ~806 ms, none succeeded. Now it only polls when the NPC is a trader. Trade intent
   still logs the "trader inventory context" line as before.

Usage: patch_round12_latency.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


patch("lib/chat_helper_functions.php",
      """    $topicCount = max(1, min(5, getSettingInt('WORLD_KNOWLEDGE_AMOUNT', 2)));
    $keywordWindow""",
      """    // Round 12: only topics[0] is used for retrieval, so one MiniMe call is enough.
    $topicCount = 1;
    $keywordWindow""")

patch("processor/chat.php",
      """        $likelyTrader = stobeNpcLikelyTraderFromData($npcData);
        $tradeIntent = stobeMessageLooksTradeIntent($message);
        if (!$likelyTrader && !$tradeIntent) {
            return $npcData;
        }
""",
      """        $likelyTrader = stobeNpcLikelyTraderFromData($npcData);
        $tradeIntent = stobeMessageLooksTradeIntent($message);
        // Round 12: the DLL only captures trader inventory for real traders, so waiting
        // on a non-trader (e.g. "here are 300 cats" to Malzin) always timed out (~806 ms).
        if (!$likelyTrader) {
            return $npcData;
        }
""")
print("round 12 (latency) applied to", root)
