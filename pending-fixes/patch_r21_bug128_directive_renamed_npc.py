#!/usr/bin/env python3
"""Bug 128: an NPC named mid-fight never makes his surrender offer.

Run 9 (test 22): the surrender directive was queued for "Dust Bandit Bowman"
(14:41:08); 8 s later he had been named "Gost [Dust Bandit Bowman]", his
bored line didn't match the directive's name, and the offer expired unseen.
A directive for "<title>" now also matches a nearby "<Name> [<title>]", and
takes that name.

Usage: patch_r21_bug128_directive_renamed_npc.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'negotiation_engine.php'
text = path.read_text(encoding='utf-8')
old = """            $present = $onlyNpc !== '';
            foreach ($candidateNames as $candidate) {
                if (strcasecmp(normalizeParticipantNameToken(strval($candidate)), $npc) === 0) $present = true;
            }
            if (!$present) continue;
            $claimed = $GLOBALS['db']->exec(
                "UPDATE stobe_negotiation_directive SET consumed_unix=$2 WHERE id=$1 AND consumed_unix=0",
                [intval($row['id']), time()]
            );
            if ($claimed === false || $GLOBALS['db']->affectedRows($claimed) !== 1) continue;
            $row['payload'] = stobeNegDecode($row['payload'] ?? []);
            return $row;"""
new = """            $present = $onlyNpc !== '';
            $renamed = '';
            foreach ($candidateNames as $candidate) {
                $candidate = normalizeParticipantNameToken(strval($candidate));
                if (strcasecmp($candidate, $npc) === 0) $present = true;
                // Bug 128: named mid-fight: "Dust Bandit Bowman" is now "Gost [Dust Bandit Bowman]".
                elseif (preg_match('/^.+\\[\\s*(.+?)\\s*\\]$/', $candidate, $bm) && strcasecmp($bm[1], $npc) === 0) {
                    $present = true;
                    $renamed = $candidate;
                }
            }
            if (!$present) continue;
            $claimed = $GLOBALS['db']->exec(
                "UPDATE stobe_negotiation_directive SET consumed_unix=$2 WHERE id=$1 AND consumed_unix=0",
                [intval($row['id']), time()]
            );
            if ($claimed === false || $GLOBALS['db']->affectedRows($claimed) !== 1) continue;
            if ($renamed !== '') {
                $GLOBALS['db']->exec("UPDATE stobe_negotiation_directive SET npc_name=$2 WHERE id=$1", [intval($row['id']), $renamed]);
                stobeLogInfo('Directive follows the NPC\\'s new name (bug 128)', ['from'=>$npc, 'to'=>$renamed, 'kind'=>$row['kind'] ?? '']);
                $row['npc_name'] = $renamed;
            }
            $row['payload'] = stobeNegDecode($row['payload'] ?? []);
            return $row;"""
if 'Bug 128' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
