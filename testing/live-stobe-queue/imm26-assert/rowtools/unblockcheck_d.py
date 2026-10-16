#!/usr/bin/env python3
"""unblockcheck_d.py <ROW> <evidence-dir>   assertions for imm26 row 03-b (rumor hearsay reaches B); prints exactly ONE line
`RESULT 03-b PASS|FAIL|SETUP-FAIL|GATED <evidence>` (exit 0/1/2/3) like rowcheck.py, whose V/rd helpers it reuses. Evidence writers: unblockdefs_d.sh.
  03-b : Cind (witness W) told B (never present) in a targeted mode=autochat pair request; B holds social_rumor basis=heard_from source=Cind hops=1; the server log has
         'NPC gossip passed on' for B WITHOUT via=director (the autochat hook, bored.php:561-567); B's prompt for "Have you heard anything about me?" holds '[hearsay from Cind'.
A precondition that was not met (no sparse B, no first-hand Cind row, request failed, pair never formed in the tries) is SETUP-FAIL with `needs: ...`; never a PASS."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..'))
import rowcheck as rc  # noqa: E402

V, rd = rc.V, rc.rd


def line(ev, name):
    return (rd(ev, name) or '').strip()


def c_03b(v, ev):
    b = line(ev, 'b.txt')
    if not b or b == 'none':
        return v.setup_fail('no sparse B found (digit serial, awake, non-slave, <= 6 social_rumor rows, <= 2 about Shay) within the chars radius (needs: recipe, --b "<name>" or --max-rows, or spawn/teleport a fresh NPC next to Shay)')
    if not line(ev, 'cind_row.txt'):
        return v.setup_fail('Cind has no active first-hand social_rumor row with subject Shay after the unwitnessed attack (attack.txt): the witness path recorded nothing '
                            '(needs: recipe, check Cind sees the attack / affinity to Malzin, or rerun with --no-attack when she already has one)')
    ok = line(ev, 'gossip_ok.txt')
    tags = ', '.join('%s=%s' % (f[7:-4], line(ev, f)) for f in sorted(os.listdir(ev)) if re.fullmatch(r'gossip_g\d+\.res', f))
    if not ok:
        return v.setup_fail('the pair requests did not run (no gossip_ok.txt)')
    if ok.startswith('none'):
        if tags and all(t.endswith('=http_err') for t in tags.split(', ')):
            return v.setup_fail('every targeted pair request failed (no HTTP=200; gossip_g1.txt): %s; needs: recipe, lane backend port / stream.php / BORED_EVENT_CHANCE' % tags)
        return v.setup_fail('the pair Cind -> %s never produced a heard_from row in the tries (%s): the speaker line must name Shay and the roll/gates must pass; '
                            'needs: recipe, more --tries (the LLM is the lottery), gossip_all.txt shows the server log per try' % (b, tags))
    allog = rd(ev, 'gossip_all.txt') or ''
    gl = [ln for ln in allog.splitlines() if 'gossip passed on' in ln]
    short = b.split(' [')[0].split(' ')[0]
    for_b = [ln for ln in gl if short in ln]
    via = [ln for ln in for_b if 'via' in ln]
    plain = [ln for ln in for_b if 'via' not in ln]
    rows = [ln for ln in (rd(ev, 'hearsay_row.txt') or '').splitlines() if ln.strip()]
    src = re.compile(r'^\d+\|%s\|[^|]*\|heard_from\|Cind[^|]*\|1\|' % re.escape(b))
    v.ck('hearsay_row_holder_B_heard_from_Cind_hops1', any(src.match(r) for r in rows), (rows[0] if rows else 'none')[:160])
    v.ck('gossip_logged_for_B_by_autochat_not_director', bool(plain), 'plain=%d via_director=%d' % (len(plain), len(via)))
    pr = rd(ev, 's1', 'prompt.txt')
    if pr is None:
        return v.setup_fail('no s1/prompt.txt: the question to B was not asked (see run.log)')
    m = re.search(r'^.*\[hearsay from Cind.*$', pr, re.M)
    v.ck('prompt_shows_hearsay_attributed_to_Cind', bool(m), (m.group(0).strip()[:200] if m else 'no "[hearsay from Cind" line in s1/prompt.txt'))
    v.note = 'R~ B=%s, pair tries: %s, Cind rank: %s' % (b, tags, line(ev, 'cind_rank.txt').replace('\n', ' '))


CHECKS = {'03-b': c_03b}


def main(argv):
    if len(argv) < 3 or rc.norm(argv[1]) not in CHECKS:
        print('usage: unblockcheck_d.py <ROW> <evidence-dir>   rows: %s' % ' '.join(sorted(CHECKS)), file=sys.stderr)
        return 2
    v = V(argv[1])
    CHECKS[rc.norm(argv[1])](v, argv[2])
    if v.note:
        v.good.append(v.note)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
