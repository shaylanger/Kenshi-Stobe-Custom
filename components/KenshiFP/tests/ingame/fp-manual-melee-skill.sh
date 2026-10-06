#!/usr/bin/env bash
# fp-manual-melee-skill.sh: in-game M04 rows of the manual melee adapter (COMBAT_TEST_PLAN.md M04): the native skill,
# defence, damage and injury effects still apply when the player starts the swings. Matched controls: same fighter,
# target, distance and click cadence; only one stat changes between the two halves of each row.
# Run with Kenshi in the world on kah-fpxbow right after load (Malzin = squad melee fighter fighting Skaera = hostile
# Hungry Bandit). Input: the product's spam switch `fp_melee spam <n> 200` (LMB edges on the game thread every 0.2 s,
# faster than any swing, so the native swing time sets the rate; wrapper-driven clicks cost ~0.3 s per harness call
# and capped every window at ~6 swings in 5090 batch 1). Evidence: `fp_melee state` swings and swing_time/swing_ends
# (native CHOP duration, game s), nat_swing_ends/nat_swing_time (native swing timer, any owner: native-AI controls),
# target flesh deltas (`hp`), `stat` effective value and wounds factor.
# Rows: M04-SPEED (attack 5 vs 80 -> the game applies a higher attack speed to manual swings, equal to the native AI's,
# and the same technique's CHOP is shorter), M04-DEF (target defence 1 vs 90 -> fewer hits per swing, 3x longer
# windows; on FAIL a native-AI control at the same stats is logged), M04-DMG (the stat that moves the native AI's per-hit
# damage for this weapon, strength/dexterity/katanas, 1 vs 80 -> more flesh per hit, scaled to the native change),
# M04-INJ (fighter at 35% health -> wounds factor < 1, effective attack lower, not more swings).
# Direction checks only (mechanical PASS); the numbers go to the balance notes.
# Usage: fp-manual-melee-skill.sh [fighter] [target] [outdir] [seconds per half, default 15].
FI=${1:-Malzin}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-manual-melee-skill}; WIN=${4:-15}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | tail -1 | cut -d= -f2; }
ms() { A fp_melee state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" 0 >/dev/null; }
flesh() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | awk '{s+=$1}END{printf "%.1f", s}'; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
# setup_fail also works inside $(window): the line goes to $OUT/ABORT and the main shell is TERMed, prints the rows
# measured so far plus the abort line, and exits (cleanup runs from the EXIT trap).
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG" | tee -a "$LOG" > "$OUT/ABORT"
  if [ "$BASH_SUBSHELL" -gt 0 ]; then kill -TERM $$; exit 1; fi; print_results; cat "$OUT/ABORT"; exit 1; }
print_results() { local r; for r in "${RESULTS[@]}"; do case "$r" in *FAIL*|*INCONCLUSIVE*) echo "$r log=$LOG";; *) echo "$r";; esac; done; }
rm -f "$OUT/ABORT"; trap 'print_results; cat "$OUT/ABORT" 2>/dev/null; exit 1' TERM
FP0=$(A fp_state | fld fp_mode)
ST0=$(A stat "$FI" strength | grep -o 'base=[0-9.]*' | head -1 | cut -d= -f2)
DX0=$(A stat "$FI" dexterity | grep -o 'base=[0-9.]*' | head -1 | cut -d= -f2)
KT0=$(A stat "$FI" katanas | grep -o 'base=[0-9.]*' | head -1 | cut -d= -f2)
cleanup() { A fp_melee passive off >/dev/null; A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A fp_melee spam off >/dev/null; A speed 1 >/dev/null   # ends the speed hold
            [ -n "$ST0" ] && A setstat "$FI" strength "$ST0" >/dev/null; [ -n "$DX0" ] && A setstat "$FI" dexterity "$DX0" >/dev/null
            [ -n "$KT0" ] && A setstat "$FI" katanas "$KT0" >/dev/null; A health "$FI" 100 >/dev/null
            A pin "$TG" off >/dev/null; [ -n "$WEP" ] && A unequip "$FI" "$WEP" >/dev/null
            A protect "$FI" off >/dev/null; A protect "$TG" off >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT
in_fight() { local s; s=$(A fp_melee state); echo "$s" | grep -q 'active=1' && ! echo "$s" | grep -q 'target_h=#0/'; }
# melee weapon: kah-fpxbow's fighter wields only a crossbow; the katana sits in the main inventory, so without an
# explicit equip every "manual" swing was unarmed martial arts (4080 batch 4: no attack XP, attack/strength rows flat).
# equip's reply proves the weapon is wielded ("equipped ..."). WEP = the wielded melee weapon.
weapons() { A inv "$FI" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOWN:-@@}"; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$FI" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }
# close: hold the target ~1.2 m in front of the fighter. Manual melee leaves spacing to the player (no AI approach
# moves the owned fighter, M06) and the test has no WASD, so the target is brought into reach instead.
close() { A pin "$TG" at "$FI" dist "${1:-12}" face "$FI" | grep -q '^pinned'; }
# engage: a live native fight with a target (after a KO or a load the fight can end: 4080 batch 4 M08-KO..LIMB all
# ran with active=0 target_h=#0). The hostile's attack order first, the fighter's own attack order as the fallback.
engage() { in_fight && return 0; local who end
  for who in 1 2; do if [ $who = 1 ]; then A attack "$TG" "$FI" >/dev/null; else A attack "$FI" "$TG" >/dev/null; fi; end=$((SECONDS+8))
    while [ $SECONDS -lt $end ]; do in_fight && return 0; sleep 0.5; done; done; return 1; }
