#!/usr/bin/env python3
"""imm26-fix17bx (row 17-bx): the claims block (lib/imm26_claims.php) gave the model no inventory verdict, so an NPC whose pack
really holds the accused item never admitted it (F x3 FAIL), retracted when the item was really missing (T2) and fabricated
"I saw" (F2). Fix: when the topic names an item (the player's line, else the NPC's own recent replies for a bare challenge such as
"Check your pack, I haven't had it"), the claims block gets an explicit verdict line read from the NPC's verified inventory
(metadata.inventory_items = the list the prompt's own Inventory section is built from; text inventory/equipment as fallback):
  "your inventory DOES contain <item>"  /  "your inventory DOES NOT contain <item>"
plus the matching rule (admit a probable mistake without inventing a cause / hold the position, never retract) and a ban on
claiming to have seen or been told anything. Fail-closed: no known inventory -> no verdict. DOES NOT only for a capitalised
item name in an ownership sentence (never for money, a person or a faction word).
Usage (WSL): python3 apply.py <tree-root>   (idempotent; anchored; CRLF-aware; also installs the regression test)"""
import sys, os
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(root, 'lib', 'imm26_claims.php')
raw = open(p, 'rb').read().decode('utf-8')
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')
TEST = 'imm26_fix17bx_inventory_verdict_regression.php'
if 'imm26ClaimsInventoryLines' in s:
    print('already applied')
