#!/usr/bin/env python3
"""unblockcheck_14d.py <ROW 14-d> <evidence-dir>   verdict for row IMM-14-d (ClearGroup for a hostile group of exactly 5; the distant 6th bandit untouched), evidence from unblockdefs_14d.sh.
SETUP-FAIL (with the cause named, never a FAIL of the feature) when the scene is bad:
  * spawn: fewer bandits than ordered; senses: the NPC does not see the bandits; probe: the native set lists fewer than 5 serials (agreedTargets n of 5) - then the
    ACTIVITY_CLEARGROUP_MEMBER lines are read per member: selected / visible / protected + protReason / pathExists and the NC22 diag ownerSerial= slaveState= chained= prison=
    ("lane DLL older than NC22" when a line has no ownerSerial= key; "owned_target with slaveState=0 chained=0 prison=0" = the ownership rule still misfires).
FAIL / PASS (real behaviour), all must hold:
  offer           the NPC's new record is a ClearGroup (not Hunt / ProvenWild), status proposed, agreedTargets == the 5 near serials, the distant bandit(s) not in it
  no_attack_early no attack-order line in the stobe.log between the ask and the accept (atk_pre.txt)
  accept          after "Yes, let's do it." the record is accepted / completed (not proposed / absent); exactly ONE accepted row (outbox revision with status accepted; falls back to
                  'one new ClearGroup record, status past proposed' when the outbox envelope carries no status)
  set_only        no attack/act line names a distant bandit serial; no `outside_fixed_hostile_set` / `target_outside_fixed_agreement` refusal of a NEAR member is hidden; at least one
                  real effect on the set (an attack line naming a near serial, a near bandit no longer alive, or record completed)
  distant_6th     every distant bandit is still alive (listed by `chars ... !dead`) and is in no attack line
Always printed in the evidence: the phrase asked and the kind the model returned (so a numeric-count reading of "5" is visible), the member diag per serial.
`unblockcheck_14d.py --has <ROW>` exits 0 for 14-d (pywrap_u14d.sh). One RESULT line, exit 0/1/2 as rowcheck.py."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402

V, rd = rc.V, rc.rd


def serials(text):
    return set(re.findall(r'#?(\d{5,10})/\d+', text or ''))


def read_bandits(ev):
    t = rd(ev, 'bandits.txt') or ''
    near = far = ''
    for ln in t.splitlines():
        if ln.startswith('NEAR '):
            near = ln[5:]
        elif ln.startswith('FAR '):
            far = ln[4:]
    return serials(near), serials(far)


def kv(line):
    return dict(re.findall(r'(\w+)=(\S+)', line))


def member_diag(ev):
    """{serial: (name, kvdict)} - the LAST ACTIVITY_CLEARGROUP_MEMBER line of each member in cleargroup_member_lines.txt (or the ask/round dumps)"""
    out = {}
    txt = (rd(ev, 'cleargroup_member_lines.txt') or '') + '\n' + (rd(ev, 'cl_ask.txt') or '')
    for ln in txt.splitlines():
        if 'ACTIVITY_CLEARGROUP_MEMBER' not in ln:
            continue
        d = kv(ln)
        m = re.search(r'name=(.*?) set=', ln)
        if d.get('serial'):
            out[d['serial']] = (m.group(1) if m else d['serial'], d, ln)
    return out


def member_cause(name, d):
    """one short named cause for a member that is not selected"""
    has_owner = 'ownerSerial' in d
    own = ' ownerSerial=%s slaveState=%s chained=%s prison=%s' % (d.get('ownerSerial', '?'), d.get('slaveState', '?'), d.get('chained', '?'), d.get('prison', '?')) if has_owner else ' (no ownerSerial= in the line: lane DLL older than NC22, need NC30/NC31)'
    if d.get('protected') == '1':
        r = d.get('protReason', '') or 'unnamed'
        extra = ''
        if r == 'owned_target' and has_owner and d.get('slaveState') == '0' and d.get('chained') == '0' and d.get('prison') == '0':
            extra = ' [owner handle alone: the NC22 corroboration rule should not protect this - DLL older than NC22 or the rule still misfires]'
        elif r == 'owned_target' and not has_owner:
            extra = ' [pre-NC22 rule: getMySlaveOwner().serial != 0]'
        return '%s protected(%s)%s%s' % (name, r, own, extra)
    if d.get('visible') == '0':
        return '%s not_visible (flicker; senses said sees=1)%s' % (name, own)
    if d.get('hostile') == '0':
        return '%s not_hostile' % name
    for k in ('active', 'dead', 'ko', 'finite'):
        if (k in ('dead', 'ko') and d.get(k) == '1') or (k in ('active', 'finite') and d.get(k) == '0'):
            return '%s %s=%s' % (name, k, d.get(k))
    if d.get('pathExists', '1') not in ('1',):
        return '%s pathExists=%s' % (name, d.get('pathExists'))
    return '%s selected=0 (no flag named)%s' % (name, own)


def scene_cause(ev, text):
    """SETUP-FAIL message from scene.txt SCENE-BAD (+ member diag read)"""
    bad = [ln for ln in text.splitlines() if ln.startswith('SCENE-BAD')]
    msg = bad[0] if bad else 'SCENE-BAD'
    if 'agreedTargets' in msg:
        md = member_diag(ev)
        causes = []
        sel = 0
        for s, (name, d, _ln) in md.items():
            if d.get('selected') == '1':
                sel += 1
            else:
                causes.append(member_cause(name, d))
        sets = [ln for ln in (rd(ev, 'set_probe.txt') or '').splitlines() if ln.strip()]
        msg += ' | rounds: ' + ' ; '.join(sets)[:160]
        if md:
            msg += ' | members selected=%d of %d; not selected: %s' % (sel, len(md), ' ; '.join(causes) if causes else 'none (all selected, prompt set smaller than the native set)')
        else:
            msg += ' | no ACTIVITY_CLEARGROUP_MEMBER line at all (lane DLL lacks the diag, or the ask never reached the native scan)'
    return msg[:900]


def parse_recs(t):
    out = []
    for ln in (t or '').splitlines():
        p = ln.split('|', 5)
        if len(p) >= 6:
            out.append(dict(id=p[0], rev=p[1], status=p[2], kind=p[3], cand=p[4], targets=set(re.findall(r'\d{5,10}', p[5]))))
        elif len(p) >= 4:
            out.append(dict(id=p[0], rev=p[1], status=p[2], kind=p[3], cand='', targets=set()))
    return out


def check(v, ev):
    scene = rd(ev, 'scene.txt')
    if scene is None:
        v.setup_fail('no scene.txt (the row script did not run to the scene; see run.log)')
        return
    near, far = read_bandits(ev)
    if 'SCENE-BAD' in scene:
        v.setup_fail(scene_cause(ev, scene))
        return
    if 'SCENE-OK' not in scene:
        v.setup_fail('scene.txt has no SCENE-OK/SCENE-BAD (row script stopped early; run.log)')
        return
    if len(near) != 5 or not far:
        v.setup_fail('bandits.txt does not hold 5 near + >=1 distant serials (near=%d far=%d)' % (len(near), len(far)))
        return
    ask = (rd(ev, 's1', 'utterance.txt') or '').strip()
    recs = parse_recs(rd(ev, 'rec_ask.txt'))
    reply = rc.first_reply(ev, 's1')[:140]
    if not recs:
        v.ck('offer_clearGroup_record', False, 'no new activity record after %r; NPC said %r' % (ask, reply))
        return
    r0 = recs[0]
    v.good.append('R~ asked %r -> kind=%s status=%s agreed=%d serials; reply=%r' % (ask, r0['kind'], r0['status'], len(r0['targets']), reply))
    v.ck('offer_is_ClearGroup', r0['kind'] == 'ClearGroup', 'kind=%s status=%s' % (r0['kind'], r0['status']))
    v.ck('offer_proposed', r0['status'] == 'proposed', r0['status'])
    v.ck('offer_set_is_the_5_near', r0['targets'] == near, 'record=%s expected=%s' % (sorted(r0['targets']), sorted(near)))
    v.ck('offer_set_excludes_distant', not (r0['targets'] & far), sorted(r0['targets'] & far))
    pre = [ln for ln in (rd(ev, 'atk_pre.txt') or '').splitlines() if ln.strip()]
    v.ck('no_attack_before_acceptance', not pre, '%d line(s) %s' % (len(pre), pre[0][:160] if pre else ''))
    if r0['kind'] != 'ClearGroup' or r0['status'] != 'proposed':
        return
    final = parse_recs(rd(ev, 'rec_final.txt'))
    if not final:
        v.ck('accept_record_after_yes', False, 'no record after %r (rec_final.txt empty)' % (rd(ev, 's2', 'utterance.txt') or '').strip())
        return
    f0 = final[0]
    v.ck('accept_moved_past_proposed', f0['status'] in ('accepted', 'completed'), 'status=%s' % f0['status'])
    ob = rd(ev, 'outbox_rows.txt') or ''
    rows = [ln for ln in ob.splitlines() if '|' in ln]
    acc = [ln for ln in rows if re.search(r'"status"\s*:\s*"accepted"', ln)]
    if rows and acc:
        v.ck('exactly_one_accepted_row', len(acc) == 1, 'outbox accepted rows=%d of %d' % (len(acc), len(rows)))
    else:
        v.ck('exactly_one_accepted_row', len(final) == 1 and f0['status'] in ('accepted', 'completed'), 'via record (outbox envelope has no status; rows=%d, new records=%d)' % (len(rows), len(final)))
    atk = [ln for ln in (rd(ev, 'atk_post.txt') or '').splitlines() if ln.strip()]
    act = [ln for ln in (rd(ev, 'act_lines.txt') or '').splitlines() if ln.strip()]
    alltxt = '\n'.join(atk + act)
    hit_far = sorted(s for s in far if s in alltxt)
    v.ck('distant_6th_not_targeted', not hit_far, hit_far)
    refused = [ln[:200] for ln in act if re.search(r'outside_fixed_hostile_set|target_outside_fixed_agreement', ln) and any(s in ln for s in near)]
    v.ck('no_set_member_refused_as_outside', not refused, refused[:1])
    alive = serials(rd(ev, 'chars_after.txt') or '')
    gone = sorted(s for s in near if s not in alive)
    hit_near = sorted(s for s in near if s in '\n'.join(atk))
    effect = bool(hit_near) or bool(gone) or f0['status'] == 'completed'
    v.ck('effect_on_the_set', effect, 'attack lines naming near=%d, near not alive=%d, record=%s' % (len(hit_near), len(gone), f0['status']))
    v.ck('distant_6th_alive', all(s in alive for s in far), 'distant=%s alive=%s' % (sorted(far), sorted(s for s in far if s in alive)))


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if rc.norm(argv[2]) == '14-d' else 1
    if len(argv) < 3 or rc.norm(argv[1]) != '14-d':
        print('usage: unblockcheck_14d.py <ROW 14-d> <evidence-dir>', file=sys.stderr)
        return 2
    v = V(argv[1])
    check(v, argv[2])
    if v.note:
        v.good.append(v.note)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
