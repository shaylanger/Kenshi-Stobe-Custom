#!/usr/bin/env python3
"""Round 11: bug 32. Malzin put her katana away for 10,000 Cats with no trust at all
(relationship had just been reset). Shay's rule (2026-09-30): an NPC gives up the
weapon she's using ONLY when (a) she's surrendering in a fight, or (b) she trusts the
player (relationship affinity >= setting NEG_WEAPON_TRUST_MIN, default 56 = "Fond").
A spare weapon doesn't count. Weapons in her pack can still be sold. Squad members
(player faction) are not affected.

Enforced in three places:
  1. Prompt: when the rule applies, she's told her weapon is not for sale.
  2. Deal capture: a term where she sells/gives/lends/unequips an equipped weapon is
     refused (error weapon_not_negotiable); chat.php replaces her line with a refusal.
  3. Any reply: UNEQUIP_ITEM/GIVE_ITEM actions on an equipped weapon are removed (logged).

Usage: patch_round11.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    t = p.read_text(encoding="utf-8")
    assert t.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(t.replace(old, new), encoding="utf-8")


P = "lib/negotiation_phase1.php"
patch(P,
      """function stobeDealSpeechClaimsCeasefire(string $text): bool {""",
      r"""// ---- Bug 32: an NPC's own weapon ----------------------------------------------------

/** Kenshi weapon names (equipped items only are checked, so food like "chewstick" never shows up). */
function stobeDealIsWeaponName(string $name): bool {
    return preg_match("/\b(katana|sabre|saber|sword|longsword|nodachi|wakizashi|machete|cleaver|blade|knife|dagger|jitte|club|mace|hammer|axe|plank|stick|tooth ?pick|polearm|naginata|halberd|spear|staff|horse chopper|falling sun|paladin'?s cross|topknot|bow|crossbow|eagle'?s cross|harpoon|weapon)\b/i", $name) === 1;
}

/** Weapons the NPC has equipped: [lower name => display name]. */
function stobeDealEquippedWeapons(array|false $npcData): array {
    if (!is_array($npcData) || !function_exists('stobeNegInventoryDisplayNames')) return [];
    $out = [];
    foreach (stobeNegInventoryDisplayNames(strval($npcData['equipment'] ?? '')) as $lower => $display) {
        if (stobeDealIsWeaponName($lower)) $out[$lower] = $display;
    }
    return $out;
}

/** The NPC's affinity toward the player, or 0 if they have no relationship. */
function stobeDealNpcTrust(array|false $npcData, string $player): int {
    if (!is_array($npcData) || !function_exists('stobeGetNpcRelationshipMap')) return 0;
    foreach (stobeGetNpcRelationshipMap($npcData) as $target => $entry) {
        if (strcasecmp(normalizeParticipantNameToken(strval($target)), normalizeParticipantNameToken($player)) === 0) {
            return intval(is_array($entry) ? ($entry['aff'] ?? 0) : 0);
        }
    }
    return 0;
}

/** May she give up the weapon she's using? Only when surrendering, or trusting the player. */
function stobeDealWeaponReleaseAllowed(array|false $npcData, string $player, string $kind): bool {
    if (!is_array($npcData)) return true;
    if (function_exists('npcIsInPlayerFaction') && npcIsInPlayerFaction($npcData)) return true;
    if ($kind === 'surrender') return true;
    $minTrust = function_exists('getSettingInt') ? getSettingInt('NEG_WEAPON_TRUST_MIN', 56) : 56;
    return stobeDealNpcTrust($npcData, $player) >= $minTrust;
}

/** The equipped weapon an item name refers to ("Chisa Katana [Ancient]", "katana", "your blade"), or ''. */
function stobeDealMatchEquippedWeapon(string $item, array $weapons): string {
    $t = strtolower(trim(preg_replace('/\s*\[[^\]]*\]|\s*\([^)]*\)/', '', $item) ?? ''));
    if ($t === '' || count($weapons) === 0) return '';
    foreach ($weapons as $lower => $display) {
        if ($t === $lower || str_contains($lower, $t) || str_contains($t, $lower)) return $display;
    }
    // A generic word ("weapon", "blade", "sword") means the one she's holding.
    if (preg_match('/\b(weapon|blade|sword)\b/', $t)) return reset($weapons);
    return '';
}

/** Name of an equipped weapon the NPC would give up under these terms, or ''. */
function stobeDealTermsGiveUpWeapon(array $terms, array|false $npcData): string {
    $weapons = stobeDealEquippedWeapons($npcData);
    if (count($weapons) === 0) return '';
    foreach ($terms as $t) {
        if (!is_array($t) || ($t['by'] ?? '') !== 'npc') continue;
        if (!in_array(strtoupper(strval($t['kind'] ?? '')), ['UNEQUIP_ITEM','GIVE_ITEM','LOAN_ITEM'], true)) continue;
        $hit = stobeDealMatchEquippedWeapon(strval($t['item'] ?? ''), $weapons);
        if ($hit !== '') return $hit;
    }
    return '';
}

/** Remove UNEQUIP_ITEM/GIVE_ITEM actions on her equipped weapon unless allowed. Returns [actions, removed]. */
function stobeDealFilterWeaponActions(array $actions, array|false $npcData, string $player, string $kind): array {
    $weapons = stobeDealEquippedWeapons($npcData);
    if (count($weapons) === 0 || stobeDealWeaponReleaseAllowed($npcData, $player, $kind)) return [$actions, []];
    $kept = [];
    $removed = [];
    foreach ($actions as $action) {
        $a = strval($action);
        $item = '';
        if (preg_match('/^UNEQUIP_ITEM@(.+)$/i', $a, $m)) $item = $m[1];
        elseif (preg_match('/^GIVE_ITEM@[^@]*@([^@]+)/i', $a, $m)) $item = $m[1];
        if ($item !== '' && stobeDealMatchEquippedWeapon($item, $weapons) !== '') { $removed[] = $a; continue; }
        $kept[] = $action;
    }
    return [$kept, $removed];
}

/** Prompt line when the rule applies to her, else ''. */
function stobeDealWeaponPromptLine(array|false $npcData, string $player, string $kind): string {
    $weapons = stobeDealEquippedWeapons($npcData);
    if (count($weapons) === 0 || stobeDealWeaponReleaseAllowed($npcData, $player, $kind)) return '';
    return 'In Kenshi your weapon is your life. Your ' . implode(' and ', array_values($weapons))
        . ' is not for sale: never sell, hand over, lend, put away or drop it for Cats or favours, whatever the price. '
        . $player . ' is not someone you trust that much. Refuse such offers, and never list it in deal_terms.';
}

function stobeDealSpeechClaimsCeasefire(string $text): bool {""")

patch(P,
      """    $deal = [
        'parties'=>['npc'=>$npc,'player'=>$player],""",
      """    // Bug 32: her own weapon only goes when she's surrendering or trusts the player.
    $weaponGiven = stobeDealTermsGiveUpWeapon($terms, $npcData);
    if ($weaponGiven !== '' && !stobeDealWeaponReleaseAllowed($npcData, $player, $kind)) {
        stobeDealLog('warn', 'Negotiation rejected: NPC would give up her weapon (not surrendering, not trusted)', [
            'npc'=>$npc, 'decision'=>$decision, 'weapon'=>$weaponGiven, 'kind'=>$kind,
            'trust'=>stobeDealNpcTrust($npcData, $player),
        ]);
        return ['ok'=>false, 'error'=>'weapon_not_negotiable', 'weapon'=>$weaponGiven,
            'refusal_line'=>'Not my ' . $weaponGiven . '. That stays with me, whatever you pay.'];
    }
    $deal = [
        'parties'=>['npc'=>$npc,'player'=>$player],""")

patch("lib/negotiation_engine.php",
      """    if ($rep !== '') $lines[] = $rep;""",
      """    if ($rep !== '') $lines[] = $rep;
    if (function_exists('stobeDealWeaponPromptLine')) {
        $weaponLine = stobeDealWeaponPromptLine($npcData, $player, count($openDeal) > 0 ? strval($openDeal['kind'] ?? '') : stobeDealKindFor($npcData));
        if ($weaponLine !== '') $lines[] = $weaponLine;
    }""")

C = "processor/chat.php"
patch(C,
      """                // Malformed terms: record nothing, but keep the NPC's own words unless they claim a deal.
                if (stobeDealSpeechClaimsCeasefire($responseText)""",
      """                // Malformed terms: record nothing, but keep the NPC's own words unless they claim a deal.
                if (strval($dealResult['error'] ?? '') === 'weapon_not_negotiable') {
                    // Bug 32: whatever she said, her weapon isn't part of the deal.
                    $responseText = strval($dealResult['refusal_line'] ?? 'My weapon stays with me.');
                } elseif (stobeDealSpeechClaimsCeasefire($responseText)""")

patch(C,
      """// An NPC attacking the player over a private matter keeps it one-on-one.""",
      """// Bug 32: an NPC doesn't give up the weapon she's using unless she's surrendering or trusts the player.
if (!$narratorMode && is_array($npcData) && function_exists('stobeDealFilterWeaponActions')) {
    [$responseActions, $weaponActionsRemoved] = stobeDealFilterWeaponActions(
        $responseActions, $npcData, $playerName, strval($dealResult['kind'] ?? ($negotiationKind ?? ''))
    );
    if (count($weaponActionsRemoved) > 0) {
        stobeLogWarn('Weapon hand-over blocked (not surrendering, not trusted)', [
            'npc'=>$targetNpc, 'removed'=>$weaponActionsRemoved, 'text'=>$responseText,
        ]);
    }
}
// An NPC attacking the player over a private matter keeps it one-on-one.""")

print("patch_round11: applied")
