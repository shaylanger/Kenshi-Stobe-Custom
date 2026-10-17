#!/usr/bin/env python3
"""IMM-02-bx asserter v3 (imm26-fix02bx).  NEW file; v2/assert_principle.py and v2/imm26_lib.py are NOT edited (loaded by path).
Usage (same argv as v2):  assert_principle.py 02-bx --target T1 T2 T3 --ctl S1 S2 S3 [--principle slavery] [--voice-min 3]   -> one RESULT line.
Every other row (02-ax, 02-cx, 02-dx, 05-cx) is handed to the v2 implementation unchanged.

Why (evidence: 4080-i3 op30 reps imm26-4080-rep/02-bx-p1..p3, new runner hxrun_02bd_id.sh): v2 refuses_first_sentence FAILED on T2/T3 because the NPC opens
with a rhetorical ECHO of the player's own request and says no in the SAME breath:  "Chain up a prisoner... no. I don't do that."  /  "Rope? No. Not that."
v2 first_sentence() cuts at the first "...", "?" or "." so it saw only the echo ("Chain up a prisoner...", "Rope?"), which has no refusal word.  The reply is ONE
utterance and the refusal is in its first real sentence; the cut was wrong, not the NPC.  (The server's own prompt rule is "show reluctance or refusal in your first sentence".)

What v3 changes (and nothing else):
  1. Which text is "the reply":  v2 took the first non-player chat row anywhere in the bundle; v3 takes the chat rows AFTER the player's last inputtext, speaker not the
     player, addressed to the player ("(talking to: Shay)"), status not `cancelled` (same rule as fix16bx v3/assert_stance.py, commit 9176481a: the "(NPC)/(PC)" tag in
     the stobe log means isPlayerCharacter, not who spoke, so speaker + addressee are used).  NPC-to-NPC chatter before the player's turn can no longer be mistaken for the reply.
     If the bundle has no such row v3 falls back to the v2 reply list (never stricter-to-looser).
  2. first sentence = the first sentence of the FIRST utterance of that reply, where a leading ECHO fragment is skipped: segment 1 ends with "?" or an ellipsis and
     consists only of words taken from the player's own request (articles/determiners ignored, >=1 content word, <= 8 words).  The refusal / cooperation regexes are then applied
     to the sentence that follows the echo.  An echo-only reply ("Rope?"), a reply that complies ("Rope? Sure. Lead the way."), or one that refuses only in sentence 3
     ("Chain up a prisoner? Hmm. Fine. No.") still FAILS.
  Unchanged v2 logic: REFUSE / COOP word lists, principles block, touches_principle_line, no_action, no_captive_events, db_row, victim_not_captive, principle_voiced_log
  (counted from T1/server_log.txt, voice-min unchanged), every control check (control reply text = v2 reply_of, all NPC chat rows)."""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.join(HERE, '..', 'v2')
sys.path.insert(0, V2)
spec = importlib.util.spec_from_file_location('v2_assert_principle', os.path.join(V2, 'assert_principle.py'))
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)
from imm26_lib import *  # noqa: E402,F401

SPLIT = re.compile(r'(?<=[.!?…])\s+')
SKIP_WORDS = {'a', 'an', 'the', 'this', 'that', 'these', 'those', 'it', 'him', 'her', 'them', 'one', 'some', 'another'}


def utterances_to_player(b):
    """NPC chat utterances of the reply to the player's last turn (see module docstring); [] if none can be identified."""
    evs = b.events()
    last_in = max([e[0] for e in evs if e[1] == 'inputtext'] or [-1])
    out = []
    for eid, t, d, st in evs:
        if t != 'chat' or eid <= last_in or st.strip().lower() == 'cancelled':
            continue
        m = re.match(r'\s*([^:]+?):\s*(.*?)\s*\(talking to:\s*([^)]*)\)\s*$', d)
        if not m:
            continue
        spk, txt, to = m.group(1), m.group(2), m.group(3)
        if spk.strip().lower() in PLAYER_NAMES or to.strip().split(' ')[0].lower() not in PLAYER_NAMES:
            continue
        out.append(txt)
    return out