else:
    A1 = "function imm26ClaimsContext(string $actor, array $npc, string $listener, int $gameTs = 0, array $meta = []): string\n{\n"
    A2 = "    if (!$lines) return '';\n    return \"<claims_and_corrections>\\n\""
    assert s.count(A1) == 1 and s.count(A2) == 1, 'anchors missing in imm26_claims.php'
    new_fns = r'''// ---------- IMM-17-bx: inventory verdict for an item the conversation names ----------
const IMM26_INV_OWNERSHIP_RE = "/\\b(?:took|take|taken|taking|stole|steal|stolen|have|has|had|got|grabbed|swiped|pocketed|borrowed|lost|misplaced|carry|carrying|carried|holding|hold|touch|touched|give|gave|return|returned|keep|kept|sold|sell|find|found|seen|saw|where(?:'s| is| are)|pack|bag|inventory|mine|yours|belongs?|stash(?:ed)?)\\b/iu";
const IMM26_INV_NOT_ITEM = ['nation','hive','lord','boss','cat','cats','kenshi','empire','guild','alliance','outlaws','order','inn','bar','shek','shek kingdom','swamp','hub'];
const IMM26_INV_GENERIC_HEAD = ['armor','armour','plate','small','large','heavy','light','chain','steel','strip','kit'];

/** lower-case name => display name of what the NPC's verified inventory holds (carried or worn). [] = unknown. Pure. */
function imm26ClaimsInventoryNames(array $npc): array
{
    $names = [];
    $strip = static fn(string $n): string => trim(preg_replace('/\s*\[[^\]]*\]|\s*\([^)]*\)/', '', $n) ?? $n);
    $meta = $npc['metadata'] ?? [];
    if (is_string($meta)) $meta = json_decode($meta, true);
    $items = is_array($meta) ? ($meta['inventory_items'] ?? []) : [];
    if (is_string($items)) $items = json_decode($items, true);
    foreach (is_array($items) ? $items : [] as $entry) {
        $n = is_array($entry) ? strval($entry['name'] ?? '') : (is_string($entry) ? $entry : '');
        $n = $strip($n);
        if ($n !== '') $names[mb_strtolower($n)] = $n;
    }
    if (!$names) {   // same fallback the prompt's Inventory section uses: the stored text lists
        foreach ([strval($npc['inventory'] ?? ''), strval($npc['equipment'] ?? '')] as $text) {
            foreach (preg_split('/,\s*(?=[^,]*\bx\d+)/', $text) ?: [] as $entry) {
                if (!preg_match('/^\s*(.+?)\s+x(\d+)\b/', $entry, $m)) continue;
                $n = $strip($m[1]);
                if ($n !== '') $names[mb_strtolower($n)] = $n;
            }
        }
    }
    return $names;
}

/** Items a text names: [[display, held?], ...] (max 2). Inventory names are matched in any case; an item the pack does not hold is
 *  only reported when it is a capitalised name after my/your/the/a in an ownership sentence. Pure. */
function imm26ClaimsItemsInText(string $text, array $names): array
{
    $found = [];
    $low = mb_strtolower($text);
    foreach ($names as $key => $display) {
        $key = strval($key);
        if (mb_strlen($key) < 3) continue;
        $hit = preg_match('/(?<![\p{L}\p{N}])' . preg_quote($key, '/') . '(?:e?s)?(?![\p{L}\p{N}])/u', $low) === 1;
        if (!$hit) {
            $words = preg_split('/\s+/u', $key) ?: [$key];
            $head = strval(end($words));
            $hit = count($words) > 1 && mb_strlen($head) >= 5 && !in_array($head, IMM26_INV_GENERIC_HEAD, true)
                && preg_match('/(?<![\p{L}\p{N}])' . preg_quote($head, '/') . '(?:e?s)?(?![\p{L}\p{N}])/u', $low) === 1;
        }
        if ($hit) $found[$key] = [$display, true];
    }
    $sentences = preg_split('/(?<=[.!?])\s+/u', $text) ?: [];
    foreach ($sentences as $sentence) {
        if (preg_match(IMM26_INV_OWNERSHIP_RE, $sentence) !== 1) continue;
        if (preg_match_all("/(?<![\\p{L}'])(?:[Mm]y|[Yy]our|[Tt]he|[Aa]n?|[Tt]hat|[Tt]his)\\s+([A-Z][\\p{L}'-]+(?:\\s+(?:of\\s+)?[A-Z][\\p{L}'-]+){0,2})/u", $sentence, $mm) < 1) continue;
        foreach ($mm[1] as $cand) {
            $ck = mb_strtolower($cand);
            $bad = false;
            foreach (preg_split('/\s+/u', $ck) ?: [] as $w) if (in_array($w, IMM26_INV_NOT_ITEM, true)) $bad = true;
            if ($bad || mb_strlen($ck) < 3) continue;
            $held = false;
            foreach ($names as $key => $display) {
                $key = strval($key);
                if ($key === $ck || str_contains($key, $ck) || str_contains($ck, $key)) { $found[$key] = [$display, true]; $held = true; }
            }
            if (!$held && !isset($found[$ck]) && $names) $found[$ck] = [$cand, false];
        }
    }
    return array_slice(array_values($found), 0, 2);
}

/** Verdict lines for the claims block ([] = no item named, or inventory unknown: fail-closed). Pure. */
function imm26ClaimsInventoryLines(array $npc, string $playerMessage, array $replies): array
{
    $names = imm26ClaimsInventoryNames($npc);
    if (!$names) return [];
    $topic = preg_match(IMM26_INV_OWNERSHIP_RE, $playerMessage) === 1 || imm26IsChallenge($playerMessage)
        || preg_match("/\\b(?:do|did|does|are)\\s+you\\s+(?:have|got|carry|hold|own|keep|take|took|steal|stole)\\b/iu", $playerMessage) === 1;
    if (!$topic) return [];
    $items = imm26ClaimsItemsInText($playerMessage, $names);
    if (!$items) {   // a bare challenge ("Check your pack, I haven't had it."): the item is in what the NPC itself said last
        foreach (array_slice($replies, 0, 3) as $reply) {
            $items = imm26ClaimsItemsInText(strval($reply), $names);
            if ($items) break;
        }
    }
    if (!$items) return [];
    $has = [];
    $lacks = [];
    foreach ($items as [$display, $held]) {
        if ($held) $has[] = $display; else $lacks[] = $display;
    }
    $out = [];
    if ($has) $out[] = 'Inventory check (read from your own pack and gear, not a guess): your inventory DOES contain ' . stobePromptXmlEscape(implode(' and ', $has)) . '.';
    if ($lacks) $out[] = 'Inventory check (read from your own pack and gear, not a guess): your inventory DOES NOT contain ' . stobePromptXmlEscape(implode(' and ', $lacks)) . '.';
    if ($has) {
        $out[] = 'If they ask whether you have it, answer yes. If you said or implied earlier that it was taken, lost or missing, you were probably mistaken or misplaced it yourself: say so plainly in one short sentence ("my mistake", "I must have misplaced it") without inventing how, where or by whom.';
    }
    if ($lacks) {
        $out[] = 'If they ask whether you have it, answer no. If you said earlier that it is missing or was taken, that still stands: hold your position, do not retract, apologise or say you were wrong, and do not accuse anyone you have no fact against.';
    }
    $out[] = 'Do not say you saw, heard or were told anything about it unless a fact in this prompt says so.';
    return $out;
}

'''
    ins = "    foreach (imm26ClaimsInventoryLines($npc, $playerMessage, $replies) as $inventoryLine) $lines[] = $inventoryLine; // IMM-17-bx\n"
    s = s.replace(A1, new_fns + A1, 1)
    s = s.replace(A2, ins + A2, 1)
    out = s.replace('\n', '\r\n') if crlf else s
    open(p, 'wb').write(out.encode('utf-8'))
    print('patched lib/imm26_claims.php (crlf=%s)' % crlf)

src = os.path.join(here, 'tests', TEST)
dst = os.path.join(root, 'tests', TEST)
data = open(src, 'rb').read().decode('utf-8').replace('\r\n', '\n')
if os.path.exists(dst) and b'\r\n' in open(dst, 'rb').read():
    data = data.replace('\n', '\r\n')
open(dst, 'wb').write(data.encode('utf-8'))
print('installed tests/' + TEST)
