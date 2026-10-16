#!/usr/bin/env bash
# rowdefs.sh: one function per ported row, `rd_<id without dash/IMM->` (rd_12a for 12-a). Each runs AFTER preflight, writes its steps into the
# evidence dir ($EV) with rl_say/rl_aff/rl_inv, and returns 0, 3 (SETUP-FAIL, reason in RL_REASON) or 4 (GATED). The verdict is rowcheck.py's.
# Say steps s1.. keep the order the check expects (rowcheck.py c_<id>). Env knobs: ROW_NPC (Cind), ROW_ITEM, ROW_TOWN, ROW_WAIT (150 s per reply).
# Ported: 04-c 06-c 08-a 12-a 12-b 12-d 14-a 19-a 19-a-nc2 19-d 23-b 24-b.  Not ported yet: 16-c (profile refresh needs dps_* + metadata toggle, tables unverified).
rd_need_npc() { rl_resolve "${ROW_NPC:-Cind}" || { RL_REASON="cannot resolve ${ROW_NPC:-Cind} (stobe-auto where)"; return 3; }; }
rd_aff() { rl_aff "$RL_NPC_FULL" Shay "$1" "${2:-platonic}" "${3:-aff}"; }   # H-AFF NPC -> Shay

rd_12a() {  # FX: H-AFF +70, a recorded broken promise exists for the pair (breach a deal as in 13-a first; checked via the PROMPT)
  rd_need_npc || return 3; rd_aff 70
  local item="${ROW_ITEM:-Metal Junk}"
  rl_inv before; rl_say 1 "Can I borrow your $item for a day?" || return $?; rl_inv after
}
rd_12b() {  # H-AFF +70; two says, answers must differ in kind, PROMPT groups experiences by domain
  rd_need_npc || return 3; rd_aff 70
  rl_say 1 "I have a secret I want to tell you." || return $?
  rl_say 2 "Come with me on a dangerous raid." || return $?
}
rd_12d() {  # numeric gates: aff 40 refused, aff 75 transfers. The NPC must carry a weapon (pair without a recorded breach)
  rd_need_npc || return 3
  rd_aff 40 platonic aff40; rl_inv before1; rl_say 1 "Can I have your sword as a gift?" || return $?; rl_inv after1
  rd_aff 75 platonic aff75; rl_inv before2; rl_say 2 "Can I have your sword as a gift?" || return $?; rl_inv after2
}
rd_08a() {  # FX-CIND; s1 positive, s2..s4 negatives (each must create no social_followup)
  rd_need_npc || return 3
  rl_say 1 "I'm heading to the Hub to find my brother." || return $?
  rl_say 2 "If I go to the Hub maybe I'll find him" || return $?
  rl_say 3 "I'm going to the Hub, would you come?" || return $?
  rl_say 4 "Let's travel to the Hub together" || return $?
}
rd_24b() {  # native-context row; preflight cleared open trips so blocked_by_existing_trip cannot come from leftovers
  ROW_NATIVE=1; rd_need_npc || return 3
  rl_say 1 "Let's consider Vain as a general area, not an exact spot." || return $?
  rl_say 2 "Yes, let's go." || return $?   # amended 2026-10-16: the NPC offers a first leg, the Yes starts the walk (c_24b needs s2)
}
rd_14a() {  # native-context row; non-faction NPC affinity 20+; town is a far known place (ROW_TOWN, default Squin)
  ROW_NATIVE=1; rd_need_npc || return 3; rd_aff 40
  rl_say 1 "Take me to ${ROW_TOWN:-Squin}." || return $?
}
# ---- 19-a trip resume (option B, Shay 2026-10-15): a trip saved mid-way and loaded must CONTINUE with the same agreement_id ----
# rd19_* helpers are self-contained (rl_*/lt_* only; tr_prep has already run for 19-a via tripdefs.sh). Steps and evidence files:
#   s1 propose, s2 accept ("Yes, let's go."), s3 "Lead the way." only when s2/reply.txt has no OWNED_TRAVEL accepted=1; agr_pre.txt = all
#   travel_agreement rows before the save (rowid|type|data); load_rowid.txt; save + load (+ wait for the world, NPC back to Shay when > 70 u);
#   s4 "Where were we going?" (first post-load turn = the resume turn), post_s4.txt (stobe_state), s5 "I'm right behind you.", post_s5.txt,
#   agr_all.txt = all rows after s5 (post-load rows = rowid > load_rowid.txt); NC leg (ROW_19A_NC=0 skips): delete the agreement rows (the DB
#   of an older save has none), load the pre-trip save kah-imm26-19a-pre-<lane>, s6 "Where were we going?", post_s6.txt.
rd19_dump() {  # rd19_dump <file>: every travel_agreement row, oldest first, as rowid|type|data
  lt_sql "select rowid,type,data from eventlog where type='travel_agreement' order by rowid asc" > "$EV/$1" 2>&1
}
rd19_state() {  # rd19_state <file>: stobe_state JSON head of the NPC (ai.first_order / ai.destination)
  printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 2500\n' "$(rl_q "$RL_NPC_FULL")" | lt_h > "$EV/$1" 2>&1
}
rd19_load() {  # rd19_load <save>: load it and wait for phase=world (20 s, then 24 x 5 s); rc 3 + RL_REASON when the world never comes back
  local o k
  printf 'stobe-auto load %s </dev/null | head -1\n' "$1" | lt_h >> "$EV/load.txt" 2>&1
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 20
  for k in $(seq 1 24); do
    o=$(echo 'stobe-auto status </dev/null | head -1' | lt_h 2>&1 | head -1)
    echo "$o" | grep -q 'phase=world' && break
    [ -n "${KAH_ROW_FAKE:-}" ] || sleep 5
  done
  echo "$o" | grep -q 'phase=world' || { RL_REASON="not in the world after loading $1 ($o)"; return 3; }
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 8
  echo 'stobe-auto speed 0.5 </dev/null | head -1' | lt_h >> "$EV/load.txt" 2>&1
  return 0
}
rd19_place() {  # rd19_place near|far: re-resolve the NPC after a load; near = teleport her to Shay when > 70 u away, far = 120 u from Shay
  local sp x y z n
  RL_NPC_ID=""; rd_need_npc || return 3
  n=$(rl_q "$RL_NPC_FULL")
  if [ "$1" = far ]; then
    sp=$(echo 'stobe-auto where Shay </dev/null | head -1' | lt_h 2>&1 | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \2 \3/p' | head -1)
    [ -n "$sp" ] || { RL_REASON="cannot read Shay's position (stobe-auto where Shay)"; return 3; }
    set -- $sp; x=$(awk -v v="$1" 'BEGIN{printf "%.0f", v+120}'); y=$2; z=$3
    printf 'stobe-auto teleport %s %s %s %s </dev/null | head -1\n' "$n" "$x" "$y" "$z" | lt_h >> "$EV/regroup.txt" 2>&1
    echo "far: NPC teleported to $x $y $z (Shay $sp)" >> "$EV/regroup.txt"
  elif awk -v d="${RL_DIST:-0}" 'BEGIN{exit !(d+0>70)}'; then
    printf 'stobe-auto teleport %s Shay </dev/null | head -1\n' "$n" | lt_h >> "$EV/regroup.txt" 2>&1
    echo "near: dist=${RL_DIST} > 70, NPC teleported to Shay" >> "$EV/regroup.txt"
  fi
  RL_NPC_ID=""; rd_need_npc
}
rd19_trip() {  # propose, accept, (lead), save, load, wait for the world; leaves ROW_NATIVE=1; does NOT place the NPC
  ROW_NATIVE=1; rd_need_npc || return 3
  local sv="kah-imm26-19a-$LT_LANE" pre="kah-imm26-19a-pre-$LT_LANE"
  if [ "${ROW_19A_NC:-1}" = 1 ]; then printf 'stobe-auto save %s </dev/null | head -1\n' "$pre" | lt_h > "$EV/save_pre.txt" 2>&1; fi
  if [ -n "${ROW_19_DEST:-}" ]; then rl_say 1 "Take me to ${ROW_19_DEST}." || return $?   # forced visited town (19-d needs a resumable destination with a known gate)
  else rl_say 1 "${TR_S1:-Walk with me to Stumble Inn.}" || return $?; fi   # a named visited_location: only those trips resume after a load (commitment_native_bridge.php:52); "Anywhere you want to go?" let the LLM pick a local landmark that is not resumed (imm26-inv19)
  if ! grep -q '"status":"PROPOSED"' "$EV/s1/ev_full.txt" 2>/dev/null; then   # the NPC answered 'nowhere in particular' (LLM-soft): ask once more for a concrete trip
    rl_say 1b "${ROW_19_DEST:+Would you lead me to $ROW_19_DEST?}${ROW_19_DEST:-Is there a town you need to get to? Lead me there.}" || return $?
    grep -q '"status":"PROPOSED"' "$EV/s1b/ev_full.txt" 2>/dev/null || { RL_REASON="no trip proposed after two asks (s1/s1b): nothing to accept"; return 3; }
  fi
  rl_say 2 "Yes, let's go." || return $?
  if ! grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" 2>/dev/null; then rl_say 3 "Lead the way." || return $?; fi
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 6
  rd19_dump agr_pre.txt
  lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9 > "$EV/load_rowid.txt"
  printf 'stobe-auto save %s </dev/null | head -1\n' "$sv" | lt_h > "$EV/save.txt" 2>&1
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 6
  rd19_load "$sv"
}
rd_19a() {  # trip continues after a save/load: same agreement_id, native order re-issued, no re-proposal; NC = older save
  rd19_trip || return $?
  rd19_place near || return $?
  rl_say 4 "Where were we going?" || return $?
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_RESUME_WAIT:-8}"
  rd19_state post_s4.txt
  rl_say 5 "I'm right behind you." || return $?
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_RESUME_WAIT:-8}"
  rd19_state post_s5.txt
  rd19_dump agr_all.txt
  if [ "${ROW_19A_NC:-1}" = 1 ]; then
    lt_sqlx "delete from eventlog where type='travel_agreement'" > "$EV/nc_prep.txt" 2>&1   # an older save's DB has no agreement
    rd19_load "kah-imm26-19a-pre-$LT_LANE" || return $?
    rd19_place near || return $?
    rl_say 6 "Where were we going?" || return $?
    rd19_state post_s6.txt
  fi
  return 0
}
rd19_prep() { declare -F tr_prep >/dev/null && { tr_prep || return $?; }; return 0; }   # 19-a is already wrapped with tr_prep (tripdefs.sh); the new rows call it
rd_19anc2() {  # row 19-a-nc2: after the load the NPC is 120 u away: the trip stays interrupted_by_load, no OWNED_TRAVEL, no new agreement id
  rd19_prep || return $?
  ROW_19A_NC=0 rd19_trip || return $?
  rd19_place far || return $?
  rl_say 4 "Where were we going?" || return $?     # no reply at that range = SETUP-FAIL (rl_say rc 3)
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_RESUME_WAIT:-8}"
  rd19_state post_s4.txt
  rd19_dump agr_all.txt
}
rd_19d() {  # row 19-d: after the resume the NPC reaches the destination (23-a recipe) -> COMPLETED, owned_work_released true
  declare -F tr_arrive >/dev/null || { RL_REASON="19-d needs tripdefs.sh (tr_arrive/tr_agr)"; return 3; }
  rd19_prep || return $?
  local ROW_19_DEST="${TR_DEST:-Squin}"
  ROW_19A_NC=0 rd19_trip || return $?
  rd19_place near || return $?
  rl_say 4 "Where were we going?" || return $?
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_RESUME_WAIT:-8}"
  rd19_state post_s4.txt
  local og="${TR_GATE:-}" dg; TR_GATE=""; dg=$(sed -nE 's/.*"destination_point": ?\{ ?"x": ?(-?[0-9.]+), ?"y": ?(-?[0-9.]+), ?"z": ?(-?[0-9.]+).*/\1 \2 \3/p' "$EV/agr_pre.txt" 2>/dev/null | tail -1); [ -n "$dg" ] || dg=$(tr_gate); TR_GATE="${TRIP_GATE:-${dg:-$og}}"   # gate = the agreement's destination_point, else the Squin default
  if [ -n "${TRIP_SHORT:-}" ]; then set -- ${TR_GATE}; TR_GATE="$(awk -v x="$1" -v s="$TRIP_SHORT" 'BEGIN{printf "%.1f", x+s}') $2 $3"; fi   # TRIP_SHORT=N: arrive N u short of the gate and let her walk the last leg (a teleport onto the goal ends the native order = FAILED native_order_ended_before_goal)
  tr_arrive || return $?
  rl_say 5 "We're here. Thanks for guiding me." || return $?
  rd19_state state_after.txt
  tr_agr agr_final.txt 8
  rd19_dump agr_all.txt
}
rd_23b() {  # H-AFF 60; native follow must start (stobe.log FOLLOW lines; else SETUP-FAIL), then game time advances and the follow must end by expiry
  # The legacy native follow is NOT a Kenshi order (stobe_state shows first_order none / current_goal OTHER): the evidence is the DLL log
  # (HOOK_MSG_PROC: FOLLOW target resolved, FOLLOW_TICK, FOLLOW_EXPIRED), imm26-inv-23b item 8. Needs the NC DLL (ROW_NATIVE -> stobe_ctxpush).
  ROW_NATIVE=1; rd_need_npc || return 3; rd_aff 60
  rl_say 1 "Follow me." || return $?
  local l; l=$(sed -nE 's/^mark=[0-9]+ [0-9]+ ([0-9]+) .*/\1/p' "$EV/s1/meta.txt" | head -1); l=${l:-0}
  echo "$RL_NPC_ID" > "$EV/follow_npc.txt"
  echo "tail -n +$((l+1)) $LT_STOBELOG | grep -a -E 'FOLLOW' | cut -c1-300 | head -60" | lt_h > "$EV/follow_log.txt"
  grep -q 'FOLLOW target resolved' "$EV/follow_log.txt" || return 0   # rowcheck -> SETUP-FAIL
  rl_gametime > "$EV/time0.txt"; rl_advance_gametime || return 3; echo "$RL_T1" > "$EV/time1.txt"
  echo "tail -n +$((l+1)) $LT_STOBELOG | grep -a -E 'FOLLOW' | cut -c1-300 | head -120" | lt_h > "$EV/follow_log_after.txt"
}
rd_04c() {  # familial tie Cind -> B, say "<B> owes me, tell them to pay."; B = first non-squad NPC within 600 (ROW_B overrides)
  rd_need_npc || return 3
  local b="${ROW_B:-}"
  [ -n "$b" ] || b=$(echo 'stobe-auto chars 600 </dev/null 2>&1' | lt_h | sed 's/ | /\n/g' | sed -E 's/^[0-9]+ within [0-9.]+: //' \
    | sed -nE 's/^(.*) #[0-9]+\/[0-9]+ \[[^]]*\] pos=.*/\1/p' | grep -v -E '^(Shay|Cind|Malzin)|Pack Beast|^Kint' | head -1)
  [ -n "$b" ] || { RL_REASON="no second NPC within 600 units to use as tie target B (set ROW_B)"; return 3; }
  echo "$b" > "$EV/tie_target.txt"
  rl_aff "$RL_NPC_FULL" "$b" 50 familial tie
  rl_say 1 "${b%% *} owes me, tell them to pay." || return $?
}
rd_06c() {  # preference row replace + forget: s1 sets Boss (06-a), s2 Jax replaces, s3 forget -> tombstone, s4 neutral turn (prompt block gone)
  rd_need_npc || return 3
  rl_say 1 "Please call me Boss." || return $?
  rl_say 2 "Actually, call me Jax." || return $?
  rl_say 3 "Please forget my preferred name." || return $?
  rl_say 4 "How are you today?" || return $?
}

# trip-family rows (13-b 20-a 20-b 23-a 23-c 23-d 24-a new; 19-a 23-b 24-b wrapped with a clean scene): see tripdefs.sh / README_TRIP.md
[ -f "$(dirname "${BASH_SOURCE[0]}")/tripdefs.sh" ] && . "$(dirname "${BASH_SOURCE[0]}")/tripdefs.sh"
