#!/usr/bin/env bash
# reloaddefs_sf26bd.sh (imm26-sf26bd): sourced AFTER reloaddefs_sfi/sfo/sfp.sh. NEW file; no operator script is edited. Fixes the TEST ARTEFACTS behind the 26-b and 26-d FAILs (diagnosis
# agents/out/imm26-inv26/latest.md): the NPC was far outside TalkRadius (80), so the native BuildPeopleJson left her out of `people` in the dispatched inputtext, so the server
# dropped the activity chat context ("Activity chat context rejected") and no CANCEL / RESUME happened.
#   1. rl_say wrapper, CANCEL teleport (26-b / 26-dx): for a say whose text starts with "Cancel" Shay is teleported next to the NPC (`teleport Shay '<NPC full name>'`, sleep
#      RW_CANCEL_TP_WAIT 0.5 s) INSIDE the say's harness body, right before stobe_say (she walks ~12 u/s). RW_CANCEL_TELEPORT=0 disables. (Fallback when the sfp rl_say anchor is
#      missing: sb_teleport_shay before the whole say, distance > RW_TALK_MAX 70 u = SETUP-FAIL.)
#   2. rl_say wrapper, PEOPLE GUARD (every row that uses this file): after the say the FIRST stobe.log line "CHAT: dispatched inputtext ... people=[...]" since the say's mark must
#      list the NPC, i.e. contain  "<name>|  or  "<name> [  (name = RL_NPC_FULL or the part before " ["). Otherwise rc 3 = SETUP-FAIL
#      "test artefact: NPC outside TalkRadius, see imm26-inv26 ...". Evidence s<N>/dispatched.txt. RW_PEOPLE_GUARD=0 disables.
#      Exact manual check:  grep -a "CHAT: dispatched inputtext" <stobe.log> | grep -F '"Malzin|'     (empty = the server never saw her; the row is a SETUP-FAIL, not a FAIL)
#   3. rw_save_load wrapper, REGROUP GUARD (26-d): the NPC that reload-cycle / rd19_place re-places after the load must be ROW_NPC (default ROW_NPC is Cind; runners of this family
#      default it to Malzin). regroup.txt may only contain `teleported: <ROW_NPC>` lines; RL_NPC_FULL must be ROW_NPC. Otherwise SETUP-FAIL. RW_REGROUP_GUARD=0 disables.
# Env: RW_CANCEL_TELEPORT RW_CANCEL_TP_WAIT RW_TALK_MAX RW_PEOPLE_GUARD RW_REGROUP_GUARD RW_REQUIRE_NPC (runner default Malzin: ROW_NPC must be it).
SB_ART="test artefact: NPC outside TalkRadius, see imm26-inv26"

# sb_say_orig = the current rl_say (sfp) with ONE inserted line: $SB_PRE_SAY, run in the SAME harness body right before `stobe_say` (so the teleport happens after ctxpush / prep / mark and
# the say follows within ~0.5 s: the NPC walks ~12 u/s, TalkRadius is 80). SB_PATCH_OK=0 when the anchor is missing (then the cancel falls back to sb_teleport_shay before the whole rl_say).
SB_PATCH_OK=0; SB_SRC="$(declare -f rl_say | tail -n +2)"
case "$SB_SRC" in *'stobe-auto stobe_say "$tgt"'*)
  SB_SRC="${SB_SRC/'stobe-auto stobe_say "$tgt"'/$'$SB_PRE_SAY
stobe-auto stobe_say "$tgt"'}"; SB_PATCH_OK=1;; esac
eval "sb_say_orig () $SB_SRC"
eval "sb_save_load_orig () $(declare -f rw_save_load | tail -n +2)"
SB_PRE_SAY=""

sb_base() { local n="$1"; echo "${n%% \[*}"; }

sb_teleport_shay() {   # Shay next to the NPC right before a cancel say; rc 3 + RL_REASON when she is still out of range
  local f="$EV/cancel_teleport.txt" npc
  [ -n "${RL_NPC_ID:-}" ] || rl_resolve >/dev/null 2>&1 || { RL_REASON="cannot resolve ${ROW_NPC:-Cind} before the cancel say (stobe-auto where)"; return 3; }
  npc="$RL_NPC_FULL"
  echo "before: $npc dist=${RL_DIST:-?}" >> "$f"
  lt_h <<EOT >> "$f" 2>&1
stobe-auto teleport Shay $(rl_q "$npc") </dev/null | head -1 | cut -c1-160
sleep ${RW_CANCEL_TP_WAIT:-1.5}
EOT
  rl_resolve >/dev/null 2>&1 || { RL_REASON="cannot resolve ${ROW_NPC:-Cind} after teleporting Shay to her"; return 3; }
  echo "after: $RL_NPC_FULL dist=${RL_DIST:-?}" >> "$f"
  if awk -v d="${RL_DIST:-0}" -v m="${RW_TALK_MAX:-70}" 'BEGIN{exit !(d+0>m+0)}'; then
    RL_REASON="$SB_ART: still ${RL_DIST} u from $RL_NPC_FULL after teleporting Shay to her; the cancel would not reach the server (see $f)"; return 3
  fi
  return 0
}

