#!/usr/bin/env python3
"""unblockcheck_sff.py <ROW> <evidence-dir>   03-b verdict for the sff recipe (imm26-sfFixA, forced witness line). When forced_line.txt exists (the Cind -> B line was seeded by calling the server's
gossip hook, sharehook.php) the verdict is: B holds a heard_from row (source Cind, hops 1) that the hook just created (SHARERC=0), and B's prompt for the in-game question holds '[hearsay from Cind'.
The 'autochat log line' check of unblockcheck_d.py is replaced (a direct hook call has no bored.php log line); the verdict says seed=forced-line so nobody reads it as proof that the LLM names the
subject. Without forced_line.txt (or with seed_mode llm-line) everything is unblockcheck_sfz.py unchanged. A precondition that failed is SETUP-FAIL with `needs:`, never a PASS."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import unblockcheck_sfz as sz  # noqa: E402

d = sz.d2.d
V = sz.V


def forced(ev):
    return bool(d.line(ev, 'forced_line.txt')) and d.line(ev, 'seed_mode.txt') != 'llm-line'


def diag(ev):
    raw = d.rd(ev, 'forced_line.txt') or ''
    m = re.search(r'^\{.*\}$', raw, re.M)
    try:
        return json.loads(m.group(0)) if m else {}
    except ValueError:
        return {}


def c_03b_forced(argv):
    ev = argv[2]
    v = V(argv[1])
    b = d.line(ev, 'b.txt')
    miss = d.line(ev, 'hearsay_missing.txt')
    if miss:
        v.setup_fail(miss)
        return v.emit(ev)
    if not b or b == 'none':
        v.setup_fail('no candidate B (digit serial, awake, non-slave) within the chars radius (needs: recipe, --b "<name>")')
        return v.emit(ev)
    if not d.line(ev, 'cind_row.txt'):
        v.setup_fail('Cind has no active first-hand social_rumor row with subject Shay after the unwitnessed attack (attack.txt): the witness path recorded nothing '
                     '(needs: recipe, check Cind sees the attack / affinity to Malzin, or rerun with --no-attack when she already has one)')
        return v.emit(ev)
    j = diag(ev)
    rc = (re.findall(r'SHARERC=(\d+)', d.rd(ev, 'forced_line.txt') or '') or ['?'])[-1]
    if rc != '0':
        why = {'1': 'the hook created no row: eligible=%s, eligible_named=%s, shared=%s (eligible=0: Cind has no active first-hand row learned by now / ttl; eligible_named empty: the scripted line does not name the subject; '
                    'otherwise the row already exists for B = dedupe, or the listener is the subject/victim)' % (j.get('eligible'), j.get('eligible_named'), j.get('shared')),
               '2': 'sharehook.php refused (env / args)', '3': 'sharehook.php refused: wrong database', '?': 'no SHARERC in forced_line.txt (php failed to start or crashed)'}.get(rc, 'sharehook.php rc=%s' % rc)
        v.setup_fail('forced witness line Cind -> %s did not seed hearsay (rc=%s): %s; forced_line.txt: %s; needs: recipe' % (b, rc, why, ' '.join((d.line(ev, 'forced_line.txt') or '').split())[:300]))
        return v.emit(ev)
    rows = [ln for ln in (d.rd(ev, 'hearsay_row.txt') or '').splitlines() if ln.strip()]
    src = re.compile(r'^\d+\|%s\|[^|]*\|heard_from\|Cind[^|]*\|1\|' % re.escape(b))
    v.ck('hook_created_heard_from_row_for_B', any(src.match(r) for r in rows),
         (rows[0] if rows else 'none')[:160])
    v.ck('hook_shared_to_B_from_Cind', any(str(s.get('listener', '')) == b and str(s.get('source', '')).startswith('Cind') for s in (j.get('shared') or [])), json.dumps(j.get('shared'))[:160])
    pr = d.rd(ev, 's1', 'prompt.txt')
    if pr is None:
        v.setup_fail('no s1/prompt.txt: the question to B was not asked (see run.log)')
        return v.emit(ev)
    m = re.search(r'^.*\[hearsay from Cind.*$', pr, re.M)
    v.ck('prompt_shows_hearsay_attributed_to_Cind', bool(m), (m.group(0).strip()[:200] if m else 'no "[hearsay from Cind" line in s1/prompt.txt'))
    v.note = 'seed=forced-line (the server gossip hook was called for the scripted line; the LLM-names-Shay leg is NOT exercised here), R~ B=%s, Cind rank: %s' % (b, d.line(ev, 'cind_rank.txt').replace('\n', ' '))
    v.good.append(v.note)
    return v.emit(ev)


def main(argv):
    if len(argv) >= 3 and d.rc.norm(argv[1]) == '03-b' and forced(argv[2]):
        return c_03b_forced(argv)
    return sz.main(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
