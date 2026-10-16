#!/usr/bin/env python3
"""Dev helper: generates files/tests/imm26_fix24bfetch_regression.php = fixR2serial test harness (up to bad_text) with a driver-faithful fixture DB + files/tests_tail.part.
The generated file is committed; apply.py never runs this."""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'imm26-fixR2serial', 'files', 'tests', 'imm26_regionroute_serial_regression.php')
DST = os.path.join(HERE, 'files', 'tests', 'imm26_fix24bfetch_regression.php')
TAIL = os.path.join(HERE, 'files', 'tests_tail.part')
src = open(SRC, encoding='utf-8').read().split('\n')
idx = next(i for i, l in enumerate(src) if l.startswith('function bad_text'))
text = '\n'.join(src[6:idx + 1])   # lines 1-5 are the old header comment, line 6 is the first require_once


def rep(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)


text = rep(text, "    public array $events=[]; public array $zones=[]; public array $world=[];\n",
           "    public array $events=[]; public array $zones=[]; public array $world=[]; public array $queries=[]; public bool $failTravelRead=false;\n")
text = rep(text, "        if ($type==='') return null;\n        $prefix=",
           "        if ($type==='') return null;\n        $this->queries[]=$sql;\n"
           "        // imm26 fix24bfetch: faithful to PostgresDB::fetchOne (pg_fetch_assoc): false on a failed query AND on a plain no-row SELECT;\n"
           "        // an always-one-row scalar-subquery SELECT returns ['data'=>NULL] when nothing matches.\n"
           "        if ($this->failTravelRead && $type==='travel_agreement') return false;\n        $prefix=")
text = rep(text, "        return $matches[0]??null;\n",
           "        if (preg_match('/^\\s*SELECT\\s*\\(\\s*SELECT\\s+data\\s+FROM\\s+eventlog/i',$sql)===1) return ['data'=>$matches[0]['data']??null];\n"
           "        return $matches[0]??false;\n")
header = """<?php
// imm26 fix24bfetch (row 24-b, found by 4080-i4op17 + 5090-i3op26 after fixR2serial): stobeAreaGoalReadCurrentTrip treated fetchOne()===false as a read failure,
// but PostgresDB::fetchOne() returns false for "no row" as well as for a failed query (lib/postgresql.class.php, pg_fetch_assoc). So a pair with no earlier
// travel_agreement row (the normal first region offer) always answered "I understand the area, but I can't verify our current trip or route yet."
// The older fixture DBs returned null for no row, so no offline test ever saw it. THIS file's fixture DB is faithful to the real driver:
// plain SELECT, no row -> false; failed query -> false; always-one-row scalar-subquery -> ['data'=>NULL] when empty.
// Run: php tests/imm26_fix24bfetch_regression.php   (fixture DB, no network, no live DB; harness copied from imm26_regionroute_serial_regression.php)
"""
out = header + text + open(TAIL, encoding='utf-8').read()
os.makedirs(os.path.dirname(DST), exist_ok=True)
open(DST, 'w', encoding='utf-8', newline='\n').write(out)
print('WROTE', DST, len(out))