ready() { inp 0 0; engage; local end=$((SECONDS+20)); while [ $SECONDS -lt $end ]; do
  [ "$(ms why)" = ok ] && [ "$(ms armed)" = 1 ] && in_fight && return 0; sleep 0.3; done; return 1; }
# window [seconds]: clicks every 0.2 s from the product's spam switch for that long (default WIN); the target is
# healed whenever it drops below 60% so it never goes down. Echoes "<swings> <hits> <flesh lost> <mean swing s>"
# (a hit = a flesh drop > 0.5 between two polls; mean swing = native CHOP time per finished swing, game s).
# ticking: the fighter's combat class advances (state_left/frame_dt change within 0.6 s; frozen in 4080 batch 13)
ticking() { local a b; a=$(A fp_melee state | grep -o 'state_left=[^ ]* \|frame_dt=[^ ]*' | tr -d '\n'); sleep 0.6
  b=$(A fp_melee state | grep -o 'state_left=[^ ]* \|frame_dt=[^ ]*' | tr -d '\n'); [ -n "$a" ] && [ "$a" != "$b" ]; }
# guard manual|ctrl <label>: per-window setup check; one repair (speed 1 hold, protect, re-take, fp_combat on/off,
# engage), then a specific SETUP FAIL instead of a silent 0-swing window
guard() { local i st ko w ok
  for i in 1 2; do st=$(A status); ko=$(A where "$FI" | grep -o 'KO\|DEAD' | head -1); ok=1
    echo "$st" | grep -q 'paused=0' || ok=0; [ -z "$ko" ] || ok=0
    if [ $ok = 1 ]; then if [ "$1" = manual ]; then ready && ticking || ok=0; else engage && ticking || ok=0; fi; fi
    [ $ok = 1 ] && return 0; [ $i = 2 ] && break
    A speed 1 hold >/dev/null; A protect "$FI" on >/dev/null; A select "$FI" >/dev/null; A fp_control take >/dev/null
    if [ "$1" = manual ]; then A fp_combat on >/dev/null; else A fp_combat off >/dev/null; fi; inp 0 0; sleep 2; done
  w=$(A fp_melee state)
  setup_fail "$2: $1 window not ready after one repair: $(echo "$st" | grep -o 'paused=[^ ]* speed=[^ ]*') fighter=${ko:-up} why=$(echo "$w" | fld why) armed=$(echo "$w" | fld armed) active=$(echo "$w" | fld active) ticking=$(ticking && echo 1 || echo 0) ui=[$(A ui | head -c 200 | tr '\n' ' ')]"; }
