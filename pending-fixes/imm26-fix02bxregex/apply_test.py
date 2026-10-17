#!/usr/bin/env python3
"""imm26 fix02bxregex: add regression checks to tests/imm26_c1_db_regression.php (idempotent, *.bak-fix02bxregex).
usage: python3 apply_test.py <tree-root> [--check]   (needs fix02bxsrv tests present: uses $vx/$ENS from that block)
Run: STOBE_DB_NAME=stobe_test php tests/imm26_c1_db_regression.php"""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
TF = os.path.join(root, 'tests/imm26_c1_db_regression.php')
ANCH = "// ---- item 7 introductions ledger\n"
MARK = 'fix02bxregex'
NEW = r'''// ---- fix02bxregex (row 02-bx rep1): "not a thing I do" stance + binding-gear words (irons/manacles) count as voicing, non-principled replies still do not
$r = $vx("No. Not that - shackles, captives, that's not a thing I do. Not for cats, not for anybody.");
check('fix02bxregex voiced: op32 rep1 "shackles, captives, that\'s not a thing I do"', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("But I won't put irons on him.");
check('fix02bxregex voiced: op32 rep1 "I won\'t put irons on him"', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("Dealing in slaves, that is not something I would do, ever.");
check('fix02bxregex voiced: "that is not something I would do" + slave word', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("I do not lock manacles on anyone.");
check('fix02bxregex voiced: "I do not ... manacles"', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("I'm not going to snap fetters on a prisoner.");
check('fix02bxregex voiced: "I\'m not going to ... fetters"', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("Chains and shackles, that's not a thing I do, friend.");
check('fix02bxregex voiced: profile word before the new stance phrase', in_array('slavery', $r['voiced'], true), $r);
$r = $vx("Sure, I'll put irons on him. Hand me the chains.");
check('fix02bxregex negative: compliant "I\'ll put irons on him" is NOT voiced', $r['voiced'] === [], $r);
$r = $vx("That's not a thing I do on an empty stomach. Got any food?");
check('fix02bxregex negative: new stance phrase with no captivity word is NOT voiced', $r['voiced'] === [], $r);
$r = $vx("I don't iron clothes, I keep my irons in the fire at the forge.");
check('fix02bxregex negative: "irons" without a put/lock verb is NOT voiced', $r['voiced'] === [], $r);
$r = $vx("I do not mind putting irons on him, go ahead.");
check('fix02bxregex negative: "I do not mind" is NOT a stance for the captivity words', $r['voiced'] === [], $r);
$r = $vx("The manacles are in the cart. That's not a thing I forgot.");
check('fix02bxregex negative: binding word in a separate sentence before an unrelated stance is NOT voiced', $r['voiced'] === [], $r);
$r = stobeImm26PrincipleAfterReply('C1T Blank', $blank, 'C1T Player', 'Would you steal for me? Steal that purse.', "That's not a thing I do. I won't put irons on anyone.", $gt);
check('fix02bxregex unrelated principle: slavery-family reply does not fire theft', $r['voiced'] === [], $r);

'''
s = open(TF, encoding='utf-8', newline='').read()
if MARK in s:
    print('tests already present:', TF); sys.exit(0)
assert 'fix02bxsrv voiced' in s, 'fix02bxsrv tests must be present first'
assert s.count(ANCH) == 1, 'anchor count %d' % s.count(ANCH)
if check:
    print('anchor ok:', TF); sys.exit(0)
shutil.copy2(TF, TF + '.bak-fix02bxregex')
open(TF, 'w', encoding='utf-8', newline='').write(s.replace(ANCH, NEW + ANCH))
print('tests added:', TF)
