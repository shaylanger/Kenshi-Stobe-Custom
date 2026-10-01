#!/usr/bin/env python3
"""Server round 17d (bug 52): "put those back in storage" stores, not gives.

Run 4: Shay said "Actually, put those medkits back in storage." The LLM answered
"Back they go" with GiveItem -> Shay (then dropped), so nothing moved. When the
player's own line asks for storage (storage/chest/stash/put away/put back in/store
them) and doesn't ask for the item himself ("give me", "hand me"), a GiveItem
becomes StoreItems (TASK_GOAL@STORE).

Usage: patch_round17d.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "chat_helper_functions.php"
s = f.read_text()
old = """    $actionUpper = stobeCanonicalizeActionCommand($actionUpper);
    $explicitAmount = stobeParseStructuredPositiveAmount($amount);

    $plannerKinds = ["""
new = """    $actionUpper = stobeCanonicalizeActionCommand($actionUpper);
    $explicitAmount = stobeParseStructuredPositiveAmount($amount);

    // "Put those back in storage": the model sometimes picks GiveItem -> player.
    if ($actionUpper === 'GIVE_ITEM' && $item !== '') {
        $playerLine = strtolower(strval($GLOBALS['STOBE_CURRENT_PLAYER_MESSAGE'] ?? ''));
        if ($playerLine !== ''
            && preg_match('/\\b(storage|chests?|stash|stockpile|put\\s+(?:\\w+\\s+){0,3}(?:away|back\\s+in)|store\\s+(?:it|them|those|these|that))\\b/', $playerLine) === 1
            && preg_match('/\\b(give|hand|pass|bring)\\s+(?:\\w+\\s+){0,3}(?:me|to\\s+me)\\b/', $playerLine) !== 1) {
            stobeLogInfo('GiveItem rewritten to StoreItems (player asked for storage)', ['item' => $item, 'target' => $target]);
            $actionUpper = 'STORE_ITEMS';
            $target = '';
        }
    }

    $plannerKinds = ["""
assert s.count(old) == 1, "anchor"
f.write_text(s.replace(old, new))
print("patched", f)
