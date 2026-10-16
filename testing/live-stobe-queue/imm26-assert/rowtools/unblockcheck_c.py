#!/usr/bin/env python3
"""unblockcheck_c.py <ROW> <evidence-dir>   verdict for the unblock rows 15-bx 20-a 10-b (imm26-u-rowsC).  `--has <ROW>` exits 0 for these rows.
ONE line on stdout: `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [evidence=<dir>]` (exit 0/1/2/3, same shape as rowcheck.py / hxcheck.py).
Nothing here loosens an assert: scene problems are SETUP-FAIL (never PASS) and every product check keeps its original threshold.
  15-bx  1. scene validation from the files unblockdefs_c.sh wrote (Malzin not a fighter, >=2 fighters, starter is one of them, X >= 250 u in distance.txt,
            P <= 15 u, S1 <= 100 u): a violation = SETUP-FAIL naming it.  2. hxcheck.py 15-bx (assert_witness.py 15-bx ...) = the verdict, unchanged;
            the line is extended with what the SERVER did (how many X samples got a [combat] line naming the fighters, eyewitness phrases) so a FAIL on a clean
            scene names the server behaviour ("witnesses > 277 u get fight events" is a separate server bug).
  20-a   stock rowcheck.py 20-a is the verdict; when it is not PASS and the confirm turns were refused because Shay was in combat or the NPC answered with a
            drawn-weapon reaction, the result becomes SETUP-FAIL (scene), with the quoted line.
  10-b   effects_c.txt (component|delta|observer|culprit|game_ts) + aff_end.txt + transfer_log.txt + inbox_transfer.txt: harm < 0; exactly ONE apology_relief <= +2;
            the gift leg really credited (a `gift` row) - a missing gift row is classified (squad pair = exempt, food = meal-judged, not captured) and is a
            SETUP-FAIL with the cause, else FAIL; cap: repair sum <= 25% of recorded harm - 1; victim affinity still negative."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROWS = ('15-bx', '20-a', '10-b')
CODES = {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}


def norm(row):
    return re.sub(r'^IMM-', '', row)


def rd(*parts):
    f = os.path.join(*parts)
    return open(f, encoding='utf-8', errors='replace').read() if os.path.isfile(f) else ''


def out(row, kind, text, ev):
    print(f'RESULT {row} {kind} {text[:1500]} [evidence={ev}]')
    return CODES[kind]


def last_result(text):
    line = ''
    for ln in (text or '').splitlines():
        if re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\b', ln):
            line = ln
    return line


# ------------------------------------------------------------------------------------------------ 15-bx
def dist_entries(d):
    res = []
    for ln in rd(d, 'distance.txt').splitlines():
        p = ln.split('|')
        if len(p) >= 2:
            try:
                res.append((p[0].strip(), float(p[1])))
            except ValueError:
                pass
    return res


def check_15bx(row, ev):
    bd = rd(ev, 'bundle_dir.txt').strip() or ev
    labs = [f'X{i}' for i in (1, 2, 3)] + [f'P{i}' for i in (1, 2, 3)] + ['S1']
    missing = [d for d in labs if not os.path.isdir(os.path.join(bd, d))]
    if missing:
        return out(row, 'SETUP-FAIL', f'bundle dirs missing under {bd}: {",".join(missing)} (the row script stopped early; see run.log)', ev)
    fighters = [f.strip() for f in rd(bd, 'fighters.txt').strip().split(',') if f.strip()]
    starter = rd(bd, 'starter.txt').strip()
    bad = []
    if len(set(f.lower() for f in fighters)) < 2:
        bad.append(f'fighters.txt has <2 names ({fighters})')
    if any(f.lower() == 'malzin' for f in fighters):
        bad.append('Malzin is in the fighter roster')
    if starter.lower() not in [f.lower() for f in fighters]:
        bad.append(f'starter "{starter}" is not one of the fighters {fighters}')
    fl = [f.lower() for f in fighters]
    for x in ('X1', 'X2', 'X3'):
        far = [v for k, v in dist_entries(os.path.join(bd, x)) if k.lower() not in fl]
        if not far or min(far) < 250:
            bad.append(f'{x} distance {far[:2]} < 250')
    for p in ('P1', 'P2', 'P3'):
        near = [v for k, v in dist_entries(os.path.join(bd, p)) if k.lower() not in fl]
        if not near or min(near) > 15:
            bad.append(f'{p} distance {near[:2]} > 15')
    s1 = [v for k, v in dist_entries(os.path.join(bd, 'S1')) if k.lower() not in fl]
    if not s1 or max(s1) > 100:
        bad.append(f'S1 distance {s1[:2]} > 100')
    if bad:
        return out(row, 'SETUP-FAIL', 'scene invalid (no behaviour verdict): ' + '; '.join(bad), ev)
    # the server side facts for the report line
    combat = []
    for x in ('X1', 'X2', 'X3'):
        pr = rd(bd, x, 'prompt.txt')
        n = sum(1 for ln in pr.splitlines() if re.search(r'\[combat[^\]]*\]', ln) and any(f in ln.lower() for f in fl))
        combat.append(n)
    argv = [sys.executable, '-u', os.path.join(HERE, 'hxcheck.py'), '15-bx', ev]
    p = subprocess.run(argv, capture_output=True, text=True, env=os.environ.copy())
    line = last_result(p.stdout)
    if not line:
        return out(row, 'FAIL', f'hxcheck.py produced no RESULT line (rc={p.returncode}): {((p.stderr or "").strip().splitlines() or ["no output"])[-1][:200]}', ev)
    m = re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\s*(.*?)(\s*\[evidence=.*\])?$', line)
    kind, rest = m.group(1), m.group(2)
    extra = f' | SERVER X combat lines naming the fighters per sample={combat} fighters={",".join(fighters)} starter={starter}'
    if kind == 'FAIL' and any(combat):
        extra += ' (a clean scene: the out-of-range witness still got fight events = the separate server bug "witnesses > 277 u get fight events")'
    return out(row, kind, rest + extra, ev)


# ------------------------------------------------------------------------------------------------ 20-a
DRAWN = re.compile(r"already swung|swung at me|put (that|the|your) (blade|weapon|machete|sword|steel) (away|down)|sheathe|drawn weapon|draw(n|ing)? (a|your) (weapon|blade|sword)", re.I)
COMBAT = re.compile(r'"?in_?combat"?\s*[:=]\s*(true|1)\b', re.I)


def check_20a(row, ev):
    py = sys.executable
    p = subprocess.run([py, '-u', os.environ.get('UB_ROWCHECK') or os.path.join(HERE, 'rowcheck.py'), '20-a', ev], capture_output=True, text=True)   # UB_ROWCHECK: selftest stub
    line = last_result(p.stdout)
    if not line:
        return out(row, 'FAIL', f'rowcheck.py produced no RESULT line (rc={p.returncode}): {((p.stderr or "").strip().splitlines() or ["no output"])[-1][:200]}', ev)
    m = re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\s*(.*?)(\s*\[evidence=.*\])?$', line)
    kind, rest = m.group(1), m.group(2)
    notes = []
    combat_tags = [t for t in ('pre', 's3', 's4', 's4b') if COMBAT.search(rd(ev, f'calm_{t}.txt'))]
    if combat_tags:
        notes.append('Shay in_combat at ' + ','.join(combat_tags))
    refused = ''
    for s in ('s4', 's4b'):
        for ln in rd(ev, s, 'reply.txt').splitlines():
            if '(NPC)' in ln and DRAWN.search(ln):
                refused = f'{s}: {ln.strip()[:160]}'
    if refused:
        notes.append('drawn-weapon reaction in the confirm turn: ' + refused)
    if kind != 'PASS' and notes:
        return out(row, 'SETUP-FAIL', 'scene not calm (not a product verdict): ' + '; '.join(notes) + f' | stock verdict was: {kind} {rest}', ev)
    return out(row, kind, rest + (' | calm: ' + '; '.join(notes) if notes else ' | calm: Shay sheathed, not in combat'), ev)


# ------------------------------------------------------------------------------------------------ 10-b
REPAIR = {'apology_relief', 'restitution_relief', 'property_returned', 'treated_relief', 'deal_forgiveness', 'grudge_fade',
          'gift', 'favorable_trade', 'generous_trade', 'exceptional_trade'}


def aff_of(text):
    for pat in (r'"after":.*"Shay":\{"aff":(-?\d+)', r'"before":.*"Shay":\{"aff":(-?\d+)', r'"aff":\s*(-?\d+)'):
        v = re.findall(pat, text)
        if v:
            return int(v[-1])
    return None


def truthy(s):
    return str(s).strip().lower() in ('t', 'true', '1')


def check_10b(row, ev):
    victim = rd(ev, 'victim.txt').strip()
    if not victim:
        return out(row, 'SETUP-FAIL', 'victim.txt missing (the row script stopped early; see run.log)', ev)
    short = victim.split()[0].lower()
    eff = rd(ev, 'effects_c.txt')
    if not eff.strip() and not os.path.isfile(os.path.join(ev, 'effects_c.txt')):
        return out(row, 'SETUP-FAIL', 'effects_c.txt missing (the row script stopped before the gift leg; see run.log)', ev)
    rows = []
    for ln in eff.splitlines():
        p = ln.split('|')
        if len(p) >= 5:
            try:
                rows.append((p[0].strip(), float(p[1]), p[2].strip().lower(), p[3].strip().lower()))
            except ValueError:
                pass
    mine = [r for r in rows if short in r[2] and 'shay' in r[3]] or rows
    harm = sum(r[1] for r in mine if r[1] < 0)
    apology = [r for r in mine if r[0] == 'apology_relief']
    gifts = [r for r in mine if r[0] == 'gift']
    repair = sum(r[1] for r in mine if r[0] in REPAIR and r[1] > 0)
    item = rd(ev, 'gift.txt').strip()
    tlog, inbox = rd(ev, 'transfer_log.txt'), rd(ev, 'inbox_transfer.txt')
    captured = 'item_transfer' in tlog or bool([ln for ln in inbox.splitlines() if ln.count('|') >= 6])
    aff = aff_of(rd(ev, 'aff_end.txt'))
    checks, setup = [], []
    if harm >= 0:
        setup.append(f'no harm row for {victim} (harm={harm}; the KO recipe did not register: harm.txt)')
    if len(apology) != 1:
        setup.append(f'apology half: {len(apology)} apology_relief rows, expected exactly 1 (10-a dependency; replies in s1)')
    if not gifts:
        cause = 'unknown'
        first = next((ln.split('|') for ln in inbox.splitlines() if ln.count('|') >= 6), None)
        if not captured:
            cause = 'the harness transfer produced no item_transfer capture at all'
        elif first and truthy(first[1]) and truthy(first[3]):
            cause = f'both {first[0]} and {first[2]} are player-faction characters: a gift between squad mates is exempt by design (use a non-squad --victim)'
        elif first and first[4].strip() not in ('', '{}', '[]', 'null'):
            cause = f'the item is FOOD ({first[4][:60]}): food gifts are only judged at the next meal (use a non-food --gift)'
        elif first and first[5].strip() not in ('', '{}', '[]', 'null'):
            cause = f'the item is flagged stolen ({first[5][:60]})'
        if cause != 'unknown':
            setup.append(f'gift leg not exercised: {cause}')
        else:
            checks.append(('gift_row_present', False, f'captured transfer of "{item}" but no gift effect after the poll and the cause is not squad/food/stolen'))
    if setup:
        return out(row, 'SETUP-FAIL', '; '.join(setup) + f' | harm={harm:g} repair={repair:g} item="{item}"', ev)
    cap = 0.25 * abs(harm) - 1
    checks.append(('apology_relief<=2', 0 < apology[0][1] <= 2, f'{apology[0][1]:g}'))
    checks.append(('repair_sum<=25%harm-1', repair <= cap, f'repair={repair:g} cap={cap:.1f} harm={harm:g}'))
    checks.append(('affinity_still_negative', aff is not None and aff < 0, f'aff={aff}'))
    if gifts:
        checks.append(('gift_row_present', True, f'gift {gifts[0][1]:g}'))
    bad = [f'{n} ({d})' for n, ok, d in checks if not ok]
    summary = f'harm={harm:g} repair={repair:g} (apology {apology[0][1]:g}, gift {sum(g[1] for g in gifts):g}) cap={cap:.1f} aff={aff} item="{item}" victim={victim}'
    if bad:
        return out(row, 'FAIL', 'FAILED checks: ' + '; '.join(bad) + ' | ' + summary, ev)
    return out(row, 'PASS', f'{len(checks)} checks pass | ' + summary, ev)


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if norm(argv[2]) in ROWS else 1
    if len(argv) < 3 or norm(argv[1]) not in ROWS:
        print(f'usage: unblockcheck_c.py <ROW> <evidence-dir>   rows: {" ".join(ROWS)}', file=sys.stderr)
        return 2
    row, ev = argv[1], argv[2]
    return {'15-bx': check_15bx, '20-a': check_20a, '10-b': check_10b}[norm(row)](row, ev)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
