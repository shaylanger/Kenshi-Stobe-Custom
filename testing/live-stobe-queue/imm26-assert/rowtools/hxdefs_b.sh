#!/usr/bin/env bash
# hxdefs_b.sh: hardening-row definitions, family B (imm26-hxB): 05-cx.  NEW file; hxdefs.sh / hxcheck.py are NOT edited (imm26-hxA appends there).
# Sourced by hxrun.sh right after hxdefs.sh (needs hxd_* helpers from it); the verdict comes from hxcheck_b.py (assert_principle.py 05-cx ...).
# 03-cx is NOT here: the TESTS file already holds a 4080 PASS for it (assert_witness 03-cx PASS on 2 fresh reloads, C:/KenshiTestRuns/imm26-4080/03-cx/{R1,R2}).
#   05-cx  E1..E3 = EMPTY roster (nothing but Shay and the speaker within 60 u: Malzin sent away, hxd_extras 60 moves every other character incl. sleepers/KO'd away)
#          H1..H3 = ONE asleep NPC close by (spawned Drifter, `stobe-auto sleep`), same load as E (spawned after the E samples)
#          N1..N3 = 3+ VISIBLE NPCs (Malzin + 3 spawned Drifters within 20 u), a second fresh load (HX_SAVE2)
#   questions (same 3 in every scene): "Are we alone?" / "Is anyone else around here?" / "Can anyone hear us?"
#   bundle per sample: the hxd_sample bundle (prompt reply events effects_full ...); scene_<E|H|N>_roster.txt (chars 60) and scene_<E|H|N>_names.txt (roster seen in the first prompt).
# Env: HX05_NSPAWN (3) HX05_FACTION ("Drifters").  Other knobs as hxdefs.sh (HX_SAVE HX_SAVE2 HX_SPOT HX_FAR HX_OUT HX_NATIVE).
HXB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HXB_ROWS="${HXB_ROWS:-} 05-cx"
hxb_py() { local p; p=$(command -v python3 || command -v python); "$p" "$HXB_HERE/hxcheck_b.py" "$@"; }

hx05_scene() {  # hx05_scene <save> : load, quiet spot, Malzin sent to the far spot (squad member would sit in the roster)
  hxd_load "$1" || return $?; hxd_scene || return $?; hxd_dbclean
  printf 'stobe-auto teleport Malzin %s </dev/null | head -1\n' "$HX_FAR" | lt_h >> "$EV/quiet.txt" 2>&1
}
hx05_roster() {  # hx05_roster <scene letter> : chars within 60 u -> scene_<L>_roster.txt
  printf 'stobe-auto chars 60 </dev/null 2>&1 | sed "s/ | /\n/g" | grep -E "#[0-9]+/[0-9]+" | cut -c1-90\n' | lt_h > "$HXD/scene_$1_roster.txt" 2>&1
}
hx05_hold() {  # hx05_hold <npc full> : stand still, do not fight
  printf 'stobe-auto protect %s on </dev/null | head -1\nstobe-auto order %s NULL_TASK </dev/null | head -1\n' "$(rl_q "$1")" "$(rl_q "$1")" | lt_h >> "$EV/hold.txt" 2>&1
}
hx05_samples() {  # hx05_samples <scene letter E|H|N> : 3 distinct questions -> <L>1..<L>3; E: the first prompt must show an empty roster
  local L="$1" i=0 q lab names
  local -a qs=("Are we alone?" "Is anyone else around here?" "Can anyone hear us?")
  for q in "${qs[@]}"; do i=$((i+1)); lab="$L$i"
    hxd_sample "$lab" "$q" || return $?
    if [ "$i" = 1 ]; then
      names=$(hxb_py --roster "$HXD/$lab"); echo "$names" > "$HXD/scene_${L}_names.txt"
      if [ "$L" = E ] && ! hxd_dry && [ -n "$names" ]; then
        RL_REASON="E scene is not empty: the first prompt lists '$names' under Nearby People Awareness (see $HXD/$lab/prompt.txt, scene_E_roster.txt); rerun after moving them"; return 3
      fi
    fi
  done
}
rd_05cx() {
  hxd_begin; rd_need_npc || return 3
  local m0 left keep sl sls n
  # --- load 1: E (empty) then H (one sleeper)
  hx05_scene "$HX_SAVE" || return $?; m0=$(hxd_rowid)
  keep="Shay #|^ *$(echo "$RL_NPC_FULL" | awk '{print $1}') "
  left=$(hxd_extras 60 "$keep"); echo "E extras_left_within_60=$left" >> "$EV/phases.txt"
  hxd_dry || [ "${left:-0}" = 0 ] || { RL_REASON="E scene: $left character(s) still within 60 u after moving them away (extras.txt)"; return 3; }
  hx05_roster E
  hx05_samples E || return $?
  hxd_trim "$m0"
  hxd_spawn "${HX05_FACTION:-Drifters}" 20 || return 3; sl="$HX_SPAWNED"; sls="${sl%% *}"; echo "$sl" > "$HXD/sleeper.txt"
  printf 'stobe-auto sleep %s </dev/null 2>&1 | head -2\n' "$(rl_q "$sl")" | lt_h >> "$EV/sleeper.txt" 2>&1
  hxd_sleep 3; hx05_roster H; echo "H sleeper=$sl" >> "$EV/phases.txt"
  hx05_samples H || return $?
  hxd_trim "$m0"
  # --- load 2: N (visible roster of 3+)
  hx05_scene "$HX_SAVE2" || return $?; hxd_trim "$m0"
  printf 'stobe-auto teleport Malzin Shay </dev/null | head -1\n' | lt_h >> "$EV/quiet.txt" 2>&1
  : > "$HXD/visible.txt"; for n in $(seq 1 "${HX05_NSPAWN:-3}"); do
    hxd_spawn "${HX05_FACTION:-Drifters}" $((6 * n)) || return 3; hx05_hold "$HX_SPAWNED"; echo "$HX_SPAWNED" >> "$HXD/visible.txt"
  done
  hxd_sleep 3; hx05_roster N; echo "N visible=$(tr '\n' ',' < "$HXD/visible.txt")" >> "$EV/phases.txt"
  hx05_samples N || return $?
  hxd_trim "$m0"
}
