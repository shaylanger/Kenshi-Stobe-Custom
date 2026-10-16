#!/usr/bin/env bash
# hxdefs_cx4.sh: 05-cx v4 (imm26-fix15bx05cx3, from the i3 live run C:/KenshiTestRuns/agents/out/imm26-5090-i3op23/out-20261016-143022.md).  NEW file; hxdefs_cx3.sh and every older file are NOT edited.
# Sourced by hxrun_cx4.sh AFTER hxdefs.sh, hxdefs_b.sh and hxdefs_cx3.sh: it REDEFINES hxd_lane_save hx05_samples rd_05cx (and adds hx05_ko_*).
# Why (the real i3 bundle: rows/05-cx/H1, prompt line "Hollin (female) | doing:moving | condition..."):
#   1  The H sleeper was put down with the harness `sleep` (SLEEP_ON_FLOOR); a spawned NPC's AI drops it at once, the prompt said "doing:moving" and roster_has_sleeper could never hold.
#      v4: `ko <#handle> 900` (as 15-bx v3) -> the prompt line reads "doing:unconscious (knocked out, cannot talk)"; a gate polls `stobe_state` <= 16 s for "unconscious":true and is a
#      SETUP-FAIL ("sleeper not KO ... needs: recipe") otherwise, and the `ko` is re-issued + gated right before EVERY H sample (state per sample: <bundle>/H_sleep_state.txt).
#   2  base save: the lane default is now a save that EXISTS (hx4lib.sh hx4_lane_save; 5090-i3 had no kah-imm26-5090-hxA and the load silently kept the loaded world).
# The verdict is assert_principle_cx4.py (hxcheck_cx4.py), see its header for the checker changes (hedge vocabulary, "just us" inside "if you meant ..., no" is not an alone claim).
HX4_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HX4_HERE/hx4lib.sh"
hxd_lane_save() { hx4_lane_save; }

