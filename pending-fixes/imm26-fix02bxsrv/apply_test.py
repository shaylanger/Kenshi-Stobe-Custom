#!/usr/bin/env python3
"""imm26 fix02bxsrv: add regression checks to tests/imm26_c1_db_regression.php (idempotent, *.bak-fix02bxsrv).
usage: python3 apply_test.py <tree-root> [--check]
Run: STOBE_DB_NAME=stobe_test php tests/imm26_c1_db_regression.php   (new 'fix02bxsrv' checks fail on the unpatched lib)."""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
TF = os.path.join(root, 'tests/imm26_c1_db_regression.php')
ANCH = "// ---- item 7 introductions ledger\n"
MARK = 'fix02bxsrv'
NEW = r'''// ---- fix02bxsrv (row 02-bx): captivity-family wording counts as voicing the slavery principle, stance phrase still required
$ENS = 'Grab the rope, he is coming with us as a slave.';
$vx = static function (string $reply) use ($abel3, $gt, $ENS): array {
    unset($GLOBALS['IMM26_PRINCIPLE_CACHE']);
    return stobeImm26PrincipleAfterReply('C1T Abel', $abel3, 'C1T Player', $ENS, $reply, $gt);
};
$r = $vx("No. I don't take captives, and I don't put rope on anybody. Not for cats, not for anybody.");
check('fix02bxsrv voiced: "I don\'t take captives, and I don\'t put rope on anybody" (p2 T3) is voiced', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("I haul cargo, I don't haul people - if you want the plain truth, that's the one line I won't cross.");
check('fix02bxsrv voiced: "I haul cargo, I don\'t haul people ... the one line I won\'t cross" (p3 T3) is voiced', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("I won't chain a prisoner for you.");
check('fix02bxsrv voiced: "I won\'t chain a prisoner" is voiced', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("I don't put shackles on people.");
check('fix02bxsrv voiced: the original profile-word path still works', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("Sure, here is the rope. Let's chain him up and haul him off.");
check('fix02bxsrv negative: a compliant reply ("sure, here is the rope") is NOT voiced', $r['voiced'] === [], $r);
$r = $vx("Rope? No. I don't do that.");
check('fix02bxsrv negative: echo + bare refusal with no family word after the stance is NOT voiced', $r['voiced'] === [], $r);
$r = $vx("I don't mind, grab the rope and the chains.");
check('fix02bxsrv negative: "I don\'t mind" + rope is NOT a stance', $r['voiced'] === [], $r);
$r = $vx("The rope is in the cart. I won't be long.");
check('fix02bxsrv negative: family word BEFORE the stance (separate sentences) is NOT voiced', $r['voiced'] === [], $r);
$r = stobeImm26PrincipleAfterReply('C1T Blank', $blank, 'C1T Player', 'Would you steal for me? Steal that purse.', "I refuse to put rope on a prisoner.", $gt);
check('fix02bxsrv unrelated principle: a slavery-family reply does not fire theft (and invents no slavery row)', $r['voiced'] === [], $r);
$defs = stobeImm26PrincipleTopics();
check('fix02bxsrv scope: only the slavery topic carries voice_extra', isset($defs['slavery']['voice_extra']) && count(array_filter($defs, static fn($d) => ($d['voice_extra'] ?? '') !== '')) === 1, array_keys(array_filter($defs, static fn($d) => ($d['voice_extra'] ?? '') !== '')));

'''
s = open(TF, encoding='utf-8', newline='').read()
if MARK in s:
    print('tests already present:', TF); sys.exit(0)
assert s.count(ANCH) == 1, 'anchor count %d' % s.count(ANCH)
if check:
    print('anchor ok:', TF); sys.exit(0)
shutil.copy2(TF, TF + '.bak-fix02bxsrv')
open(TF, 'w', encoding='utf-8', newline='').write(s.replace(ANCH, NEW + ANCH))
print('tests added:', TF)
