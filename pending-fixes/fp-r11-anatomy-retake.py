#!/usr/bin/env python3
"""fp-manual-anatomy.sh (R11) measurement fixes after 5090 fp-5090-11 (KenshiFP 4FD22DEF):
 R11-RACE: aimed_part counted shots where the target was crouched/staggered at impact (impact head bone 1.0-1.5 dm
   under its standing height: 5090 shots 1, 2, 4 of 6; the aim heights assume the upright pose read before the trigger).
   Such hits still count for the routing checks (hits / consistent / fallbacks), but are retaken for aimed_part
   (<= 3 tries per counted shot). Fewer counted shots than 3*NRACE = SETUP FAIL reason=pose_unstable. Criterion unchanged.
 R11-LIMB: the 2 forced shots (fp_combat wound force leg_l) both missed with the ray off the crawling target
   (forced=0/2 -> leg_l_picked=0). A forced shot that misses is re-aimed (fresh bone point) and fired again (<= 3 tries);
   the extra misses are logged. Criterion unchanged.
Usage: fp-r11-anatomy-retake.py <KenshiFP root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "tests" / "ingame" / "fp-manual-anatomy.sh"
s = p.read_text(encoding="utf-8")
if "pose_unstable" in s:
    print("already applied"); sys.exit(0)

def rep(old, new):
    global s
    assert s.count(old) == 1, "anchor not unique/found: " + old[:80]
    s = s.replace(old, new)

# ---- R11-RACE ----
rep('''  else hits=0; cons=0; good=0; total=0; fb=""; ev=""; ontg=0; nofp=0; tooclose=0; nup=0; REFH=''',
    '''  else hits=0; cons=0; good=0; total=0; fb=""; ev=""; ontg=0; nofp=0; tooclose=0; nup=0; REFH=; shots=0; disturbed=0''')
rep('''      for _ in $(seq 1 "$NRACE"); do
''',
    '''      # counted shots: the target upright at impact (impact head bone >= REFH-1.0); a crouched/staggered impact (5090
      # fp-5090-11: head bone 16.6-17.0 vs 18.0 standing, aims placed for the upright pose) is retaken for aimed_part
      valid=0; tries=0; while [ "$valid" -lt "$NRACE" ] && [ "$tries" -lt $((NRACE*3)) ]; do tries=$((tries+1))
''')
rep('''shot "$SPAWN"; AIM_COL=""; judge "${S_HURT[0]}"; total=$((total+1))
        [ "$S_FP" = 0 ] && nofp=$((nofp+1)); [ "$S_ON" = 1 ] && ontg=$((ontg+1))
        for w in ${want//,/ }; do [[ ",${S_HURT[0]}" == *",$w("* ]] && { good=$((good+1)); break; }; done
        [ "$J" = hit ] && { hits=$((hits+1)); [ "$JC" = 1 ] && cons=$((cons+1)); [ "$JS" = 0 ] && fb+="$(gf last_fallback "$W1"),"; }
        ev+="$name:aim_h=$ht jit_h=${JIT_H:-none} on_target=$S_ON $JD; "; done; done''',
    '''shot "$SPAWN"; AIM_COL=""; judge "${S_HURT[0]}"; shots=$((shots+1))
        [ "$S_FP" = 0 ] && nofp=$((nofp+1)); [ "$S_ON" = 1 ] && ontg=$((ontg+1))
        [ "$J" = hit ] && { hits=$((hits+1)); [ "$JC" = 1 ] && cons=$((cons+1)); [ "$JS" = 0 ] && fb+="$(gf last_fallback "$W1"),"; }
        ih=$(gf last_bones "$W1" | cut -d, -f1)
        if [ "$J" = hit ] && [ -n "$REFH" ] && awk -v h="$ih" -v r="$REFH" 'BEGIN{exit !(h!="nan" && h!="" && h<r-1.0)}'; then
          disturbed=$((disturbed+1)); ev+="$name:DISTURBED(impact_head=$ih ref=$REFH; retaken) aim_h=$ht jit_h=${JIT_H:-none} on_target=$S_ON $JD; "; continue; fi
        valid=$((valid+1)); total=$((total+1))
        for w in ${want//,/ }; do [[ ",${S_HURT[0]}" == *",$w("* ]] && { good=$((good+1)); break; }; done
        ev+="$name:aim_h=$ht jit_h=${JIT_H:-none} on_target=$S_ON $JD; "; done; done''')
rep('''aim_on_target=$ontg/$total hits=$hits consistent=$cons aimed_part=$good/$total not_upright=$nup''',
    '''aim_on_target=$ontg/$shots hits=$hits consistent=$cons aimed_part=$good/$total disturbed=$disturbed not_upright=$nup''')
rep('''    elif [ "$nofp" -gt 0 ]; then row R11-RACE SETUP "FAIL FP control lost and not re-taken on $nofp shots: $sum"
''',
    '''    elif [ "$nofp" -gt 0 ]; then row R11-RACE SETUP "FAIL FP control lost and not re-taken on $nofp shots: $sum"
    elif [ "$total" -lt $((3*NRACE)) ]; then row R11-RACE SETUP "FAIL reason=pose_unstable: only $total of $((3*NRACE)) shots had the target upright at impact: $sum"
''')

# ---- R11-LIMB ----
rep('''  for spec in "${SPECS[@]}"; do read -r ht lat fc <<<"$spec"
    A hp "$TG" | grep -q ' KO ' ''',
    '''  for spec in "${SPECS[@]}"; do read -r ht lat fc <<<"$spec"; att=0
    # a forced shot that misses (5090 fp-5090-11: both forced shots missed the crawling target, ray off her) is
    # re-aimed at a fresh bone point and fired again, <= 3 tries; the extra misses are logged, not counted
    while :; do att=$((att+1))
    A hp "$TG" | grep -q ' KO ' ''')
rep('''    shot "$TG"; judge "${S_HURT[0]}"
    if [ "$fc" = force ]; then forced=$((forced+1)); FR=$(A fp_combat wound force none)''',
    '''    shot "$TG"; judge "${S_HURT[0]}"
    if [ "$fc" = force ] && [ "$J" = miss ] && [ "$att" -lt 3 ]; then A fp_combat wound force none >/dev/null
      [ "$S_FP" = 0 ] && nofp=$((nofp+1)); ev+="h=$ht force retry$att(miss on_target=$S_ON); "; continue; fi
    break; done
    if [ "$fc" = force ]; then forced=$((forced+1)); FR=$(A fp_combat wound force none)''')
p.write_text(s, encoding="utf-8")
print("patched", p)
