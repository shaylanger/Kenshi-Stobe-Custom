#!/usr/bin/env python3
"""fix23a_selftest.py (imm26-fix23acheck): OFFLINE test of the 23-a option-A checker (rowcheck_trip.py c_23a: completion acknowledgement counted per LLM reply
= per request_id, plus the following-turn no-re-acknowledgement check). Fixtures: fix23a_fixtures/v1 and v2b = the REAL rows 23-a-v1 / 23-a-v2b (5090-i3, 2026-10-16)
with the real output_to_plugin.log lines of the completion turn (s3/plugin_out.txt). Prints `SELFTEST fix23a-<name> PASS|FAIL` and `SELFTEST FIX23A ALL PASS|FAIL n/m`.
Usage: python3 fix23a_selftest.py [path-to-rowcheck_trip.py]   (default: rowcheck_trip.py if it already has the new checker, else rowcheck_trip.py.candidate23a)
No game, lane, ssh or server is touched."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, 'fix23a_fixtures')
ROOT = os.path.dirname(HERE)           # imm26-assert (imm26_lib.py)


def pick_src():
    if len(sys.argv) > 1:
        return sys.argv[1]
    live = os.path.join(HERE, 'rowcheck_trip.py')
    return live if 'reply_groups' in open(live, encoding='utf-8').read() else live + '.candidate23a'


def rd(p):
    return open(p, encoding='utf-8', errors='replace').read()


def wr(p, t):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding='utf-8', newline='').write(t)


class Rig:
    """a throw-away copy of rowcheck.py + imm26_lib.py + one (possibly mutated) rowcheck_trip.py"""

    def __init__(self, src_text):
        self.t = tempfile.mkdtemp(prefix='fix23a_')
        os.makedirs(os.path.join(self.t, 'rowtools'))
        shutil.copy(os.path.join(ROOT, 'imm26_lib.py'), self.t)
        shutil.copy(os.path.join(HERE, 'rowcheck.py'), os.path.join(self.t, 'rowtools'))
        wr(os.path.join(self.t, 'rowtools', 'rowcheck_trip.py'), src_text)
        self.n = 0

    def run(self, ev):
        r = subprocess.run([sys.executable, os.path.join(self.t, 'rowtools', 'rowcheck.py'), '23-a', ev], capture_output=True, text=True,
                           env=dict(os.environ, PYTHONPATH=''))
        line = [ln for ln in r.stdout.splitlines() if ln.startswith('RESULT 23-a ')]
        return (line[0] if line else 'NO-RESULT ' + r.stderr[-300:])

    def ev(self, base, edit=None):
        """copy fixture <base> into a fresh evidence dir; edit(dir) may change it"""
        self.n += 1
        d = os.path.join(self.t, f'ev{self.n}')
        shutil.copytree(os.path.join(FIX, base), d)
        if edit:
            edit(d)
        return d


def s3_lines(d, step='s3'):
    return [ln for ln in rd(os.path.join(d, step, 'reply.txt')).splitlines() if 'ACTION_EXEC: SAY [Cind' in ln]


def add_s4(*texts, ts='2026-10-16 19:00:00'):
    def f(d):
        body = '[%s.100] [Stobe] CHAT_SEND_STAGE: begin mode=chat\n[%s.200] [Stobe] ACTION_EXEC: SAY [Shay]: What do you make of this place? (PC)\n' % (ts, ts)
        for i, t in enumerate(texts):
            body += '[2026-10-16 19:00:%02d.300] [Stobe] ACTION_EXEC: SAY [Cind [Hungry Bandit]]: %s (NPC)\n' % (10 + i * 7, t)
        wr(os.path.join(d, 's4', 'reply.txt'), body)
    return f


def chain(*fs):
    def f(d):
        for g in fs:
            g(d)
    return f


def set_s3_times(gap_s):
    """rewrite the two NPC SAY timestamps of s3 to be gap_s apart (real gap was 6.7-7.8 s)"""
    def f(d):
        p = os.path.join(d, 's3', 'reply.txt')
        out, k = [], 0
        for ln in rd(p).splitlines(True):
            if 'ACTION_EXEC: SAY [Cind' in ln:
                ln = re.sub(r'^\[[^\]]+\]', '[2026-10-16 18:00:%06.3f]' % (10 + k * gap_s), ln); k += 1
            out.append(ln)
        wr(p, ''.join(out))
    return f


def split_request_ids(d):
    p = os.path.join(d, 's3', 'plugin_out.txt')
    ls = rd(p).splitlines()
    ls[1] = re.sub(r'"request_id":"[^"]+"', '"request_id":"req_SECOND_REPLY"', ls[1])
    wr(p, '\n'.join(ls) + '\n')


def drop_plugin(d):
    os.remove(os.path.join(d, 's3', 'plugin_out.txt'))


CLEAN = 'This place? Squin is loud, but it pays well enough for a trader.'
S3_LATE = 'If you\'ve somewhere else in mind, say it plain and I\'ll tell you whether it fits my route.'   # v2b chunk 2, spoken late into s4


def cases():
    """(name, base fixture, edit, expected-kind, must-contain-substring-or-None)"""
    pas = 'PASS'
    return [
        ('v1-real-ack-count-pass-no-s4-setup-fail', 'v1', None, 'SETUP-FAIL', 'one_completion_acknowledgement=n=1 replies from 2 SAY lines by request_id'),
        ('v2b-real-ack-count-pass-no-s4-setup-fail', 'v2b', None, 'SETUP-FAIL', 'one_completion_acknowledgement=n=1 replies from 2 SAY lines by request_id'),
        ('v1-real-plus-clean-follow-up-pass', 'v1', add_s4(CLEAN), pas, 'following_turn_no_reacknowledgement=1 line(s) clean'),
        ('v2b-real-plus-clean-follow-up-pass', 'v2b', add_s4(CLEAN, 'Mind the guards at the gate.'), pas, 'following_turn_no_reacknowledgement=2 line(s) clean'),
        ('two-separate-replies-fail', 'v1', chain(split_request_ids, add_s4(CLEAN)), 'FAIL', 'one_completion_acknowledgement=n=2'),
        ('two-separate-replies-fail-v2b', 'v2b', chain(split_request_ids, add_s4(CLEAN)), 'FAIL', 'one_completion_acknowledgement=n=2'),
        ('no-request-id-evidence-real-gap-fails-strict', 'v1', chain(drop_plugin, add_s4(CLEAN)), 'FAIL', 'only SAY lines < 2 s apart count as one reply'),
        ('window-fallback-1s-apart-is-one-reply', 'v1', chain(drop_plugin, set_s3_times(1.0), add_s4(CLEAN)), pas, 'by window'),
        ('window-fallback-3s-apart-is-two-replies', 'v1', chain(drop_plugin, set_s3_times(3.0), add_s4(CLEAN)), 'FAIL', 'one_completion_acknowledgement=n=2'),
        ('following-turn-reacknowledges-fail-1', 'v1', add_s4("Like I said, we've arrived. The leg's done."), 'FAIL', 'following_turn_no_reacknowledgement=re-acknowledged'),
        ('following-turn-reacknowledges-fail-2', 'v2b', add_s4(CLEAN, 'Arrived at last, and that is the end of the trip.'), 'FAIL', 'following_turn_no_reacknowledgement=re-acknowledged'),
        ('following-turn-reacknowledges-fail-3', 'v2b', add_s4('We made it here, so the guide work is finished.'), 'FAIL', 'following_turn_no_reacknowledgement'),
        ('following-turn-has-only-late-s3-chunk-setup-fail', 'v2b', add_s4(S3_LATE), 'SETUP-FAIL', 'no NPC reply in the following turn'),
        ('late-s3-chunk-is-not-a-reack', 'v2b', add_s4(S3_LATE, CLEAN), pas, 'following_turn_no_reacknowledgement=1 line(s) clean'),
        ('following-turn-file-without-npc-line-setup-fail', 'v1', lambda d: wr(os.path.join(d, 's4', 'reply.txt'), '[2026-10-16 19:00:00.100] [Stobe] CHAT_SEND_STAGE: begin mode=chat\n'), 'SETUP-FAIL', 'no NPC reply in the following turn'),
        ('other-checks-unweakened-agreement-not-completed', 'v1', chain(add_s4(CLEAN), lambda d: wr(os.path.join(d, 'agr_final.txt'), rd(os.path.join(d, 'agr_final.txt')).replace('COMPLETED', 'FAILED'))), 'FAIL', 'agreement_COMPLETED'),
        ('missing-s4-does-not-mask-a-real-fail', 'v1', chain(lambda d: wr(os.path.join(d, 'agr_final.txt'), rd(os.path.join(d, 'agr_final.txt')).replace('COMPLETED', 'FAILED'))), 'FAIL', 'agreement_COMPLETED'),
    ]


# (label, text to find in the checker source, replacement): each must make at least one case above fail
MUTATIONS = [
    ('no-request-id-grouping', "if ('rid', rid) in keys:", 'if False:'),
    ('accept-any-reply-count', 'len(groups) == 1', 'len(groups) >= 1'),
    ('reack-regex-ignored', 'hit = [t for t in later if REACK_RE.search(t)]', 'hit = []'),
    ('missing-s4-passes', "v.setup_fail('following-turn evidence missing", "v.ck('x', True, 'following-turn evidence missing"),
    ('window-too-wide', 'SAY_WINDOW_S = 2.0', 'SAY_WINDOW_S = 20.0'),
    ('late-chunk-not-dropped', 'if _norm_txt(t) not in spoken3]', 'if True]'),
    ('empty-s4-passes', "v.setup_fail('no NPC reply in the following turn", "v.ck('x', True, 'no NPC reply in the following turn"),
]


def run_suite(src_text):
    rig = Rig(src_text)
    res = []
    for name, base, edit, kind, has in cases():
        out = rig.run(rig.ev(base, edit))
        ok = out.startswith(f'RESULT 23-a {kind} ') and (has is None or has in out)
        res.append((name, ok, out))
    shutil.rmtree(rig.t, ignore_errors=True)
    return res


def main():
    src = pick_src()
    text = rd(src)
    n = ok = 0

    def chk(name, good, detail=''):
        nonlocal n, ok
        n += 1
        ok += bool(good)
        print(f'SELFTEST fix23a-{name} {"PASS" if good else "FAIL"} {"" if good else detail[:600]}'.rstrip())
    print(f'# checker under test: {src}')
    for name, good, out in run_suite(text):
        chk(name, good, out)
    for label, old, new in MUTATIONS:
        if text.count(old) != 1:
            chk(f'mutation-{label}-anchor', False, f'anchor not found exactly once: {old!r}')
            continue
        bad = [nm for nm, good, _ in run_suite(text.replace(old, new)) if not good]
        chk(f'mutation-{label}-is-caught', bool(bad), 'mutant survived: every case still passes' if not bad else '')
    print(f'SELFTEST FIX23A ALL {"PASS" if ok == n else "FAIL"} {ok}/{n}')
    return 0 if ok == n else 1


if __name__ == '__main__':
    sys.exit(main())
