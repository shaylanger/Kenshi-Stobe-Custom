#!/usr/bin/env python3
"""sfxcheck.py <ROW 12-d> <evidence-dir>   verdict for 12-d v2 (imm26-sfX, fxC finding).  Reuses rowcheck.V/rd/inv/gained; rowcheck.py is NOT edited.
Evidence: s1 = aff40 ask; s2..sN = aff85 positive-control asks (each in a purged conversation, sfxdefs.sh); inv_before<k>/after<k>.txt per step.
  aff40_refused_no_transfer   hard: Shay's inventory unchanged at aff40 (a transfer = the server gate was bypassed)
  aff40_gate_log              info: `Blocked low-trust outsider` / `required_affinity` in s1 server/reply = gate exercised; absent = "not exercised" (the model refused in words)
  aff85_not_blocked_by_gate   hard: the block line must not appear in a control step (85 >= the weapon floor 70)
  aff85_transferred           an item moved NPC->Shay in some control step (PASS)
  no transfer + a control prompt still carrying a sword-ask history line  -> SETUP-FAIL contaminated (fix the purge, not the NPC)
  no transfer + clean prompts                                              -> GATED  SERVER-GATE-PASS ... LLM-DECLINED (never FAIL; numeric gate proven offline W2/W3)
Replies are taken only from lines after the step's own `CHAT_SEND_STAGE: begin` (stale lines of the previous step are counted, not shown as this step's reply)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rowcheck as rc  # noqa: E402

BLOCK_RE = re.compile(r'Blocked low-trust outsider|required_affinity', re.I)
BLOCK_HARD_RE = re.compile(r'Blocked low-trust outsider', re.I)
SAY_RE = re.compile(r'ACTION_EXEC: SAY \[(.+?)\]: (.*?)(?: \((?:NPC|PC)\))?$')
HIST_RE = re.compile(r'^\s*-?\s*Shay, speaking to [^:\n]+: [^\n]*sword', re.I | re.M)


def step_nums(ev):
    return sorted(int(d[1:]) for d in os.listdir(ev) if re.fullmatch(r's\d+', d) and os.path.isdir(os.path.join(ev, d)))


def npc_says(lines):
    out = []
    for ln in lines:
        m = SAY_RE.search(ln.strip())
        if m and m.group(1).strip() != 'Shay':
            out.append(m.group(2).strip())
    return out


def own_reply(ev, k):
    """(first NPC line after this step's own CHAT_SEND_STAGE: begin, number of NPC lines before it)"""
    lines = (rc.rd(ev, f's{k}', 'reply.txt') or '').splitlines()
    b = next((i for i, ln in enumerate(lines) if 'CHAT_SEND_STAGE: begin' in ln), None)
    if b is None:
        return (npc_says(lines) or [''])[0], 0
    return (npc_says(lines[b:]) or [''])[0], len(npc_says(lines[:b]))


def c_12d(v, ev):
    ks = step_nums(ev)
    if not rc.need(v, ev, 's1/reply.txt', 'inv_before1.txt', 'inv_after1.txt'):
        return
    ctl = [k for k in ks if k >= 2]
    if not ctl:
        v.setup_fail('no positive-control step (s2..) in the evidence dir')
        return
    b1, a1 = rc.inv(ev, 'before1'), rc.inv(ev, 'after1')
    v.ck('aff40_refused_no_transfer', b1 == a1 and bool(b1), 'unchanged' if b1 == a1 else f'gained {rc.gained(b1, a1, "SHAY")}')
    s1txt = (rc.rd(ev, 's1', 'server.txt') or '') + (rc.rd(ev, 's1', 'reply.txt') or '')
    m = BLOCK_RE.search(s1txt)
    v.ck('aff40_gate_log', True, f'exercised ({m.group(0)})' if m else 'not exercised (model refused in words; numeric gate proven offline imm26_wpW W2/W3)')
    transfer, blocked, contam, replies = None, [], [], {}
    for k in ctl:
        if not os.path.isfile(os.path.join(ev, f'inv_after{k}.txt')) or not os.path.isfile(os.path.join(ev, f'inv_before{k}.txt')):
            v.ck(f'file:inv_after{k}.txt', False, 'missing')
            continue
        g = rc.gained(rc.inv(ev, f'before{k}'), rc.inv(ev, f'after{k}'), 'SHAY')
        sv = (rc.rd(ev, f's{k}', 'server.txt') or '') + (rc.rd(ev, f's{k}', 'reply.txt') or '')
        if BLOCK_HARD_RE.search(sv):
            blocked.append(k)
        if HIST_RE.search(rc.rd(ev, f's{k}', 'prompt.txt') or ''):
            contam.append(k)
        replies[k] = own_reply(ev, k)
        if g and transfer is None:
            transfer = (k, g)
    v.ck('aff85_not_blocked_by_gate', not blocked, 'no block line' if not blocked else f'gate blocked the gift at aff85 in s{blocked} (weapon floor is 70): product bug?')
    if transfer:
        v.ck('aff85_transferred', True, f's{transfer[0]} shay_gained={transfer[1]}')
    elif not v.bad:
        if contam:
            v.setup_fail(f'contaminated control: s{contam} prompt still carries a "Shay, speaking to ...: ...sword" history line (purge did not take; see purge.txt) - not an LLM verdict')
        else:
            v.gated(f'SERVER-GATE-PASS (aff40 no transfer; numeric gate proven offline W2/W3) + LLM-DECLINED (no item moved in {len(ctl)} clean aff85 ask(s) s{ctl[0]}..s{ctl[-1]}; positive control not exercisable this run)')
    ex = [f'aff40: {rc.first_reply(ev, "s1")[:80]!r}']
    for k, (r, stale) in replies.items():
        ex.append(f's{k}: {r[:90]!r}' + (f' (+{stale} stale line(s) before its own send, ignored)' if stale else ''))
    v.note = 'R~ ' + ' '.join(ex)


def main(argv):
    if len(argv) < 3 or rc.norm(argv[1]) != '12-d':
        print('usage: sfxcheck.py <ROW 12-d> <evidence-dir>', file=sys.stderr)
        return 2
    v = rc.V(argv[1])
    c_12d(v, argv[2])
    if v.note:
        v.good.append(v.note)
    return v.emit(argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
