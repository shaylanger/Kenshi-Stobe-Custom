#!/usr/bin/env python3
"""Item 100 option (b) (Shay 2026-10-03): reputation and relationship history follow the
character who is speaking / who made the deal, not the PLAYER_NAME persona ("shay").

- stobeNegApplyConsequences: the reputation row (lower-case key, item 50) and the NPC's
  relationship-map delta go to the deal's player_name (Beaks' deal -> "beaks", Shay's -> "shay").
- stobeNegDealPromptExtras: the deal/reputation lines name the deal's character, else the
  speaking character (STOBE_PLAYER_ACTOR), else the persona.
- stobeRelValue: the persona entry is only the fallback when nobody speaks (empty name).
- comments that still said "Shay's call (a)".
- regression checks in tests/negotiation_engine_regression.php and
  tests/relationship_trading_regression.php.

Usage: python3 item100b_reputation_follows_speaker.py <tree root>
Idempotent: a file that already carries the change is left alone.
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new, marker):
    p = root / rel
    s = p.read_text()
    if marker in s:
        print(f"skip (already applied): {rel}: {marker[:60]}")
        return
    if s.count(old) != 1:
        sys.exit(f"anchor not found exactly once in {rel}: {old[:80]!r} (count {s.count(old)})")
    p.write_text(s.replace(old, new))
    print(f"patched: {rel}: {marker[:60]}")


# ---------------------------------------------------------------- negotiation_engine.php: consequences
patch("lib/negotiation_engine.php",
"""        // Item 100 (Shay's call (a)): reputation and relationship history stay keyed by the PLAYER_NAME persona.
        // Only a player-squad character other than the persona is mapped (a deal made as Beaks counts for "shay").
        $persona = normalizeParticipantNameToken(strval(getSetting('PLAYER_NAME', '')));
        if ($persona === '' || strcasecmp($persona, $player) === 0 || !stobeNegIsPlayerSide($player, $persona)) $persona = $player;
""",
"""        // Item 100 (b), Shay 2026-10-03: reputation and relationship history follow the character the deal was
        // made with ($player = deal player_name, else PLAYER_NAME): Beaks' deal counts for "beaks", Shay's for "shay".
        $persona = $player;
""",
"// Item 100 (b), Shay 2026-10-03: reputation and relationship history follow")

patch("lib/negotiation_engine.php",
"[strtolower($persona)] /* item 50; Item 100: persona */",
"[strtolower($persona)] /* item 50: lower-case key; item 100 (b): the deal's character */",
"item 100 (b): the deal's character */")

# ---------------------------------------------------------------- negotiation_engine.php: prompt extras
patch("lib/negotiation_engine.php",
"""function stobeNegDealPromptExtras(string $npc, array $npcData, array $openDeal = []): string {
    $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
""",
"""function stobeNegDealPromptExtras(string $npc, array $npcData, array $openDeal = []): string {
    // Item 100 (b): the deal's character, else the speaking character, else the PLAYER_NAME persona.
    $player = normalizeParticipantNameToken(strval($openDeal['player_name'] ?? ''));
    if ($player === '' && function_exists('stobePlayerActorName')) $player = stobePlayerActorName();
    if ($player === '') $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
""",
"// Item 100 (b): the deal's character, else the speaking character, else the PLAYER_NAME persona.")

# ---------------------------------------------------------------- relationship_trading.php: r lookup
patch("lib/relationship_trading.php",
"""    $names = [normalizeParticipantNameToken($player)];
    if (function_exists('getSetting')) $names[] = normalizeParticipantNameToken(strval(getSetting('PLAYER_NAME', '')));
""",
"""    // Item 100 (b): the speaking character's own entry; the persona only when nobody speaks.
    $names = [normalizeParticipantNameToken($player)];
    if ($names[0] === '' && function_exists('getSetting')) $names[] = normalizeParticipantNameToken(strval(getSetting('PLAYER_NAME', '')));
""",
"// Item 100 (b): the speaking character's own entry; the persona only when nobody speaks.")

patch("lib/relationship_trading.php",
""" * system writes into the same map) by the character's name, else by the PLAYER_NAME persona (item 100: a squad
 * character's history is kept on the persona). No entry = 0.""",
""" * system writes into the same map) by the character's name (item 100 (b): each squad character has its own
 * history); the PLAYER_NAME persona only when no character is given. No entry = 0.""",
"item 100 (b): each squad character has its own")

