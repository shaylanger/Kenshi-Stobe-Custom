#!/bin/bash
# fix26f-selftest.sh: OFFLINE stub test of rs_scene_clear in reloaddefs_sfe.sh.candidate (or $1): settle wait, blind (fov=-1) polls, settle kick, flicker, pass. No game/lane/server access.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; F="${1:-$H/reloaddefs_sfe.sh.candidate}"
EV=$(mktemp -d); fails=0; export EV
chk() { if [ "$2" = ok ]; then echo "PASS $1"; else echo "FAIL $1 $3"; fails=$((fails+1)); fi; }
a=$(grep -n '^rs_sh()' "$F" | cut -d: -f1); b=$(grep -n '^rs_reseat26f()' "$F" | cut -d: -f1)
sed -n "${a},$((b-1))p" "$F" > "$EV/fn.sh"
rl_q() { printf "'%s'" "$1"; }; rw_sleep() { :; }; rd_aff() { :; }; rl_resolve() { RL_NPC_ID='#111/1'; return 0; }
ROW_NPC=Cind; RW_REFACTION=0; RW_SENTINEL='#9/9'
# Scenario knobs: WHERE_FAIL=n (first n `where` calls give no pos=), BLIND_POLLS=n (senses poll 1..n all fov=-1 entry=0), SEQ="3 0 3 ..." sees count per poll after blind ones
_cnt() { local f="$EV/$1"; local n; n=$(cat "$f" 2>/dev/null || echo 0); echo $((n+1)) > "$f"; echo $((n+1)); }
mk() { local sees="$1" i=0; for b in 1 2 3 4; do i=$((i+1)); if [ $i -le "$sees" ]; then s=1; else s=0; fi; echo "senses #$b/1: Cind -> Dust Bandit sees=$s hears=1 aware=1 entry=1 last_seen_s=0.4 fov=1.0000 dist=31.6 observer_ko=0"; done; }
SQN="$EV/sq"
lt_h() { local c; c=$(cat); case "$c" in
  *"stobe-auto spawn"*) echo "spawned #1/1 #2/1 #3/1 #4/1";;
  *) :;; esac; }
rs_sh_stub() { local c="$1"; case "$c" in
  *"where Shay"*) n=$(_cnt wh); if [ "$n" -le "${WHERE_FAIL:-0}" ]; then echo "no answer within 20s"; else echo "Shay #971557632/1 pos=-47333,730,-55600"; fi;;
  *"senses"*) n=$(_cnt sn); poll=$(( (n-1)/4 + 1 )); k=$(( (n-1)%4 + 1 ))
      if [ "$poll" -le "${BLIND_POLLS:-0}" ]; then echo "senses #$k/1: Cind -> Dust Bandit sees=0 hears=0 aware=0 entry=0 last_seen_s=-1.0 fov=-1.0000 dist=32.3 observer_ko=0"
      else idx=$(( poll - ${BLIND_POLLS:-0} )); want=$(echo $SEQ | awk -v i=$idx '{print ($i==""?0:$i)}'); mk "$want" | sed -n "${k}p"; fi;;
  *teleport*) _cnt tp >/dev/null;;
  *) echo ok;; esac; }
rs_sh() { rs_sh_stub "$1"; }
. "$EV/fn.sh"
rs_sh() { rs_sh_stub "$1"; }   # re-assert the stub after sourcing the real helper
RL_NPC_FULL="Cind [Hungry Bandit]"
run() { rm -f "$EV"/wh "$EV"/sn "$EV"/tp; rs_scene_clear >/dev/null 2>&1; tail -1 "$EV/scene.txt"; }
WHERE_FAIL=0 BLIND_POLLS=0 SEQ="3 3"; r=$(run); [ "$r" = SCENE-OK ] && chk immediate-pass ok || chk immediate-pass bad "$r"
WHERE_FAIL=0 BLIND_POLLS=0 SEQ="4 0 3"; r=$(run); [ "$r" = SCENE-OK ] && chk flicker-then-pass ok || chk flicker-then-pass bad "$r"
WHERE_FAIL=2 BLIND_POLLS=3 SEQ="3 3"; r=$(run); [ "$r" = SCENE-OK ] && grep -q 'ready-wait 2' "$EV/scene.txt" && chk op15-blind-then-pass ok || chk op15-blind-then-pass bad "$r"
WHERE_FAIL=0 BLIND_POLLS=4 SEQ="3 3"; r=$(run); grep -q 'settle-kick at poll 4' "$EV/scene.txt" && [ "$r" = SCENE-OK ] && chk settle-kick ok || chk settle-kick bad "$r"
WHERE_FAIL=0 BLIND_POLLS=0 SEQ="3 2 2 2 2 2 2 2 2 2 2 2 2 2"; r=$(run); case "$r" in SCENE-BAD*"ok=1 of 2"*) chk never-stable-bad ok;; *) chk never-stable-bad bad "$r";; esac
WHERE_FAIL=0 BLIND_POLLS=14 SEQ=""; r=$(run); case "$r" in SCENE-BAD*) chk always-blind-bad ok;; *) chk always-blind-bad bad "$r";; esac
rm -rf "$EV"; echo "fix26f-selftest: fails=$fails"; [ "$fails" = 0 ]
