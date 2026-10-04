#!/usr/bin/env python3
"""m23 fixer 8: rel-m18 scenario fixes for batch E (SR09, SR06, SR13/SR14). Test files only.

- p3-06 (SR09): the name must have stuck (Stobe rename race, fixed in Stobe m23-rename-guard: assert ^Rel Wren);
  W is put next to the body right before the take and the game stays paused 5 s after it (the Stobe sweep runs while
  paused) so the take's witness list is taken with W 3 m away (batch E: seq=10919 witnesses=0, W ran 27 -> 169 m).
- p2-01 (SR06): TNAME must be "Rel Vorn" (batch E: Stobe renamed him to "Skethis 2 [Hungry Bandit]", p2-04b found nobody).
- p5-03 (SR13): the greeting left Tess in FOLLOW_WHILE_TALKING during the theft (crime: targeting_him FOLLOW_WHILE_TALKING):
  she gets an IDLE order before the drop; the detection check accepts the theft dialog event (Stobe m23-theft-dialog)
  as well as the HUNT_MY_THIEF line. rel-m18.sh counts both.

Usage: python3 m23-rel-m18.py <StobeServer tree root>   (marker M23_F8_REL)
"""
import pathlib, sys

MARK = 'M23_F8_REL'
root = pathlib.Path(sys.argv[1])
D = root / 'tests/social_relationship/ingame'


def patch(name, pairs):
    p = D / name
    s = p.read_text()
    if MARK in s:
        print('already', name); return
    for old, new in pairs:
        c = s.count(old)
        if c != 1:
            raise SystemExit(f'{name}: anchor found {c}x: {old[:90]!r}')
        s = s.replace(old, new, 1)
    p.write_text(s)
    print('patched', name)


patch('REL-p3-06-ko-loot-witnessed.txt', [
    ('@set WNAME where ${W} ~ ^(.+?) #\\d+',
     '# M23_F8_REL: the name must stick (batch E: Stobe renamed her back to "Skenn 2 [Hungry Bandit]")\n'
     '@set WNAME where ${W} ~ ^(Rel Wren) #\\d+'),
    ('transfer ${V} Malzin "Iron Plates"\nspeed 1\n@sleep 20\n',
     '# M23_F8_REL: W 3 m from the body at the take; paused 5 s so the sweep (runs while paused) lists her before she walks off\n'
     'teleport ${W} ${V} dist 3\n'
     'transfer ${V} Malzin "Iron Plates"\n@sleep 5\nwhere ${W}\nspeed 1\n@sleep 15\n'),
])
patch('REL-p2-01-player-first-strike.txt', [
    ('@set TNAME where ${BANDIT} ~ ^(.+?) #\\d+',
     '# M23_F8_REL: the name must stick (batch E: Stobe renamed him to "Skethis 2 [Hungry Bandit]", p2-04b lost him)\n'
     '@set TNAME where ${BANDIT} ~ ^(Rel Vorn) #\\d+'),
])
patch('REL-p5-03-theft-owned-seen.txt', [
    ('teleport ${O} Shay dist 4\ndrop ${O}',
     '# M23_F8_REL: end the greeting\'s FOLLOW_WHILE_TALKING so her own theft reaction can run\n'
     'order ${O} IDLE\n'
     'teleport ${O} Shay dist 4\ndrop ${O}'),
    ('~ SOCIAL_CAPTURE: theft hunt hunter=.* thief=Shay',
     '~ SOCIAL_CAPTURE: theft (hunt hunter|dialog ev)=.* thief=Shay'),
])
patch('rel-m18.sh', [
    ('grep -a "theft hunt\\|kind=theft_caught\\|kind=item_gain" $L | tail -8 > "$O/p5-03.stobe.txt"',
     '# M23_F8_REL: the game\'s theft dialog event (Stobe m23) counts like HUNT_MY_THIEF\n'
     'grep -a "theft hunt\\|theft dialog\\|kind=theft_caught\\|kind=item_gain" $L | tail -8 > "$O/p5-03.stobe.txt"'),
    ("(hunt lines: $(grep -c 'theft hunt' \"$O/p5-03.stobe.txt\"))",
     "(hunt/dialog lines: $(grep -c 'theft hunt\\|theft dialog' \"$O/p5-03.stobe.txt\"))"),
])
