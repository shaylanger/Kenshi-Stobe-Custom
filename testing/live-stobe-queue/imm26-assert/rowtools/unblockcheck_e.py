#!/usr/bin/env python3
"""unblockcheck_e.py <ROW> <evidence-dir>   verdict for row 10-b after the imm26-sfD2 recipe (unblockdefs_e.sh).  `--has <ROW>` exits 0 for 10-b only.
Same thresholds and output shape as unblockcheck_c.check_10b (nothing loosened); fixes and additions (imm26-sfD / sfD2):
  - the transfer row is the inbox row whose ITEMS column holds the gift item (gift.txt) and whose actor is not in the player faction, not simply the newest
    row (the old pick took `Shay|true|Cind|false|{"bread": 1}` and misreported FOOD);
  - a missing harm row whose worker line (interp.txt) says `no_encounter` is a SETUP-FAIL naming that cause (the attack order did not open an encounter);
  - a missing gift row whose judged line (judged.txt) says `deal_payment` is a SETUP-FAIL naming the inDeal() defect (deploy pending-fixes/imm26-sfD/inDeal-terminal.py).
Other rows are not handled here (use unblockcheck_c.py)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import unblockcheck_c as c  # noqa: E402

rd, out, truthy, REPAIR, aff_of, norm = c.rd, c.out, c.truthy, c.REPAIR, c.aff_of, c.norm


def pick_transfer(inbox, item):
    """-> (row fields or None, matched_by_item). Row = actor|actor_in_pf|target|target_in_pf|food|stolen|items."""
    rows = [ln.split('|') for ln in inbox.splitlines() if ln.count('|') >= 6]
    want = (item or '').strip().lower()
    if want:
        hit = [r for r in rows if want in r[-1].lower()]
        nonsquad = [r for r in hit if not truthy(r[1])]
        if nonsquad:
            return nonsquad[0], True
        if hit:
            return hit[0], True
    return (rows[0] if rows else None), False


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
    interp, judged = rd(ev, 'interp.txt'), rd(ev, 'judged.txt')
    first, by_item = pick_transfer(inbox, item)
    captured = 'item_transfer' in tlog or first is not None
    aff = aff_of(rd(ev, 'aff_end.txt'))
    checks, setup = [], []
    if harm >= 0:
        why = ' (worker judged the harm event `no_encounter`: the attack order before the hits did not open an encounter; attack.txt, interp.txt)' \
            if 'no_encounter' in interp else ''
        setup.append(f'no harm row for {victim} (harm={harm}; the KO recipe did not register: harm.txt){why}')
    if len(apology) != 1:
        setup.append(f'apology half: {len(apology)} apology_relief rows, expected exactly 1 (10-a dependency; replies in s1)')
    if not gifts:
        cause = 'unknown'
        if not captured:
            cause = 'the harness transfer produced no item_transfer capture at all'
        elif 'deal_payment' in judged:
            cause = ('the worker judged the transfer `deal_payment`: the victim is "in a deal" because a CANCELLED/EXPIRED contract with resolved_at NULL keeps '
                     'social_property.php inDeal() true (deploy pending-fixes/imm26-sfD/inDeal-terminal.py, or the recipe\'s deal cleanup did not run: deal_fix.txt)')
        elif first and truthy(first[1]) and truthy(first[3]):
            cause = f'both {first[0]} and {first[2]} are player-faction characters: a gift between squad mates is exempt by design (use a non-squad --victim)'
        elif first and by_item and first[4].strip() not in ('', '{}', '[]', 'null'):
            cause = f'the item is FOOD ({first[4][:60]}): food gifts are only judged at the next meal (use a non-food --gift)'
        elif first and by_item and first[5].strip() not in ('', '{}', '[]', 'null'):
            cause = f'the item is flagged stolen ({first[5][:60]})'
        elif first and not by_item:
            cause = f'the inbox has no item_transfer row holding "{item}" (newest row: {"|".join(first)[:100]})'
        if cause != 'unknown':
            setup.append(f'gift leg not exercised: {cause}')
        else:
            checks.append(('gift_row_present', False, f'captured transfer of "{item}" but no gift effect after the poll and the cause is not squad/food/stolen/deal'))
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
        return 0 if norm(argv[2]) == '10-b' else 1
    if len(argv) < 3 or norm(argv[1]) != '10-b':
        print('usage: unblockcheck_e.py <ROW> <evidence-dir>   rows: 10-b', file=sys.stderr)
        return 2
    return check_10b(argv[1], argv[2])


if __name__ == '__main__':
    sys.exit(main(sys.argv))
