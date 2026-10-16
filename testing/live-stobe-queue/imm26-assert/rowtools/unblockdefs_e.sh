#!/usr/bin/env bash
# unblockdefs_e.sh (imm26-sfD2): one-call row 10-b with the three root-cause fixes found by imm26-sfD. NEW file: unblockdefs_c.sh / unblockcheck_c.py are NOT edited;
# this file sources unblockdefs_c.sh as a library (its uc_main runner, ub10_gift_pick, ub10_effects) and redefines rd_10b. Verdicts come from unblockcheck_e.py.
#   RUN (one call):  bash testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_e.sh 10-b <lane> [options as unblockdefs_c.sh: --save --no-reload --dry --allow-retry --victim --gift]
# Fixes versus unblockdefs_c.sh rd_10b (imm26-sfD findings):
#  A harm: harness `hit` creates NO attack event, and the server scores harm between non-squad characters only when an encounter is open ("no_encounter"). So Shay first
#    gets a real attack order on the victim (`stobe-auto attack Shay <victim>`, fires attackingYou -> `attack` event), THEN the two `hit ... head 130`; after the KO the fight is
#    ended (`order Shay NULL_TASK`, `order <v> NULL_TASK`, `relation <v> 0`, health 100, protect on both).
#  B scene: the whole row runs at the quiet spot HX_SPOT (TR_SCENE) - the Hub outlaws attacked Shay and cancelled the replies; strays within 400 u go to the far spot.
#  C gift: lib/social_property.php inDeal() treats a CANCELLED deal with resolved_at NULL as an open deal forever (judged `deal_payment`). Lane workaround (private lane DB only):
#    terminal-status contracts get resolved_at=updated_at, and the victim's stale open contracts are expired with resolved_at one hour ago. Permanent fix:
#    pending-fixes/imm26-sfD/inDeal-terminal.py (report only; not deployed). Evidence: deal_before.txt deal_fix.txt deal_after.txt.
# Extra evidence: attack.txt (attack order reply), interp.txt (worker SOCIAL_INTERPRET harm/attack lines), judged.txt (item_transfer judgement), harm.txt.
# Library use: `. unblockdefs_e.sh` AFTER go-row.sh / hxdefs.sh. Shim mode: `unblockdefs_e.sh <...>rowcheck.py <ROW> <ev>` (used as $PY) sends 10-b to unblockcheck_e.py.

UE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UE_SELF="$UE_HERE/$(basename "${BASH_SOURCE[0]}")"
UE_EXEC=0; [ "${#BASH_SOURCE[@]}" -eq 1 ] && [ "${BASH_SOURCE[0]}" = "$0" ] && UE_EXEC=1   # executed (not sourced)

# ---------------------------------------------------------------------------------------------- shim mode
if [ "$UE_EXEC" = 1 ] && [ -n "${UC_LOADED:-}" ]; then
  REAL=$(command -v python3 || command -v python)
  if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
    case "${2#IMM-}" in 10-b) exec "$REAL" "$UE_HERE/unblockcheck_e.py" "$2" "$3";; esac
  fi
  exec "$REAL" "$@"
fi

declare -F uc_main >/dev/null || . "$UE_HERE/unblockdefs_c.sh"
UC_HERE="$UE_HERE"; UC_SELF="$UE_SELF"     # the c runner re-sources UC_SELF after go-row.sh/hxdefs.sh, so OUR rd_10b wins and PY (the shim) is this file

ue_spot() { printf '%s' "${HX_SPOT:-${HX_SPOT_DEF:--48000 1500 2960}}"; }
ue_deals() {  # ue_deals <victim short> <file> : the victim's contracts and every terminal contract still resolved_at NULL
  lt_sql "select contract_id||'|'||npc_name||'|'||status||'|'||coalesce(performance_started_unix,0)||'|'||coalesce(resolved_at::text,'NULL')||'|'||coalesce(updated_at::text,'') from stobe_social_contract where lower(npc_name) like lower('$1')||'%' or (resolved_at is null and status in ('CANCELLED','EXPIRED','IMPOSSIBLE','REJECTED')) order by updated_at desc limit 20" > "$EV/$2" 2>&1
}
ue_deal_fix() {  # lane workaround for the inDeal() defect (private lane DB only)
  local s="$1"; s="${s//\'/\'\'}"
  ue_deals "$s" deal_before.txt
  lt_sqlx "update stobe_social_contract set resolved_at=updated_at where resolved_at is null and status in ('CANCELLED','EXPIRED','IMPOSSIBLE','REJECTED'); update stobe_social_contract set status='EXPIRED', resolved_at=now() - interval '1 hour' where lower(npc_name) like lower('$s')||'%' and status in ('PROPOSED','NEGOTIATING','ACCEPTED','AWAITING_PERFORMANCE')" > "$EV/deal_fix.txt" 2>&1
  ue_deals "$s" deal_after.txt
}
ue_worker_lines() {  # ue_worker_lines <file> <kind regex> [n] : newest SOCIAL_INTERPRET lines of the lane's relationship worker
  printf 'grep -a -E "SOCIAL_INTERPRET kind=(%s) " %s/site/log/relationship_worker.log 2>/dev/null | tail -%s | cut -c1-320\n' "$2" "$LT_ROOT" "${3:-4}" | lt_w > "$EV/$1" 2>&1
}

