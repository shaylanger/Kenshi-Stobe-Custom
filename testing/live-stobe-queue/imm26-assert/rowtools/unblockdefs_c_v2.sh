#!/usr/bin/env bash
# unblockdefs_c_v2.sh (imm26-sfU, 2026-10-16): v2 of the 15-bx one-call row script (unblockdefs_c.sh is NOT edited: an operator may be using it).  Only 15-bx lives here.
# WHY (fxA table, C:/KenshiTestRuns/agents/out/imm26-fxA/latest.md): in v1 the X NPC (Cind) stood at the fight spot, 16 u from the fighters, while the pair was spawned
#   and fought for 10 s, and was teleported to spot+320 only afterwards.  The DLL tags a fight's audience at emission (Utils.cpp:1313-1348), so Cind legitimately got the
#   early events.  S1's sleep state was never verified at event time.
# v2 CHANGES (nothing else differs from v1):
#   1. OUT phase: after the scene load X (the row NPC) AND Shay are teleported to HX_FAR (far spot, ~5000 u away; --away near = spot+320 instead, keeps the fight zone loaded) BEFORE ub15_pair; X is brought to spot+320 only for the
#      samples (ub15_place_x, unchanged), so no fight event can have listed X.  The IN phase is unchanged (P must be at the spot when the pair fights).
#   2. S1 sleep state is recorded: <bundle>/S1/sleep_state.txt, lines `<tag>|<unconscious/first_order/current_goal/dead of stobe_state>` for tags ordered (right after
#      `sleep`), after_fight (after the 10 s fight) and sample (right before the S1 sample); unblockcheck_c_v2.py makes "S1 not asleep/KO after the fight" a SETUP-FAIL.
#   RUN (one call):  bash testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c_v2.sh 15-bx <lane> [options]   (options as unblockdefs_c.sh: --save --save2 --no-reload
#      --dry --allow-retry "why" --out DIR --out-dist U --faction F).  The attempt guard blocks a row whose last attempt FAILed: add --allow-retry "sfU v2 scene".
#   Verdict: unblockcheck_c_v2.py (scene validation + S1 sleep check) -> hxcheck.py 15-bx with HX_ASSERT_DIR=imm26-assert/v2 (assert_witness.py unchanged, v2 imm26_lib.py).
#   Library use / shim mode: as unblockdefs_c.sh (`. unblockdefs_c_v2.sh` AFTER go-row.sh / hxdefs.sh; shim sends rowcheck.py 15-bx to unblockcheck_c_v2.py).

UC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UC_SELF="$UC_HERE/$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------------------------- shim mode (executed, first arg is a python path)
UC_EXEC=0; [ "${#BASH_SOURCE[@]}" -eq 1 ] && [ "${BASH_SOURCE[0]}" = "$0" ] && UC_EXEC=1   # executed (not sourced)
if [ "$UC_EXEC" = 1 ] && [ -n "${UC_LOADED:-}" ]; then   # executed as $PY by go-row.sh (UC_LOADED is exported by the runner)
  REAL=$(command -v python3 || command -v python)
  if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
    case "${2#IMM-}" in 15-bx) exec "$REAL" "$UC_HERE/unblockcheck_c_v2.py" "$2" "$3";; esac
  fi
  exec "$REAL" "$@"
fi

