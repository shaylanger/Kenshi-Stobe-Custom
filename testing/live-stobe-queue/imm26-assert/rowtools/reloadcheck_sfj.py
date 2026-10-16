#!/usr/bin/env python3
"""reloadcheck_sfj.py <ROW> <evidence-dir>   (imm26-sfJ) row 23-e with the corrected legacy-FOLLOW assertion; every other row (incl. 20-d) is the unchanged reloadcheck_a.py check.
Prints exactly ONE `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence>` line like reloadcheck_a.py.

23-e (reloaddefs_sfj.sh rd_23e): the old check wanted `end <= 35 u` after Shay was teleported 80 u away; the real follower keeps a stand-off of about 40-60 u (79.7 -> 57.1 -> 43.5 u).
New: a control chase (no FOLLOW order, same Shay offset) must NOT approach (end >= 0.8 x start, else SETUP-FAIL: the chase cannot discriminate); the pre-save chase must end
<= FOLLOW_NEAR (RW_FOLLOW_NEAR, default 70) and below its start (start >= MIN_START, RW_FOLLOW_MIN_START, default 90); post-load the same, plus FOLLOW_TICK lines after the load."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import reloadcheck_a as ra  # noqa: E402

rc, rd, need, chase = ra.rc, ra.rd, ra.need, ra.chase
FOLLOW_NEAR = float(os.environ.get('RW_FOLLOW_NEAR', '70'))
MIN_START = float(os.environ.get('RW_FOLLOW_MIN_START', '90'))


def _ser(ev, tag):
    s = (rd(ev, f'chase_{tag}.series') or '').strip()
    return f' series[{s}]' if s else ''


def c_23e_sj(v, ev):
    if not need(v, ev, 'follow_log_pre.txt'):
        return
    if 'FOLLOW target resolved' not in (rd(ev, 'follow_log_pre.txt') or ''):
        return v.setup_fail('native FOLLOW never started on "Follow me." (no FOLLOW target resolved; needs the NC DLL, see 23-b)')
    if not need(v, ev, 'chase_ctrl.txt', 'chase_pre.txt', 'chase_post.txt', 'follow_log_post.txt'):
        return
    c0, c1 = chase(ev, 'chase_ctrl.txt')
    if c0 is None or c0 < MIN_START:
        return v.setup_fail(f'control chase: Shay only {c0} u from the NPC after the teleport (< {MIN_START:g}); the chase cannot discriminate (needs: recipe, raise RW_AWAY_F or change RW_AWAY_DIR)')
    if c1 is None or c1 < 0.8 * c0:
        return v.setup_fail(f'NPC approaches Shay without a FOLLOW order (control {c0} -> {c1}): the chase cannot discriminate (needs: recipe){_ser(ev, "ctrl")}')
    a0, a1 = chase(ev, 'chase_pre.txt')
    if a0 is None or a0 < MIN_START or a1 is None or a1 > FOLLOW_NEAR or a1 >= a0:
        return v.setup_fail(f'follow did not work BEFORE the save (dist after teleporting Shay away {a0} -> {a1}; need start >= {MIN_START:g}, end <= {FOLLOW_NEAR:g} and < start): nothing to resume (needs: recipe){_ser(ev, "pre")}')
    b0, b1 = chase(ev, 'chase_post.txt')
    lp = rd(ev, 'follow_log_post.txt') or ''
    ticks = len(re.findall(r'FOLLOW_TICK', lp))
    v.ck('follow_ticks_after_load', ticks > 0, f'FOLLOW_TICK lines={ticks}')
    v.ck('not_expired_early', 'FOLLOW_EXPIRED' not in lp, 'FOLLOW_EXPIRED present' if 'FOLLOW_EXPIRED' in lp else 'none')
    v.ck('no_stale_hand', 'setDestination failed' not in lp, 'FOLLOW: setDestination failed' if 'setDestination failed' in lp else 'none')
    v.ck('post_load_precondition_Shay_away', b0 is not None and b0 >= MIN_START, f'dist after teleport={b0}')
    v.ck('post_load_follower_closes_distance', b1 is not None and b0 is not None and b1 <= FOLLOW_NEAR and b1 < b0, f'{b0} -> {b1} (limit {FOLLOW_NEAR:g})')
    v.note = f'R~ control {c0}->{c1}; pre-load chase {a0}->{a1}{_ser(ev, "pre")}{_ser(ev, "post")}; verdict FAIL with no ticks and a far NPC = the legacy follow is LOST on load'


ra.CHECKS['23-e'] = c_23e_sj

if __name__ == '__main__':
    sys.exit(ra.main(sys.argv))
