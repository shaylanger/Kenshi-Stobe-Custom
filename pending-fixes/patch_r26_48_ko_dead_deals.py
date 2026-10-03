#!/usr/bin/env python3
"""Item 48: a dying or dead NPC negotiates.

Run 12: a raider hit by `stobe-auto kill` (dying) proposed a deal 19 s later, died, and
his COUNTER came 2 s after death. Shay's rule: dying but conscious may still deal;
unconscious or dead may not; a deal interrupted by a KO resumes when they wake (they
know they were negotiating).

- stobeNegNpcOutState(): 'dead' / 'unconscious' / '' from the NPC's newest knockout,
  death or recovered event (the NPC is the event's actor, matched on serial when known),
  else from the stored character state.
- A chat reply in a negotiation is not recorded (and not spoken: text and actions are
  cleared) when the NPC is out by the time it comes back.
- NPC-started offers (surrender/assist initiatives) and queued directives skip an NPC
  who is out; directives stay queued until their window closes.
- An open PROPOSED/COUNTERED deal doesn't expire while its NPC is unconscious. On
  "regained consciousness" the deal is refreshed and a resume_deal directive makes the
  NPC bring it up again (bored path, 120 s window).

Usage: patch_r26_48_ko_dead_deals.py <StobeServer tree>  (idempotent)
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


FUNCS = r'''// ---- Item 48: knocked out or dead NPCs don't negotiate ------------------------------

/** Unsigned hand serial of an NPC ("hand_<serial>" in her metadata), or ''. */
function stobeNegNpcHandSerial(string $npc, array|false $npcData): string {
    $sid = '';
    if (is_array($npcData)) {
        $sid = strval($npcData['storage_id'] ?? '');
        if ($sid === '') {
            $meta = $npcData['metadata'] ?? [];
            if (is_string($meta)) $meta = json_decode($meta, true);
            $sid = is_array($meta) ? strval($meta['storage_id'] ?? '') : '';
        }
    }
    if (preg_match('/^hand_(-?\d+)$/', $sid, $m)) {
        $serial = intval($m[1]);
        if ($serial < 0) $serial += 4294967296;
        return $serial > 0 ? strval($serial) : '';
    }
    $serial = function_exists('stobeNegSerialFromStorage') ? stobeNegSerialFromStorage($npc) : 0;
    return $serial > 0 ? strval($serial) : '';
}

/**
 * 'dead' or 'unconscious' from the NPC's newest knockout / death / recovered event (she
 * is the event's actor; matched on her serial when known, else her name), '' when she is
 * conscious. Dying but conscious counts as conscious. No events: her stored state decides.
 */
function stobeNegNpcOutState(string $npc, array|false $npcData = false): string {
    $npc = trim($npc);
    if ($npc === '') return '';
    if ($npcData === false && function_exists('getNpcData')) $npcData = getNpcData($npc);
    try {
        $serial = stobeNegNpcHandSerial($npc, $npcData);
        $row = $serial !== ''
            ? $GLOBALS['db']->fetchOne(
                "SELECT type FROM eventlog WHERE type IN ('knockout','death','recovered') AND people ~ $1
                  ORDER BY localts DESC, rowid DESC LIMIT 1",
                ['^\["[^"]*\|hand_' . $serial . '"'])
            : $GLOBALS['db']->fetchOne(
                "SELECT type FROM eventlog WHERE type IN ('knockout','death','recovered') AND data LIKE $1
                  ORDER BY localts DESC, rowid DESC LIMIT 1",
                [$npc . ':%']);
        if (is_array($row)) {
            $type = strval($row['type'] ?? '');
            return $type === 'death' ? 'dead' : ($type === 'knockout' ? 'unconscious' : '');
        }
    } catch (Throwable $e) {
        // fall through to the stored state
    }
    if (is_array($npcData) && function_exists('stobeResolveNpcAwarenessState')) {
        $state = stobeResolveNpcAwarenessState($npcData);
        if ($state === 'dead') return 'dead';
        if (in_array($state, ['unconscious', 'knocked_out'], true)) return 'unconscious';
    }
    return '';
}

/** On "X: regained consciousness": her open offer is refreshed and she brings it up again. */
function stobeNegResumeAfterKnockout(string $eventData): void {
    if (!preg_match('/^(.+?):\s*regained consciousness/i', trim($eventData), $m)) return;
    $npc = normalizeParticipantNameToken($m[1]);
    $base = preg_match('/\[\s*(.+?)\s*\]$/', $npc, $bm) ? $bm[1] : $npc; // "Hesk [Dust Bandit Bowman]"
    $deal = $GLOBALS['db']->fetchOne(
        "SELECT * FROM stobe_social_contract WHERE LOWER(npc_name) IN (LOWER($1), LOWER($2))
            AND status IN ('PROPOSED','COUNTERED') AND updated_at > NOW() - INTERVAL '2 hours'
          ORDER BY updated_at DESC LIMIT 1",
        [$npc, $base]
    );
    if (!is_array($deal)) return;
    $GLOBALS['db']->exec("UPDATE stobe_social_contract SET updated_at=NOW() WHERE contract_id=$1", [strval($deal['contract_id'])]);
    $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
    $terms = stobeNegDecode($deal['terms'] ?? []);
    $line = function_exists('stobeDealPlainTermsLine') && is_array($terms) && count($terms) > 0
        ? trim(stobeDealPlainTermsLine($terms, 'COUNTER')) : '';
    stobeNegQueueDirective(strval($deal['npc_name']), 'resume_deal', strval($deal['contract_id']), [
        'actions'=>[],
        'instruction'=>'You just came to after being knocked out. Before that you were negotiating with ' . $player
            . ($line !== '' ? ' (the offer on the table: ' . $line . ')' : '')
            . '. You remember it: bring the deal up again in one short line.',
    ], true);
    stobeLogInfo('Deal resumes after a knockout (item 48)', ['npc'=>$npc, 'contract_id'=>$deal['contract_id'] ?? '', 'status'=>$deal['status'] ?? '']);
}

/** Bug 98: newest live health from the fight'''

patch('lib/negotiation_engine.php', 'function stobeNegNpcOutState(', [
    ('/** Bug 98: newest live health from the fight', FUNCS),
    # a recovered NPC picks the deal up again
    ("    $type = strtolower(trim($eventType));\n    if ($type === 'combat') {",
     "    $type = strtolower(trim($eventType));\n"
     "    if ($type === 'recovered') {\n"
     "        try { stobeNegResumeAfterKnockout($eventData); } catch (Throwable $e) {} // item 48\n"
     "    }\n"
     "    if ($type === 'combat') {"),
    # no NPC-started offers from someone who is out
    ("            $data = getNpcData($name);\n            if (!is_array($data)) continue;\n",
     "            $data = getNpcData($name);\n            if (!is_array($data)) continue;\n"
     "            if (stobeNegNpcOutState($name, $data) !== '') continue; // item 48: knocked out or dead\n"),
    # queued directives wait while the NPC is out
    ("            if (!$present) continue;\n            $claimed = $GLOBALS['db']->exec(",
     "            if (!$present) continue;\n"
     "            if (stobeNegNpcOutState($renamed !== '' ? $renamed : $npc) !== '') continue; // item 48\n"
     "            $claimed = $GLOBALS['db']->exec("),
    ("(CASE WHEN kind IN ('refund','reissue_payment') THEN 600 ELSE 45 END) ORDER BY id LIMIT 20\",",
     "(CASE WHEN kind IN ('refund','reissue_payment') THEN 600 WHEN kind='resume_deal' THEN 120 ELSE 45 END) ORDER BY id LIMIT 20\","),
    # an offer doesn't expire while its NPC is knocked out
    ("    // Bargaining that went quiet expires (Phase 3), accepted-but-unstarted deals are cleaned up.\n",
     "    // Item 48: an offer waits while its NPC is knocked out (it resumes when they wake).\n"
     "    $quiet = $GLOBALS['db']->fetchAll(\n"
     "        \"SELECT contract_id, npc_name FROM stobe_social_contract\n"
     "          WHERE status IN ('PROPOSED','COUNTERED') AND updated_at < NOW() - INTERVAL '10 minutes' LIMIT 20\"\n"
     "    );\n"
     "    foreach (is_array($quiet) ? $quiet : [] as $q) {\n"
     "        if (stobeNegNpcOutState(strval($q['npc_name'] ?? '')) === 'unconscious') {\n"
     "            $GLOBALS['db']->exec(\"UPDATE stobe_social_contract SET updated_at=NOW() - INTERVAL '9 minutes' WHERE contract_id=$1\", [strval($q['contract_id'])]);\n"
     "        }\n"
     "    }\n"
     "    // Bargaining that went quiet expires (Phase 3), accepted-but-unstarted deals are cleaned up.\n"),
])

CHAT_OLD = '''        if ($negotiationActive) {
            $dealResult = stobeDealCaptureResponse('''
CHAT_NEW = '''        $npcOutNow = $negotiationActive && function_exists('stobeNegNpcOutState') ? stobeNegNpcOutState($targetNpc, $npcData) : '';
        if ($npcOutNow !== '') {
            // Item 48: knocked out or dead by the time the reply came back: no deal, no words.
            stobeLogWarn('Deal reply from a knocked-out or dead NPC dropped (item 48)', [
                'npc'=>$targetNpc, 'state'=>$npcOutNow, 'text'=>$responseText,
            ]);
            $responseText = '';
            $responseActions = [];
            $negotiationActive = false;
        }
''' + CHAT_OLD

patch('processor/chat.php', "dropped (item 48)", [(CHAT_OLD, CHAT_NEW)])