window() { guard manual "window(${1:-$WIN}s)"; close; A health "$TG" 100 >/dev/null; sleep 0.3
  local w=${1:-$WIN} s0 t0 e0 p n end lost=0 hits=0; s0=$(ms swings); t0=$(ms swing_time); e0=$(ms swing_ends); p=$(flesh "$TG")
  A fp_melee spam $((w*5)) 200 | grep -q "spam on" || { echo "0 0 0 0 spam_refused"; return; }; end=$((SECONDS+w+5))
  while [ $SECONDS -lt $end ]; do sleep 0.3
    n=$(flesh "$TG"); if awk -v a="$p" -v b="$n" 'BEGIN{exit !(b<a-0.5)}'; then hits=$((hits+1)); lost=$(awk -v l="$lost" -v a="$p" -v b="$n" 'BEGIN{printf "%.1f", l+a-b}'); fi
    p=$n; A hp "$TG" | grep -q 'worst=[0-5]\?[0-9]%' && { A health "$TG" 100 >/dev/null; p=$(flesh "$TG"); }
    if [ -n "$HOLD_FI" ]; then local hf; hf=$(A hp "$FI"); echo "$hf" | grep -q ' KO ' && { : > "$OUT/fi_ko"; break; }
      echo "$hf" | grep -q 'worst=[0-2]\?[0-9]%' && A health "$FI" "$HOLD_FI" >/dev/null; fi
    [ "$(ms spam_left)" = 0 ] && break; done
  A fp_melee spam off >/dev/null
  sleep 1.5; n=$(flesh "$TG"); awk -v a="$p" -v b="$n" 'BEGIN{exit !(b<a-0.5)}' && { hits=$((hits+1)); lost=$(awk -v l="$lost" -v a="$p" -v b="$n" 'BEGIN{printf "%.1f", l+a-b}'); }
  local mean; mean=$(awk -v t0="$t0" -v t1="$(ms swing_time)" -v e0="$e0" -v e1="$(ms swing_ends)" 'BEGIN{printf "%.3f", (e1>e0) ? (t1-t0)/(e1-e0) : 0}')
  echo "$(( $(ms swings) - s0 )) $hits $lost $mean"; }
# ctrl_window <s>: native-AI control (manual ownership off, the fighter's own AI swings)
#   -> "<hits> <flesh lost> <native swings> <mean native swing s>" (product native swing timer nat_swing_*)
ctrl_window() { A fp_combat off >/dev/null; guard ctrl "ctrl_window(${1}s)"; close; A health "$TG" 100 >/dev/null; sleep 0.3
  local p n end=$((SECONDS+$1)) lost=0 hits=0 ne0 nt0; p=$(flesh "$TG"); ne0=$(ms nat_swing_ends); nt0=$(ms nat_swing_time)
  while [ $SECONDS -lt $end ]; do sleep 0.3; n=$(flesh "$TG")
    if awk -v a="$p" -v b="$n" 'BEGIN{exit !(b<a-0.5)}'; then hits=$((hits+1)); lost=$(awk -v l="$lost" -v a="$p" -v b="$n" 'BEGIN{printf "%.1f", l+a-b}'); fi
    p=$n; A hp "$TG" | grep -q 'worst=[0-5]\?[0-9]%' && { A health "$TG" 100 >/dev/null; p=$(flesh "$TG"); }; done
  local ne1 nt1; ne1=$(ms nat_swing_ends); nt1=$(ms nat_swing_time)
  A fp_combat on >/dev/null
  echo "$hits $lost $((ne1-ne0)) $(awk -v t0="$nt0" -v t1="$nt1" -v e0="$ne0" -v e1="$ne1" 'BEGIN{printf "%.3f", (e1>e0) ? (t1-t0)/(e1-e0) : 0}')"; }
eff() { A stat "$FI" "$1" | grep -o 'effective=[-0-9.]*' | head -1 | cut -d= -f2; }
# tech_ratio <techs5> <techs80>: swingstat techs (addr:n:time;...) -> "<ratio> <common>": over techniques with >= 2
# completed CHOPs in both halves, total time at 80 / (count at 80 x mean time at 5); < 1 = the same moves got faster
tech_ratio() { awk -v a="$1" -v b="$2" 'BEGIN{na=split(a,A,";");for(i=1;i<=na;i++){split(A[i],f,":");if(f[2]+0>=2)ma[f[1]]=f[3]/f[2]}
  nb=split(b,B,";");for(i=1;i<=nb;i++){split(B[i],f,":");if(f[2]+0>=2&&(f[1] in ma)){num+=f[3];den+=f[2]*ma[f[1]];c++}}
  if(c&&den>0)printf "%.3f %d",num/den,c;else print "0 0"}'; }
