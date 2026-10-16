#!/usr/bin/env python3
"""imm26-fix10a (row 10-a): social repair capture compared the model's npc_quote with strpos() against response_message,
which is the sanitizeForKenshi()-normalised reply (em/en dash -> '-', curly quotes -> straight, ellipsis -> '...', nbsp -> ' ').
The model copies its npc_quote from its raw reply (em dash kept), so the apology was never recognised.
Fix: ONE normaliser (stobeSocialRepairQuoteNormalize: reuses sanitizeForKenshi when loaded, then folds remaining unicode
dashes/quotes/spaces, collapses whitespace, case-folds) applied to BOTH sides of every quote/reply comparison in the module:
npc_quote in reply (new stobeSocialRepairNpcQuoteInReply) and the player_quote core comparison. Strictness otherwise unchanged.
Usage (WSL): python3 apply.py <tree-root>   (requires fix-pq applied first; idempotent; anchored; CRLF-aware; installs the test)"""
import sys, os
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(root, 'lib', 'social_repair_dialogue.php')
raw = open(p, 'rb').read().decode('utf-8')
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')
TEST = 'imm26_fix10a_quote_norm_regression.php'
if 'stobeSocialRepairQuoteNormalize' in s:
    print('already applied'); sys.exit(0)
A1 = "function stobeSocialRepairQuoteMatches(string $quote, string $message, string $speaker): bool\n{\n    $core=stobeSocialRepairQuoteCore($message,$speaker);\n    return $core!=='' && stobeSocialRepairQuoteCore($quote,$speaker)===$core;\n}\n"
A2 = "|| strpos(strval($meta['response_message'] ?? ''),$update['npc_quote'])===false) continue;"
assert s.count(A1) == 1 and s.count(A2) == 1, 'anchors missing (fix-pq must be applied first)'
new = r'''/**
 * One normaliser for every quote/reply comparison. The reply reaches this module already passed through
 * sanitizeForKenshi() (em/en dash, curly quotes, ellipsis, nbsp), while the model copies npc_quote/player_quote from its
 * raw text; so both sides go through the same transformations. Reuses sanitizeForKenshi() when loaded, then folds the
 * remaining unicode dash/quote/space variants, collapses whitespace and case-folds. Different words still differ.
 */
function stobeSocialRepairQuoteNormalize(string $text): string
{
    if (function_exists('sanitizeForKenshi')) $t=sanitizeForKenshi($text);
    else $t=str_replace(["\u{2018}","\u{2019}","\u{201c}","\u{201d}","\u{2013}","\u{2014}","\u{2026}","\u{00a0}","\r\n","\\n","\\r"],
        ["'","'",'"','"','-','-','...',' ',"\n","\n",''],$text);
    $t=preg_replace('/[\x{2010}-\x{2015}\x{2212}\x{FE58}\x{FE63}\x{FF0D}]/u','-',$t) ?? $t;
    $t=strtr($t,["\u{201a}"=>"'","\u{201b}"=>"'","\u{2032}"=>"'","\u{ff07}"=>"'","\u{201e}"=>'"',"\u{201f}"=>'"',"\u{2033}"=>'"',"\u{ff02}"=>'"']);
    $t=preg_replace('/[\p{Z}\s]+/u',' ',$t) ?? $t;
    $t=trim($t);
    return function_exists('mb_strtolower') ? mb_strtolower($t,'UTF-8') : strtolower($t);
}

function stobeSocialRepairQuoteMatches(string $quote, string $message, string $speaker): bool
{
    $core=stobeSocialRepairQuoteNormalize(stobeSocialRepairQuoteCore($message,$speaker));
    return $core!=='' && stobeSocialRepairQuoteNormalize(stobeSocialRepairQuoteCore($quote,$speaker))===$core;
}

function stobeSocialRepairNpcQuoteInReply(string $npcQuote, string $reply): bool
{
    $q=stobeSocialRepairQuoteNormalize($npcQuote);
    return $q!=='' && strpos(stobeSocialRepairQuoteNormalize($reply),$q)!==false;
}
'''
s = s.replace(A1, new)
s = s.replace(A2, "|| !stobeSocialRepairNpcQuoteInReply($update['npc_quote'],strval($meta['response_message'] ?? ''))) continue;")
out = s.replace('\n', '\r\n') if crlf else s
open(p, 'wb').write(out.encode('utf-8'))
t = open(os.path.join(here, TEST), 'rb').read().decode('utf-8').replace('\r\n', '\n')
open(os.path.join(root, 'tests', TEST), 'wb').write((t.replace('\n', '\r\n') if crlf else t).encode('utf-8'))
print('applied')