hx05_ko_state() {  # hx05_ko_state <#handle> : "unconscious"/"first_order"/"current_goal"/"dead" fields of stobe_state
  local js st
  js=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 6000\n' "$(rl_q "$1")" | lt_h 2>&1)
  st=$(echo "$js" | grep -oE '"(dead|unconscious|first_order|current_goal)": ?("[^"]*"|[a-z]+)' | tr '\n' ' ')
  echo "$st"
}
hx05_ko_gate() {  # hx05_ko_gate <#handle> <seconds> <tag> : ko order, poll <= 16 s until stobe_state says "unconscious":true, state appended to <bundle>/H_sleep_state.txt; rc 3 + RL_REASON otherwise
  local h="$1" secs="$2" tag="$3" i st=""
  hxd_dry && return 0
  printf 'stobe-auto ko %s %s </dev/null 2>&1 | head -2\n' "$(rl_q "$h")" "$secs" | lt_h >> "$EV/ko.txt" 2>&1
  for i in 1 2 3 4 5 6 7 8; do
    st=$(hx05_ko_state "$h"); echo "$st" | grep -qE '"unconscious": ?true' && break
    hxd_sleep 2
  done
  echo "$tag|$st" >> "$HXD/H_sleep_state.txt"
  echo "$st" | grep -qE '"unconscious": ?true' || { RL_REASON="H sleeper $h not KO at '$tag' after the ko order and a 16 s poll ($(echo "$st" | cut -c1-120)); needs: recipe (H_sleep_state.txt)"; return 3; }
}
hx05_samples() {  # as hxdefs_cx3.sh hx05_samples, plus: H scene = ko re-issued + gated before every sample
  local L="$1" i=0 q lab names left keep shl
  local -a qs=("Are we alone?" "Is anyone else around here?" "Can anyone hear us?")
  keep=$(hx05_keep)
  [ "$L" = H ] && shl=$(head -1 "$HXD/sleeper.txt" 2>/dev/null | awk '{print $1}')
  for q in "${qs[@]}"; do i=$((i+1)); lab="$L$i"
    if [ "$L" = H ] && [ -n "$shl" ]; then hx05_ko_gate "$shl" "${HX05_KO_RE_S:-600}" "sample-$lab" || return $?; fi
    if [ "$L" = E ] && ! hxd_dry; then
      left=$(hxd_extras 60 "$keep"); echo "E sample $lab extras_left_within_60=$left" >> "$EV/phases.txt"
      [ "${left:-0}" = 0 ] || { RL_REASON="E scene: $left character(s) still within 60 u before $lab after moving them away (extras.txt, pin.txt); Malzin/bandit not held"; return 3; }
      HXD_DFILE=scene_distance.txt hxd_dist "$lab" Shay "$(echo "$RL_NPC_FULL" | awk '{print $1}')" || return $?
      hx05_near "$HXD/$lab/scene_distance.txt" || { RL_REASON="E scene: the NPC under test is not within 60 u of Shay before $lab (scene_distance.txt: $(tr '\n' ' ' < "$HXD/$lab/scene_distance.txt")); NPC itself moved away (extras/keep regex)"; return 3; }
    fi
    hxd_sample "$lab" "$q" || return $?
    [ "$i" = 1 ] && hx05_infonpc "$L"
    names=$(hxb_py --roster "$HXD/$lab")
    if [ "$i" = 1 ]; then echo "$names" > "$HXD/scene_${L}_names.txt"; else echo "$names" >> "$HXD/scene_${L}_names.txt"; fi
    if [ "$L" = E ] && ! hxd_dry && [ -n "$names" ]; then
      RL_REASON="E scene is not empty at $lab: the prompt lists '$names' under Nearby People Awareness (see $HXD/$lab/prompt.txt, scene_E_roster.txt, infonpc_people.txt); the hedge check is conditional on an empty roster: rerun after pinning them away"; return 3
    fi
  done
}
rd_05cx() {  # v4: as hxdefs_cx3.sh rd_05cx; the H sleeper is KO'd (gated), not `sleep`ed
  hxd_begin; rd_need_npc || return 3
  local m0 left keep sleeper_h sleeper_nm n
  # --- load 1: E (empty) then H (one KO'd sleeper)
  hx05_scene "$HX_SAVE" || return $?; m0=$(hxd_rowid)
  keep=$(hx05_keep)
  left=$(hxd_extras 60 "$keep"); echo "E extras_left_within_60=$left" >> "$EV/phases.txt"
  hxd_dry || [ "${left:-0}" = 0 ] || { RL_REASON="E scene: $left character(s) still within 60 u after moving them away (extras.txt)"; return 3; }
  hx05_roster E
  hx05_samples E || return $?
  hxd_trim "$m0"
  hx05_spawn_named 20 4 || return 3; sleeper_h="$HX05_H"; sleeper_nm="$HX05_NM"; echo "$sleeper_h $sleeper_nm" > "$HXD/sleeper.txt"
  : > "$HXD/H_sleep_state.txt"
  hx05_ko_gate "$sleeper_h" "${HX05_KO_S:-900}" ordered || return $?
  hxd_sleep 3; hx05_roster H; echo "H sleeper=$sleeper_nm ($sleeper_h) ko" >> "$EV/phases.txt"
  hx05_samples H || return $?
  hxd_trim "$m0"
  # --- load 2: N (visible roster of 3+, distinct names, pinned)
  hx05_scene "$HX_SAVE2" || return $?; hxd_trim "$m0"
  printf 'stobe-auto teleport Malzin Shay </dev/null | head -1\n' | lt_h >> "$EV/quiet.txt" 2>&1
  hx05_pin Malzin
  : > "$HXD/visible.txt"; for n in $(seq 1 "${HX05_NSPAWN:-3}"); do
    hx05_spawn_named $((6 * n)) "$n" || return 3; hx05_hold "$HX05_H"; echo "$HX05_NM $HX05_H" >> "$HXD/visible.txt"
  done
  hxd_sleep 3; hx05_roster N; echo "N visible=$(awk '{print $1}' "$HXD/visible.txt" | tr '\n' ',')" >> "$EV/phases.txt"
  hx05_samples N || return $?
  hxd_trim "$m0"
  hx05_unpin Malzin; [ -n "${HX05_NOPIN:-}" ] || { while read -r _ h; do hx05_unpin "$h"; done < "$HXD/visible.txt"; }
}