# merge_techs <techs> <techs>: sum two swingstat techs lists (addr:n:time;...) per technique
merge_techs() { awk -v a="$1" -v b="$2" 'BEGIN{s=a";"b;m=split(s,P,";");for(i=1;i<=m;i++){if(split(P[i],f,":")<3)continue;if(!(f[1] in n))o[++k]=f[1];n[f[1]]+=f[2];t[f[1]]+=f[3]}
  for(i=1;i<=k;i++)printf "%s%s:%d:%.3f",(i>1?";":""),o[i],n[o[i]],t[o[i]];if(!k)printf "none"}'; }
# tech_cmp <techs5> <techs80> -> "<pooled ratio> <median per-technique ratio> <common> <list>" over techniques with >= 2
# completed CHOPs in both halves (stumble/block-cut and cancelled swings are excluded by the product: nat_cut, nat_cancel;
# 4080 batch 16: swings cancelled at the hit point without dead time had been counted as complete); ratio < 1 = faster at 80
tech_cmp() { awk -v a="$1" -v b="$2" 'BEGIN{na=split(a,A,";");for(i=1;i<=na;i++){split(A[i],f,":");if(f[2]+0>=2)ma[f[1]]=f[3]/f[2]}
  nb=split(b,B,";");for(i=1;i<=nb;i++){split(B[i],f,":");if(f[2]+0>=2&&(f[1] in ma)){num+=f[3];den+=f[2]*ma[f[1]];c++;r[c]=(f[3]/f[2])/ma[f[1]];l=l sprintf("%s%s=%.3f(%d)",(c>1?",":""),f[1],r[c],f[2])}}
  if(!c||den<=0){print "0 0 0 none";exit}
  for(i=1;i<=c;i++)for(j=i+1;j<=c;j++)if(r[j]<r[i]){x=r[i];r[i]=r[j];r[j]=x}
  med=(c%2)?r[(c+1)/2]:(r[c/2]+r[c/2+1])/2;printf "%.3f %.3f %d %s",num/den,med,c,l}'; }
# nstat <stat>: effective value (setstat proof)
nstat() { A stat "$FI" "$1" | grep -o 'effective=[-0-9.]*' | head -1 | cut -d= -f2; }

