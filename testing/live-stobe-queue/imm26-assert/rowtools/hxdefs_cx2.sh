#!/usr/bin/env bash
# hxdefs_cx2.sh: 05-cx v2 (imm26-sfS).  NEW file; hxdefs.sh / hxdefs_b.sh / hxcheck_b.py / assert_principle.py are NOT edited.  Sourced by hxrun_cx2.sh AFTER hxdefs.sh and
# hxdefs_b.sh: it REDEFINES hx05_scene hx05_roster hx05_hold hx05_samples rd_05cx (only inside the hxrun_cx2.sh shell).  Verdict = hxcheck_b.py (assert_principle.py 05-cx), unchanged.
# Why (imm26-fxC findings, handoff section "05-cx"): the first 05-cx FAIL was three TEST defects, none a product proof:
#   A  3 spawned bandits all named "Hungry Bandit" collapse to ONE roster line (server dedupes names case-insensitively, lifelike_npc.php stobeLifelikeLatestNearbyRosterNames), and they
#      wandered off (protect + NULL_TASK does not hold).   v2: every spawned NPC gets its OWN name (setname <#handle> <name>, HX05_NAMES) and is PINNED (`pin <#handle>`: held on
#      the spot every frame); the NATIVE `nearby NPC roster (N)` count of the latest infonpc row is recorded next to the prompt roster (scene_<L>_native.txt).
#   B  Malzin (squad member) walked back during the 3 E chats, so the roster was not empty at E2/E3 and "Just you and the other one" was TRUE.   v2: Malzin is pinned at the far spot
#      (`pin Malzin at <HX_FAR>`) and every E sample is CONDITIONAL on an empty roster: extras are re-moved before each E sample, and an E sample whose prompt roster is not empty is a
#      SETUP-FAIL (names in the reason), never a FAIL.  The assertion itself (roster_empty + hedge) is unchanged and still runs on all three E samples.
#   C  hx05_roster: printf "...sed 's/ | /\n/g'..." turned \n into a real newline inside the sed script ("unterminated s").   v2: heredoc, no printf format.
#   H  UNPROVEN server question: the prompt roster of the H scene was [Shay] only although the native row listed the sleeper.   v2: the `people` column (and data) of the last 5 infonpc rows is
#      written to <L>1/infonpc_people.txt at the time of the first sample of every scene (E1 H1 N1), so the next run shows which row the server picked.
# Env: HX05_NSPAWN (3)  HX05_FACTION ("Drifters")  HX05_NAMES ("Brannoc Tessik Valo Hollin": N scene uses the first NSPAWN, the H sleeper uses the 4th)  HX05_NOPIN=1 (skip pins)
HX2_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hx05_pin() {  # hx05_pin <npc|#handle> [x y z] : hold on the spot (or at x y z) every frame; output kept in pin.txt (an older harness without `pin` just prints an error: the E-scene check still catches it)
  [ -n "${HX05_NOPIN:-}" ] && return 0
  if [ -n "${2:-}" ]; then printf 'stobe-auto pin %s at %s </dev/null 2>&1 | head -2\n' "$(rl_q "$1")" "$2"
  else printf 'stobe-auto pin %s </dev/null 2>&1 | head -2\n' "$(rl_q "$1")"; fi | lt_h >> "$EV/pin.txt" 2>&1
}
hx05_unpin() {  # hx05_unpin <npc|#handle>... : `pin off` (reports put_back=<n>)
  [ -n "${HX05_NOPIN:-}" ] && return 0
  local w; for w in "$@"; do printf 'stobe-auto pin %s off </dev/null 2>&1 | head -1\n' "$(rl_q "$w")"; done | lt_h >> "$EV/pin.txt" 2>&1
}
hx05_handle() {  # hx05_handle : "#serial/n" of the LAST line of spawn.txt (the spawn just made)
  tail -1 "$EV/spawn.txt" 2>/dev/null | grep -oE '#[0-9]+/[0-9]+' | head -1
}
hx05_name_at() {  # hx05_name_at <n> : n-th word of HX05_NAMES
  local -a nm; read -r -a nm <<<"${HX05_NAMES:-Brannoc Tessik Valo Hollin}"; echo "${nm[$(($1-1))]:-Npc$1}"
}
hx05_spawn_named() {  # hx05_spawn_named <dx> <name index> : spawn, give it a DISTINCT name; sets HX_SPAWNED (full name as spawned) HX05_H (#handle) HX05_NM (new name)
  hxd_spawn "${HX05_FACTION:-Drifters}" "$1" || return 3
  HX05_H=$(hx05_handle); HX05_NM=$(hx05_name_at "$2")
  if [ -z "$HX05_H" ]; then hxd_dry && HX05_H="#9${2}/1" || { RL_REASON="spawned NPC has no #handle in spawn.txt: $(tail -1 "$EV/spawn.txt" | cut -c1-120)"; return 3; }; fi
  printf 'stobe-auto setname %s %s </dev/null 2>&1 | head -1\n' "$(rl_q "$HX05_H")" "$(rl_q "$HX05_NM")" | lt_h >> "$EV/names.txt" 2>&1
  echo "$HX05_H $HX_SPAWNED -> $HX05_NM" >> "$EV/names.txt"
}
hx05_scene() {  # hx05_scene <save> : load, quiet spot, Malzin sent to the far spot AND pinned there
  hxd_load "$1" || return $?; hxd_scene || return $?; hxd_dbclean
  printf 'stobe-auto teleport Malzin %s </dev/null | head -1\n' "$HX_FAR" | lt_h >> "$EV/quiet.txt" 2>&1
  hx05_pin Malzin "$HX_FAR"
}
hx05_roster() {  # hx05_roster <scene letter> : characters within 60 u -> scene_<L>_roster.txt (v2: heredoc; the printf version lost the sed quoting)
  lt_h > "$HXD/scene_$1_roster.txt" 2>&1 <<'EOT'
stobe-auto chars 60 </dev/null 2>&1 | sed 's/ | /\n/g' | grep -E '#[0-9]+/[0-9]+' | cut -c1-90
EOT
}
hx05_infonpc() {  # hx05_infonpc <scene letter> : last 5 infonpc rows (data + people column) -> <L>1/infonpc_people.txt and the native roster count of the newest -> scene_<L>_native.txt
  local L="$1" d="$HXD/${1}1" o
  mkdir -p "$d"
  o=$(lt_sql "select rowid,left(data,260),left(coalesce(people,''),360) from eventlog where type='infonpc' order by rowid desc limit 5" 2>&1)
  { echo "# last 5 infonpc rows at ${L}1 time: rowid|data|people"; echo "$o"; } > "$d/infonpc_people.txt"
  echo "$o" | head -1 | sed -nE 's/.*nearby NPC roster \(([0-9]+)\).*/native_roster_count=\1/p' > "$HXD/scene_${L}_native.txt"
  [ -s "$HXD/scene_${L}_native.txt" ] || echo "native_roster_count=unknown (no infonpc roster row)" > "$HXD/scene_${L}_native.txt"
}
hx05_hold() {  # hx05_hold <#handle|npc> : stand still, do not fight (protect + NULL_TASK as before) AND pinned on the spot
  printf 'stobe-auto protect %s on </dev/null | head -1\nstobe-auto order %s NULL_TASK </dev/null | head -1\n' "$(rl_q "$1")" "$(rl_q "$1")" | lt_h >> "$EV/hold.txt" 2>&1
  hx05_pin "$1"
}
hx05_samples() {  # hx05_samples <scene letter E|H|N> : 3 distinct questions -> <L>1..<L>3.  E: CONDITIONAL on an empty roster (extras re-moved before each sample, a non-empty prompt roster = SETUP-FAIL)
  local L="$1" i=0 q lab names left keep
  local -a qs=("Are we alone?" "Is anyone else around here?" "Can anyone hear us?")
  keep="Shay #|^ *$(echo "$RL_NPC_FULL" | awk '{print $1}') "
  for q in "${qs[@]}"; do i=$((i+1)); lab="$L$i"
    if [ "$L" = E ] && ! hxd_dry; then
      left=$(hxd_extras 60 "$keep"); echo "E sample $lab extras_left_within_60=$left" >> "$EV/phases.txt"
      [ "${left:-0}" = 0 ] || { RL_REASON="E scene: $left character(s) still within 60 u before $lab after moving them away (extras.txt, pin.txt); Malzin/bandit not held"; return 3; }
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
rd_05cx() {  # v2: same phases and labels as hxdefs_b.sh rd_05cx (E empty, H one sleeper, N 3+ visible on load 2)
  hxd_begin; rd_need_npc || return 3
  local m0 left keep sleeper_h sleeper_nm n
  # --- load 1: E (empty) then H (one sleeper)
  hx05_scene "$HX_SAVE" || return $?; m0=$(hxd_rowid)
  keep="Shay #|^ *$(echo "$RL_NPC_FULL" | awk '{print $1}') "
  left=$(hxd_extras 60 "$keep"); echo "E extras_left_within_60=$left" >> "$EV/phases.txt"
  hxd_dry || [ "${left:-0}" = 0 ] || { RL_REASON="E scene: $left character(s) still within 60 u after moving them away (extras.txt)"; return 3; }
  hx05_roster E
  hx05_samples E || return $?
  hxd_trim "$m0"
  hx05_spawn_named 20 4 || return 3; sleeper_h="$HX05_H"; sleeper_nm="$HX05_NM"; echo "$sleeper_h $sleeper_nm" > "$HXD/sleeper.txt"
  printf 'stobe-auto sleep %s </dev/null 2>&1 | head -2\n' "$(rl_q "$sleeper_h")" | lt_h >> "$EV/sleeper.txt" 2>&1
  hxd_sleep 3; hx05_roster H; echo "H sleeper=$sleeper_nm ($sleeper_h)" >> "$EV/phases.txt"
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
