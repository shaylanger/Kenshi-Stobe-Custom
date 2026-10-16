#!/usr/bin/env bash
# unblockdefs_c_v4.sh (imm26-fix15bx05cx3, 2026-10-16) = v3c (= v3b + rename poll 30x2 s) + the fixes from the i3 live run op23 (C:/KenshiTestRuns/agents/out/imm26-5090-i3op23/out-20261016-143022.md).  NEW file; v3/v3b/v3c are NOT edited.
#   V4 CHANGES: (1) the pair gets its OWN names at spawn (`setname <#handle> <name>`, HX15_NAMES default "Garrick Odrun"; --names 'A B'): spawned fighters stayed "Hungry Bandit" for ever (the server
#      never renamed them in 60 s) and the old starter query (first 20 combat rows by time) was flooded by AMBIENT Dust Bandit fights (Grink, Saint, Noric ...: tr_quiet piles every bystander at HX_FAR).
#      The starter is now read with a SQL filter on the fighters' names (`Initiated attack` rows whose actor is one of them), polled <= 30 s; evidence ours/total in phases.txt, a diagnosis file
#      pair_diag.txt (where of both fighters, fight.txt tail, ambient actors) on failure.  A fighter whose setname did not hold (read back by handle) falls back to its spawn name.
#      (2) `--away near` is the DEFAULT (HX15_AWAY=near; `--away far` unloads the spawned pair so `where #handle` errors).  (3) the base save must EXIST (hx4lib.sh): lane default for 5090-i3 is
#      kah-imm26-5090-ready (kah-imm26-5090-hxA never existed on i3 and the load silently kept the loaded world); a missing save = SETUP-FAIL SAVE-MISSING.  (4) KO gate polls (v3b) and rename poll (v3c)
#      are folded in; the rename poll only waits for the server when setname could not be applied.  Verdict checker unchanged (unblockcheck_c_v2.py).
#   FIX (imm26-fix15bxv5, op25 live P3 SETUP-FAIL 17.4 u > 15): ub15_place_p pins F1 (`order F1 HOLD_POSITION keep`, ub4_pin) before every placement try; the <= 15 u guard is unchanged.
#   RUN (one call): bash testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c_v4.sh 15-bx <lane> [--allow-retry "why"] [--save S] [--save2 S] [--names 'A B'] [--away far|near] ...
# (v3c header follows) unblockdefs_c_v3c.sh = v3b + rename poll up to HX15_RENAME_N (30) x 2 s (op23: 20 s was too short, fighters renamed later). v3b: v3 + S1 KO gate polls <=16 s (op23: first read right after the ko order says unconscious:false; 2 s later true). # unblockdefs_c_v3.sh (imm26-fix15bx05cx, 2026-10-16): v3 = v2 + the fixes diagnosed by imm26-inv15bx (C:/KenshiTestRuns/agents/out/imm26-inv15bx/out-20261016-134157.md); unblockdefs_c_v2.sh is NOT edited.
#   V3 CHANGES: (1) S1 is put to sleep with `ko <s1> ${HX15_KO_S:-900}` instead of `sleep` (the harness SLEEP_ON_FLOOR order is dropped at once by a spawned NPC's AI); a gate right after it
#   SETUP-FAILs in seconds unless stobe_state shows "unconscious":true; `ko <s1> 120` is re-issued right before the sample (game-time timer). (2) ub15_scene retires every active social_rumor
#   (stale first-hand "you saw it yourself" claims survive loads and made X/P prompts fail for an unrelated reason). (3) ub15_pair polls ub_name <= 20 s until the server renamed the spawns
#   (fighters were all "Hungry"), and the starter is taken from a renamed fighter first.  Verdict checker unchanged (unblockcheck_c_v2.py already accepts "unconscious":true).
# (v2 header follows) unblockdefs_c_v2.sh (imm26-sfU, 2026-10-16): v2 of the 15-bx one-call row script (unblockdefs_c.sh is NOT edited: an operator may be using it).  Only 15-bx lives here.
# WHY (fxA table, C:/KenshiTestRuns/agents/out/imm26-fxA/latest.md): in v1 the X NPC (Cind) stood at the fight spot, 16 u from the fighters, while the pair was spawned
#   and fought for 10 s, and was teleported to spot+320 only afterwards.  The DLL tags a fight's audience at emission (Utils.cpp:1313-1348), so Cind legitimately got the
#   early events.  S1's sleep state was never verified at event time.
# v2 CHANGES (nothing else differs from v1):
#   1. OUT phase: after the scene load X (the row NPC) AND Shay are teleported to HX_FAR (far spot, ~5000 u away; --away near = spot+320 instead, keeps the fight zone loaded) BEFORE ub15_pair; X is brought to spot+320 only for the
#      samples (ub15_place_x, unchanged), so no fight event can have listed X.  The IN phase is unchanged (P must be at the spot when the pair fights).
#   2. S1 sleep state is recorded: <bundle>/S1/sleep_state.txt, lines `<tag>|<unconscious/first_order/current_goal/dead of stobe_state>` for tags ordered (right after
#      `sleep`), after_fight (after the 10 s fight) and sample (right before the S1 sample); unblockcheck_c_v2.py makes "S1 not asleep/KO after the fight" a SETUP-FAIL.
#   RUN (one call):  bash testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c_v3.sh 15-bx <lane> [options]   (options as unblockdefs_c.sh: --save --save2 --no-reload
#      --dry --allow-retry "why" --out DIR --out-dist U --faction F).  The attempt guard blocks a row whose last attempt FAILed: add --allow-retry "sfU v2 scene".
#   Verdict: unblockcheck_c_v2.py (scene validation + S1 sleep check) -> hxcheck.py 15-bx with HX_ASSERT_DIR=imm26-assert/v2 (assert_witness.py unchanged, v2 imm26_lib.py).
#   Library use / shim mode: as unblockdefs_c.sh (`. unblockdefs_c_v3.sh` AFTER go-row.sh / hxdefs.sh; shim sends rowcheck.py 15-bx to unblockcheck_c_v2.py).

