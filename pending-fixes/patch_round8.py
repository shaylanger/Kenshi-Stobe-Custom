#!/usr/bin/env python3
"""Round 8 (server): remaining bugs from the 2026-09-30 automated run.

  bug 14  main.php base64-decoded DATA straight from the raw QUERY_STRING, which is still
          URL-encoded: "%2F" / "%3D" were fed to base64_decode as literal characters, so
          the tail of many chat lines turned into junk ("Deal?" -> "Deal6\\x14??...").
          Now rawurldecode() first ('+' stays '+', the DLL sends it as %2B anyway).
  bug 12  The NPC said "let me put the sandals back on" with action Talk, so nothing
          happened. If a reply announces putting on / taking off clothing and carries no
          EQUIP/UNEQUIP action, infer it when exactly one item fits. Skipped on deal turns
          (the ledger decides when deal clothing comes off) and for negated/conditional lines.
  late    Actions added after the LLM streamed its own (the inferred ones above, attached
          refunds/settlements) were dropped when actions_streamed was true. They are now
          emitted separately.

Usage: patch_round8.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new, count=1):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == count, f"{rel}: anchor found {text.count(old)}x, expected {count}: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


# bug 14 --------------------------------------------------------------------
patch("main.php",
      'base64_decode(substr($_SERVER["QUERY_STRING"], 5)',
      'base64_decode(rawurldecode(substr($_SERVER["QUERY_STRING"], 5))')
patch("main.php",
      'base64_decode(substr($_SERVER["QUERY_STRING"], 5, strpos($_SERVER["QUERY_STRING"], "&") - 5))',
      'base64_decode(rawurldecode(substr($_SERVER["QUERY_STRING"], 5, strpos($_SERVER["QUERY_STRING"], "&") - 5)))')

# bug 12: inference helper --------------------------------------------------
patch("lib/negotiation_engine.php",
      "/** Run verification for open deals. Cheap when nothing is open; throttled by caller. */",
      r'''/**
 * The NPC announces putting on / taking off clothing ("let me put the sandals back on")
 * but sent no EQUIP/UNEQUIP action. Returns the one action that fits, or ''.
 */
function stobeInferClothingAction(string $text, array|false $npcData, array $actions): string {
    if (!is_array($npcData) || trim($text) === '') return '';
    foreach ($actions as $action) {
        if (preg_match('/^(UN)?EQUIP_ITEM@/i', strval($action))) return '';
    }
    $lower = strtolower($text);
    $sentence = '';
    $mode = '';
    foreach (preg_split('/(?<=[.!?])\s+/', $lower) ?: [] as $s) {
        $on = preg_match("/\b(put|putting|get|getting|strap|strapping|pull|pulling|slip|slipping)\b[^.!?]{0,40}\bon\b/", $s);
        $off = preg_match("/\b(take|taking|get|getting|pull|pulling|strip|stripping|slip|slipping)\b[^.!?]{0,40}\boff\b/", $s);
        if ($on xor $off) {
            // Negated, conditional or later: not an action now.
            if (preg_match("/\b(not|never|won'?t|don'?t|can'?t|if|unless|until|once|when|after|first|then|later|pay)\b/", $s)) return '';
            if ($mode !== '' && $mode !== ($on ? 'equip' : 'unequip')) return '';
            $mode = $on ? 'equip' : 'unequip';
            $sentence .= ' ' . $s;
        }
    }
    if ($mode === '') return '';
    $source = strval($mode === 'equip' ? ($npcData['inventory'] ?? '') : ($npcData['equipment'] ?? ''));
    $names = function_exists('stobeNegInventoryDisplayNames') ? stobeNegInventoryDisplayNames($source) : [];
    $synonyms = ['hat'=>['hat','helm','cap','zukin','hood'], 'shoes'=>['sandal','boot','shoe'], 'sandals'=>['sandal'],
        'boots'=>['boot'], 'shirt'=>['shirt'], 'vest'=>['rag shirt','vest'], 'pants'=>['pants','shorts','trousers'],
        'shorts'=>['shorts'], 'trousers'=>['trousers','pants'], 'coat'=>['coat'], 'gloves'=>['glove'], 'mask'=>['mask']];
    $best = [];
    $bestScore = 0;
    foreach ($names as $base => $display) {
        $score = 0;
        foreach (preg_split('/[^a-z]+/', $base) ?: [] as $word) {
            if (strlen($word) >= 4 && preg_match('/\b' . preg_quote($word, '/') . 's?\b/', $sentence)) $score += 2;
        }
        foreach ($synonyms as $said => $matches) {
            if (!preg_match('/\b' . $said . '\b/', $sentence)) continue;
            foreach ($matches as $m) {
                if (str_contains($base, $m)) { $score += 1; break; }
            }
        }
        if (preg_match('/\b(katana|sword|sabre|saber|blade|knife|bow|crossbow|club|hammer|spear|axe|polearm|nodachi|wakizashi|machete)\b/', $base)) $score = 0;
        if ($score > $bestScore) { $best = [$display]; $bestScore = $score; }
        elseif ($score > 0 && $score === $bestScore) { $best[] = $display; }
    }
    if (count($best) !== 1) return '';
    $item = trim(preg_replace('/\s*\[[^\]]*\]/', '', strval($best[0])) ?? strval($best[0]));
    return ($mode === 'equip' ? 'EQUIP_ITEM@' : 'UNEQUIP_ITEM@') . $item;
}

/** Run verification for open deals. Cheap when nothing is open; throttled by caller. */''')

# bug 12 + late actions: chat.php ------------------------------------------
patch("processor/chat.php",
      """$responseActions = stobeDedupeActionList($responseActions, 'chat', $actionConfig);
if ($narratorMode) {
    $responseActions = [];
}
if (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {""",
      """$responseActions = stobeDedupeActionList($responseActions, 'chat', $actionConfig);
if ($narratorMode) {
    $responseActions = [];
}
// Anything added from here on was not streamed with the LLM's own actions.
$preLateActions = $responseActions;
$dealTurnDecision = isset($dealResult) && is_array($dealResult) ? strval($dealResult['decision'] ?? '') : '';
if (!$narratorMode && function_exists('stobeInferClothingAction')
    && !in_array($dealTurnDecision, ['ACCEPT','COUNTER','PROPOSE'], true)) {
    $inferredAction = stobeInferClothingAction($responseText, $npcData, $responseActions);
    if ($inferredAction !== '') {
        $responseActions[] = $inferredAction;
        stobeLogInfo('Clothing action inferred from speech', ['npc'=>$targetNpc, 'action'=>$inferredAction, 'text'=>$responseText]);
    }
}
if (!$narratorMode && function_exists('stobeNegAttachPendingForChat')) {""")

patch("processor/chat.php",
      """    if (count($responseActions) > 0 && !$actionsStreamedInLlm) {
        streamResponse($targetNpc, 'ScriptQueue', '', $npcData, $responseActions, 'chat', $replyTarget, $gamets);
    }""",
      """    if (count($responseActions) > 0 && !$actionsStreamedInLlm) {
        streamResponse($targetNpc, 'ScriptQueue', '', $npcData, $responseActions, 'chat', $replyTarget, $gamets);
    } elseif ($actionsStreamedInLlm) {
        $lateActions = array_values(array_diff($responseActions, $preLateActions ?? $responseActions));
        if (count($lateActions) > 0) {
            streamResponse($targetNpc, 'ScriptQueue', '', $npcData, $lateActions, 'chat', $replyTarget, $gamets);
        }
    }""")

print("patch_round8: applied")