# ---- setup (same as fp-manual-melee.sh) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$FI" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
BOWN=$(A rangedinfo "$FI" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//')
[ "$(A rangedinfo "$FI" | fld bow)" = none ] || A unequip "$FI" "$(A rangedinfo "$FI" | fld bow)" >/dev/null
arm_melee || setup_fail "$FI has no melee weapon that equips (inv weapons: $(weapons | tr '\n' ';'))"
A protect "$FI" on >/dev/null
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$FI") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$FI" dist 600 >/dev/null;; esac; done
A setstat "$TG" defence 1 >/dev/null; A setstat "$TG" dodge 1 >/dev/null
A select "$FI" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$FI" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $FI"
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
close || setup_fail "pin $TG in reach of $FI refused"
ready || setup_fail "adapter not ready (why=$(ms why) armed=$(ms armed) manual_ready=$(ms manual_ready))"
# the game pauses itself on squad events/dialogs (4080 batch 13: frozen after the first window): harness unpauses
A speed 1 hold >/dev/null
# no AI attack aimed at the fighter starts (test switch): no auto-block in manual mode, so its hits would stumble-lock the
# fighter and reject the clicks (4080 batch 2); M03 switches it back on, it needs a real attacker
PS=$(A where "$FI" | grep -o '#[0-9]*' | head -1 | tr -d '#')
A fp_melee passive "$PS" | grep -q "passive on" || setup_fail "fp_melee passive $PS refused"

# ---- M04-SPEED: attack 5 vs 80, target defence 1 ----
# 4080 batch 11: manual mean CHOP 0.837 -> 1.085 s, native AI 1.174 -> 1.007 s. RE: the click path runs the same
# AttackState::initialiseAttack as the AI (initialise 0x2B4AB0 = initialiseAttack + movement stop, both mirrored), which
# plays the technique at CharStats+0x188 (attack speed) x technique anim speed (0x2B48A4). Mean CHOP time mixes
# techniques (picked by distance/skill/previous move) and cut swings, so it is not a speed measure. Evidence now
# (product `fp_melee swingstat`): the attack speed the game applied at each CHOP start (manual and native-AI control
# at the same skill must match: parity), its rise from attack 5 to 80, and per-technique completed CHOP time.
# The old mean-swing/swing-count numbers stay in the line (same technique-mix flaw, not asserted).
# The swing rate under spam is set by the native swing (CHOP) time: higher attack must shorten the mean native swing
# (>= 5%) with no fewer swings. 5090 batch 2: 12 vs 10 swings, mean 0.92 vs 1.02 s (from swing_time/swing_ends):
# no speed-up. On FAIL a native-AI control (fp_combat off, same stats) reports the AI's own native swing time, so the
# row tells a manual-path bug (AI faster at 80) from game behaviour (AI not faster either).
A fp_melee swingstat | grep -q 'atk_speed_mean=' || setup_fail "fp_melee swingstat missing (needs the round-4 KenshiFP)"
sw_half() { A fp_melee swingstat reset >/dev/null; if [ "$1" = manual ]; then window >/dev/null; else ctrl_window "$WIN" >/dev/null; fi; A fp_melee swingstat; }
A setstat "$FI" attack 5 >/dev/null; EL=$(eff attack); A fp_melee swingstat reset >/dev/null; read -r SL HL LL ML _ <<<"$(window)"; WL=$(A fp_melee swingstat)
WCL=$(sw_half ctrl)
A setstat "$FI" attack 80 >/dev/null; EH=$(eff attack); A fp_melee swingstat reset >/dev/null; read -r SH HH LH MH _ <<<"$(window)"; WH=$(A fp_melee swingstat)
WCH=$(sw_half ctrl)
ASL=$(echo "$WL" | fld atk_speed_mean); NL=$(echo "$WL" | fld atk_speed_n); ASH=$(echo "$WH" | fld atk_speed_mean); NH=$(echo "$WH" | fld atk_speed_n)
CAL=$(echo "$WCL" | fld atk_speed_mean); CNL=$(echo "$WCL" | fld atk_speed_n); CAH=$(echo "$WCH" | fld atk_speed_mean); CNH=$(echo "$WCH" | fld atk_speed_n)
# same-move check needs >= 3 common techniques (4080 batch 15: decided by 1 common technique, inconclusive): extra
# paired windows (attack 5 then 80, swingstat reset per window, techs summed here), at most 3 extra pairs
T5=$(echo "$WL" | fld techs); T80=$(echo "$WH" | fld techs); XP=0
read -r TR TM TC TL <<<"$(tech_cmp "$T5" "$T80")"
while [ "$TC" -lt 3 ] && [ $XP -lt 3 ]; do XP=$((XP+1))
  A setstat "$FI" attack 5 >/dev/null; A fp_melee swingstat reset >/dev/null; window >/dev/null; T5=$(merge_techs "$T5" "$(A fp_melee swingstat | fld techs)")
  A setstat "$FI" attack 80 >/dev/null; A fp_melee swingstat reset >/dev/null; window >/dev/null; T80=$(merge_techs "$T80" "$(A fp_melee swingstat | fld techs)")
  read -r TR TM TC TL <<<"$(tech_cmp "$T5" "$T80")"; done
read -r CTR CTC <<<"$(tech_ratio "$(echo "$WCL" | fld techs)" "$(echo "$WCH" | fld techs)")"
par() { awk -v m="$1" -v c="$2" 'BEGIN{exit !(m>0 && c>0 && (m-c<=0.03*c) && (c-m<=0.03*c))}'; }
rise() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>0 && b>=a*1.05)}'; }
ev="applied atk_speed manual 5->80: $ASL(n=$NL)->$ASH(n=$NH) native_ai: $CAL(n=$CNL)->$CAH(n=$CNH) | same_move manual pooled=$TR median=$TM common=$TC extra_pairs=$XP [$TL] ai=$CTR(common=$CTC) | ${WIN}s spam: attack5(eff=$EL) swings=$SL hits=$HL mean_swing=${ML}s cut=$(echo "$WL" | fld nat_cut) cancel=$(echo "$WL" | fld nat_cancel) attack80(eff=$EH) swings=$SH hits=$HH mean_swing=${MH}s cut=$(echo "$WH" | fld nat_cut) cancel=$(echo "$WH" | fld nat_cancel) | manual cancel_refused=$(ms cancel_refused) abort_refused=$(ms abort_refused)"
if [ "${NL:-0}" -lt 3 ] || [ "${NH:-0}" -lt 3 ] || [ "${CNL:-0}" -lt 3 ] || [ "${CNH:-0}" -lt 3 ]; then cls=few_swings
elif ! par "$ASL" "$CAL" || ! par "$ASH" "$CAH"; then cls=manual_speed_differs_from_ai
elif ! rise "$ASL" "$ASH"; then cls=attack_skill_does_not_raise_applied_speed
elif [ "$TC" -lt 3 ]; then cls="inconclusive: only $TC techniques with >=2 uncut swings in both halves after $XP extra window pairs"
elif ! awk -v r="$TR" -v m="$TM" 'BEGIN{exit !(r>0 && r<=0.95 && m>0 && m<=0.95)}'; then cls=speed_applied_tech_time_not_shorter
else cls=ok; fi
case "$cls" in ok) row M04-SPEED PASS "$ev";; inconclusive*) row M04-SPEED INCONCLUSIVE "$ev ($cls)";; *) row M04-SPEED FAIL "$ev ($cls)";; esac