UC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UC_SELF="$UC_HERE/$(basename "${BASH_SOURCE[0]}")"
. "$UC_HERE/hx4lib.sh"

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
uc_lane_save() { hx4_lane_save "${LT_LANE:-}"; }   # v4: a save that exists (hx4lib.sh)
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
  lt_sqlx "update social_rumor set status='retired' where status='active'" >> "$EV/clean.txt" 2>&1   # v3: stale eyewitness claims (private lane DB)
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
  uc_dry && st="${st:-\"unconscious\":true \"first_order\":\"none\"}"
  echo "$tag|$st" >> "$HXD/S1/sleep_state.txt"
}
ub4_name_at() {  # ub4_name_at <n> : n-th word of HX15_NAMES (default "Garrick Odrun")
  local -a nm; read -r -a nm <<<"${HX15_NAMES:-Garrick Odrun}"; echo "${nm[$(($1-1))]:-Fighter$1}"
}
ub4_setname() {  # ub4_setname <#handle> <name> : own the fighter's name (single word); output kept in names.txt
  printf 'stobe-auto setname %s %s </dev/null 2>&1 | head -1\n' "$(rl_q "$1")" "$(rl_q "$2")" | lt_h >> "$EV/names.txt" 2>&1
  echo "$1 -> $2" >> "$EV/names.txt"
}
ub4_starter_sql() {  # ub4_starter_sql <mark rowid> <name,name,..> : `Initiated attack` rows whose ACTOR is one of the names (the ambient fights of other bandits are not ours)
  local or="" w
  for w in $(echo "$2" | tr ',' ' '); do or="${or:+$or or }data like '$w:%'"; done
  printf "select data from eventlog where type='combat' and rowid>%s and data like '%%Initiated attack%%' and (%s) order by gamets asc, rowid asc limit 10" "$1" "${or:-false}"
}
ub15_pair() {  # fresh pair at the spot -> UB_ID1 UB_ID2 UB_FN (comma list of the fighters' names) UB_STARTER ; rc 3 + RL_REASON.  v4: own names via setname, starter by SQL name filter
  local fac="${HX15_FACTION:-Holy Nation Outlaws}" o1 o2 n1 n2 mk cand c w a1 a2 try total ours rn
  ub_spawn "$fac" 0 || return $?; UB_ID1="$UB_ID"; o1="$UB_SHORT"
  ub_spawn "${HX15_FACTION2:-Dust Bandits}" 6 || return $?; UB_ID2="$UB_ID"; o2="$UB_SHORT"
  a1=$(ub4_name_at 1); a2=$(ub4_name_at 2)
  ub4_setname "$UB_ID1" "$a1"; ub4_setname "$UB_ID2" "$a2"
  mk=$(hxd_rowid)
  hxd_fight "$UB_ID1" "$UB_ID2"; hxd_sleep "${HX15_WAIT:-10}"
  n1=$(ub_name "$UB_ID1"); n2=$(ub_name "$UB_ID2")
  if ! uc_dry; then   # the setname normally holds; only while a fighter still carries its spawn name wait (<= HX15_RENAME_N x 2 s) for the server rename
    for w in $(seq 1 ${HX15_RENAME_N:-30}); do
      case "${n1%% *}|${n2%% *}" in "$a1|$a2") break;; esac
      case "$n1|$n2" in *"Hungry Bandit"*) ;; "|"*|*"|") ;; *) break;; esac
      uc_sleep 2; n1=$(ub_name "$UB_ID1"); n2=$(ub_name "$UB_ID2")
    done
    echo "rename_poll rounds=$w now=$n1 / $n2" >> "$EV/phases.txt"
  fi
  uc_dry && { n1="${n1:-$a1}"; n2="${n2:-$a2}"; }
  [ -n "$n1" ] && [ -n "$n2" ] || { RL_REASON="cannot read the fighters back by handle ($UB_ID1 / $UB_ID2): they are gone, unloaded (use --away near, the default) or the fight killed them"; return 3; }
  # fighters = the assigned names + the names they carry now; a fighter that did not take its assigned name also contributes its spawn name
  UB_FN=$(printf '%s\n' "$a1" "$a2" "${n1%% *}" "${n2%% *}" | awk 'NF && !s[$0]++' | paste -sd, -)
  case "${n1%% *}" in "$a1") ;; *) UB_FN="$UB_FN,$o1";; esac
  case "${n2%% *}" in "$a2") ;; *) UB_FN="$UB_FN,$o2";; esac
  UB_FN=$(echo "$UB_FN" | tr ',' '\n' | awk 'NF && !s[$0]++' | paste -sd, -)
  echo "pair ids=$UB_ID1,$UB_ID2 spawned=$o1,$o2 assigned=$a1,$a2 now=$n1 / $n2 fighters=$UB_FN mark=$mk" >> "$EV/phases.txt"
  cand=""; UB_STARTER=""
  for try in 1 2 3 4 5 6 7 8 9 10; do   # the first "Initiated attack" of the pair can take a few game seconds; poll <= 30 s
    cand=$(lt_sql "$(ub4_starter_sql "$mk" "$UB_FN")")
    [ -n "$cand" ] && break; uc_dry && break; uc_sleep 3
  done
  rn=",$UB_FN,"
  while IFS= read -r c; do w="${c%%:*}"; w="${w%% *}"; [ -n "$w" ] || continue; case "$rn" in *",$w,"*) UB_STARTER="$w"; break;; esac; done <<<"$cand"
  uc_dry && UB_STARTER="${UB_STARTER:-${n1%% *}}"
  total=$(lt_sql "select count(*) from eventlog where type='combat' and rowid>$mk and data like '%Initiated attack%'" | head -1 | tr -dc 0-9)
  ours=$(printf '%s\n' "$cand" | grep -c .)
  echo "combat_rows initiated_total=${total:-?} ours=$ours" >> "$EV/phases.txt"
  if [ -z "$UB_STARTER" ]; then
    { echo "fighters=$UB_FN ids=$UB_ID1,$UB_ID2 mark=$mk"
      printf 'stobe-auto where %s </dev/null 2>&1 | head -1\nstobe-auto where %s </dev/null 2>&1 | head -1\n' "$(rl_q "$UB_ID1")" "$(rl_q "$UB_ID2")" | lt_h 2>&1
      echo "--- fight.txt tail"; tail -3 "$EV/fight.txt" 2>/dev/null
      echo "--- ambient Initiated-attack rows after the mark"; lt_sql "select left(data,80) from eventlog where type='combat' and rowid>$mk and data like '%Initiated attack%' order by rowid limit 12"; } > "$EV/pair_diag.txt" 2>&1
    RL_REASON="no 'Initiated attack' row by one of the fighters ($UB_FN) within 30 s after the fight started (Initiated-attack rows after the mark: ${total:-?}, by our pair: 0; see pair_diag.txt: where of both, fight.txt, ambient rows). Not within reach of each other (unloaded zone) or the fight order was refused; needs: recipe"; return 3
  fi
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
ub4_pin() {  # ub4_pin <#handle> : imm26-fix15bxv5: freeze the fighter in place (HOLD_POSITION) so it does not run off between the teleport and the distance read (op25 live: P3 17.4 u, limit 15).
  # The order reply goes to pin.txt (evidence only).  The distance guard in ub15_place_p is NOT relaxed.
  printf 'stobe-auto order %s HOLD_POSITION keep </dev/null 2>&1 | head -1\n' "$(rl_q "$1")" | lt_h >> "$EV/pin.txt" 2>&1
  echo "$(date +%T) pinned $1 (HOLD_POSITION keep)" >> "$EV/pin.txt"
}
ub15_place_p() {  # ub15_place_p <label> : F1 pinned (HOLD_POSITION), then P within 15 u of F1 (teleport npc F1 dist 10 / 6 / 3), Shay on P; the pin is re-issued before every try
  local lab="$1" d
  for d in 10 6 3; do
    ub4_pin "$UB_ID1"
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
    # v4c (5090-i3 op29: fighters drift during X1-X3, a KO'd S1 cannot be teleported, S1 567 u away): the AWAKE fighter F1 is pinned and moved next to S1 instead; Shay goes to S1
    ub4_pin "$UB_ID1"
    printf 'stobe-auto teleport %s %s dist %s </dev/null | head -1
stobe-auto teleport Shay %s </dev/null | head -1
' "$(rl_q "$UB_ID1")" "$(rl_q "$sid")" "$d" "$(rl_q "$sid")" | lt_h >> "$EV/place.txt" 2>&1
    mkdir -p "$HXD/S1"; hxd_dist S1 "$UB_ID1" "$sid" || return $?
    uc_dry && return 0
    awk -F'|' '{ if ($2+0 > 100) bad=1 } END{exit bad}' "$HXD/S1/distance.txt" && return 0
  done
  RL_REASON="sleeper S1 not within 100 u of the fight ($(tr '\n' ' ' < "$HXD/S1/distance.txt"))"; return 3
}
ub15_say() {  # ub15_say <label> "text" <place fn> : hxd_sample for X/P.  ticket sfU2 (5090-i3 P1 "no reply within 150 s"): the reply WAS generated (eventlog chat row `Cind...|cancelled`) but never
  # spoken (no ACTION_EXEC SAY), so hxd_sample timed out.  (The rl_say (NPC)|(PC) wait is NOT the cause: hxd_sample already accepts both.)  v2: if the only failure is "no reply" AND the bundle
  # has a cancelled chat row of the NPC, the first try is kept in $EV/retry/<label>-try1, the NPC is placed again and the say is repeated ONCE; a second cancellation is a SETUP-FAIL that names it.
  local lab="$1" q="$2" placefn="$3" rc d="$HXD/$1"
  hxd_sample "$lab" "$q" "$UB_NPC"; rc=$?
  [ $rc = 3 ] || return $rc
  uc_dry && return $rc
  case "$RL_REASON" in *"no reply of"*) ;; *) return $rc;; esac
  grep -qE '^[0-9]+[|]chat[|].*[|]cancelled' "$d/events.txt" 2>/dev/null || return $rc
  mkdir -p "$EV/retry"; rm -rf "$EV/retry/$lab-try1"; cp -r "$d" "$EV/retry/$lab-try1"
  grep -E '[|]cancelled' "$d/events.txt" | cut -c1-300 > "$EV/retry/$lab-cancelled.txt"
  echo "$(date +%T) $lab: reply generated but cancelled, placing again and repeating the say once" >> "$EV/phases.txt"
  rm -rf "$d"; mkdir -p "$d"; $placefn "$lab" || return $?
  hxd_sample "$lab" "$q" "$UB_NPC"; rc=$?
  [ $rc = 0 ] || { case "$RL_REASON" in *"no reply of"*) RL_REASON="$RL_REASON; the first try AND the retry produced a cancelled chat row (reply generated, not spoken: NPC busy/in combat?), see $EV/retry/$lab-cancelled.txt";; esac; }
  return $rc
}
rd_15bx() {
  hxd_begin; rd_need_npc || return 3
  local m0 i q lab s1id fn_x st_x
  local -a qs=("Who started the fight?" "What happened over there?" "Did you see who attacked first?")
  echo "ShoutRadius 200 / TalkRadius 80 (Utils.cpp:1327-1348): X must be >= 250 u" > "$HXD/shout_radius.txt"
  # --- OUT phase
  ub15_scene "$HX_SAVE" away || return $?; m0=$(hxd_rowid)
  ub_spawn "${HX15_SLEEPER_FACTION:-Drifters}" 40 || return $?; s1id="$UB_ID"
  # v4b (5090-i3 op28 15-bx SETUP-FAIL S1 229 u): a KO'd character cannot be teleported (moved=0 method=none), so S1 goes next to Shay (= the spot the pair spawns at) BEFORE the ko order
  printf 'stobe-auto teleport %s Shay dist 25 </dev/null | head -1
' "$(rl_q "$s1id")" | lt_h >> "$EV/place.txt" 2>&1
  printf 'stobe-auto ko %s %s </dev/null 2>&1 | head -2\n' "$(rl_q "$s1id")" "${HX15_KO_S:-900}" | lt_h >> "$EV/sleeper.txt" 2>&1
  mkdir -p "$HXD/S1"; : > "$HXD/S1/sleep_state.txt"
  ub15_sleep_state ordered "$s1id"
  for i in 1 2 3 4 5 6 7 8; do uc_dry && break; grep -qE '"unconscious": ?true' "$HXD/S1/sleep_state.txt" && break; uc_sleep 2; : > "$HXD/S1/sleep_state.txt"; ub15_sleep_state ordered "$s1id"; done   # v3b: the KO lands on the next game tick; poll <= 16 s before the gate
  uc_dry || grep -qE '"unconscious": ?true' "$HXD/S1/sleep_state.txt" || { RL_REASON="S1 not KO right after the ko order ($(tr '\n' ' ' < "$HXD/S1/sleep_state.txt" | cut -c1-160)); needs: recipe"; return 3; }
  ub15_pair || return $?; fn_x="$UB_FN"; st_x="$UB_STARTER"
  ub15_sleep_state after_fight "$s1id"
  printf 'stobe-auto protect %s on </dev/null | head -1\n' "$(rl_q "$UB_NPC")" | lt_h >> "$EV/place.txt" 2>&1
  printf 'stobe-auto chars 300 </dev/null 2>&1 | sed "s/ | /\\n/g" | grep -E "#[0-9]+/[0-9]+" | cut -c1-80\n' | lt_h > "$EV/roster.txt" 2>&1
  i=0; for q in "${qs[@]}"; do i=$((i+1)); lab="X$i"; mkdir -p "$HXD/$lab"
    ub15_place_x "$lab" || return $?
    ub15_say "$lab" "$q" ub15_place_x || return $?; HXD_DFILE=distance_after.txt hxd_dist "$lab" "$UB_ID1" "$UB_NPC" || return $?
  done
  ub15_place_s "$s1id" || return $?
  printf 'stobe-auto ko %s 120 </dev/null 2>&1 | head -2\n' "$(rl_q "$s1id")" | lt_h >> "$EV/sleeper.txt" 2>&1   # the KO timer runs in game time: X1-X3 + S1 take minutes
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
    ub15_say "$lab" "$q" ub15_place_p || return $?; HXD_DFILE=distance_after.txt hxd_dist "$lab" "$UB_ID1" "$UB_NPC" || return $?
  done
  hxd_trim "$m0"
}

