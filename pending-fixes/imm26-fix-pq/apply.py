#!/usr/bin/env python3
"""imm26-fix-pq: social repair capture compared the model's player_quote strictly to the raw player message.
The prompt builder shows the model "Speaker: text (talking to: X)" (and may append "[Player tone: ...]"), so the model
echoes those context decorations and every update was dropped -> no_valid_repair (row 10-a).
Fix: compare after stripping ONLY those decorations (leading "<speaker>: ", trailing "(talking to: X)" / "[Player tone: ...]")
from both sides; the remainder must still be identical. Stored player_quote stays the untouched literal message.
Usage (WSL): python3 apply.py <tree-root>     (idempotent; asserts anchors; installs the regression test)"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(root, 'lib', 'social_repair_dialogue.php')
s = open(p, encoding='utf-8').read()
if 'stobeSocialRepairQuoteMatches' in s:
    print('already applied'); sys.exit(0)
A1 = "function stobeSocialRepairCapture(string $actor, array $npc, string $speaker, string $message,\n"
A2 = "|| $update['player_quote']!==$message || $update['kind']!==$kind"
assert s.count(A1) == 1 and s.count(A2) == 1, 'anchors missing'
helper = r'''/**
 * The prompt shows the model "Speaker: text (talking to: X)" (+ optional "[Player tone: ...]"), so its player_quote may echo
 * those decorations. Strip only them (leading "<speaker>: ", trailing talking-to / player-tone tags) from both sides;
 * the remaining text must still be byte-identical.
 */
function stobeSocialRepairQuoteCore(string $text, string $speaker): string
{
    $t=trim($text);
    do {
        $before=$t;
        $t=preg_replace('/\s*\((?:talking to:?|to:)[^()]*\)\s*$/iu','',$t) ?? $t;
        $t=preg_replace('/\s*\[Player tone:[^\]]*\]\s*$/u','',$t) ?? $t;
    } while ($t!==$before);
    if ($speaker!=='' && strncmp($t,$speaker.':',strlen($speaker)+1)===0) $t=substr($t,strlen($speaker)+1);
    return trim($t);
}

function stobeSocialRepairQuoteMatches(string $quote, string $message, string $speaker): bool
{
    $core=stobeSocialRepairQuoteCore($message,$speaker);
    return $core!=='' && stobeSocialRepairQuoteCore($quote,$speaker)===$core;
}

'''
s = s.replace(A1, helper + A1)
s = s.replace(A2, "|| !stobeSocialRepairQuoteMatches($update['player_quote'],$message,$speaker) || $update['kind']!==$kind")
open(p, 'w', encoding='utf-8').write(s)
shutil.copy(os.path.join(here, 'imm26_pq_quote_regression.php'), os.path.join(root, 'tests', 'imm26_pq_quote_regression.php'))
print('applied')