# ---- M04-DEF: fighter attack 30; target defence 1 vs 90 (dodge 1) ----
A setstat "$FI" attack 30 >/dev/null
# 6 swings per half (5090 batch 1: 2/6 vs 4/6 hits) can't separate the rates: 3x longer windows, >= 8 swings per half
A setstat "$TG" defence 1 >/dev/null; read -r S1 H1 L1 _ <<<"$(window $((WIN*3)))"; DA=$(A stat "$TG" defence | grep -o 'effective=[0-9.]*' | cut -d= -f2)
A setstat "$TG" defence 90 >/dev/null; read -r S2 H2 L2 _ <<<"$(window $((WIN*3)))"; DB=$(A stat "$TG" defence | grep -o 'effective=[0-9.]*' | cut -d= -f2)
ev="attack30: def1(eff_after=$DA) swings=$S1 hits=$H1 | def90(eff_after=$DB) swings=$S2 hits=$H2"
if [ "$S1" -ge 8 ] && [ "$S2" -ge 8 ] && awk -v a="$H1" -v b="$S1" -v c="$H2" -v d="$S2" 'BEGIN{exit !(a/b > c/d)}'; then row M04-DEF PASS "$ev"
else # classification evidence: does the native AI's own fighting show the defence effect on this fixture?
  A setstat "$TG" defence 1 >/dev/null; read -r CH1 CL1 _ <<<"$(ctrl_window $((WIN*2)))"
  A setstat "$TG" defence 90 >/dev/null; read -r CH2 CL2 _ <<<"$(ctrl_window $((WIN*2)))"
  row M04-DEF FAIL "$ev | native_ai_ctrl $((WIN*2))s: def1 hits=$CH1 lost=$CL1 def90 hits=$CH2 lost=$CL2"; fi
A setstat "$TG" defence 1 >/dev/null

# ---- M04-DMG: attack 80; the stat that moves the native weapon damage, 1 vs 80 -> flesh per hit ----
# 5090 batch 1: strength 1->80 gave per_hit 24.6->26.4 (+7%) with the Chisa Katana (cutting weapon). The reference is
# the native AI's own per-hit damage (fp_combat off, ctrl_window) with the stat (strength/dexterity/katanas, each set
# alone 1 vs 80, the others at their start value): the stat that moves it most (>= 10%, >= 3 hits per half) is used,
# and the manual per-hit damage must rise by at least half that native change. (5090 batch 2: `stat <c>
# primaryweapondamage` reads 0.0 always: CharStats::getStat doesn't compute the derived stats, no harness reader.)
A setstat "$FI" attack 80 >/dev/null; best=""; NR=1; nd=""
for s in strength dexterity katanas; do
  A setstat "$FI" "$s" 1 >/dev/null; v1=$(nstat "$s"); read -r h1 l1 _ <<<"$(ctrl_window $WIN)"
  A setstat "$FI" "$s" 80 >/dev/null; v2=$(nstat "$s"); read -r h2 l2 _ <<<"$(ctrl_window $WIN)"
  case "$s" in strength) A setstat "$FI" "$s" "$ST0" >/dev/null;; dexterity) A setstat "$FI" "$s" "$DX0" >/dev/null;; katanas) A setstat "$FI" "$s" "$KT0" >/dev/null;; esac
  q1=$(awk -v l="$l1" -v h="$h1" 'BEGIN{printf "%.2f", h? l/h : 0}'); q2=$(awk -v l="$l2" -v h="$h2" 'BEGIN{printf "%.2f", h? l/h : 0}')
  nd="$nd $s:$v1->$v2:ai_hits=$h1/$h2:ai_per_hit=$q1->$q2"
  r=$(awk -v a="$q1" -v b="$q2" -v h1="$h1" -v h2="$h2" 'BEGIN{printf "%.4f", (a>0 && h1>=3 && h2>=3)? b/a : 0}')
  awk -v r="$r" -v n="$NR" 'BEGIN{exit !(r>n)}' && { NR=$r; best=$s; }