# ---------------------------------------------------------------------------------------------- helpers
UC_NPC_DEF="Cind [Hungry Bandit]"
uc_sleep() { [ -n "${KAH_ROW_FAKE:-}" ] || sleep "$1"; }
uc_dry() { [ -n "${KAH_ROW_DRY:-}" ]; }
uc_lane_save() { case "${LT_LANE:-}" in 4080-i4) echo kah-imm26-4080-i4h;; 5090-i3) echo kah-imm26-5090-hxA;; 5090-i4) echo kah-imm26-i4-hx0;; esac; }
ub_spawn() {  # ub_spawn <faction> [dx] : hxd_spawn + the #serial/idx handle -> UB_ID UB_NAME UB_SHORT (rc 3 + RL_REASON on failure)
  hxd_spawn "$1" "${2:-0}" || return $?
  UB_NAME="$HX_SPAWNED"; UB_SHORT="${UB_NAME%% *}"
  UB_ID=$(grep -a '^spawned' "$EV/spawn.txt" 2>/dev/null | tail -1 | grep -oE '#[0-9]+/[0-9]+' | head -1)
  uc_dry && UB_ID="${UB_ID:-#9/9}"
  [ -n "$UB_ID" ] || { RL_REASON="spawn reply has no #serial/idx handle: $(tail -1 "$EV/spawn.txt" 2>/dev/null | cut -c1-120)"; return 3; }
}
ub_name() {  # ub_name <#handle|name> : current full name (the server renames spawned bandits)
  printf 'stobe-auto where %s </dev/null 2>&1 | head -1\n' "$(rl_q "$1")" | lt_h 2>&1 | sed -nE 's/^(.*) #[0-9]+\/[0-9]+.*/\1/p' | head -1
}

