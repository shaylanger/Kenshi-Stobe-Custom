#!/usr/bin/env python3
"""m22 fixer 7: REL rel-m18 setup fixes (fixer 6 diagnosis). Test files only, no server/DLL code.

- rel-m18.sh fresh(<row>): after the load wait for Stobe's NPC event sweep (stobe_ready from
  tests/ingame/stobe/stobe-ready.sh: last "heavy sync pipeline complete" after the last "world transition detected");
  a timeout is a SETUP FAIL with the reason (was: fixed sleep 8, the sweep came 45 s after the last transition, so the
  drop/pickup/KO/sever events of the first ~1-2 min were only baselined).
- p5-03/p5-04: owner in Nomads (Drifters is "not a real faction": BountyManager::setCrime refuses it, no HUNT_MY_THIEF);
  @sleep 8 after the drop so the pickup is an item_gain (pending loss expired), not an in-sweep transfer from the owner.
- p2-01: @log-wait (harness fc53dba) for the knockout harm line instead of racing the 3 s sweep.
- p7-01c: `state` is no harness command -> `where`.
- p3-05b: Shay attacks again right before the cut (recent-attacker window 10 s); @log-wait for limb_loss + maiming.
- p3-06 (SR09): W stands next to the body from the start; positions logged before the take; W must be in the take's
  witness list with sees_actor (the m22 run had only Shay as witness, so no known_thief).

Usage: python3 m22-rel-m18-setup.py <StobeServer tree root>   (marker M22_F7_READY)
"""
import pathlib, sys

MARK = 'M22_F7_READY'
root = pathlib.Path(sys.argv[1])
D = root / 'tests/social_relationship/ingame'
LOG = r'D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log'


def patch(name, pairs):
    p = D / name
    s = p.read_text()
    for old, new, n in pairs:
        c = s.count(old)
        if c < n:
            raise SystemExit(f'{name}: anchor found {c}x (need {n}): {old[:90]!r}')
        if n == 1 and c != 1:
            raise SystemExit(f'{name}: anchor found {c}x (need exactly 1): {old[:90]!r}')
        s = s.replace(old, new, 1)
    p.write_text(s)
    print('patched', name)


if MARK in (D / 'rel-m18.sh').read_text():
    raise SystemExit('already applied')

# --- wrapper ---
shadow = 'insp --set-mode shadow >/dev/null; fresh\n'
patch('rel-m18.sh', [
    ('mkdir -p "$O"\n',
     'mkdir -p "$O"\n'
     '# ' + MARK + ': stobe_ready / stobe_log_lines (bounded poll for the Stobe NPC event sweep after a load)\n'
     'source /mnt/c/KenshiModding/tests/ingame/stobe/stobe-ready.sh || { echo "VERDICT rel-m18: SETUP FAIL no stobe-ready.sh"; exit 4; }\n', 1),
    ('fresh(){ stobe-auto load auto-home >/dev/null; sleep 12; stobe-auto wait-world 240 >/dev/null; sleep 8; }\n',
     '# fresh <row>: load auto-home, wait for the world, then for Stobe\'s NPC event sweep (it starts 45 s after the last\n'
     '# world transition: events before that are only baselined, m22). Not ready in 150 s = SETUP FAIL for <row>.\n'
     'fresh(){ local b; b=$(stobe_log_lines)\n'
     '  stobe-auto load auto-home >/dev/null; sleep 12; stobe-auto wait-world 240 >/dev/null\n'
     '  stobe_ready 150 "$b" || { v "$1: SETUP FAIL $STOBE_READY_WHY"; exit 4; }; }\n', 1),
    (shadow, 'insp --set-mode shadow >/dev/null; fresh "SR13 seen"\n', 5),
    (shadow, 'insp --set-mode shadow >/dev/null; fresh "SR13 unseen"\n', 4),
    (shadow, 'insp --set-mode shadow >/dev/null; fresh SR09\n', 3),
    (shadow, 'insp --set-mode shadow >/dev/null; fresh SR07\n', 2),
    (shadow, 'insp --set-mode shadow >/dev/null; fresh SR06\n', 1),
    ('insp --set-mode enabled >/dev/null; fresh\n', 'insp --set-mode enabled >/dev/null; fresh SR30\n', 1),
])

# --- SR13/SR14 theft: a real faction, and the pickup after the drop's pending loss expired ---
for name, comment in (('REL-p5-03-theft-owned-seen.txt', True), ('REL-p5-04-theft-owned-unseen.txt', False)):
    pairs = [
        ('spawn "Hungry Bandit" Drifters near Shay dist 10 count 1 ~ spawned 1/1\n',
         '# m22: Nomads, not Drifters: Drifters is "not a real faction" (FCS), BountyManager::setCrime refuses it and the game\n'
         '# never treats taking their goods as a crime (no HUNT_MY_THIEF, crime commit set=0)\n'
         'spawn "Hungry Bandit" Nomads near Shay dist 10 count 1 ~ spawned 1/1\n', 1),
        ('drop ${O} "Iron Plates" owned ~ owner_faction=Drifters\n',
         'drop ${O} "Iron Plates" owned ~ owner_faction=Nomads\n'
         '# m22: let the owner\'s pending loss expire (6 s) so the pickup is an item_gain, not an in-sweep transfer from him\n'
         '@sleep 8\n', 1),
    ]
    if comment:
        pairs.append(('# run m11: Malzin/Shay attack test Drifters otherwise\n',
                      '# run m11: Malzin/Shay attack the test faction otherwise\n', 1))
    patch(name, pairs)

