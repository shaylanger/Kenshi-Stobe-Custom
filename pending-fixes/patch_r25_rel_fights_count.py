#!/usr/bin/env python3
"""Relationship fix R4: a fight never changed a relationship.

Run 12: Malzin fought Vren; afterwards Vren said something friendly and the evaluator
(which only runs when someone speaks, and sees one line) gave +6 "No hard feelings
after the fight" -> Acquaintance. Combat events were not evaluated at all.
Now every "A: Initiated attack (talking to: B)" event lowers B's feeling for A by 10
("attacked me") and A's for B by 4 ("fought them"), once per pair per 15 minutes,
for named characters only (generic template names are skipped, R3).
Hook: stobeNegTickThrottled (the game-event path that already sees combat).
Switch: RELATIONSHIP_FIGHTS_COUNT (default on).

Usage: patch_r25_rel_fights_count.py <StobeServer tree>  (idempotent; after R1-R3)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
f = root / 'lib/chat_helper_functions.php'
s = f.read_text(encoding='utf-8')
if 'function stobeRelationshipOnAttack(' not in s:
    FUNC = r'''/** R4: an attack lowers both sides' feelings (once per pair per 15 min). Returns the changes made. */
function stobeRelationshipOnAttack(string $eventData, ?int $now = null): array {
    if (function_exists('getSettingBool') && !getSettingBool('RELATIONSHIP_FIGHTS_COUNT', true)) return [];
    if (!preg_match('/^(.+?):\s*Initiated attack\s*\(talking to:\s*(.+?)\)/', trim($eventData), $m)) return [];
    $attacker = normalizeParticipantNameToken($m[1]);
    $victim = normalizeParticipantNameToken($m[2]);
    if ($attacker === '' || $victim === '' || strcasecmp($attacker, $victim) === 0) return [];
    if (stobeIsGenericNpcName($attacker) || stobeIsGenericNpcName($victim)) return [];
    $now = $now ?? time();
    $pairKey = 'STOBE_REL_FIGHT_' . md5(strtolower($attacker) . '|' . strtolower($victim));
    $last = intval(function_exists('getConfOpt') ? getConfOpt($pairKey, '0') : 0);
    if ($last > 0 && $now - $last < 900) return [];
    if (function_exists('setConfOpt')) setConfOpt($pairKey, strval($now));
    $done = [];
    foreach ([[$victim, $attacker, -10, 'attacked me'], [$attacker, $victim, -4, 'fought them']] as [$who, $target, $delta, $note]) {
        $data = getNpcData($who);
        if (!is_array($data)) continue; // the player has no relationship map of her own
        $map = stobeGetNpcRelationshipMap($data);
        $r = stobeApplyRelationshipUpdatesMap($map, [['target' => $target, 'aff_delta' => $delta, 'note' => $note]]);
        if (($r['updated'] ?? 0) > 0 && stobePersistNpcRelationshipMap($who, $r['map'], $data)) {
            $done[] = ['who' => $who, 'target' => $target, 'delta' => $delta];
        }
    }
    if (count($done) > 0 && function_exists('stobeLogInfo')) stobeLogInfo('Relationship: a fight counts (R4)', ['changes' => $done]);
    return $done;
}

'''
    anchor = "function stobeApplyRelationshipUpdatesMap(array $relationshipMap, array $updates, array $allowedTargets = []): array {"
    assert s.count(anchor) == 1
    s = s.replace(anchor, FUNC + anchor)
    f.write_text(s, encoding='utf-8'); print('patched', f)
else:
    print('already patched', f)

g = root / 'lib/negotiation_engine.php'
gs = g.read_text(encoding='utf-8')
if 'stobeRelationshipOnAttack(' not in gs:
    old = """    if ($type === 'combat') {
        try { stobeNegPersonalFightJoiner($eventData); } catch (Throwable $e) {}
    }"""
    assert gs.count(old) == 1, 'hook anchor'
    gs = gs.replace(old, """    if ($type === 'combat') {
        try { stobeNegPersonalFightJoiner($eventData); } catch (Throwable $e) {}
        if (function_exists('stobeRelationshipOnAttack')) {
            try { stobeRelationshipOnAttack($eventData); } catch (Throwable $e) {} // R4: fights count
        }
    }""")
    g.write_text(gs, encoding='utf-8'); print('patched', g)

t = root / 'tests/relationship_stance_regression.php'
ts = t.read_text(encoding='utf-8')
if 'R4:' not in ts:
    anchor = 'echo "\\n$pass passed, $fail failed\\n";'
    ts = ts.replace(anchor, r'''// R4: a fight counts
$GLOBALS['db']->exec("DELETE FROM core_npc_master WHERE name IN ('Ann4 [Rel4]','Bob4 [Rel4]')");
$GLOBALS['db']->exec("INSERT INTO core_npc_master (name, extended_data) VALUES ('Ann4 [Rel4]', '{}'::jsonb), ('Bob4 [Rel4]', '{}'::jsonb)");
$GLOBALS['db']->exec("DELETE FROM conf_opts WHERE id LIKE 'STOBE_REL_FIGHT_%'");
$r4 = stobeRelationshipOnAttack('Ann4 [Rel4]: Initiated attack (talking to: Bob4 [Rel4])', 1000000);
$bob = stobeRelationshipEntryFor(getNpcData('Bob4 [Rel4]'), 'Ann4 [Rel4]');
$ann = stobeRelationshipEntryFor(getNpcData('Ann4 [Rel4]'), 'Bob4 [Rel4]');
check('R4: the victim likes the attacker 10 less, the attacker the victim 4 less', intval($bob['aff'] ?? 0) === -10 && intval($ann['aff'] ?? 0) === -4, [$r4, $bob, $ann]);
$again = stobeRelationshipOnAttack('Ann4 [Rel4]: Initiated attack (talking to: Bob4 [Rel4])', 1000100);
check('R4: once per pair per 15 min', $again === []);
check('R4: generic names are skipped', stobeRelationshipOnAttack('Rel4: Initiated attack (talking to: Bob4 [Rel4])', 1000200) === []);
$GLOBALS['db']->exec("DELETE FROM core_npc_master WHERE name IN ('Ann4 [Rel4]','Bob4 [Rel4]')");
''' + anchor)
    t.write_text(ts, encoding='utf-8'); print('patched tests')
