#!/usr/bin/env python3
"""sfrcheck.py <ROW> <evidence-dir>   verdicts for the imm26-sfR recipe-v2 rows 23-b 22-b 20-a; prints exactly ONE line
`RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [evidence=<dir>]` (exit 0/1/2/3 as rowcheck.py, whose helpers it reuses). Definitions + evidence writers: sfrdefs.sh.
  23-b : legacy FOLLOW expiry. limit_hours.txt = the limit in force (lane ini FollowExpiryGameHours or 24). Preconditions (SETUP-FAIL, never PASS): the follow started, the control
         advance stayed below the limit, the total advance reached the limit. Asserts: game_hours_ge_limit, follow_ticking, control_follow_alive_at_mid, no_expiry_before_limit
         (control), follow_ended_by_expiry (FOLLOW_EXPIRED for the follower), expired_at_or_after_limit (now_gamets - started_gamets >= limit * 3600), no_tick_after_expiry.
  22-b : arrival remark after a REAL native arrival: arrival situated_event row, exactly ONE situated_remark_claim for that event, claim for the arrival event, the silent tick says
         nothing (res nothing_claimable, no second claim). Preconditions (SETUP-FAIL): native arrival seen, at least one bored request reached the server.
  20-a : verdict = unblockcheck_c.py (-> rowcheck.py 20-a, unchanged, + the calm-scene rule). Only a NOT-PASS becomes SETUP-FAIL when a turn was sent with the NPC outside
         TalkRadius (dist_to_target > 80 u in s3/s4/s4b reply.txt): the confirm logic was not judged. A PASS stays PASS; a FAIL with the NPC in range stays FAIL.
Nothing here loosens an assertion."""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402

V, rd, need = rc.V, rc.rd, rc.need
TALK_RADIUS = 80.0


def fnum(s):
    m = re.search(r'-?\d+(?:\.\d+)?', s or '')
    return float(m.group(0)) if m else None


# ---------------------------------------------------------------- 23-b
def c_23b(v, ev):
    if not need(v, ev, 'follow_log.txt', 'limit_hours.txt'):
        return
    st = rd(ev, 'follow_log.txt')
    if 'FOLLOW target resolved' not in st:
        return v.setup_fail('no follow order after "Follow me." (no "FOLLOW target resolved" in the stobe.log slice): expiry untestable')
    if not need(v, ev, 'time0.txt', 'time_mid.txt', 'time1.txt', 'follow_log_mid.txt', 'follow_log_after.txt', 'follow_npc.txt'):
        return
    limit = fnum(rd(ev, 'limit_hours.txt'))
    if not limit or limit <= 0:
        return v.setup_fail('limit_hours.txt holds no positive limit (0 = expiry disabled): expiry untestable')
    t0, tm, t1 = (fnum(rd(ev, f)) for f in ('time0.txt', 'time_mid.txt', 'time1.txt'))
    if None in (t0, tm, t1):
        return v.setup_fail('game time unreadable in time0/time_mid/time1.txt')
    d_mid, d_all = tm - t0, t1 - t0
    ser = (re.search(r'#(\d+)', rd(ev, 'follow_npc.txt') or '') or [None, ''])[1]
    exp_re = r'FOLLOW_EXPIRED: follower=' + (re.escape(ser) if ser else r'\d+')
    mid, after = rd(ev, 'follow_log_mid.txt'), rd(ev, 'follow_log_after.txt')
    if d_mid <= 0 or d_mid >= limit:
        return v.setup_fail(f'control advance {d_mid:.2f} h is not inside (0, limit {limit:g} h): the no-early-expiry control would be vacuous (needs: recipe, smaller SR_CTRL_FRAC / chunks)')
    if d_all < limit:
        return v.setup_fail(f'game time advanced only {d_all:.2f} h < limit {limit:g} h: expiry untestable (needs: recipe, advance.txt)')
    v.ck('game_hours_ge_limit', True, f'{d_all:.2f} h >= {limit:g} h (control at {d_mid:.2f} h)')
    v.ck('follow_ticking', bool(re.search(r'FOLLOW_TICK: follower=', st + mid + after)), 'no FOLLOW_TICK line')
    v.ck('control_follow_alive_at_mid', bool(re.search(r'FOLLOW_TICK: follower=', mid)), 'no FOLLOW_TICK in the mid slice')
    v.ck('no_expiry_before_limit', not re.search(exp_re, mid), f'FOLLOW_EXPIRED already at +{d_mid:.2f} h (limit {limit:g} h)' if re.search(exp_re, mid) else f'none at +{d_mid:.2f} h')
    m = re.search(exp_re + r'\b[^\n]*started_gamets=(-?\d+) now_gamets=(-?\d+)', after)
    v.ck('follow_ended_by_expiry', bool(re.search(exp_re, after)), 'no FOLLOW_EXPIRED line for ' + (ser or 'any follower'))
    if m:
        age = int(m.group(2)) - int(m.group(1))
        v.ck('expired_at_or_after_limit', age >= limit * 3600, f'age {age} game s vs limit {int(limit * 3600)}')
    elif re.search(exp_re, after):
        v.ck('expired_at_or_after_limit', False, 'FOLLOW_EXPIRED line without started_gamets/now_gamets')
    k = re.search(r'# ticks_after_expiry=(\d+)', after)
    if k:
        v.ck('no_tick_after_expiry', int(k.group(1)) == 0, f'{k.group(1)} ticks after the expiry line')
    rest = rd(ev, 'ini_restore.txt')
    if rd(ev, 'limit_mode.txt') and 'ini=1' in rd(ev, 'limit_mode.txt') and not (rest and 'restored' in rest):
        v.note = 'WARNING lane ini NOT restored (ini_restore.txt): run sfrrun.sh --restore-ini <lane>'


