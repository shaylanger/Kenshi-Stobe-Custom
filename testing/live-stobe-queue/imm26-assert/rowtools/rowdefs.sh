#!/usr/bin/env bash
# rowdefs.sh: one function per ported row, `rd_<id without dash/IMM->` (rd_12a for 12-a). Each runs AFTER preflight, writes its steps into the
# evidence dir ($EV) with rl_say/rl_aff/rl_inv, and returns 0, 3 (SETUP-FAIL, reason in RL_REASON) or 4 (GATED). The verdict is rowcheck.py's.
# Say steps s1.. keep the order the check expects (rowcheck.py c_<id>). Env knobs: ROW_NPC (Cind), ROW_ITEM, ROW_TOWN, ROW_WAIT (150 s per reply).
# Ported: 04-c 06-c 08-a 12-a 12-b 12-d 14-a 19-a 23-b 24-b.  Not ported yet: 16-c (profile refresh needs dps_* + metadata toggle, tables unverified).
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
}
rd_14a() {  # native-context row; non-faction NPC affinity 20+; town is a far known place (ROW_TOWN, default Squin)
  ROW_NATIVE=1; rd_need_npc || return 3; rd_aff 40
  rl_say 1 "Take me to ${ROW_TOWN:-Squin}." || return $?
}
rd_19a() {  # accept leg only (reload leg is manual -> check reports GATED with the accept leg's verdict)
  rd_need_npc || return 3
  rl_say 1 "Anywhere you want to go?" || return $?
  rl_say 2 "Yes, let's go." || return $?
}
rd_23b() {  # H-AFF 60; follow order must exist (else SETUP-FAIL), then game time advances and the order must end by expiry
  rd_need_npc || return 3; rd_aff 60
  rl_say 1 "Follow me." || return $?
  echo "stobe-auto stobe_state $(rl_q "$RL_NPC_FULL") </dev/null | head -c 1500" | lt_h > "$EV/follow_state.txt"
  grep -qiE '"(first_order|current_goal|order)"\s*:\s*"[^"]*follow' "$EV/follow_state.txt" || return 0   # rowcheck -> SETUP-FAIL
  rl_gametime > "$EV/time0.txt"; rl_advance_gametime || return 3; echo "$RL_T1" > "$EV/time1.txt"
  echo "stobe-auto stobe_state $(rl_q "$RL_NPC_FULL") </dev/null | head -c 1500" | lt_h > "$EV/follow_state_after.txt"
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
