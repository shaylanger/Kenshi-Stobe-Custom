#!/usr/bin/env python3
"""m24 fixer 12: batch F REL fails (home save). Usage: m24-f12-rel.py <tree root>  (edits files in place: run it on a copy, then mv).
- SR13 seen / SR14 (product): the owner's own theft alarm (Stobe theft dialog EV_THIEF_CAUGHT_STEALING_FROM_ME, Rel Tess) reached
  the server 464 game s after the stolen pickup (item_gain seq 666 @515520, theft_caught seq 716 @515984 = 15 real s at 1x);
  theft_caught_window_seconds defaulted to 300 game s (~10 real s at 1x), so the catch matched nothing (hunt_open) and the
  give-back became a gift instead of property_returned. Default 900 game s (~30 real s at 1x). Regression in
  tests/social_property_regression.php (fails with 300).
- SR09 (setup): Rel Wren was teleported 3 m from the body while paused and the take happened at once: her senses were stale
  (sees_actor=false, perceived=false while 3 m away). She now follows Malzin (faces her) for 2 s of game time before the take.
- SR06 (wrapper): the verdict line never said PASS/FAIL. PASS = Rel Vorn -> Shay aggression in >= 2 distinct combat incidents.
- B55 wild (wrapper): the squad check also matched theft_caught lines (Malzin/Shay as witnesses of the bandits' burglary in
  Shay's home, not the fight). Only non-theft lines with Shay/Malzin mean the squad joined.
- B55 bleed (setup): chest 100 + blood 30 % + fightko leg cuts bled Rel Vex out before he woke. Now a deep arm wound that
  doesn't bleed (about -70 % = native "health" <= -0.3 on waking), a blood watchdog while he is KO, SETUP FAIL if the wound is off.
"""
import sys
root = sys.argv[1].rstrip('/')

def patch(rel, pairs):
    p = root + '/' + rel
    s = open(p, encoding='utf-8').read()
    for old, new in pairs:
        n = s.count(old)
        if n != 1:
            sys.exit(f'{rel}: anchor count {n} != 1: {old[:80]!r}')
        s = s.replace(old, new)
    open(p, 'w', encoding='utf-8').write(s)
    print('patched', rel)

patch('lib/social_property.php', [
    ("private function theftWindow(): int { return max(30, (int)$this->economy('theft_caught_window_seconds', 300)); }",
     "// M24_F12: 900 game s (~30 real s at 1x). The owner's own alarm (theft dialog) came 464 game s after the pickup in m22 F.\n"
     "    private function theftWindow(): int { return max(30, (int)$this->economy('theft_caught_window_seconds', 900)); }"),
])

patch('tests/social_property_regression.php', [
    ("""ok(affOf('Prop Owner', 'Prop Thief') - $o5 === $late, 'SR13 late caught once');
""",
     """ok(affOf('Prop Owner', 'Prop Thief') - $o5 === $late, 'SR13 late caught once');
// M24_F12: the owner's theft dialog arrives after he walked over (m22 F: 464 game s after the pickup): still caught.
$gd = affOf('Prop Guard', 'Prop Shop Thief');
send('item_gain', ent('Prop Shop Thief'), null, ['items'=>['Iron Bar'=>1], 'stolen_items'=>['Iron Bar'=>1]], 50009000);
send('theft_caught', ent('Prop Shop Thief'), ent('Prop Guard'), ['goal'=>'EV_THIEF_CAUGHT_STEALING_FROM_ME', 'stolen_items'=>['Iron Bar'=>1]], 50009464);
ok(affOf('Prop Guard', 'Prop Shop Thief') < $gd, 'SR13 theft dialog 464 game s after the pickup still scores (m22 F)');
"""),
])

patch('tests/social_relationship/ingame/REL-p3-06-ko-loot-witnessed.txt', [
    ("""teleport ${W} ${V} dist 3
transfer ${V} Malzin "Iron Plates"
""",
     """teleport ${W} ${V} dist 3
# M24_F12: a teleport leaves her senses stale (m22 F: 3 m away, sees_actor=false): she follows Malzin (faces her) 2 s first
order ${W} FOLLOW_WHILE_TALKING target Malzin
speed 1
@sleep 2
speed 0
where ${W}
transfer ${V} Malzin "Iron Plates"
"""),
])

