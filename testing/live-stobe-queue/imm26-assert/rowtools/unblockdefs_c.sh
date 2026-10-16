#!/usr/bin/env bash
# unblockdefs_c.sh (imm26-u-rowsC): one-call row scripts for the SETUP-FAIL rows 15-bx, 20-a, 10-b on the 4080-i4 operator lane. Rewrites ONLY the row
# recipes (scene); the verdicts come from unblockcheck_c.py. rowdefs.sh / hxdefs.sh / tripdefs.sh / hunt26a-scene.sh are NOT edited (live operators change them):
# this file sources them and then redefines rd_15bx / rd_20a / rd_10b (the function names go-row.sh looks up) for the runs started from HERE only.
#   RUN (one call):  bash testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c.sh <15-bx|20-a|10-b> <lane> [options]
#   -> reload the lane's ready save -> preflight -> go-row (attempt guard + timing log) -> row steps -> unblockcheck_c.py -> up to 4 EVIDENCE lines + ONE
#      `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [evidence=<dir>]` line (exit 0/1/2/3, 4 = ROW-NEEDS-FIXER as go-row.sh).
#   Options: --save S (default for 4080-i4: kah-imm26-4080-i4h)  --save2 S (15-bx second load)  --no-reload  --dry  --allow-retry "why"  --out DIR (15-bx bundles)
#            --out-dist U (15-bx, X distance, 320)  --faction F (15-bx fighters, "Holy Nation Outlaws")  --victim "Name" (10-b, default "Cind [Hungry Bandit]")
#            --gift "Item[,Item2]" (10-b, tried in order until `give` + `inv` show it; default "Bandages,Iron Plates,Copper Ore,Sabreclaw")  --dest T --alt P (20-a)
# Also usable as a library: `. unblockdefs_c.sh` AFTER go-row.sh / hxdefs.sh (the row functions are then defined; nothing runs). Shim mode: `unblockdefs_c.sh <...>rowcheck.py
# <ROW> <ev>` (used as $PY by the runner) sends 15-bx / 20-a / 10-b to unblockcheck_c.py and everything else to python unchanged.
#
# 15-bx  (sf report imm26-unblock-sf): the old scene was invalid (Malzin in the fighter roster, X 218-235 u, sleeper 5267 u away, P not within 15 u, old Hub fights
#   in the eventlog).  Now: fresh load, Malzin sent to the far spot, ALL old combat rows deleted, F1+F2 = two spawned fighters (Malzin is NOT a fighter), the names are
#   read back from `stobe-auto where <#handle>` AFTER the fight starts (the server renames spawns; handles never change) and the starter is the earliest
#   `Initiated attack` row since the fight whose first word is one of the fighters.  X is re-teleported to spot+320 and Shay onto X before EVERY sample and
#   distance.txt (X to F1) is re-measured until >= 255 u (3 tries, else SETUP-FAIL).  The sleeper S1 is `sleep`ed then `teleport S1 <F1> dist 60`, distance <= 100 or
#   SETUP-FAIL.  P is `teleport <npc> <F1> dist 10` (retries 6, 3), distance <= 15.  ShoutRadius 200 goes to shout_radius.txt (NOT distance.txt: a line there would be
#   read as a non-fighter at 200 u).  Evidence: <bundle dir>/{X1..X3,S1,P1..P3}/, fighters.txt, starter.txt, phases.txt, place.txt.
# 20-a   tr_prep + calm scene: before every say Shay is sheathed (`stobe_drawn hold Shay off` + `sheathe`) and calm_<tag>.txt records Shay's combat state and the
#   characters within 120 u; two confirm turns (s4, s4b).  unblockcheck_c.py turns a refusal caused by a drawn weapon / combat into SETUP-FAIL, never into a PASS.
# 10-b   victim V = a NON-squad NPC (default Cind): the server treats a gift between two player-faction characters as `exempt` (social_property.php consciousTransfer
#   squadPair) and FOOD ("Dried Meat") as a food gift that is only judged at the next meal (foodGift) - the old Malzin + Dried Meat scene could never produce a
#   `gift` row.  The harness record is NOT reversed: SocialPostStructuredW("item_transfer", actor = TAKER, target = LOSER) (main.cpp:7345), so
#   `transfer Shay Malzin X` is correctly captured as actor=Malzin target=Shay.  Steps: baseline aff 0, protect V off, `hit Shay V head 130` (KO), wake, apology (the 10-a
#   wording), non-food gift (give Shay + transfer Shay V), poll for a `gift` effect, dump effects/inbox/capture.  unblockcheck_c.py classifies a missing gift row
#   (squad / food / not captured) as SETUP-FAIL with the cause, and applies the cap `repair sum <= 25% of recorded harm - 1`, one apology_relief <= 2, aff < 0.

