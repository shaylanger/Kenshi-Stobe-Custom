#!/usr/bin/env python3
"""Round 7: fixes from the 2026-09-30 automated Malzin run (see test-run-2026-09-30.md).

  bug 1   A deal whose NPC side is IMPOSSIBLE resolves IMPOSSIBLE (refund) instead of
          staying open, and a refusal on it is not the player's breach.
  bug 3   Player money for negotiation checks falls back to conf_opts PLAYER_CATS.
  bug 4   "...and you take the hat off. Deal?" is not a hand-over ("take the" after "you").
  bug 6   The ceasefire speech rewrite applies to combat/surrender deals only.
  bug 7+11 resolved_at is stamped with the database clock. It was UTC (gmdate) against a
          Europe/Madrid NOW(), so "finished in the last N minutes" checks never matched:
          duplicate deals slipped through and refunds were blocked as unpaid gifts.
  bug 8   A different deal swallowed while another is being performed is now logged.
  bug 9   The generic "one food you carry" hand-over is skipped when a deal names what's owed.
  bug 10  A GIVE_* term without "to" gets the other side as recipient instead of failing.

Usage: patch_round7.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


# bug 7 + 11 ---------------------------------------------------------------
patch("lib/negotiation_engine.php",
      "        $fields['resolved_at'] = gmdate('Y-m-d H:i:s');",
      "        $fields['resolved_at'] = true; // database clock, see stobeNegSaveDeal")
patch("lib/negotiation_engine.php",
      """    foreach ($fields as $column => $value) {
        if (!preg_match('/^[a-z_]+$/', $column)) continue;
""",
      """    foreach ($fields as $column => $value) {
        if (!preg_match('/^[a-z_]+$/', $column)) continue;
        // Timestamps compared against NOW() must come from NOW(): the DB clock is not UTC.
        if ($column === 'resolved_at' && $value === true) { $sets[] = 'resolved_at=NOW()'; continue; }
""")

# bug 1 ---------------------------------------------------------------------
patch("lib/negotiation_engine.php",
      """    if ($playerUnmet) {
        // Wait for NPC actions already in flight so evidence is complete, then call it.""",
      """    // The NPC can't do their part: the deal fails (anything paid is refunded), and an
    // unpaid or refused player side is not the player's breach.
    $npcImpossible = false;
    foreach ($required as $t) {
        if (($t['by'] ?? '') === 'npc' && ($t['status'] ?? '') === 'IMPOSSIBLE') $npcImpossible = true;
    }
    if ($npcImpossible) {
        $npcInFlight = array_filter($required, static fn($t) => ($t['by'] ?? '') === 'npc' && in_array($t['status'] ?? '', ['DISPATCHED','REISSUE_QUEUED'], true));
        return count($npcInFlight) > 0 ? '' : 'IMPOSSIBLE';
    }
    if ($playerUnmet) {
        // Wait for NPC actions already in flight so evidence is complete, then call it.""")

# bug 3 ---------------------------------------------------------------------
patch("lib/negotiation_engine.php",
      """function stobeNegMoney(array $row): array {
    $meta = stobeNegDecode($row['metadata'] ?? []);
    if (!array_key_exists('money', $meta)) return ['known'=>false, 'value'=>0, 'observed_at'=>0];""",
      """function stobeNegMoney(array $row): array {
    $meta = stobeNegDecode($row['metadata'] ?? []);
    if (!array_key_exists('money', $meta)) {
        // The DLL syncs the player's balance into conf_opts PLAYER_CATS, not onto the character row.
        $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
        if ($player !== '' && strcasecmp(normalizeParticipantNameToken(strval($row['name'] ?? '')), $player) === 0) {
            $cats = trim(strval(getSetting('PLAYER_CATS', '')));
            if ($cats !== '' && is_numeric($cats)) return ['known'=>true, 'value'=>max(0, intval($cats)), 'observed_at'=>time()];
        }
        return ['known'=>false, 'value'=>0, 'observed_at'=>0];
    }""")

# bug 4 ---------------------------------------------------------------------
patch("lib/negotiation_voice.php",
      "|here,|take (it|this|these|them|that|the)|",
      "|here,|(?<!you )take (it|this|these|them|that|the)|")

# bug 9 ---------------------------------------------------------------------
patch("lib/negotiation_voice.php",
      """        // 3. No deal but generic ("here, have a drink" / "here's some food"): hand over one you carry.
        if (count($items) === 0) {""",
      """        // 3. No deal but generic ("here, have a drink" / "here's some food"): hand over one you carry.
        // Not when a deal names what's owed: "here's your food" must not swap in some other food.
        if (count($items) === 0 && count(stobeNegPlayerOwedItems($npc)) === 0) {""")

# bug 10 --------------------------------------------------------------------
patch("lib/negotiation_phase1.php",
      """        foreach (['by', 'to', 'target'] as $field) {
            if (isset($term[$field])) $term[$field] = $side($term[$field]);
        }
""",
      """        foreach (['by', 'to', 'target'] as $field) {
            if (isset($term[$field])) $term[$field] = $side($term[$field]);
        }
        // Models often leave out "to" on a transfer; it can only go to the other side.
        if (in_array(strval($term['kind'] ?? ''), ['GIVE_CATS','GIVE_ITEM','RETURN_ITEM','LOAN_ITEM'], true)
            && trim(strval($term['to'] ?? '')) === '' && in_array(strval($term['by'] ?? ''), ['npc','player'], true)) {
            $term['to'] = $term['by'] === 'player' ? 'npc' : 'player';
        }
""")

# bug 8 ---------------------------------------------------------------------
patch("lib/negotiation_phase1.php",
      """            } else {
                // Already agreed: never open a second deal for the same matter.
                return""",
      """            } else {
                // Already agreed: never open a second deal for the same matter.
                if (stobeDealTermsDiffer(is_array($openTerms) ? $openTerms : [], $terms)) {
                    stobeDealLog('warn', 'Negotiation capture ignored: another deal is still being performed', [
                        'npc'=>$npc, 'open_contract_id'=>$openId, 'decision'=>$decision,
                    ]);
                }
                return""")

# bug 6 ---------------------------------------------------------------------
patch("processor/chat.php",
      """                if (in_array(($dealResult['decision'] ?? ''), ['COUNTER','REJECT'], true)
                    && stobeDealSpeechClaimsCeasefire($responseText)) {""",
      """                if (in_array(($dealResult['decision'] ?? ''), ['COUNTER','REJECT'], true)
                    && in_array(strval($dealResult['kind'] ?? ($negotiationKind ?: 'combat')), ['combat','surrender'], true)
                    && stobeDealSpeechClaimsCeasefire($responseText)) {""")

print("patch_round7: applied")