done
if [ -z "$best" ] || ! awk -v n="$NR" 'BEGIN{exit !(n>=1.1)}'; then
  row M04-DMG FAIL "native-AI per-hit damage moved < 10% for every stat ($WEP):$nd"
else
  A setstat "$FI" "$best" 1 >/dev/null; read -r S1 H1 L1 _ <<<"$(window)"
  A setstat "$FI" "$best" 80 >/dev/null; read -r S2 H2 L2 _ <<<"$(window)"
  case "$best" in strength) A setstat "$FI" "$best" "$ST0" >/dev/null;; dexterity) A setstat "$FI" "$best" "$DX0" >/dev/null;; katanas) A setstat "$FI" "$best" "$KT0" >/dev/null;; esac
  P1=$(awk -v l="$L1" -v h="$H1" 'BEGIN{printf "%.2f", h? l/h : 0}'); P2=$(awk -v l="$L2" -v h="$H2" 'BEGIN{printf "%.2f", h? l/h : 0}')
  ev="attack80 $WEP: ${best}1 hits=$H1 per_hit=$P1 | ${best}80 hits=$H2 per_hit=$P2 | native_ratio=$NR;$nd"
  if [ "$H1" -ge 3 ] && [ "$H2" -ge 3 ] && awk -v a="$P1" -v b="$P2" -v n="$NR" 'BEGIN{exit !(a>0 && b/a >= 1+(n-1)*0.5)}'; then row M04-DMG PASS "$ev"; else row M04-DMG FAIL "$ev"; fi
fi

# ---- M04-INJ: attack 50; healthy vs 35% health (protect off for the injured half) ----
A setstat "$FI" attack 50 >/dev/null; A health "$FI" 100 >/dev/null
E1=$(A stat "$FI" attack | grep -o 'eff[a-z]*=[0-9.]*' | head -1 | cut -d= -f2); read -r S1 _ _ M1 _ <<<"$(window)"
A protect "$FI" off >/dev/null; A health "$FI" 35 >/dev/null; sleep 1
SI=$(A stat "$FI" attack); E2=$(echo "$SI" | grep -o 'eff[a-z]*=[0-9.]*' | head -1 | cut -d= -f2); WF=$(echo "$SI" | fld wounds)
# protect heals every frame (it would undo the 35%), so the injured half runs unprotected; window() tops the fighter
# back up to 35% when a part drops below 30% (4080 b18: Skaera KO'd her mid-window -> not_allowed, 0 swings) and
# stops on a KO; one repair (wake via protect, back to 35%), then SETUP FAIL
for t in 1 2; do HOLD_FI=35; rm -f "$OUT/fi_ko"; read -r S2 _ _ M2 _ <<<"$(window)"; HOLD_FI=
  [ ! -e "$OUT/fi_ko" ] && ! A hp "$FI" | grep -q ' KO ' && break
  [ $t = 2 ] && { A protect "$FI" on >/dev/null; setup_fail "M04-INJ: fighter KO'd during the 35% window twice (swings=$S2)"; }
  A protect "$FI" on >/dev/null; sleep 3; A protect "$FI" off >/dev/null; A health "$FI" 35 >/dev/null; sleep 1; done
A health "$FI" 100 >/dev/null; A protect "$FI" on >/dev/null
ev="attack50: healthy eff=$E1 swings=$S1 mean_swing=${M1}s | 35% eff=$E2 wounds=$WF swings=$S2 mean_swing=${M2}s"
if awk -v w="$WF" -v a="$E1" -v b="$E2" 'BEGIN{exit !(w<1 && b<a)}' && [ "$S2" -le "$S1" ] && [ "$S2" -ge 1 ]; then row M04-INJ PASS "$ev"; else row M04-INJ FAIL "$ev"; fi

print_results