# ---------------------------------------------------------------- comments
patch("lib/negotiation_phase1.php",
"return stobeRelValue($npcData, $player); // Item 102: character, else persona",
"return stobeRelValue($npcData, $player); // Item 102; item 100 (b): the speaking character's entry",
"item 100 (b): the speaking character's entry")

patch("lib/chat_helper_functions.php",
"/** Item 100: the PLAYER_NAME persona (reputation/relationship history key, Shay's call (a)). */",
"/** Item 100: the PLAYER_NAME persona (fallback when nobody speaks; item 100 (b): history follows the speaker). */",
"fallback when nobody speaks; item 100 (b)")

# ---------------------------------------------------------------- tests: negotiation_engine_regression.php
patch("tests/negotiation_engine_regression.php",
"""// GIVE_ITEM for the persona; "me" is the speaking character; deal actions target it; the reputation key stays the persona.""",
"""// GIVE_ITEM for the persona; "me" is the speaking character; deal actions target it; item 100 (b): reputation and
// relationship history follow the character (Shay 2026-10-03).""",
"// relationship history follow the character (Shay 2026-10-03).")

patch("tests/negotiation_engine_regression.php",
"""$beaksRep = $db->fetchOne("SELECT 1 AS x FROM stobe_negotiation_reputation WHERE player_name='negtestbeaks'");
check('item 100: reputation stays on the persona (no row for the character)', !$beaksRep);
""",
"""$beaksRep = $db->fetchOne("SELECT player_kept FROM stobe_negotiation_reputation WHERE player_name='negtestbeaks'");
check('item 100 (b): Beaks\\' deal lands on "negtestbeaks"', intval($beaksRep['player_kept'] ?? 0) === 1, $beaksRep);
$repP100after = intval($db->fetchOne("SELECT COALESCE(MAX(player_kept),0) AS k FROM stobe_negotiation_reputation WHERE player_name=LOWER($1)", [$player])['k'] ?? 0);
check('item 100 (b): the persona row is untouched by Beaks\\' deal', $repP100after === $repP100before, [$repP100before, $repP100after]);
$bandit100 = getNpcData('NegTestBandit');
$rels100 = is_array($bandit100) ? stobeGetNpcRelationshipMap($bandit100) : [];
$relKeys100 = array_map('strtolower', array_keys($rels100));
$relP100after = stobeRelationshipEntryFor(getNpcData('NegTestBandit'), $player)['aff'] ?? null;
check('item 100 (b): the NPC\\'s relationship delta goes to the Beaks entry, not the persona',
    in_array('negtestbeaks', $relKeys100, true) && $relP100after === $relP100before, [$relKeys100, $relP100before, $relP100after]);
// A broken deal by Beaks counts against "negtestbeaks"; the same by the persona (other casing) against the persona row.
$idB100 = makeDeal('NegTestBandit', [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>20]], 'social');
$db->exec("UPDATE stobe_social_contract SET player_name='NegTestBeaks' WHERE contract_id=$1", [$idB100]);
$dealB100 = stobeNegFetchDeal($idB100); $dealB100['status'] = 'BREACHED_PLAYER';
stobeNegApplyConsequences($dealB100, 'NegTestBeaks');
check('item 100 (b): Beaks\\' broken deal lands on "negtestbeaks"',
    intval($db->fetchOne("SELECT player_broken FROM stobe_negotiation_reputation WHERE player_name='negtestbeaks'")['player_broken'] ?? 0) === 1);
$brokenP0 = intval($db->fetchOne("SELECT COALESCE(MAX(player_broken),0) AS b FROM stobe_negotiation_reputation WHERE player_name=LOWER($1)", [$player])['b'] ?? 0);
$idS100 = makeDeal('NegTestBandit', [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>20]], 'social');
$dealS100 = stobeNegFetchDeal($idS100); $dealS100['status'] = 'BREACHED_PLAYER';
stobeNegApplyConsequences($dealS100, strtoupper($player));
check('item 100 (b): the persona\\'s broken deal (any casing) lands on the persona row',
    intval($db->fetchOne("SELECT COALESCE(MAX(player_broken),0) AS b FROM stobe_negotiation_reputation WHERE player_name=LOWER($1)", [$player])['b'] ?? 0) === $brokenP0 + 1);
check('item 100 (b): no upper-case duplicate row', !$db->fetchOne("SELECT 1 AS x FROM stobe_negotiation_reputation WHERE player_name<>LOWER(player_name) AND LOWER(player_name) IN ('negtestbeaks', LOWER($1))", [$player]));
// Prompt lines read the speaking character's reputation, not the persona's.
$db->exec("UPDATE stobe_negotiation_reputation SET player_kept=0, player_broken=3 WHERE player_name='negtestbeaks'");
$extras100 = stobeNegDealPromptExtras('NegTestBandit', getNpcData('NegTestBandit') ?: []);
check('item 100 (b): deal prompt reputation line names the speaking character', str_contains($extras100, 'NegTestBeaks has a reputation for breaking deals'), $extras100);
$GLOBALS['STOBE_PLAYER_ACTOR'] = $player; // the open deal's character wins over the speaker
$extrasDeal100 = stobeNegDealPromptExtras('NegTestBandit', getNpcData('NegTestBandit') ?: [], ['player_name'=>'NegTestBeaks', 'status'=>'PROPOSED']);
$GLOBALS['STOBE_PLAYER_ACTOR'] = 'NegTestBeaks';
check('item 100 (b): an open deal\\'s character names the line', str_contains($extrasDeal100, 'NegTestBeaks has a reputation'), $extrasDeal100);
// The stance block reads the speaker's own entry.
$stanceNpc100 = ['name'=>'NegTestBandit', 'extended_data'=>json_encode(['relationships'=>[
    $player=>['aff'=>80, 'type'=>'platonic'], 'NegTestBeaks'=>['aff'=>-60, 'type'=>'enemy']]])];
$stance100 = stobeBuildRelationshipStanceBlock('NegTestBandit', $stanceNpc100, 'NegTestBeaks', false);
check('item 100 (b): an NPC\\'s stance toward Beaks reads the Beaks entry', str_contains($stance100, '-60') && !str_contains($stance100, ' 80 of'), $stance100);
$db->exec("DELETE FROM stobe_social_contract WHERE contract_id IN ($1, $2)", [$idB100, $idS100]);
$db->exec("DELETE FROM stobe_negotiation_reputation WHERE player_name='negtestbeaks'");
""",
"item 100 (b): Beaks\\' deal lands on")

