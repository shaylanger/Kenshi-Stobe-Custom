#!/usr/bin/env python3
"""m31 batch P REL scenario fixes (setup, not product; assertions kept or tightened).

p7-04: the lockpick order was never carried out (Izumi's slave state never moved in 180 s; batch O: same scenario,
  progress within 10 s). Setup check first (the game's lockpick chance > 0), then wait 60 s for progress (chains off,
  or Stobe's new "EVENT_SCAN: liberation task" line for the freer), else give the order once more (kah @any with
  @log-wait alternatives, harness 660a994).
p7-05: same order guard; lockpicking 100 set here too (was inherited from p7-04); the last check looked Rel Nima up
  by a handle the game had replaced 25 s after he left the cage (#706909184/5 gone): look him up by name (or the old
  handle, or his original name) and require that he is not in the squad ([Nameless]), as the header says.
p4-03 (SR19 sub-check): the second bandit came from `chars 60` around the first squad member (Full-Base: Avarek's
  squad leader is not next to Shay->Beaks: none found) and the base's only cage held Kade. Now the handle the spawn
  prints, next to Malzin, a cage built for him (unbuilt after), cage/uncage replies checked, and the "placed" line
  with no actor (unknown captor) required.
rel-enslaved.sh koslavers: KO isn't visible to `chars` while paused, so every pass re-knocked the same 40 nearest
  guards ("awake left: 38"): run one second of game time between passes.

usage: python3 m31-rel-scenarios.py <server tree root>   (asserts anchors; refuses to apply twice)
"""
import sys

root = sys.argv[1].rstrip('/') + '/tests/social_relationship/ingame/'
L = r'D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log'


def patch(name, pairs):
    p = root + name
    s = open(p, encoding='utf-8').read()
    if 'm31' in s:
        sys.exit('already applied: ' + name)
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, (name, n, old[:70])
        s = s.replace(old, new)
    open(p, 'w', encoding='utf-8').write(s)
    print('patched', name)


def order_guard(free, target, tname, freer):
    return (
        "# m31 (batch P: the order was never carried out, the slave state never moved): setup check, then progress\n"
        "#   (chains off, or Stobe's 'liberation task' line for the freer) within 60 s, else the order once more\n"
        "chance ${%s} lockpick ${%s} ~ lockpick_chance=(0\\.0*[1-9]|[1-9])\n"
        "order ${%s} PICK_LOCK_ON_SHACKLES target ${%s}\n"
        "speed 2\n"
        "@any @log-wait 60 %s ~ (slave state serial=\\d+ name=%s chained=1->0|liberation task serial=\\d+ name=%s task=) "
        "|| order ${%s} PICK_LOCK_ON_SHACKLES target ${%s}\n" % (free, target, free, target, L, tname, freer, free, target))


patch('REL-p7-04-enslaved-real-liberator.txt', [
    ("order ${FREE} PICK_LOCK_ON_SHACKLES target ${SLAVE}\nspeed 2\n", order_guard('FREE', 'SLAVE', '__SLAVE__', '__FREE__')),
])

patch('REL-p7-05-enslaved-free-recruit.txt', [
    ("protect ${FREE} on\n", "protect ${FREE} on\nsetstat ${FREE} lockpicking 100\n"),
    ("order ${FREE} PICK_LOCK_ON_SHACKLES target ${NS}\nspeed 2\n", order_guard('FREE', 'NS', 'Rel Nima', '__FREE__')),
    ("where ${NS2} ~ .", "# m31 (batch P): a while after leaving the cage the game re-creates him under a new handle (#706909184/5 gone\n"
     "#   25 s after the ask): by name, else the old handle, else his original name; never in the squad\n"
     "@any where \"Rel Nima\" ~ \\[(?!Nameless\\])[^\\]]+\\] pos= || where ${NS2} ~ \\[(?!Nameless\\])[^\\]]+\\] pos= "
     "|| where \"${NSNAME}\" ~ \\[(?!Nameless\\])[^\\]]+\\] pos="),
    ("@set NS where \"__NS__\" ~ (#\\d+/\\d+)\n",
     "@set NS where \"__NS__\" ~ (#\\d+/\\d+)\n@set NSNAME where ${NS} ~ ^(.+?) #\\d+\n"),
])

patch('REL-p4-03-carry-to-cage.txt', [
    ("""spawn "Hungry Bandit" Drifters near Shay dist 15 count 1 ~ spawned 1/1
@set U chars 60 ~ Hungry Bandit\\]? (#\\d+/\\d+)
setname ${U} "Rel Ulf" ~ ^([^ ].* \\[)?Hungry Bandit\\]? -> 
@set UNAME where ${U} ~ ^(.+?) #\\d+
cage ${U}
speed 1
@sleep 6
speed 0
uncage ${U}""",
     """# m31 (Full-Base batch P: `chars 60` is centred on the first squad member, no bandit found; the only cage held Kade):
#   the handle the spawn prints, next to Malzin, in a cage built for him (unbuilt after); unknown captor = actor #0
@set U spawn "Hungry Bandit" Drifters near Malzin dist 15 count 1 ~ spawned 1/1 .*?(#\\d+/\\d+)
@set U_S where ${U} ~ (#\\d+)/\\d+
setname ${U} "Rel Ulf" ~ ^([^ ].* \\[)?Hungry Bandit\\]? -> 
@set UNAME where ${U} ~ ^(.+?) #\\d+
build "Prisoner Cage" near ${U} dist 6 ~ ^built Prisoner Cage
cage ${U} "Prisoner Cage" ~ cage Prisoner Cage \\(
speed 1
@log-wait 30 %s ~ SOCIAL_CAPTURE: structured kind=placed seq=\\d+ load=\\d+ actor=#0 target=${U_S} witnesses=\\d+ facts="place":"prison"
speed 0
uncage ${U} "Prisoner Cage" ~ uncage Prisoner Cage \\(
unbuild "Prisoner Cage" 1000 ~ ^destroyed""" % L),
])

patch('rel-enslaved.sh', [
    ("""    [ -s "$O/slavers-$1.todo" ] || break
    while read -r h; do stobe-auto ko "$h" 1500 >> "$O/guards.txt" 2>&1; n=$((n + 1)); done < "$O/slavers-$1.todo"
""",
     """    [ -s "$O/slavers-$1.todo" ] || break
    while read -r h; do stobe-auto ko "$h" 1500 >> "$O/guards.txt" 2>&1; n=$((n + 1)); done < "$O/slavers-$1.todo"
    # m31: a KO shows in `chars` only after a frame (paused, every pass re-knocked the same nearest 40): 1 s of time
    stobe-auto speed 1 >/dev/null; sleep 1; stobe-auto speed 0 >/dev/null
"""),
])