# ---------------------------------------------------------------------------------------------- 15-bx
ub15_scene() {  # ub15_scene <save> [away] : load, quiet spot, Malzin to the far spot, every old fight row gone.  v2: with `away` X (the row NPC) and Shay also go to the
  # far spot BEFORE the caller spawns the pair, so X never stands inside the fight audience (ShoutRadius 200) while the events are emitted.  away.txt records it.
  hxd_load "$1" || return $?; hxd_scene || return $?; hxd_dbclean
  printf 'stobe-auto teleport Malzin %s </dev/null | head -1\n' "$HX_FAR" | lt_h >> "$EV/quiet.txt" 2>&1
  lt_sqlx "delete from eventlog where type in ('combat','combat_start','combat_end')" >> "$EV/clean.txt" 2>&1
  UB_NPC="$RL_NPC_FULL"
  if [ "${2:-}" = away ]; then
    local ax ay az; read ax ay az <<<"$HX_FAR"   # default (ticket sfU): HX_FAR.  HX15_AWAY=near: spot+HX15_OUT (the squad then keeps the fight zone loaded)
    if [ "${HX15_AWAY:-far}" = near ]; then read ax ay az <<<"$HX_SPOT"; ax=$(awk -v v="$ax" -v d="${HX15_OUT:-320}" 'BEGIN{printf "%.0f", v+d}'); fi
    printf 'stobe-auto protect %s on </dev/null | head -1\nstobe-auto teleport %s %s %s %s </dev/null | head -1\nstobe-auto teleport Shay %s </dev/null | head -1\n' \
      "$(rl_q "$UB_NPC")" "$(rl_q "$UB_NPC")" "$ax" "$ay" "$az" "$(rl_q "$UB_NPC")" | lt_h >> "$EV/place.txt" 2>&1
    echo "X ($UB_NPC) and Shay sent to ${HX15_AWAY:-far} ($ax $ay $az) before the pair is spawned" >> "$EV/phases.txt"
    echo "$(date +%T) away=${HX15_AWAY:-far} $UB_NPC -> $ax $ay $az" >> "$EV/away.txt"
    if [ -n "${HXD:-}" ] && [ "$HXD" != "$EV" ]; then cp "$EV/away.txt" "$HXD/away.txt" 2>/dev/null; fi
    return 0
  fi
}
ub15_sleep_state() {  # ub15_sleep_state <tag> <sleeper handle> : append `<tag>|<state fields>` to <bundle>/S1/sleep_state.txt (stobe_state: unconscious, first_order, current_goal, dead)
  local tag="$1" sid="$2" js st
  mkdir -p "$HXD/S1"
  js=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 6000\n' "$(rl_q "$sid")" | lt_h 2>&1)
  st=$(echo "$js" | grep -oE '"(dead|unconscious|first_order|current_goal)": ?("[^"]*"|[a-z]+)' | tr '\n' ' ')
  uc_dry && st="${st:-\"unconscious\":false \"first_order\":\"SLEEP_ON_FLOOR\"}"
  echo "$tag|$st" >> "$HXD/S1/sleep_state.txt"
}
ub15_pair() {  # fresh pair at the spot -> UB_ID1 UB_ID2 UB_FN (comma list: current + spawn names) UB_STARTER ; rc 3 + RL_REASON
  local fac="${HX15_FACTION:-Holy Nation Outlaws}" o1 o2 n1 n2 mk cand c w
  ub_spawn "$fac" 0 || return $?; UB_ID1="$UB_ID"; o1="$UB_SHORT"
  ub_spawn "${HX15_FACTION2:-Dust Bandits}" 6 || return $?; UB_ID2="$UB_ID"; o2="$UB_SHORT"
  mk=$(hxd_rowid)
  hxd_fight "$UB_ID1" "$UB_ID2"; hxd_sleep "${HX15_WAIT:-10}"
  n1=$(ub_name "$UB_ID1"); n2=$(ub_name "$UB_ID2")
  uc_dry && { n1="${n1:-$o1}"; n2="${n2:-$o2}"; }
  [ -n "$n1" ] && [ -n "$n2" ] || { RL_REASON="cannot read the fighters back by handle ($UB_ID1 / $UB_ID2): they are gone or the fight killed them"; return 3; }
  UB_FN=$(printf '%s\n' "${n1%% *}" "${n2%% *}" "$o1" "$o2" | awk 'NF && !s[$0]++' | paste -sd, -)
  echo "pair ids=$UB_ID1,$UB_ID2 spawned=$o1,$o2 now=$n1 / $n2 fighters=$UB_FN mark=$mk" >> "$EV/phases.txt"
  cand=$(lt_sql "select data from eventlog where type='combat' and rowid>$mk and data like '%Initiated attack%' order by gamets asc, rowid asc limit 20")
  UB_STARTER=""
  while IFS= read -r c; do w="${c%%:*}"; w="${w%% *}"; [ -n "$w" ] || continue; case ",$UB_FN," in *",$w,"*) UB_STARTER="$w"; break;; esac; done <<<"$cand"
  uc_dry && UB_STARTER="${UB_STARTER:-${n1%% *}}"
  [ -n "$UB_STARTER" ] || { RL_REASON="no 'Initiated attack' row by one of the fighters ($UB_FN) after the fight started (first candidates: $(echo "$cand" | head -2 | cut -c1-100 | tr '\n' ' ')); v2 hint: with X+Shay at the far spot the fight zone may be unloaded - retry with --away near"; return 3; }
  echo "starter=$UB_STARTER" >> "$EV/phases.txt"
}
ub15_place_x() {  # ub15_place_x <label> : X at spot+out, Shay on X, distance.txt (X to F1) >= 255 or SETUP-FAIL (3 tries, +40 u each)
  local lab="$1" try out="${HX15_OUT:-320}" x y z
  read x y z <<<"$HX_SPOT"; x=$(awk -v v="$x" -v d="$out" 'BEGIN{printf "%.0f", v+d}')
  for try in 1 2 3; do
    printf 'stobe-auto teleport %s %s %s %s </dev/null | head -1\nstobe-auto teleport Shay %s </dev/null | head -1\n' "$(rl_q "$UB_NPC")" "$x" "$y" "$z" "$(rl_q "$UB_NPC")" | lt_h >> "$EV/place.txt" 2>&1
    hxd_dist "$lab" "$UB_ID1" "$UB_NPC" || return $?
    uc_dry && return 0
    awk -F'|' '{ if ($2+0 < 255) bad=1 } END{exit bad}' "$HXD/$lab/distance.txt" && return 0
    x=$(awk -v v="$x" 'BEGIN{printf "%.0f", v+40}')
  done
  RL_REASON="X could not be held >= 255 u from the fight at $lab ($(tr '\n' ' ' < "$HXD/$lab/distance.txt"))"; return 3
}
ub15_place_p() {  # ub15_place_p <label> : P within 15 u of F1 (teleport npc F1 dist 10 / 6 / 3), Shay on P
  local lab="$1" d
  for d in 10 6 3; do
    printf 'stobe-auto teleport %s %s dist %s </dev/null | head -1\nstobe-auto teleport Shay %s </dev/null | head -1\n' "$(rl_q "$UB_NPC")" "$(rl_q "$UB_ID1")" "$d" "$(rl_q "$UB_NPC")" | lt_h >> "$EV/place.txt" 2>&1
    hxd_dist "$lab" "$UB_ID1" "$UB_NPC" || return $?
    uc_dry && return 0
    awk -F'|' '{ if ($2+0 > 15) bad=1 } END{exit bad}' "$HXD/$lab/distance.txt" && return 0
  done
  RL_REASON="P could not be placed within 15 u of the fight at $lab ($(tr '\n' ' ' < "$HXD/$lab/distance.txt"))"; return 3
}
ub15_place_s() {  # ub15_place_s <sleeper handle> : S1 asleep, next to the fight (dist 60 / 40 / 25) , distance S1 label <= 100
  local sid="$1" d
  for d in 60 40 25; do
    printf 'stobe-auto teleport %s %s dist %s </dev/null | head -1\nstobe-auto teleport Shay %s </dev/null | head -1\n' "$(rl_q "$sid")" "$(rl_q "$UB_ID1")" "$d" "$(rl_q "$sid")" | lt_h >> "$EV/place.txt" 2>&1
    mkdir -p "$HXD/S1"; hxd_dist S1 "$UB_ID1" "$sid" || return $?
    uc_dry && return 0
    awk -F'|' '{ if ($2+0 > 100) bad=1 } END{exit bad}' "$HXD/S1/distance.txt" && return 0
  done
  RL_REASON="sleeper S1 not within 100 u of the fight ($(tr '\n' ' ' < "$HXD/S1/distance.txt"))"; return 3
}
rd_15bx() {
  hxd_begin; rd_need_npc || return 3
  local m0 i q lab s1id fn_x st_x
  local -a qs=("Who started the fight?" "What happened over there?" "Did you see who attacked first?")
  echo "ShoutRadius 200 / TalkRadius 80 (Utils.cpp:1327-1348): X must be >= 250 u" > "$HXD/shout_radius.txt"
  # --- OUT phase
  ub15_scene "$HX_SAVE" away || return $?; m0=$(hxd_rowid)
  ub_spawn "${HX15_SLEEPER_FACTION:-Drifters}" 40 || return $?; s1id="$UB_ID"
  printf 'stobe-auto sleep %s </dev/null 2>&1 | head -2\n' "$(rl_q "$s1id")" | lt_h >> "$EV/sleeper.txt" 2>&1
  mkdir -p "$HXD/S1"; : > "$HXD/S1/sleep_state.txt"
  ub15_sleep_state ordered "$s1id"
  ub15_pair || return $?; fn_x="$UB_FN"; st_x="$UB_STARTER"
  ub15_sleep_state after_fight "$s1id"
  printf 'stobe-auto protect %s on </dev/null | head -1\n' "$(rl_q "$UB_NPC")" | lt_h >> "$EV/place.txt" 2>&1
  printf 'stobe-auto chars 300 </dev/null 2>&1 | sed "s/ | /\\n/g" | grep -E "#[0-9]+/[0-9]+" | cut -c1-80\n' | lt_h > "$EV/roster.txt" 2>&1
  i=0; for q in "${qs[@]}"; do i=$((i+1)); lab="X$i"; mkdir -p "$HXD/$lab"
    ub15_place_x "$lab" || return $?
    hxd_sample "$lab" "$q" "$UB_NPC" || return $?; HXD_DFILE=distance_after.txt hxd_dist "$lab" "$UB_ID1" "$UB_NPC" || return $?
  done
  ub15_place_s "$s1id" || return $?
  ub15_sleep_state sample "$s1id"
  hxd_sample S1 "Who started the fight?" "$s1id" 25 noreply || return $?
  hxd_trim "$m0"
  # --- IN phase: a fresh load, P within 15 u of a fresh pair, saw it start
  ub15_scene "${HX_SAVE2:-$HX_SAVE}" || return $?; hxd_trim "$m0"
  ub15_pair || return $?
  printf '%s\n' "$fn_x,$UB_FN" | tr ',' '\n' | awk 'NF && !s[$0]++' | paste -sd, - > "$HXD/fighters.txt"
  echo "$UB_STARTER" > "$HXD/starter.txt"; echo "$st_x" > "$HXD/starter_out_phase.txt"
  i=0; for q in "${qs[@]}"; do i=$((i+1)); lab="P$i"; mkdir -p "$HXD/$lab"
    ub15_place_p "$lab" || return $?
    hxd_sample "$lab" "$q" "$UB_NPC" || return $?; HXD_DFILE=distance_after.txt hxd_dist "$lab" "$UB_ID1" "$UB_NPC" || return $?
  done
  hxd_trim "$m0"
}