# ---------------------------------------------------------------- 22-b
def rows_of(text):
    out = []
    for ln in (text or '').splitlines():
        p = ln.split('|', 2)
        if len(p) == 3 and p[0].strip().isdigit():
            m = re.search(r'\{.*\}', p[2])
            js = {}
            if m:
                try:
                    js = json.loads(m.group(0))
                except ValueError:
                    js = {}
            out.append((p[0].strip(), p[1], js, p[2]))
    return out


def ticks_of(ev):
    out = []
    for ln in (rd(ev, 'sr_ticks.txt') or '').splitlines():
        p = ln.strip().split('|')
        if len(p) >= 3:
            d = dict(x.split('=', 1) for x in p[1:] if '=' in x)
            out.append({'tag': p[0], 'res': d.get('res', ''), 'claims': int(d.get('claims', '0') or 0), 'gh': fnum(d.get('game_hours', ''))})
    return out


def c_22b(v, ev):
    if not need(v, ev, 'arrival.txt', 'sr_ticks.txt', 'sit_after_silent.txt', 'agr_final.txt'):
        return
    if 'end=TIMEOUT' in (rd(ev, 'arrival.txt') or '') or 'end=FAILED' in (rd(ev, 'arrival.txt') or ''):
        return v.setup_fail('no native arrival (arrival.txt): an arrival remark is untestable')
    ticks = ticks_of(ev)
    if not ticks:
        return v.setup_fail('no bored tick recorded (sr_ticks.txt empty)')
    if all(t['res'] == 'http_err' for t in ticks):
        return v.setup_fail('every targeted bored request failed before the server answered (bored_*.txt HTTP): the arrival event was never given a chance to be claimed')
    rows = rows_of(rd(ev, 'sit_after_silent.txt'))
    events = [(r, js) for r, t, js, _ in rows if t == 'situated_event' and js.get('kind') == 'arrival']
    claims = [(r, js) for r, t, js, _ in rows if t == 'situated_remark_claim']
    agr = (rd(ev, 'agr_final.txt') or '').strip().splitlines()
    ap = agr[0].split('|') if agr else []
    state = f'receipt status={ap[1] if len(ap) > 1 else "?"} phase={ap[2] if len(ap) > 2 else "?"}'
    v.ck('situated_event_arrival', bool(events),
         ','.join(r for r, _ in events) if events else f'none after {len(ticks)} bored requests; {state} (native receipt not ingested: needs the N1 terminal-phase context push / fresher snapshot)')
    v.ck('single_remark_claim', len(claims) == 1, f'{len(claims)} situated_remark_claim rows ({",".join(r for r, _ in claims)})')
    if events and claims:
        ids = {js.get('event_id') for _, js in events}
        v.ck('claim_is_for_the_arrival_event', any(js.get('event_id') in ids and js.get('kind') == 'arrival' for _, js in claims), ','.join(str(js.get('event_id')) for _, js in claims)[:90])
    silent = ticks[-1]
    before = ticks[-2]['claims'] if len(ticks) >= 2 else 0
    v.ck('second_tick_silent', silent['tag'] == 'tick_silent' and silent['res'] == 'nothing_claimable' and silent['claims'] == before,
         f'res={silent["res"]} claims {before}->{silent["claims"]}')
    first, gh = ticks[0]['gh'], silent['gh']
    if first is not None and gh is not None:
        v.note = f'silent tick {(gh - first) * 3600:.0f} game s after tick1 (row limit 180)'


# ---------------------------------------------------------------- 20-a
def c_20a_line(ev):
    """(code, line) of the unchanged chain; None when it produced no RESULT line"""
    p = subprocess.run([sys.executable, '-u', os.path.join(HERE, 'unblockcheck_c.py'), '20-a', ev], capture_output=True, text=True)
    line = ''
    for ln in (p.stdout or '').splitlines():
        if re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\b', ln):
            line = ln
    return line


def main(argv):
    if len(argv) < 3 or rc.norm(argv[1]) not in ('23-b', '22-b', '20-a'):
        print('usage: sfrcheck.py <23-b|22-b|20-a> <evidence-dir>', file=sys.stderr)
        return 2
    row, ev = argv[1], argv[2]
    if rc.norm(row) == '20-a':
        line = c_20a_line(ev)
        if not line:
            print(f'RESULT {row} FAIL unblockcheck_c.py produced no RESULT line [evidence={ev}]')
            return 1
        m = re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\s*(.*?)(\s*\[evidence=.*\])?$', line)
        kind, rest = m.group(1), m.group(2)
        dists = []
        for s in ('s3', 's4', 's4b'):
            for d in re.findall(r'dist_to_target=([0-9.]+)', rd(ev, s, 'reply.txt') or ''):
                dists.append((s, float(d)))
        far = [f'{s}={d:.0f}' for s, d in dists if d > TALK_RADIUS]
        info = 'dist_to_target ' + ', '.join(f'{s}={d:.0f}' for s, d in dists) if dists else 'dist_to_target unknown'
        if kind not in ('PASS', 'SETUP-FAIL') and far:
            kind, rest = 'SETUP-FAIL', f'NPC outside TalkRadius {TALK_RADIUS:g} u when a turn was sent ({", ".join(far)}): the confirm logic was not judged (needs: recipe, placement) | stock verdict was: {line.split(None, 2)[2][:300]}'
        else:
            rest = f'{rest} | {info}'
        print(f'RESULT {row} {kind} {rest[:1500]} [evidence={ev}]')
        return {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}[kind]
    v = V(row)
    {'23-b': c_23b, '22-b': c_22b}[rc.norm(row)](v, ev)
    if v.note:
        v.good.append(v.note)
    return v.emit(ev)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