# --- SR06: poll for the knockout harm line (the 3 s sweep logged it ~1 s after the old @log looked) ---
harm = ('@log ' + LOG + ' ~ SOCIAL_CAPTURE: structured kind=harm seq=\\d+ load=\\d+ actor=#\\d+ target=${BANDIT_S} witnesses=\\d+ '
        'facts="level":"knockout","attribution":"(defeated_by|attacker_list|recent_attacker)"\n')
attack = '@log ' + LOG + ' ~ SOCIAL_CAPTURE: structured kind=attack seq=\\d+ load=\\d+ actor=${SHAY_S} target=${BANDIT_S}\n'
patch('REL-p2-01-player-first-strike.txt', [
    ('@until 20 where ${BANDIT} ~ KO\nspeed 0\n' + attack + harm,
     '@until 20 where ${BANDIT} ~ KO\n'
     '# m22: the knockout harm comes from the 3 s world sweep: poll for it while the game runs (harness fc53dba @log-wait)\n'
     '@log-wait 15 ' + harm[len('@log '):] +
     'speed 0\n' + attack, 1),
])

# --- SR30 trusted: no `state` command ---
patch('REL-p7-01c-recruit-forced-trusted.txt', [('\nstate ${R}\n', '\nwhere ${R}\n', 1)])

# --- SR07: the cut within the 10 s recent-attacker window of Shay's attack ---
old07 = ('attack Shay ${L}\nspeed 1\n@sleep 4\nspeed 0\n'
         '# the arm is cut off while he is in Shay\'s attacker list (attribution attacker_list / recent_attacker); KAH 20 sever\n'
         'sever ${L} left_arm\nhp ${L} ~ .\nspeed 1\n@sleep 5\nspeed 0\n'
         '@log ' + LOG + ' ~ \\[EVENT\\] limb_loss: \n'
         '@log ' + LOG + ' ~ SOCIAL_CAPTURE: structured kind=harm seq=\\d+ load=\\d+ actor=${SHAY_S} target=${L_S} witnesses=\\d+ facts="level":"maiming"\n')
new07 = ('attack Shay ${L}\nspeed 1\n@sleep 4\nspeed 0\n'
         '# m22: recent_attacker counts Shay\'s attacks of the last 10 s (m22: the cut came 10.7 s after): attack again right\n'
         '# before the cut and poll for the sweep\'s limb_loss/maiming lines instead of fixed sleeps\n'
         'attack Shay ${L}\nspeed 1\n@sleep 1\nspeed 0\n'
         '# the arm is cut off while he is in Shay\'s attacker list (attribution attacker_list / recent_attacker); KAH 20 sever\n'
         'sever ${L} left_arm\nhp ${L} ~ .\nspeed 1\n'
         '@log-wait 10 ' + LOG + ' ~ \\[EVENT\\] limb_loss: \n'
         '@log-wait 5 ' + LOG + ' ~ SOCIAL_CAPTURE: structured kind=harm seq=\\d+ load=\\d+ actor=${SHAY_S} target=${L_S} witnesses=\\d+ facts="level":"maiming"\n'
         'speed 0\n')
patch('REL-p3-05b-defensive-limb-loss-sever.txt', [
    (old07, new07, 1),
    ('# needs: harness 08AB6BF0+ (protect);', '# needs: harness 08AB6BF0+ (protect), kah.py fc53dba+ (@log-wait);', 1),
])

# --- SR09: W next to the body all along, and must be in the take's witness list ---
patch('REL-p3-06-ko-loot-witnessed.txt', [
    ('protect ${W} on\nrelation ${W} 60\n',
     'protect ${W} on\nrelation ${W} 60\n'
     '# m22: the take\'s witness list had only Shay (W was not within 40 m of the body when the sweep saw the take):\n'
     '# W stands next to the body from here on, and is put back right before the take\n'
     'teleport ${W} ${V} dist 4\n', 1),
    ('transfer ${V} Malzin "Iron Plates"\n',
     'where ${W}\nwhere ${V}\nwhere Malzin\n'
     'transfer ${V} Malzin "Iron Plates"\n', 1),
    ('speed 0\n@log ' + LOG + ' ~ SOCIAL_CAPTURE: structured kind=item_(gain|transfer) seq=\\d+ load=\\d+ actor=${MALZIN_S} .*witnesses=[1-9]\n',
     'speed 0\nwhere ${W}\n@log ' + LOG + ' ~ SOCIAL_CAPTURE: structured kind=item_(gain|transfer) seq=\\d+ load=\\d+ actor=${MALZIN_S} .*witnesses=[1-9]\n'
     '# m22: W (not just Shay) must be a conscious witness who saw Malzin take it (server witnessedTaker -> known_thief)\n'
     '@log ' + LOG + ' ~ SOCIAL_CAPTURE: structured kind=item_(gain|transfer) seq=\\d+ load=\\d+ actor=${MALZIN_S} .*"name":"${WNAME}"[^}]*\\},"conscious":true,"perceived":true,"sees_actor":true\n', 1),
])
print('done', MARK)