UC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UC_SELF="$UC_HERE/$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------------------------- shim mode (executed, first arg is a python path)
UC_EXEC=0; [ "${#BASH_SOURCE[@]}" -eq 1 ] && [ "${BASH_SOURCE[0]}" = "$0" ] && UC_EXEC=1   # executed (not sourced)
if [ "$UC_EXEC" = 1 ] && [ -n "${UC_LOADED:-}" ]; then   # executed as $PY by go-row.sh (UC_LOADED is exported by the runner)
  REAL=$(command -v python3 || command -v python)
  if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
    case "${2#IMM-}" in 15-bx|20-a|10-b) exec "$REAL" "$UC_HERE/unblockcheck_c.py" "$2" "$3";; esac
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
ub15_scene() {  # ub15_scene <save> : load, quiet spot, Malzin to the far spot, every old fight row gone
  hxd_load "$1" || return $?; hxd_scene || return $?; hxd_dbclean
  printf 'stobe-auto teleport Malzin %s </dev/null | head -1\n' "$HX_FAR" | lt_h >> "$EV/quiet.txt" 2>&1
  lt_sqlx "delete from eventlog where type in ('combat','combat_start','combat_end')" >> "$EV/clean.txt" 2>&1
  UB_NPC="$RL_NPC_FULL"
}
ub15_pair() {  # fresh pair at the spot -> UB_ID1 UB_ID2 UB_FN (comma list: current + spawn names) UB_STARTER ; rc 3 + RL_REASON
  local fac="${HX15_FACTION:-Holy Nation Outlaws}" o1 o2 n1 n2 mk cand c w
  ub_spawn "$fac" 0 || return $?; UB_ID1="$UB_ID"; o1="$UB_SHORT"
  ub_spawn "$fac" 6 || return $?; UB_ID2="$UB_ID"; o2="$UB_SHORT"
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
  [ -n "$UB_STARTER" ] || { RL_REASON="no 'Initiated attack' row by one of the fighters ($UB_FN) after the fight started (first candidates: $(echo "$cand" | head -2 | cut -c1-100 | tr '\n' ' '))"; return 3; }
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
  ub15_scene "$HX_SAVE" || return $?; m0=$(hxd_rowid)
  ub_spawn "${HX15_SLEEPER_FACTION:-Drifters}" 40 || return $?; s1id="$UB_ID"
  printf 'stobe-auto sleep %s </dev/null 2>&1 | head -2\n' "$(rl_q "$s1id")" | lt_h >> "$EV/sleeper.txt" 2>&1
  ub15_pair || return $?; fn_x="$UB_FN"; st_x="$UB_STARTER"
  printf 'stobe-auto protect %s on </dev/null | head -1\n' "$(rl_q "$UB_NPC")" | lt_h >> "$EV/place.txt" 2>&1
  printf 'stobe-auto chars 300 </dev/null 2>&1 | sed "s/ | /\\n/g" | grep -E "#[0-9]+/[0-9]+" | cut -c1-80\n' | lt_h > "$EV/roster.txt" 2>&1
  i=0; for q in "${qs[@]}"; do i=$((i+1)); lab="X$i"; mkdir -p "$HXD/$lab"
    ub15_place_x "$lab" || return $?
    hxd_sample "$lab" "$q" "$UB_NPC" || return $?; HXD_DFILE=distance_after.txt hxd_dist "$lab" "$UB_ID1" "$UB_NPC" || return $?
  done
  ub15_place_s "$s1id" || return $?
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

# ---------------------------------------------------------------------------------------------- 20-a
ub20_calm() {  # ub20_calm <tag> : Shay sheathed (hold off), then calm_<tag>.txt = Shay's state + characters within 120 u
  lt_h <<EOT > "$EV/calm_$1.txt" 2>&1
stobe-auto stobe_drawn hold Shay off </dev/null 2>&1 | head -1
stobe-auto stobe_drawn sheathe Shay </dev/null 2>&1 | head -1
echo "STATE \$(stobe-auto stobe_state Shay </dev/null 2>&1 | head -c 1500 | tr '\n' ' ')"
echo "CHARS \$(stobe-auto chars 120 </dev/null 2>&1 | head -c 700 | tr '\n' ' ')"
EOT
}
rd_20a() {  # ACCEPTED trip; change request must not move the row; two confirm turns; calm, sheathed Shay every turn
  tr_prep || return $?; ub20_calm pre; tr_trip_setup || return $?
  echo "$TR_ALT" > "$EV/alt.txt"
  local core="${TR_ALT#the }"
  ub20_calm s3; rl_say 3 "Actually, go to $TR_ALT instead." || return $?
  ub20_calm s4; rl_say 4 "Yes, I mean it. I am sure, change it to $TR_ALT." || return $?
  grep -qE '"status":"(ENDED|CANCELLED)"' "$EV/s4/ev_full.txt" 2>/dev/null || grep -qiE "\"destination\":\"[^\"]*$core" "$EV/s4/ev_full.txt" 2>/dev/null \
    || { ub20_calm s4b; rl_say 4b "Yes. Take me to $TR_ALT." || return $?; }
  tr_agr agr_final.txt 8
}

# ---------------------------------------------------------------------------------------------- 10-b
ub10_gift_pick() {  # ub10_gift_pick : first item of UB_GIFT (comma list) that `give Shay` really puts into Shay's pack -> UB_GIFT_ITEM (rc 3 when none)
  local it inv="$EV/gift_inv.txt"
  UB_GIFT_ITEM=""
  while IFS= read -r it; do
    [ -n "$it" ] || continue
    printf 'stobe-auto give Shay %s 1 </dev/null 2>&1 | head -2\n' "$(rl_q "$it")" | lt_h >> "$EV/gift_give.txt" 2>&1
    : > "$inv"; hxd_inv "$inv" Shay
    if grep -qiF "$it" "$inv" 2>/dev/null; then UB_GIFT_ITEM="$it"; break; fi
  done < <(printf '%s' "${UB_GIFT:-Bandages,Iron Plates,Copper Ore,Sabreclaw}" | tr ',' '\n')
  uc_dry && UB_GIFT_ITEM="${UB_GIFT_ITEM:-Bandages}"
  [ -n "$UB_GIFT_ITEM" ] || { RL_REASON="no gift item could be given to Shay (tried ${UB_GIFT:-Bandages,Iron Plates,Copper Ore,Sabreclaw}; gift_give.txt)"; return 3; }
  echo "$UB_GIFT_ITEM" > "$EV/gift.txt"
}
ub10_effects() {  # ub10_effects <file> : rows after the pre-harm timestamp: component|delta|observer|culprit|game_ts
  local ts0; ts0=$(tr -dc 0-9 < "$EV/eff_ts0.txt" 2>/dev/null); ts0="${ts0:-0}"
  lt_sql "select component||'|'||delta||'|'||coalesce(detail->>'observer_name','')||'|'||coalesce(detail->>'culprit_name','')||'|'||game_ts from social_effect where game_ts > $ts0 order by game_ts, component" > "$EV/$1" 2>&1
}
rd_10b() {
  tr_cfg; unset ROW_NATIVE TR_SCENE
  rd_need_npc || return 3
  local v="$RL_NPC_FULL" short n n0 k
  short="${v%% *}"; echo "$v" > "$EV/victim.txt"; n=$(rl_q "$v")
  tr_clean_db; rl_aff "$v" Shay 0 platonic aff0
  tr_quiet; rl_resolve "$ROW_NPC" >/dev/null 2>&1
  ub10_gift_pick || return $?
  lt_sql "select coalesce(max(game_ts),0) from social_effect" | head -1 | tr -dc 0-9 > "$EV/eff_ts0.txt"
  # --- serious harm: KO the victim (protect off), wake, back to normal speed, victim protected again
  lt_h <<EOT >> "$EV/harm.txt" 2>&1
stobe-auto protect $n off </dev/null 2>&1 | head -1
stobe-auto hit Shay $n head 130 </dev/null 2>&1 | head -2
sleep 8
grep -a "knockout:" $(rl_q "$LT_STOBELOG") | tail -1 | cut -c1-200
stobe-auto health $n 100 </dev/null 2>&1 | head -1
stobe-auto speed 3 </dev/null 2>&1 | head -1
for k in \$(seq 1 15); do r=\$(stobe-auto chars 40 </dev/null | sed 's/ | /\n/g' | grep -F $(rl_q "$short") | cut -c1-200); echo "\$r" | grep -q " KO" || break; sleep 8; done; echo "\$r"
stobe-auto speed 1 </dev/null 2>&1 | head -1
stobe-auto protect $n on </dev/null 2>&1 | head -1
stobe-auto teleport $n Shay </dev/null 2>&1 | head -1
EOT
  rl_resolve "$ROW_NPC" >/dev/null 2>&1
  rl_aff "$v" Shay "" read aff_harm
  # --- apology (the 10-a wording)
  ROW_NATIVE=1; rl_say 1 "$short, I'm sorry I knocked you out. I was angry and I was wrong to hit you." || return $?
  rl_aff "$v" Shay "" read aff_apology
  # --- gift: a non-food item moved Shay -> victim (the victim is the TAKER: actor=victim target=Shay is the correct capture)
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
  lt_sql "select coalesce(payload->'actor'->>'name','')||'|'||coalesce(payload->'actor'->>'in_player_faction','')||'|'||coalesce(payload->'target'->>'name','')||'|'||coalesce(payload->'target'->>'in_player_faction','')||'|'||coalesce(payload->'facts'->>'food_items','')||'|'||coalesce(payload->'facts'->>'stolen_items','')||'|'||coalesce(payload->'facts'->>'items','') from social_event_inbox where payload->>'event_kind'='item_transfer' order by sequence desc limit 3" > "$EV/inbox_transfer.txt" 2>&1
  rl_aff "$v" Shay "" read aff_end
  ub10_effects effects_c.txt
  return 0
}

# ---------------------------------------------------------------------------------------------- runner
uc_usage() { echo "usage: unblockdefs_c.sh <15-bx|20-a|10-b> <lane: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4> [--save S] [--save2 S] [--no-reload] [--dry] [--allow-retry 'why'] [--out DIR] [--out-dist U] [--faction F] [--victim NAME] [--gift 'A,B'] [--dest T] [--alt P]" >&2; }
uc_main() {
  local ROW="" LANE="" RELOAD=1 ALLOW=() norm pf prc out rc n f SAVE=""
  while [ $# -gt 0 ]; do case "$1" in
    --save) SAVE="$2"; shift 2;; --save2) export HX_SAVE2="$2"; shift 2;; --out) export HX_OUT="$2"; shift 2;; --out-dist) export HX15_OUT="$2"; shift 2;;
    --faction) export HX15_FACTION="$2"; shift 2;; --victim) export UB_VICTIM="$2"; shift 2;; --gift) export UB_GIFT="$2"; shift 2;;
    --dest) export TRIP_DEST="$2"; shift 2;; --alt) export TRIP_ALT="$2"; shift 2;;
    --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
    --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
    -h|--help) uc_usage; return 0;;
    *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; uc_usage; return 2; fi; shift;;
  esac; done
  [ -n "$ROW" ] && [ -n "$LANE" ] || { uc_usage; return 2; }
  norm="${ROW#IMM-}"
  case "$norm" in 15-bx|20-a|10-b) ;; *) echo "RESULT $ROW SETUP-FAIL not an unblock-C row (15-bx 20-a 10-b)"; return 2;; esac
  export UC_LOADED=1; . "$UC_HERE/../go-row.sh"; . "$UC_HERE/hxdefs.sh"; . "$UC_SELF"    # libraries first, then OUR rd_15bx / rd_20a / rd_10b win
  PY="$UC_SELF"
  lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; return 2; }
  SAVE="${SAVE:-$(uc_lane_save)}"
  if [ "$norm" = 10-b ]; then ROW_NPC="${UB_VICTIM:-$UC_NPC_DEF}"; else ROW_NPC="${ROW_NPC:-$UC_NPC_DEF}"; fi
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
  n=0; for f in phases.txt calm_s4.txt calm_s4b.txt harm.txt transfer_log.txt inbox_transfer.txt agr_final.txt; do
    [ -s "$LT_OUT/$ROW/$f" ] && [ $n -lt 4 ] && { echo "EVIDENCE $ROW $f: $(tail -3 "$LT_OUT/$ROW/$f" | tr '\n' ' ' | cut -c1-300)"; n=$((n+1)); }
  done
  echo "$out" | head -1
  return $rc
}
if [ "$UC_EXEC" = 1 ] && [ -z "${UC_LOADED:-}" ]; then uc_main "$@"; exit $?; fi