# ---------------------------------------------------------------------------------------------- runner
uc_usage() { echo "usage: unblockdefs_c_v2.sh <15-bx> <lane: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4> [--save S] [--save2 S] [--no-reload] [--dry] [--allow-retry 'why'] [--out DIR] [--out-dist U] [--faction F] [--away far|near]" >&2; }
uc_main() {
  local ROW="" LANE="" RELOAD=1 ALLOW=() norm pf prc out rc n f SAVE=""
  while [ $# -gt 0 ]; do case "$1" in
    --save) SAVE="$2"; shift 2;; --save2) export HX_SAVE2="$2"; shift 2;; --out) export HX_OUT="$2"; shift 2;; --out-dist) export HX15_OUT="$2"; shift 2;;
    --faction) export HX15_FACTION="$2"; shift 2;; --away) export HX15_AWAY="$2"; shift 2;; --victim) export UB_VICTIM="$2"; shift 2;; --gift) export UB_GIFT="$2"; shift 2;;
    --dest) export TRIP_DEST="$2"; shift 2;; --alt) export TRIP_ALT="$2"; shift 2;;
    --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
    --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
    -h|--help) uc_usage; return 0;;
    *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; uc_usage; return 2; fi; shift;;
  esac; done
  [ -n "$ROW" ] && [ -n "$LANE" ] || { uc_usage; return 2; }
  norm="${ROW#IMM-}"
  case "$norm" in 15-bx) ;; *) echo "RESULT $ROW SETUP-FAIL not a v2 row (only 15-bx; 20-a / 10-b: unblockdefs_c.sh)"; return 2;; esac
  export HX_ASSERT_DIR="$UC_HERE/../v2"    # hxcheck.py (called by unblockcheck_c_v2.py) takes assert_*.py + imm26_lib.py from the v2 directory
  export UC_LOADED=1; . "$UC_HERE/../go-row.sh"; . "$UC_HERE/hxdefs.sh"; . "$UC_SELF"    # libraries first, then OUR rd_15bx wins
  PY="$UC_SELF"
  lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; return 2; }
  SAVE="${SAVE:-$(uc_lane_save)}"
  ROW_NPC="${ROW_NPC:-$UC_NPC_DEF}"
  export ROW_NPC; export TRIP_SAVE="$SAVE" HX_SAVE="$SAVE"; tr_cfg
  mkdir -p "$LT_OUT"; local RLOG="$LT_OUT/$ROW.reload.log"
  if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
  if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
    [ -n "$SAVE" ] || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL no ready save known for lane $LANE (use --save S)"; return 2; }
    tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; return 2; }
    [ "$norm" = 15-bx ] && export HX_PRELOADED=1
  fi
  pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
  if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; return 2; fi
  out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
  n=0; for f in phases.txt away.txt sleeper.txt fighters.txt; do
    [ -s "$LT_OUT/$ROW/$f" ] && [ $n -lt 4 ] && { echo "EVIDENCE $ROW $f: $(tail -3 "$LT_OUT/$ROW/$f" | tr '\n' ' ' | cut -c1-300)"; n=$((n+1)); }
  done
  echo "$out" | head -1
  return $rc
}
if [ "$UC_EXEC" = 1 ] && [ -z "${UC_LOADED:-}" ]; then uc_main "$@"; exit $?; fi