sb_people_guard() {   # sb_people_guard <step>: the NPC must be in people= of the dispatched inputtext of that say
  [ "${RW_PEOPLE_GUARD:-1}" = 1 ] || return 0
  local d="$EV/s$1" l first full base
  l=$(sed -nE 's/^mark=[0-9]+ [0-9]+ ([0-9]+) .*/\1/p' "$d/meta.txt" 2>/dev/null | head -1); l=${l:-0}
  lt_h <<EOT > "$d/dispatched.txt" 2>&1
tail -n +$((l+1)) $(rl_q "$LT_STOBELOG") | grep -a "CHAT: dispatched inputtext" | cut -c1-500 | head -3
EOT
  full="${RL_NPC_FULL:-${ROW_NPC:-Cind}}"; base=$(sb_base "$full")
  first=$(grep -a 'dispatched inputtext' "$d/dispatched.txt" | head -1)
  if [ -z "$first" ]; then
    RL_REASON="$SB_ART: no 'CHAT: dispatched inputtext' line after the say in s$1, cannot prove $full was in people= (see $d/dispatched.txt)"; return 3
  fi
  if printf '%s\n' "$first" | grep -qF "\"$full|" || printf '%s\n' "$first" | grep -qF "\"$base|" || printf '%s\n' "$first" | grep -qF "\"$base ["; then
    echo "people-guard s$1 OK: $base in people=" >> "$EV/people_guard.txt"; return 0
  fi
  echo "people-guard s$1 MISSING: $base not in: $(printf '%s' "$first" | sed -E 's/.*people=//' | cut -c1-200)" >> "$EV/people_guard.txt"
  RL_REASON="$SB_ART: $base missing from people= of the dispatched inputtext in s$1 ($(printf '%s' "$first" | sed -E 's/.*people=//' | cut -c1-120)); dist=${RL_DIST:-?}; the server dropped the activity chat context (see $d/dispatched.txt)"
  return 3
}

rl_say() {   # rl_say <N> "text" [wait_s]   (sfp rl_say + cancel teleport + people guard)
  local rc iscancel=0
  case "${2:-}" in Cancel*|cancel*) [ "${RW_CANCEL_TELEPORT:-1}" = 1 ] && iscancel=1;; esac
  SB_PRE_SAY=""
  if [ $iscancel = 1 ]; then
    [ -n "${RL_NPC_ID:-}" ] || rl_resolve >/dev/null 2>&1 || { RL_REASON="cannot resolve ${ROW_NPC:-Cind} before the cancel say (stobe-auto where)"; return 3; }
    echo "cancel step $1: $RL_NPC_FULL dist=${RL_DIST:-?} before the teleport" >> "$EV/cancel_teleport.txt"
    if [ "$SB_PATCH_OK" = 1 ]; then
      SB_PRE_SAY="stobe-auto teleport Shay $(rl_q "$RL_NPC_FULL") </dev/null | head -1 | cut -c1-160"$'
'"sleep ${RW_CANCEL_TP_WAIT:-0.5}"
    else
      sb_teleport_shay || return $?
    fi
  fi
  sb_say_orig "$@"; rc=$?
  SB_PRE_SAY=""
  [ $rc = 0 ] || return $rc
  sb_people_guard "$1" || return 3
  return 0
}

sb_regroup_guard() {   # after a load the NPC that was re-placed must be ROW_NPC (the default ROW_NPC=Cind teleported Cind, not Malzin: imm26-inv26)
  [ "${RW_REGROUP_GUARD:-1}" = 1 ] || return 0
  local want base f="$EV/regroup.txt" t
  want="${ROW_NPC:-}"; base=$(sb_base "$want"); [ -n "$base" ] || return 0
  if [ -n "${RW_REQUIRE_NPC:-}" ] && [ "$base" != "$(sb_base "$RW_REQUIRE_NPC")" ]; then
    RL_REASON="$SB_ART: ROW_NPC is '$want' but this row needs $RW_REQUIRE_NPC (the default ROW_NPC=Cind re-places Cind, not Malzin); run with ROW_NPC=$RW_REQUIRE_NPC"; return 3
  fi
  case "${RL_NPC_FULL:-}" in "$base"*) ;; *) RL_REASON="$SB_ART: after the load the resolved NPC is '${RL_NPC_FULL:-?}', not ROW_NPC '$want' (run with ROW_NPC=$want)"; return 3;; esac
  if [ -s "$f" ]; then
    t=$(grep -a '^teleported:' "$f")
    if [ -n "$t" ] && ! printf '%s\n' "$t" | grep -qF "teleported: $base "; then
      RL_REASON="$SB_ART: regroup.txt re-placed another NPC than ROW_NPC '$want': $(printf '%s' "$t" | head -1 | cut -c1-100) (see $f)"; return 3
    fi
  fi
  echo "regroup-guard OK: $base" >> "$EV/people_guard.txt"
  return 0
}

rw_save_load() {   # rw_save_load <tag> [near|far]   (+ regroup guard)
  sb_save_load_orig "$@" || return $?
  sb_regroup_guard
}