# ---------------------------------------------------------------------------------------------- runner
uc_usage() { echo "usage: unblockdefs_c_v4.sh <15-bx> <lane: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4> [--save S] [--save2 S] [--no-reload] [--dry] [--allow-retry 'why'] [--out DIR] [--out-dist U] [--faction F] [--names 'A B'] [--away near|far (default near)]" >&2; }
uc_main() {
  local ROW="" LANE="" RELOAD=1 ALLOW=() norm pf prc out rc n f SAVE=""
  while [ $# -gt 0 ]; do case "$1" in
    --save) SAVE="$2"; shift 2;; --save2) export HX_SAVE2="$2"; shift 2;; --out) export HX_OUT="$2"; shift 2;; --out-dist) export HX15_OUT="$2"; shift 2;;
    --faction) export HX15_FACTION="$2"; shift 2;; --away) export HX15_AWAY="$2"; shift 2;; --names) export HX15_NAMES="$2"; shift 2;; --victim) export UB_VICTIM="$2"; shift 2;; --gift) export UB_GIFT="$2"; shift 2;;
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
  SAVE="${SAVE:-$(uc_lane_save)}"; export HX15_AWAY="${HX15_AWAY:-near}"   # v4: near is the default (far unloads the pair)
  for f in "$SAVE" "${HX_SAVE2:-}"; do   # a missing save makes `stobe-auto load` keep the loaded world silently: fail loudly
    [ -n "$f" ] || continue
    hx4_save_check "$f" || { echo "RESULT $ROW SETUP-FAIL SAVE-MISSING $HX4_WHY"; return 2; }
    [ -z "$HX4_WHY" ] || echo "NOTE $ROW $HX4_WHY" >&2
  done
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
  n=0; for f in phases.txt names.txt pair_diag.txt away.txt sleeper.txt fighters.txt; do
    [ -s "$LT_OUT/$ROW/$f" ] && [ $n -lt 5 ] && { echo "EVIDENCE $ROW $f: $(tail -3 "$LT_OUT/$ROW/$f" | tr '\n' ' ' | cut -c1-300)"; n=$((n+1)); }
  done
  echo "$out" | head -1
  return $rc
}
if [ "$UC_EXEC" = 1 ] && [ -z "${UC_LOADED:-}" ]; then uc_main "$@"; exit $?; fi
