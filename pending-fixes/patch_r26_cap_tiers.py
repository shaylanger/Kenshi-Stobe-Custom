#!/usr/bin/env python3
"""Deal-offer cap tiers (plan section E, Shay 2026-10-02; also item 53).

The most an NPC offers to pay the player in a fight deal (combat / surrender / assist):
  tier 0 Destitute 100, 1 Common 300, 2 Professional 5,000, 3 Elite/officer 10,000,
  4 Local leaders 50,000, 5 Rulers 100,000.
Tier by template name / title, then by bounty (>= 10k / 30k / 100k -> 3 / 4 / 5).
- "Carried" uses the template's money (data/npc_wealth_templates.json, from the wealth
  survey): min(real purse, template max); unknown purse -> template middle. The real purse
  often is the squad's shared purse (spawned raiders showed 10,000).
- The 35 %-of-carried rule is gone: tiers 0-2 offer up to what they carry (<= tier cap);
  their payment is exact (all or nothing, "@exact").
- Tiers 3-5 can offer up to the tier cap; above what they carry, the purse is topped up
  just before paying ("@topup"), at most one top-up deal per NPC per 3 game days.
- The purse suffix is sent only with setting NEG_CATS_PURSE_MODES on (Stobe.dll with the
  modes installed); the action normalizer keeps a trailing @topup/@exact.
- Item 53: her prompt names her limit and tells her not to claim she's broke.

Usage: patch_r26_cap_tiers.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])


def patch(rel, marker, pairs):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', f)
        return
    for old, new in pairs:
        assert s.count(old) == 1, f'{rel}: anchor not unique/missing: {old[:70]!r}'
        s = s.replace(old, new)
    assert marker in s, f'{rel}: marker missing after patch'
    f.write_text(s, encoding='utf-8')
    print('patched', f)


OLD_CAP = '''/**
 * Bug 91: most Cats an NPC offers to be spared / for help. Common bandits
 * 50-300, leaders/bosses up to ~1000, wealthy NPCs scaled to their purse;
 * never more than 35 % of what they carry (Shay, 2026-10-01).
 * Returns [cap, carried, tier].
 */
function stobeNegOfferCap(string $npc, array $npcData): array {
    $meta = function_exists('normalizeNpcMetadataPayload')
        ? normalizeNpcMetadataPayload($npcData['metadata'] ?? []) : (is_array($npcData['metadata'] ?? null) ? $npcData['metadata'] : []);
    $carried = max(0, intval($meta['money'] ?? ($npcData['money'] ?? 0)));
    $who = strtolower($npc . ' ' . strval($npcData['faction'] ?? '') . ' ' . strval($meta['faction'] ?? '') . ' ' . strval($meta['title'] ?? ''));
    if (preg_match('/\\b(traders?|merchants?|caravans?|nobles?|lords?|lady|shopkeepers?|barman|bartenders?|innkeepers?)\\b/', $who)) {
        $tier = 'wealthy'; $tierCap = PHP_INT_MAX;
    } elseif (preg_match('/\\b(leaders?|boss|king|queen|chief|captain|warlord|commander|elder)\\b/', $who)) {
        $tier = 'leader'; $tierCap = 1000;
    } else {
        $tier = 'common'; $tierCap = 300;
    }
    $cap = min($tierCap, intval(floor($carried * 0.35)));
    return [max(0, $cap), $carried, $tier];
}
'''

NEW_CAP = r'''// ---- Deal-offer cap tiers (Shay, 2026-10-02) ---------------------------------------

const STOBE_NEG_TIER_CAPS = [0=>100, 1=>300, 2=>5000, 3=>10000, 4=>50000, 5=>100000];
const STOBE_NEG_TIER_LABELS = [0=>'destitute', 1=>'common', 2=>'professional', 3=>'elite', 4=>'local leader', 5=>'ruler'];
const STOBE_NEG_TOPUP_COOLDOWN_GAMETS = 259200; // one top-up deal per NPC per 3 game days

/** Template wealth from the survey: lower template name => [cats_min, cats_max, bounty]. */
function stobeNegWealthTemplates(): array {
    static $table = null;
    if ($table === null) {
        $raw = @file_get_contents(dirname(__DIR__) . '/data/npc_wealth_templates.json');
        $table = is_string($raw) ? (json_decode($raw, true) ?: []) : [];
    }
    return $table;
}

/**
 * The NPC's wealth tier: ['tier'=>0..5, 'label', 'cap', 'template', 'tmin', 'tmax' (null = unknown), 'bounty'].
 * Template = the bracketed part of "Vorl [Dust Bandit Bowman]", else the name.
 */
function stobeNegWealthTier(string $npc, array $npcData): array {
    $name = trim($npc);
    $template = preg_match('/\[\s*([^\]]+?)\s*\]\s*$/', $name, $m) ? $m[1] : $name;
    $key = strtolower(preg_replace('/\s+/', ' ', $template) ?? $template);
    $row = stobeNegWealthTemplates()[$key] ?? null;
    $bounty = max(intval($npcData['bounty'] ?? 0), is_array($row) ? intval($row[2] ?? 0) : 0);
    $who = strtolower($template . ' | ' . $name);
    if (preg_match('/\b(holy lord|phoenix|emperor tengu|tengu|bugmaster)\b/', $who)) $tier = 5;
    elseif (preg_match('/\b(lords?|lady|nobles?|nobleman|noblewoman|market master|slave master|high inquisitor|shogun|emperor|king|queen)\b/', $who)) $tier = 4;
    elseif (preg_match('/\b(high paladin|paladin elite|samurai elite|samurai sergeant|inquisitor captain|inquisitor|trader boss|mercenary captain)\b/', $who)) $tier = 3;
    elseif (preg_match('/\b(samurai|paladins?|holy sentinel|sentinels?|shek|mercenar(?:y|ies)|caravan guard|barman|bartender|bar owner|barkeep|shopkeeper|traders?|merchants?|innkeeper|captain)\b/', $who)) $tier = 2;
    elseif (preg_match('/\b(hungry|starving|slaves?|savage|beggars?|vagrants?)\b/', $who)) $tier = 0;
    else $tier = 1;
    if ($bounty >= 100000) $tier = max($tier, 5);
    elseif ($bounty >= 30000) $tier = max($tier, 4);
    elseif ($bounty >= 10000) $tier = max($tier, 3);
    return ['tier'=>$tier, 'label'=>STOBE_NEG_TIER_LABELS[$tier], 'cap'=>STOBE_NEG_TIER_CAPS[$tier], 'template'=>$template,
        'tmin'=>is_array($row) ? intval($row[0]) : null, 'tmax'=>is_array($row) ? intval($row[1]) : null, 'bounty'=>$bounty];
}

/** A top-up deal (tiers 3-5) with this NPC in the last 3 game days (1 h real when no game time is known). */
function stobeNegTopupOnCooldown(string $npc): bool {
    $base = preg_match('/\[\s*(.+?)\s*\]$/', trim($npc), $bm) ? $bm[1] : trim($npc);
    try {
        $rows = $GLOBALS['db']->fetchAll(
            "SELECT terms, EXTRACT(EPOCH FROM (NOW() - updated_at))::bigint AS age FROM stobe_social_contract
              WHERE LOWER(npc_name) IN (LOWER($1), LOWER($2)) AND status IN ('ACCEPTED','AWAITING_PERFORMANCE','COMPLETE')
                AND terms::text ILIKE '%topup%' ORDER BY updated_at DESC LIMIT 10",
            [trim($npc), $base]
        );
    } catch (Throwable $e) {
        return false;
    }
    $now = function_exists('stobeNegLatestGamets') ? stobeNegLatestGamets() : 0;
    foreach (is_array($rows) ? $rows : [] as $row) {
        $terms = json_decode(strval($row['terms'] ?? '[]'), true);
        foreach (is_array($terms) ? $terms : [] as $t) {
            if (!is_array($t) || ($t['purse'] ?? '') !== 'topup') continue;
            $at = intval($t['topup_gamets'] ?? 0);
            if ($now > 0 && $at > 0) {
                if ($at <= $now && $now - $at < STOBE_NEG_TOPUP_COOLDOWN_GAMETS) return true;
            } elseif (intval($row['age'] ?? 0) < 3600) {
                return true;
            }
        }
    }
    return false;
}

/**
 * Most Cats an NPC offers the player in a fight deal (cap tiers). Tiers 0-2: what she
 * carries, at most the tier cap. Tiers 3-5: the tier cap; the purse is topped up when
 * she carries less (unless she had a top-up deal in the last 3 game days).
 * Carried = min(real purse, template max); unknown purse -> template middle.
 * Returns [cap, carried, tier label, topup allowed].
 */
function stobeNegOfferCap(string $npc, array $npcData): array {
    $meta = function_exists('normalizeNpcMetadataPayload')
        ? normalizeNpcMetadataPayload($npcData['metadata'] ?? []) : (is_array($npcData['metadata'] ?? null) ? $npcData['metadata'] : []);
    $w = stobeNegWealthTier($npc, $npcData);
    $purseKnown = array_key_exists('money', $meta) || array_key_exists('money', $npcData);
    $purse = max(0, intval($meta['money'] ?? ($npcData['money'] ?? 0)));
    if ($w['tmax'] !== null) {
        $carried = $purseKnown ? min($purse, intval($w['tmax'])) : intdiv(intval($w['tmin']) + intval($w['tmax']), 2);
    } else {
        $carried = $purse;
    }
    $topup = $w['tier'] >= 3 && !stobeNegTopupOnCooldown($npc);
    $cap = $topup ? $w['cap'] : min($w['cap'], $carried);
    return [max(0, $cap), $carried, $w['label'], $topup];
}
'''

OLD_CAPTURE = '''    if (in_array($kind, ['surrender','assist'], true)) {
        [$offerCap, $offerCarried, $offerTier] = stobeNegOfferCap($npc, $npcData);'''
NEW_CAPTURE = '''    if (in_array($kind, ['surrender','assist','combat'], true)) {
        [$offerCap, $offerCarried, $offerTier, $offerTopup] = stobeNegOfferCap($npc, $npcData) + [3=>false];'''

OLD_MARK = '''        $terms = array_values($terms);
        if ($capped !== null && $decision === 'ACCEPT') {'''
NEW_MARK = '''        $terms = array_values($terms);
        // Cap tiers: tiers 3-5 have the rest brought (top-up); tiers 0-2 pay exactly or not at all.
        foreach ($terms as $ti => $term) {
            if (($term['kind'] ?? '') !== 'GIVE_CATS' || ($term['by'] ?? '') !== 'npc') continue;
            if ($offerTopup && intval($term['amount'] ?? 0) > $offerCarried) {
                $terms[$ti]['purse'] = 'topup';
                $terms[$ti]['topup_gamets'] = function_exists('stobeNegLatestGamets') ? stobeNegLatestGamets() : 0;
            } else {
                $terms[$ti]['purse'] = 'exact';
            }
        }
        if ($capped !== null && $decision === 'ACCEPT') {'''

patch('lib/negotiation_phase1.php', 'const STOBE_NEG_TIER_CAPS', [
    (OLD_CAP, NEW_CAP), (OLD_CAPTURE, NEW_CAPTURE), (OLD_MARK, NEW_MARK),
])

OLD_TOKEN = "        'GIVE_CATS' => 'GIVE_CATS@' . $player . '@' . max(1, intval($term['amount'] ?? 0)),\n        'GIVE_ITEM', 'RETURN_ITEM', 'LOAN_ITEM' =>"
NEW_TOKEN = ("        'GIVE_CATS' => 'GIVE_CATS@' . $player . '@' . max(1, intval($term['amount'] ?? 0))\n"
             "            . (in_array(strval($term['purse'] ?? ''), ['topup','exact'], true) && getSettingBool('NEG_CATS_PURSE_MODES', false)\n"
             "                ? '@' . strval($term['purse']) : ''), // cap tiers: Stobe.dll tops up / pays exactly\n"
             "        'GIVE_ITEM', 'RETURN_ITEM', 'LOAN_ITEM' =>")

OLD_PURSE = "    if ($money['known']) $lines[] = 'Your purse: ' . $money['value'] . ' Cats (you cannot promise more than you have).';"
NEW_PURSE = '''    if (function_exists('stobeNegOfferCap')) {
        // Cap tiers / item 53: her real limit, and no "I'm broke" when she has money.
        [$capNow, $carriedNow, , $topupNow] = stobeNegOfferCap($npc, $npcData) + [3=>false];
        $lines[] = $topupNow
            ? 'You carry about ' . $carriedNow . ' Cats, but you can have more brought: the most you will pay in a deal is ' . $capNow . ' Cats.'
            : ($capNow > 0
                ? 'You carry about ' . $carriedNow . ' Cats; the most you will pay in a deal is ' . $capNow . ' Cats. Asked for more, refuse or offer ' . $capNow . ' at most; do not claim you have no money.'
                : 'You have no Cats to pay with: offer an item or something else instead.');
    } elseif ($money['known']) {
        $lines[] = 'Your purse: ' . $money['value'] . ' Cats (you cannot promise more than you have).';
    }'''

OLD_OFFERLINE = '''            [$offerCap, $offerCarried] = function_exists('stobeNegOfferCap') ? stobeNegOfferCap($name, $data) : [0, 0];
            $offerLine = $offerCap > 0
                ? 'You carry about ' . $offerCarried . ' Cats; if you offer Cats, offer at most ' . $offerCap . ' (keep it modest). \''''
NEW_OFFERLINE = '''            [$offerCap, $offerCarried, , $offerTopup] = (function_exists('stobeNegOfferCap') ? stobeNegOfferCap($name, $data) : [0, 0]) + [3=>false];
            $offerLine = $offerTopup
                ? 'You carry about ' . $offerCarried . ' Cats but can have more brought; if you offer Cats, offer at most ' . $offerCap . '. '
                : ($offerCap > 0
                ? 'You carry about ' . $offerCarried . ' Cats; if you offer Cats, offer at most ' . $offerCap . ' (keep it modest). \''''

patch('lib/negotiation_engine.php', "getSettingBool('NEG_CATS_PURSE_MODES', false)", [
    (OLD_TOKEN, NEW_TOKEN), (OLD_PURSE, NEW_PURSE), (OLD_OFFERLINE, NEW_OFFERLINE),
    ("                : 'You have next to no Cats: offer an item, information or just beg - do not offer Cats. ';",
     "                : 'You have next to no Cats: offer an item, information or just beg - do not offer Cats. ');"),
])

OLD_NORM = '''    if ($command === 'GIVE_CATS' || $command === 'TAKE_CATS') {
        $segments = $splitActionSegments($argument);
        if (count($segments) === 0) {
            return '';
        }'''
NEW_NORM = '''    if ($command === 'GIVE_CATS' || $command === 'TAKE_CATS') {
        $segments = $splitActionSegments($argument);
        if (count($segments) === 0) {
            return '';
        }
        // Cap tiers: a trailing purse mode (GIVE_CATS@Shay@500@topup) is kept for Stobe.dll.
        $purseMode = '';
        if ($command === 'GIVE_CATS' && count($segments) >= 2
            && in_array(strtolower(trim(strval($segments[count($segments) - 1]))), ['topup', 'exact'], true)) {
            $purseMode = '@' . strtolower(trim(strval(array_pop($segments))));
        }'''
OLD_NORM_RET = '''        if ($targetName !== '') {
            return $command . '@' . $targetName . '@' . strval($amount);
        }
        return $command . '@' . strval($amount);
    }

    if ($command === 'TAKE_ITEM' || $command === 'GIVE_ITEM') {'''
NEW_NORM_RET = '''        if ($targetName !== '') {
            return $command . '@' . $targetName . '@' . strval($amount) . $purseMode;
        }
        return $command . '@' . strval($amount) . $purseMode;
    }

    if ($command === 'TAKE_ITEM' || $command === 'GIVE_ITEM') {'''

patch('lib/chat_helper_functions.php', 'a trailing purse mode (GIVE_CATS@Shay@500@topup)', [
    (OLD_NORM, NEW_NORM), (OLD_NORM_RET, NEW_NORM_RET),
])