patch("tests/negotiation_engine_regression.php",
"""stobeLine("ACTION_EXEC: GIVE_CATS actor=NegTestBandit recipient=NegTestBeaks amount=20", time());
""",
"""$relP100before = stobeRelationshipEntryFor(getNpcData('NegTestBandit'), $player)['aff'] ?? null; // item 100 (b)
$repP100before = intval($db->fetchOne("SELECT COALESCE(MAX(player_kept),0) AS k FROM stobe_negotiation_reputation WHERE player_name=LOWER($1)", [$player])['k'] ?? 0);
stobeLine("ACTION_EXEC: GIVE_CATS actor=NegTestBandit recipient=NegTestBeaks amount=20", time());
""",
"$relP100before = stobeRelationshipEntryFor(")

# ---------------------------------------------------------------- tests: relationship_trading_regression.php
patch("tests/relationship_trading_regression.php",
"""check('r: a squad character falls back to the persona entry', stobeRelValue($npc(33), 'SomeSquadChar') === 33);
""",
"""check('r (item 100 b): a squad character without an entry reads 0, not the persona entry', stobeRelValue($npc(33), 'SomeSquadChar') === 0);
check('r (item 100 b): nobody speaking falls back to the persona entry', stobeRelValue($npc(33), '') === 33);
check('r: the persona entry is case-insensitive', stobeRelValue($npc(21), strtoupper($player)) === 21);
""",
"r (item 100 b): a squad character without an entry reads 0")