patch('tests/social_relationship/ingame/rel-m18.sh', [
    ("""n=$(grep -o '"aggression"' "$O/p2-04b.inspect.txt" | wc -l)
v "SR06: aggression rows mentioned=$n (need two combat incidents; forced lines=$(wc -l < "$O/p2-04b.forced.txt"))"
""",
     """# M24_F12: PASS/FAIL. Rel Vorn -> Shay aggression in >= 2 distinct combat incidents (min of the pair's aggression parts and
# the distinct combat incidents carrying an aggression row).
n=$(php -r '$j = json_decode(file_get_contents($argv[1]), true) ?: []; $p = 0; $i = [];
  foreach ($j["pair_effects"] ?? [] as $r) if (($r["observer"] ?? "") === "Rel Vorn" && ($r["culprit"] ?? "") === "Shay") $p = substr_count($r["components"] ?? "", "aggression:");
  foreach ($j["effect_rows"] ?? [] as $r) if (($r["component"] ?? "") === "aggression" && strpos($r["incident_id"] ?? "", "combat:") === 0) $i[$r["incident_id"]] = 1;
  echo min($p, count($i));' "$O/p2-04b.inspect.txt" 2>/dev/null)
fs=$(grep -c '"attacker":"Shay","victim":"Rel Vorn"' "$O/p2-04b.forced.txt")
if [ "${n:-0}" -ge 2 ]; then v "SR06: PASS Rel Vorn -> Shay aggression in $n combat incidents (forced first strike lines $fs)"
elif [ "$fs" = 0 ]; then v "SR06: SETUP FAIL the forced first strike never fired for Shay -> Rel Vorn (aggression incidents ${n:-0}, p2-04b.forced.txt)"
else v "SR06: FAIL Rel Vorn -> Shay aggression in ${n:-0} combat incidents, need 2 (p2-04b.inspect.txt)"; fi
"""),
])

patch('tests/social_relationship/ingame/rel-b55.sh', [
    ("""  if grep -a -q -e '"actor":"Shay"' -e '"target":"Shay"' -e '"actor":"Malzin"' -e '"target":"Malzin"' "$O/wild.log.txt"; then""",
     """  # M24_F12: theft_caught = Shay/Malzin saw the bandits' burglary in the home, not the fight
  if grep -a -v '"kind":"theft_caught"' "$O/wild.log.txt" | grep -a -q -e '"actor":"Shay"' -e '"target":"Shay"' -e '"actor":"Malzin"' -e '"target":"Malzin"'; then"""),
    ("""  fightko "$h" 40
  stobe-auto damage "$h" chest 100 >/dev/null; stobe-auto blood "$h" 30% >/dev/null
  stobe-say speed 3 >/dev/null
  for i in $(seq 1 80); do stobe-auto where "$h" | grep -q ' KO' || break; sleep 2; done
""",
     """  fightko "$h" 40
  # M24_F12: chest 100 + blood 30 % bled him out before waking (m22 F). A deep arm wound that doesn't bleed instead:
  # about -70 % (native "health" = worst part ratio <= -0.3 on waking = near death); blood watchdog while KO.
  d=$(stobe-auto damage "$h" right_arm 1 bleed 0); echo "$d" > "$O/bleed.setup.txt"
  idx=$(echo "$d" | grep -o 'part [0-9]*' | grep -o '[0-9]*$'); fl=$(echo "$d" | grep -o 'flesh [-0-9.]* -> [-0-9.]*' | awk '{print $4}')
  mx=$(stobe-auto hp "$h" | grep -o " $idx:[-0-9.]*/[0-9.]*" | head -1 | cut -d/ -f2)
  cut=$(awk -v f="$fl" -v m="$mx" 'BEGIN{ if (m > 0) printf "%.1f", f + 0.7 * m }')
  [ -n "$cut" ] && stobe-auto damage "$h" right_arm "$cut" bleed 0 >> "$O/bleed.setup.txt"
  ratio=$(stobe-auto hp "$h" | tee -a "$O/bleed.setup.txt" | grep -o " $idx:[-0-9.]*/[0-9.]*" | head -1 | awk -F'[:/]' '{ if ($3 > 0) printf "%d", 100 * $2 / $3 }')
  if [ -z "$ratio" ] || [ "$ratio" -gt -50 ] || [ "$ratio" -le -95 ]; then
    v "bleed: SETUP FAIL arm wound ${ratio:-?}% (want -50..-95; bleed.setup.txt)"; stobe-auto speed 0 >/dev/null; away "$h"; continue; fi
  stobe-say speed 3 >/dev/null
  for i in $(seq 1 80); do hl=$(stobe-auto hp "$h"); echo "$hl" | grep -q ' KO' || break
    bf=$(echo "$hl" | grep -o 'blood=[0-9.]*/[0-9.]*' | head -1 | awk -F'[=/]' '{ if ($3 > 0) printf "%d", 100 * $2 / $3 }')
    if [ -n "$bf" ] && [ "$bf" -lt 30 ]; then stobe-auto blood "$h" 40% >/dev/null; echo "watchdog: blood $bf% -> 40%" >> "$O/bleed.setup.txt"; fi
    sleep 2; done
"""),
])
