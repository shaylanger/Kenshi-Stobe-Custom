#!/usr/bin/env python3
"""Bug 116: a paid ceasefire broken by a gang-mate's idle chatter.

Run 9 (test 55): Shay paid Ulan 300 cats to stop; the deal went COMPLETE
(STOP_ATTACK verified). 80 s later his gang-mate Falt, in an idle chat with
Skovrek ("Shay's still on his feet and swinging... You with me or not?"),
got action Attack -> ATTACK@Shay, which broke the truce and the gang
attacked again. The bug 90 guard only covers the chat path and only the
NPC who made the deal.

Guard in streamResponse (all paths): drop ATTACK@<player side> from an NPC
whose faction has a COMPLETE combat/surrender deal in the last 10 minutes,
unless the player side attacked that NPC in the last 60 s.

Usage: patch_r21_bug116_ceasefire_attack_guard.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
p1 = root / 'lib' / 'negotiation_phase1.php'
t1 = p1.read_text(encoding='utf-8')
helper_anchor = "function stobeDealRecentCompletedCeasefire(string $npc, int $seconds = 600): ?array {\n"
helper = r"""/**
 * Bug 116: a paid ceasefire covers the NPC's whole faction for 10 minutes.
 * True when $action is ATTACK on the player side and must be dropped.
 */
function stobeNegCeasefireBlocksAttack(string $npc, string $action): bool {
    if (!preg_match('/^ATTACK@([^@]+)(?:@help)?$/i', trim($action), $m)) return false;
    try {
        $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
        $target = normalizeParticipantNameToken(trim($m[1]));
        if (!function_exists('stobeNegIsPlayerSide') || !stobeNegIsPlayerSide($target, $player)) return false;
        $me = $GLOBALS['db']->fetchOne("SELECT faction FROM core_npc_master WHERE LOWER(name)=LOWER($1) LIMIT 1", [$npc]);
        $faction = trim(strval($me['faction'] ?? ''));
        $deal = $faction === '' ? stobeDealRecentCompletedCeasefire($npc) : $GLOBALS['db']->fetchOne(
            "SELECT c.contract_id FROM stobe_social_contract c JOIN core_npc_master m ON LOWER(m.name)=LOWER(c.npc_name)
              WHERE c.kind IN ('combat','surrender') AND c.status='COMPLETE'
                AND c.updated_at > NOW() - interval '600 seconds' AND LOWER(m.faction)=LOWER($1)
              ORDER BY c.updated_at DESC LIMIT 1",
            [$faction]
        );
        if (!is_array($deal)) return false;
        if (function_exists('stobeNegCombatEvents')) {
            foreach (stobeNegCombatEvents(time() - 60, $npc) as $ev) {
                if (stobeNegCharMatches($ev['target'], $npc) && stobeNegIsPlayerSide($ev['attacker'], $player)) return false;
            }
        }
        stobeLogInfo('Attack on the player dropped: paid ceasefire stands (bug 116)',
            ['npc'=>$npc, 'action'=>$action, 'faction'=>$faction, 'contract_id'=>$deal['contract_id'] ?? '']);
        return true;
    } catch (Throwable $e) {
        return false;
    }
}

"""
if 'function stobeNegCeasefireBlocksAttack' not in t1:
    assert t1.count(helper_anchor) == 1, 'helper anchor'
    t1 = t1.replace(helper_anchor, helper + helper_anchor)
    p1.write_text(t1, encoding='utf-8', newline='')
    print('patched', p1)
else:
    print('already patched', p1)

p2 = root / 'lib' / 'chat_helper_functions.php'
t2 = p2.read_text(encoding='utf-8')
anchor = """        $structuredAction = trim(strval($structuredFromMessage['action_tag'] ?? ''));
        if ($structuredAction !== '' && !in_array($structuredAction, $actions, true)) {
            array_unshift($actions, $structuredAction);
        }
    }
"""
add = """    if (count($actions) > 0 && function_exists('stobeNegCeasefireBlocksAttack')) { // bug 116
        $actions = array_values(array_filter($actions, static fn($a) => !stobeNegCeasefireBlocksAttack($actor, strval($a))));
    }
"""
if 'stobeNegCeasefireBlocksAttack($actor' not in t2:
    assert t2.count(anchor) >= 1, 'stream anchor'
    i = t2.index("function streamResponse(")
    j = t2.index(anchor, i) + len(anchor)
    t2 = t2[:j] + add + t2[j:]
    p2.write_text(t2, encoding='utf-8', newline='')
    print('patched', p2)
else:
    print('already patched', p2)
