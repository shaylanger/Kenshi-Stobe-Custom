#!/usr/bin/env python3
"""Round 9: a new deal while another is underway (Shay's decision, 2026-09-30).

  - Nothing done yet on the open deal: the new deal replaces it (unchanged).
  - Underway (a term already carried out or part-paid, something still owed, either side):
    the NPC asks for it to be finished first. The prompt says what's still owed. If the
    model agrees to a clearly different deal anyway, the ledger keeps the old deal and the
    reply is replaced with a fixed line naming what's owed; deal actions are dropped.
  - Restating the same deal with other wording ("Iron Hat" vs "Iron Hat [Shoddy]") is
    still the same deal.

Usage: patch_round9.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor found {text.count(old)}x: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


# helpers (negotiation_phase1.php) ------------------------------------------
patch("lib/negotiation_phase1.php",
      "/** True while no term of this deal has been carried out or sent to the game. */",
      r'''/** What each side still has to do on a deal, as short phrases in the NPC's voice. */
function stobeDealOutstanding(array $deal): array {
    $state = $deal['term_state'] ?? [];
    if (is_string($state)) $state = json_decode($state, true);
    $done = ['VERIFIED','RECORDED','IMPOSSIBLE','UNMET','BETRAYED'];
    $out = ['npc'=>[], 'player'=>[]];
    foreach (is_array($state) ? $state : [] as $t) {
        if (!is_array($t) || in_array(strval($t['status'] ?? ''), $done, true)) continue;
        $by = ($t['by'] ?? '') === 'npc' ? 'npc' : 'player';
        $kind = strtoupper(strval($t['kind'] ?? ''));
        $item = trim(preg_replace('/\s*\[[^\]]*\]/', '', strval($t['item'] ?? '')) ?? '');
        $the = $item !== '' ? 'the ' . $item : 'it';
        if ($kind === 'GIVE_CATS') {
            $left = max(0, intval($t['amount'] ?? 0) - intval($t['paid_so_far'] ?? 0));
            if ($left > 0) $out[$by][] = ($by === 'npc' ? 'pay you ' : 'pay me ') . $left . ' Cats';
        } elseif ($kind === 'GIVE_ITEM') {
            $out[$by][] = ($by === 'npc' ? 'give you ' : 'give me ') . $the;
        } elseif ($kind === 'RETURN_ITEM') {
            $out[$by][] = 'return ' . $the;
        } elseif ($kind === 'UNEQUIP_ITEM') {
            $out[$by][] = 'take off ' . $the;
        } elseif ($kind === 'EQUIP_ITEM') {
            $out[$by][] = 'put on ' . $the;
        } elseif ($kind === 'FIRST_AID') {
            $out[$by][] = $by === 'npc' ? 'patch you up' : 'patch me up';
        }
    }
    return $out;
}

/** A deal is underway: something was carried out or part-paid, and something is still owed. */
function stobeDealIsUnderway(array $deal): bool {
    if (!in_array(strval($deal['status'] ?? ''), ['ACCEPTED','AWAITING_PERFORMANCE'], true)) return false;
    if (stobeDealNothingPerformedYet($deal)) return false;
    $owed = stobeDealOutstanding($deal);
    return count($owed['npc']) + count($owed['player']) > 0;
}

/** The fixed "finish this first" line, naming what's owed on each side. */
function stobeDealFinishFirstLine(array $deal): string {
    $owed = stobeDealOutstanding($deal);
    $line = "Let's finish our last deal first.";
    if (count($owed['player']) > 0) $line .= ' You still need to ' . implode(' and ', $owed['player']) . '.';
    if (count($owed['npc']) > 0) $line .= ' I still need to ' . implode(' and ', $owed['npc']) . '.';
    return $line;
}

/** Same deal restated with other wording: every new term has a counterpart in the open deal. */
function stobeDealTermsLooselySame(array $new, array $open): bool {
    $base = static fn($s): string => strtolower(trim(preg_replace('/\s*\[[^\]]*\]/', '', strval($s)) ?? ''));
    $any = false;
    foreach ($new as $n) {
        if (!is_array($n)) continue;
        $any = true;
        $found = false;
        foreach ($open as $o) {
            if (!is_array($o)) continue;
            if (strtoupper(strval($n['kind'] ?? '')) !== strtoupper(strval($o['kind'] ?? ''))) continue;
            if (strval($n['by'] ?? '') !== strval($o['by'] ?? '')) continue;
            if (isset($n['amount']) && intval($n['amount']) !== intval($o['amount'] ?? 0)) continue;
            $ni = $base($n['item'] ?? '');
            $oi = $base($o['item'] ?? '');
            if ($ni !== '' && $oi !== '' && !str_contains($ni, $oi) && !str_contains($oi, $ni)) continue;
            $found = true;
            break;
        }
        if (!$found) return false;
    }
    return $any;
}

/** True while no term of this deal has been carried out or sent to the game. */''')

# capture: refuse a clearly different deal while one is underway -----------
patch("lib/negotiation_phase1.php",
      """            } else {
                // Already agreed: never open a second deal for the same matter.
                if (stobeDealTermsDiffer(is_array($openTerms) ? $openTerms : [], $terms)) {
                    stobeDealLog('warn', 'Negotiation capture ignored: another deal is still being performed', [
                        'npc'=>$npc, 'open_contract_id'=>$openId, 'decision'=>$decision,
                    ]);
                }
                return""",
      """            } else {
                // Underway and something still owed: a clearly different deal waits until it's settled.
                if (stobeDealTermsDiffer(is_array($openTerms) ? $openTerms : [], $terms)
                    && !stobeDealTermsLooselySame($terms, is_array($openTerms) ? $openTerms : [])
                    && stobeDealIsUnderway($open)) {
                    stobeDealLog('info', 'Negotiation: new deal refused while another is underway', [
                        'npc'=>$npc, 'open_contract_id'=>$openId, 'decision'=>$decision,
                    ]);
                    return ['ok'=>true, 'decision'=>'NONE', 'blocked_by_active'=>true, 'id'=>$openId,
                        'blocked_line'=>stobeDealFinishFirstLine($open)];
                }
                // Already agreed: never open a second deal for the same matter.
                return""")

# prompt: tell the NPC -------------------------------------------------------
patch("lib/negotiation_engine.php",
      """            $lines[] = 'Deal progress (observed, authoritative): ' . implode('; ', $parts) . '.';
        }""",
      """            $lines[] = 'Deal progress (observed, authoritative): ' . implode('; ', $parts) . '.';
        }
        if (function_exists('stobeDealIsUnderway') && stobeDealIsUnderway($openDeal)) {
            $owed = stobeDealOutstanding($openDeal);
            $still = [];
            if (count($owed['player']) > 0) $still[] = $player . ' still has to ' . str_replace([' me ', ' me'], [' you ', ' you'], implode(' and ', $owed['player']));
            if (count($owed['npc']) > 0) $still[] = 'you still have to ' . str_replace([' you ', ' you'], [' ' . $player . ' ', ' ' . $player], implode(' and ', $owed['npc']));
            $lines[] = 'This deal is underway and not finished (' . implode('; ', $still) . '). Do not agree to or offer any new or different deal until it is settled. '
                . 'If ' . $player . ' proposes one, tell them to finish this deal first and say what is still owed, with deal_decision NONE.';
        }""")

# chat.php: apply the refusal ------------------------------------------------
patch("processor/chat.php",
      """            if (empty($dealResult['ok'])) {
                // Malformed terms: record nothing, but keep the NPC's own words unless they claim a deal.""",
      """            if (!empty($dealResult['blocked_by_active'])) {
                // A different deal while the last one is underway: finish that one first.
                $responseText = strval($dealResult['blocked_line'] ?? "Let's finish our last deal first.");
                $responseActions = array_values(array_filter($responseActions, static fn($a) =>
                    !preg_match('/^(STOP_ATTACK|GIVE_CATS|GIVE_ITEM|TAKE_CATS|TAKE_ITEM|UNEQUIP_ITEM|EQUIP_ITEM)@/i', strval($a))));
            }
            if (empty($dealResult['ok'])) {
                // Malformed terms: record nothing, but keep the NPC's own words unless they claim a deal.""")

print("patch_round9: applied")