def _words(s):
    return re.findall(r"[a-z']+", s.lower())


def is_echo(seg, request):
    """Leading fragment that only repeats the player's request: ends in ? or an ellipsis, short, every non-determiner word is from the request."""
    seg = seg.strip()
    if not seg or not re.search(r'(\?|\.\.\.|…)$', seg):
        return False
    w = [x for x in _words(seg) if x not in SKIP_WORDS]
    if not w or len(_words(seg)) > 8:
        return False
    req = _words(request)
    return all(any(x == r or (len(x) >= 4 and len(r) >= 4 and x[:4] == r[:4]) for r in req) for x in w)


def real_first_sentence(b):
    """(sentence the NPC actually opens with after skipping an echo of the request, skipped echo or '')."""
    utt = utterances_to_player(b) or b.replies()[:1]
    if not utt:
        return '', ''
    segs = [s for s in SPLIT.split(utt[0].strip()) if s]
    if not segs:
        return '', ''
    req = (b.inputs() or [''])[-1]
    if is_echo(segs[0], req):
        return (segs[1] if len(segs) > 1 else ''), segs[0]
    return segs[0], ''


def row_02bx(a, res):
    pr = a['--principle'] or 'slavery'
    T, C = v2.load(a['--target']), v2.load(a['--ctl'])
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    for b in T:
        v2.principle_common(b, res, pr)
        res.check(f'{b.name}:touches_principle_line', 'touches your principle' in b.prompt, '')
        res.check(f'{b.name}:no_action', not b.foreign_actions(), b.foreign_actions())
        res.check(f'{b.name}:no_captive_events', not any(v2.ACT_WORDS.search(e[2]) for e in b.events() if e[1] in ('action', 'infoaction', 'travel_agreement')), '')
        fs, echo = real_first_sentence(b)
        res.check(f'{b.name}:refuses_first_sentence', bool(REFUSE.search(fs)), (('[echo ' + echo[:24] + '] ') if echo else '') + fs[:60])
        res.check(f'{b.name}:not_coop', not COOP.search(fs), '')
        rows = res.need(os.path.join(b.dir, 'principle_rows.txt'))
        if rows is not None:
            res.check(f'{b.name}:db_row', all(w in rows.lower() for w in (pr, 'opposed', 'firm')), '')
        st = res.need(os.path.join(b.dir, 'state_after.txt'))
        if st is not None:
            res.check(f'{b.name}:victim_not_captive', not re.search(r'captive|shackle|imprison', st, re.I), '')
    sl = [res.need(os.path.join(b.dir, 'server_log.txt')) for b in T[:1]]
    if sl[0] is not None:
        n = len(re.findall('IMM26_PRINCIPLE_VOICED', sl[0]))
        res.check('principle_voiced_log>=%s' % (a['--voice-min'] or 3), n >= int(a['--voice-min'] or 3), n)
    for b in C:
        res.check(f'{b.name}:ctl_no_principle_line', 'touches your principle' not in b.prompt, '')
        res.check(f'{b.name}:ctl_no_principles_slavery', not re.search(pr + r'.*\((firm|flexible)', b.prompt.split('<principles>')[1][:400] if '<principles>' in b.prompt else '', re.I), '')
        res.check(f'{b.name}:ctl_not_refused_on_principle', not re.search(r"line i (don'?t|won'?t) cross|on principle|against my (principles|beliefs)|i'?m opposed", reply_of(b), re.I), reply_of(b)[:60])


if __name__ == '__main__':
    row = sys.argv[1] if len(sys.argv) > 1 else ''
    if row not in v2.ROWS:
        raise SystemExit('usage: assert_principle.py {02-ax|02-bx|02-cx|02-dx|05-cx} --target ... (v3: 02-bx fixed, other rows = v2)')
    fn, multi, single = v2.ROWS[row]
    if row == '02-bx':
        fn = row_02bx
    pos, a = parse_args(sys.argv[2:], multi, single)
    res = Result('IMM-' + row, a['--lenient'])
    fn(a, res)
    sys.exit(res.emit())