rd_10b() {
  tr_cfg; unset ROW_NATIVE TR_SCENE
  rd_need_npc || return 3
  local v="$RL_NPC_FULL" short n n0 k
  short="${v%% *}"; echo "$v" > "$EV/victim.txt"; n=$(rl_q "$v")
  tr_clean_db; rl_aff "$v" Shay 0 platonic aff0
  ue_deal_fix "$short"
  TR_SCENE="$(ue_spot)"; tr_quiet; unset TR_SCENE; rl_resolve "$ROW_NPC" >/dev/null 2>&1      # B: the scene is the quiet spot, not the Hub
  ub10_gift_pick || return $?
  lt_sql "select coalesce(max(game_ts),0) from social_effect" | head -1 | tr -dc 0-9 > "$EV/eff_ts0.txt"
  # --- A: a real attack order first (opens the encounter), then the two hits (KO), then the fight is ended
  lt_h <<EOT >> "$EV/harm.txt" 2>&1
stobe-auto protect $n off </dev/null 2>&1 | head -1
stobe-auto protect Shay on </dev/null 2>&1 | head -1
stobe-auto attack Shay $n </dev/null 2>&1 | head -2
sleep 3
stobe-auto hit Shay $n head 130 </dev/null 2>&1 | head -2
sleep 2
stobe-auto hit Shay $n head 130 </dev/null 2>&1 | head -2
sleep 8
grep -a "knockout:" $(rl_q "$LT_STOBELOG") | tail -1 | cut -c1-200
stobe-auto order Shay NULL_TASK </dev/null 2>&1 | head -1
stobe-auto order $n NULL_TASK </dev/null 2>&1 | head -1
stobe-auto relation $n 0 </dev/null 2>&1 | head -1
stobe-auto health $n 100 </dev/null 2>&1 | head -1
stobe-auto speed 3 </dev/null 2>&1 | head -1
for k in \$(seq 1 15); do r=\$(stobe-auto chars 40 </dev/null | sed 's/ | /\n/g' | grep -F $(rl_q "$short") | cut -c1-200); echo "\$r" | grep -q " KO" || break; sleep 8; done; echo "\$r"
stobe-auto speed 1 </dev/null 2>&1 | head -1
stobe-auto order Shay NULL_TASK </dev/null 2>&1 | head -1
stobe-auto order $n NULL_TASK </dev/null 2>&1 | head -1
stobe-auto protect $n on </dev/null 2>&1 | head -1
stobe-auto protect Shay on </dev/null 2>&1 | head -1
stobe-auto teleport $n Shay </dev/null 2>&1 | head -1
EOT
  sed -n 3,4p "$EV/harm.txt" > "$EV/attack.txt" 2>/dev/null
  ue_worker_lines interp.txt 'harm|attack' 6
  rl_resolve "$ROW_NPC" >/dev/null 2>&1
  rl_aff "$v" Shay "" read aff_harm
  # --- apology (the 10-a wording)
  ROW_NATIVE=1; rl_say 1 "$short, I'm sorry I knocked you out. I was angry and I was wrong to hit you." || return $?
  rl_aff "$v" Shay "" read aff_apology
  # --- gift: a non-food item moved Shay -> victim (victim = TAKER: actor=victim target=Shay is the correct capture)
  rl_inv before_gift
  n0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9)
  lt_h <<EOT >> "$EV/gift_give.txt" 2>&1
stobe-auto transfer Shay $n $(rl_q "$UB_GIFT_ITEM") </dev/null 2>&1 | head -2
EOT
  rl_inv after_gift
  for k in $(seq 1 12); do
    [ "$(lt_sql "select count(*) from social_effect where component='gift' and game_ts > $(tr -dc 0-9 < "$EV/eff_ts0.txt")" | head -1 | tr -dc 0-9)" -gt 0 ] 2>/dev/null && break
    uc_sleep 5
  done
  printf 'tail -n +%s %s | grep -a SOCIAL_CAPTURE | grep -a item_transfer | cut -c1-320 | tail -6\n' "$(( ${n0:-0} + 1 ))" "$(rl_q "$LT_STOBELOG")" | lt_h > "$EV/transfer_log.txt" 2>&1
  ue_worker_lines judged.txt 'item_transfer' 3
  lt_sql "select coalesce(payload->'actor'->>'name','')||'|'||coalesce(payload->'actor'->>'in_player_faction','')||'|'||coalesce(payload->'target'->>'name','')||'|'||coalesce(payload->'target'->>'in_player_faction','')||'|'||coalesce(payload->'facts'->>'food_items','')||'|'||coalesce(payload->'facts'->>'stolen_items','')||'|'||coalesce(payload->'facts'->>'items','') from social_event_inbox where payload->>'event_kind'='item_transfer' order by sequence desc limit 5" > "$EV/inbox_transfer.txt" 2>&1
  rl_aff "$v" Shay "" read aff_end
  ub10_effects effects_c.txt
  return 0
}

# ---------------------------------------------------------------------------------------------- runner
if [ "$UE_EXEC" = 1 ] && [ -z "${UC_LOADED:-}" ]; then
  case "${1#IMM-}" in 10-b|-h|--help|"") uc_main "$@"; exit $?;; *) echo "RESULT ${1:-?} SETUP-FAIL unblockdefs_e.sh handles row 10-b only (use unblockdefs_c.sh for 15-bx / 20-a)"; exit 2;; esac
fi
