#!/usr/bin/env python3
"""Item 111 (server): "go buy X from the shop here" agreed without an action -> unnamed BUY goal.

m18 Squin STOBE 14: Beak: "Kint, go buy one Limited-sight Scrap Helm from the shop here." Kint: "Aye, I'll see
what the armor trader's got." + MOVE_TO@Beak, no BUY. The item 74 guard only matched "from <Trader Name>".
Now "from the shop/store/trader/merchant/vendor/market/stall/counter [here|nearby|in town]" gives
TASK_GOAL@BUY@@<item>@<qty>@<dest>@0 (empty trader = KenshiFP picks the nearest trader; item 111 KenshiFP
widens that search when none is within 220).

Usage: item111_buy_from_the_shop.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == 1, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

patch("lib/chat_helper_functions.php",
"""    if (!preg_match("/\\b(?i:buy)\\s+(?:me\\s+|us\\s+)?(?:(\\d{1,4})\\s+)?(?:(?:a|an|the|some)\\s+)?([A-Za-z][A-Za-z' -]{1,60}?)\\s+from\\s+(?:the\\s+)?([A-Z][A-Za-z' -]{1,60}?)(?=\\s*(?:\\band\\b|\\bfor\\b|[,.!;]|$))/", $line, $m)) return '';
    $item = trim(preg_replace('/\\s+/', ' ', $m[2]) ?? '');
    $trader = trim(preg_replace('/\\s+/', ' ', $m[3]) ?? '');
    if ($item === '' || $trader === '' || preg_match('/^(it|them|that|this|something|stuff)$/i', $item)) return '';
    $known = $traderKnown !== null ? boolval($traderKnown($trader))
        : (function_exists('getNpcData') && is_array(getNpcData($trader)));
    if (!$known) return '';""",
"""    $anyShop = false;
    if (!preg_match("/\\b(?i:buy)\\s+(?:me\\s+|us\\s+)?(?:(\\d{1,4})\\s+)?(?:(?:a|an|the|some)\\s+)?([A-Za-z][A-Za-z' -]{1,60}?)\\s+from\\s+(?:the\\s+)?([A-Z][A-Za-z' -]{1,60}?)(?=\\s*(?:\\band\\b|\\bfor\\b|[,.!;]|$))/", $line, $m)) {
        // Item 111: "from the shop here" = whichever trader is nearest (KenshiFP picks it).
        if (!preg_match("/\\b(?i:buy)\\s+(?:me\\s+|us\\s+)?(?:(\\d{1,4})\\s+)?(?:(?:a|an|the|some)\\s+)?([A-Za-z][A-Za-z' -]{1,60}?)\\s+(?i:from|at)\\s+(?i:the|a|this|that)\\s+(?i:shop|store|trader|merchant|vendor|market|stall|counter)(?:\\s+(?i:here|nearby|over there|in town))?(?=\\s*(?:\\band\\b|\\bfor\\b|[,.!;]|$))/", $line, $m)) return '';
        $anyShop = true;
        $m[3] = '';
    }
    $item = trim(preg_replace('/\\s+/', ' ', $m[2]) ?? '');
    $trader = trim(preg_replace('/\\s+/', ' ', $m[3]) ?? '');
    if ($item === '' || ($trader === '' && !$anyShop) || preg_match('/^(it|them|that|this|something|stuff)$/i', $item)) return '';
    $known = $anyShop || ($traderKnown !== null ? boolval($traderKnown($trader))
        : (function_exists('getNpcData') && is_array(getNpcData($trader))));
    if (!$known) return '';""")

patch("tests/goal_destination_regression.php",
"""check('item 74: a refusal -> nothing', stobeInferBuyFromAgreedRequest($line74, $npc73, [], "No, I'm not wasting cats on that.", true, $known74) === '');""",
"""check('item 74: a refusal -> nothing', stobeInferBuyFromAgreedRequest($line74, $npc73, [], "No, I'm not wasting cats on that.", true, $known74) === '');
// 111: "from the shop here" (m18 Squin) -> unnamed BUY, KenshiFP picks the nearest trader
check('item 111: "buy one X from the shop here" + agreement -> TASK_GOAL@BUY with no trader',
    stobeInferBuyFromAgreedRequest('Kint, go buy one Limited-sight Scrap Helm from the shop here.', $npc73, ['MOVE_TO@Beak'], "Aye, I'll see what the armor trader's got.", true, $known74)
    === 'TASK_GOAL@BUY@@Limited-sight Scrap Helm@1@@0',
    stobeInferBuyFromAgreedRequest('Kint, go buy one Limited-sight Scrap Helm from the shop here.', $npc73, ['MOVE_TO@Beak'], "Aye, I'll see what the armor trader's got.", true, $known74));
check('item 111: "from the trader" refused -> nothing', stobeInferBuyFromAgreedRequest('Buy 2 bread from the trader.', $npc73, [], "No, I'm not wasting cats on that.", true, $known74) === '');""")
