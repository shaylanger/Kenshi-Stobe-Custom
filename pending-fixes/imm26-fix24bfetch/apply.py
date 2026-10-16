#!/usr/bin/env python3
"""apply.py <server-tree-root>   (imm26 fix24bfetch; SERVER ONLY; follow-up to pending-fixes/imm26-fixR2serial (commit d17dae65); lane/compose copy, never the live tree)

DEFECT (row 24-b, 4080-i4op17 + coordinator confirm from 5090-i3op26 after d17dae65 was applied to the i3 lane site):
stobeAreaGoalReadCurrentTrip (lib/area_goal_integration.php) read the pair's latest travel_agreement with PostgresDB::fetchOne() and treated
`$row===false` as a read failure. fetchOne() (lib/postgresql.class.php:90) is `pg_fetch_assoc($result)`, which is FALSE when the query returned no row, and it
also returns false when the query failed. So a pair with no earlier travel_agreement row (the normal first region offer) was reported as a failed read and the
reply was the fixed "I understand the area, but I can't verify our current trip or route yet." The offline fixture DBs returned null for no row, so every
existing suite passed.

FIX (one edit): the query becomes an always-one-row scalar subquery
    SELECT (SELECT data FROM eventlog WHERE ... LIMIT 1) AS data
which returns exactly one row on success (data NULL = no trip). Then false can only mean a failed query and stays a read failure (fail closed). A row whose
data is NULL is the empty trip (state null); fixture adapters that return null for no row are still the empty trip; every present row goes through the
unchanged validation (shape, key prefix, JSON, stobeAreaGoalTripStateValid). The query keeps `type='travel_agreement'` and the $1/$2 parameter order.

ORDER: anchors touch only the fetchOne statement and the `if ($row!==null)` line, which fixR2serial does not edit, so this applies before or after
fixR2serial (tested both orders). All edits anchored, idempotent (ALREADY-APPLIED), a missing anchor exits 3 without writing anything.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NEW_FILES = ['tests/imm26_fix24bfetch_regression.php']
EDITS = []


def edit(path, old, new, marker):
    EDITS.append((path, old, new, marker))


edit('lib/area_goal_integration.php',
     "        $row=$GLOBALS['db']->fetchOne(\"SELECT data FROM eventlog WHERE type='travel_agreement' AND gamets <= $2\n"
     "            AND LEFT(data,LENGTH($1))=$1 ORDER BY gamets DESC,rowid DESC LIMIT 1\",[$key,$gamets]);\n"
     "        $state=null;\n"
     "        // This adapter's no-row sentinel is null. false, scalars, malformed\n"
     "        // rows and unknown records are read failures, never an empty trip.\n"
     "        if ($row!==null) {\n",
     "        // imm26 fix24bfetch: PostgresDB::fetchOne() (pg_fetch_assoc) returns false for \"no row\" AND for a failed query, so a plain SELECT cannot tell an\n"
     "        // empty trip from a DB error. The scalar subquery yields exactly one row on success (data NULL = no trip); false therefore can only be a failure.\n"
     "        $row=$GLOBALS['db']->fetchOne(\"SELECT (SELECT data FROM eventlog WHERE type='travel_agreement' AND gamets <= $2\n"
     "            AND LEFT(data,LENGTH($1))=$1 ORDER BY gamets DESC,rowid DESC LIMIT 1) AS data\",[$key,$gamets]);\n"
     "        $state=null;\n"
     "        // NULL data (or a fixture adapter's null) is the empty trip. false, scalars, malformed\n"
     "        // rows and unknown records are read failures, never an empty trip.\n"
     "        if (is_array($row) && array_key_exists('data',$row) && $row['data']===null) $row=null;\n"
     "        if ($row!==null) {\n",
     "imm26 fix24bfetch: PostgresDB::fetchOne()")


def main():
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        print('usage: apply.py <server-tree-root>', file=sys.stderr)
        return 2
    root = sys.argv[1]
    plan = []
    for rel in NEW_FILES:
        src = os.path.join(HERE, 'files', rel)
        if not os.path.isfile(src):
            print('MISSING source file', src, file=sys.stderr)
            return 3
        plan.append(('new', rel, open(src, 'rb').read()))
    texts = {}
    for path, old, new, marker in EDITS:
        full = os.path.join(root, path)
        if not os.path.isfile(full):
            print('MISSING target', full, file=sys.stderr)
            return 3
        text = texts.get(path)
        if text is None:
            text = open(full, 'rb').read().decode('utf-8')
        if marker in text:
            print('ALREADY-APPLIED', path, '::', marker[:50].replace('\n', ' '))
        else:
            n = text.count(old)
            if n != 1:
                print('ANCHOR %s (%d matches) in %s: %r' % ('MISSING' if n == 0 else 'AMBIGUOUS', n, path, old[:90]), file=sys.stderr)
                return 3
            text = text.replace(old, new)
            print('APPLIED', path, '::', marker[:50].replace('\n', ' '))
        texts[path] = text
    for path, text in texts.items():
        full = os.path.join(root, path)
        data = text.encode('utf-8')
        if open(full, 'rb').read() != data:
            open(full, 'wb').write(data)
    for kind, rel, data in plan:
        full = os.path.join(root, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        if os.path.isfile(full) and open(full, 'rb').read() == data:
            print('ALREADY-APPLIED', rel)
        else:
            open(full, 'wb').write(data)
            print('WROTE', rel)
    return 0


if __name__ == '__main__':
    sys.exit(main())
