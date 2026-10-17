#!/usr/bin/env bash
# hunt26a-run-dest.sh = hunt26a-run.sh v2 + (op14) the AGREED goat teleported+pinned at the route goal after the Yes (op13 spawned substitute goats there: never selectable). Orig header: hunt26a-run.sh v2 (imm26-fix26a; v1 = imm26-fix26ad, SETUP-FAIL ticket 26-a): row 26-a on lane 5090-i5 in ONE command: clean scene + sfO inject arm + hunt26a-scene.sh (offer + accept) + "Shay follows Malzin" loop + verdict.
#   bash rowtools/hunt26a-run.sh [outdir]        (Malzin [Nameless]; hunt26a-scene.sh itself is unchanged)
# Why (ticket 26-a, op9p): the Hunt is a JOINT trip. After the Yes Malzin walks to the target (~1000 u away) and Shay stood still at the scene: NATIVE_TRAVEL brk_sep:132 participation_qualified=0
#   -> owned_order_removed_native_end_pending -> ACTIVITY_END_DIAG activity_no_verified_progress (record failed/timeout, participation not_completed). Also earlier KO by goats (Malzin unarmed / low blood),
#   leftover goats from earlier scenes, and the outlaw fight near The Hub ("Not now, I am in the middle of a fight.") that eats the offer. What this runner does:
#   1. clean: kill every [Herbivore] within 150 (old goats pile up and are somebody's stock); give + equip a Katana (give only when the inventory has none), blood 100, hunger RW_HUNGER (250 = well fed;
#      NOT 0: hunger <= 20 KOs Malzin, i4op5 lesson), wake + health 100 (the scene also does both).
#   2. arm the sfO inject (Hunt, Malzin), run hunt26a-scene.sh (COUNT=3 goats, REFACTION=0 APOLOGY=0), require SCENE-OK. If Malzin's offer reply is "...in the middle of a fight" the attempt is NOT a test
#      (the offer never existed): wait RW_FIGHT_WAIT (45 s), kill the goats, retry, at most RW_FIGHT_TRIES (4); still refused = SETUP-FAIL.
#   3. FOLLOW (v2): right after the Yes, Shay is teleported onto Malzin every ~1.5 s real (RW_FOLLOW_N=5 teleports per harness call, each preceded by a `where` that logs the separation JUST BEFORE the jump,
#      sleep RW_FOLLOW_STEP=1) at game speed RW_HUNT_SPEED (default 1, the 13-c recipe), polling the NEWEST Hunt record of Malzin (ids that existed before this run are ignored) until it is completed |
#      failed | cancelled | expired or RW_HUNT_WAIT (300 s) is over. Why (op10, 26-a): v1 jumped every 4 s at speed 0.5; Malzin ran up to 35 u away between jumps, NC21 ParticipationEvidence Break()s on 3D
#      separation > 35 (brk_sep:98, best_span:36, participation_qualified=0). A jump per 1.5 s keeps the separation ~10-20 u and each per-sample displacement far below 20*dt+5 (no brk_jump), like 13-c.
#      Evidence follow.log has `sep_before=...` (max/each) and `SEP>35` flags; native.txt = stobe.log participation / NATIVE_TRAVEL lines of the run (participation_qualified, brk_*).
#   4. verdict from REAL state: PASS = the record went proposed -> accepted -> completed, participationOutcome.status set (not not_completed), outbox row(s) of the agreement acknowledged, Malzin's
#      inventory gained >= 1 item (names / stack counts before vs after, Katana excluded). FAIL = the record ended failed/cancelled/expired or no delivery. SETUP-FAIL = no scene, no offer (fight),
#      accept did not land.
# Prints ONE line:  HUNT26A-RUN <lane> PASS|FAIL|SETUP-FAIL <detail> [evidence=<dir>]   exit 0 / 1 / 2.    Evidence in <dir>: try<N>/ (scene), follow.log, rec_*.txt, inv_before/after.txt, verdict.txt.
# Env: RW_HUNGER RW_FIGHT_WAIT RW_FIGHT_TRIES RW_FOLLOW_STEP (1) RW_FOLLOW_N (5) RW_HUNT_WAIT RW_ACCEPT_WAIT (40) RW_HUNT_SPEED (game speed during the follow, default 1; restored to 0.5) COUNT (3 goats)
#   HUNT26A_SCENE / HUNT26A_INJECT (script paths; selftest stubs). Offline: bash rowtools/hunt26a-run-selftest.sh
HR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE=5090-i5; export ROW_NPC="${ROW_NPC:-Malzin}"
. "$HR_HERE/../go-row.sh"; . "$HR_HERE/reloaddefs_a.sh"
lt_load "$LANE" >/dev/null || { echo "HUNT26A-RUN $LANE SETUP-FAIL unknown lane"; exit 2; }
tr_cfg; rl_begin 26a-run >/dev/null
RW_HUNT_SPEED="${RW_HUNT_SPEED:-0.5}"; RW_FOLLOW_STEP="${RW_FOLLOW_STEP:-0.1}"; RW_FOLLOW_N="${RW_FOLLOW_N:-12}"   # op11 live tuning 2026-10-16: speed 1 step 1 left 100+ u gaps (Malzin ~80 u/s real); 0.5/0.1/12 keeps 8-16 u
[ -n "${1:-}" ] && { EV="$1"; mkdir -p "$EV"; }
OUT="$EV"; SCENE="${HUNT26A_SCENE:-$HR_HERE/hunt26a-scene.sh}"
rl_resolve "$ROW_NPC" >/dev/null 2>&1 || { echo "HUNT26A-RUN $LANE SETUP-FAIL cannot resolve $ROW_NPC [evidence=$OUT]"; exit 2; }
NPC_ID="$RL_NPC_ID"; NPC_FULL="$RL_NPC_FULL"; ACTOR="${NPC_ID#\#}"; ACTOR="${ACTOR%%/*}"
say() { echo "[$(date +%T)] $*" >> "$OUT/run.log"; }
pa_h() { printf '%s\n' "$1" | lt_h 2>&1; }
fin() { [ -n "${RW_HUNT_SPEED:-}" ] && pa_h 'stobe-auto speed 0.5 </dev/null | head -1' >/dev/null; echo "HUNT26A-RUN $LANE $1 $2 [evidence=$OUT]" | tee "$OUT/verdict.txt"; exit "$3"; }

pa_kill_goats() {   # kill every [Herbivore] within 150 (leftover scenes)
  local ids g; ids=$(pa_h 'stobe-auto chars 150 "[Herbivore]|!dead" </dev/null | head -40' | grep -oE '#[0-9]+/[0-9]+' | sort -u)
  echo "leftover goats: $(echo $ids | wc -w)" >> "$OUT/prep.txt"
  for g in $ids; do pa_h "stobe-auto kill \"$g\" </dev/null | head -1" >> "$OUT/prep.txt"; done
}
pa_prep() {         # kill goats; Katana (give once + equip), blood 100, hunger, wake, health
  local inv; pa_kill_goats
  inv=$(pa_h "stobe-auto inv \"$NPC_ID\" </dev/null 2>&1")
  if ! echo "$inv" | grep -qi '"name":"[^"]*katana'; then
    pa_h "stobe-auto give \"$NPC_ID\" Katana 1 </dev/null | head -2" >> "$OUT/prep.txt"
  fi
  pa_h "stobe-auto equip \"$NPC_ID\" Katana </dev/null | head -2
stobe-auto blood \"$NPC_ID\" 100 </dev/null | head -1
stobe-auto hunger \"$NPC_ID\" ${RW_HUNGER:-250} </dev/null | head -1
stobe-auto wake \"$NPC_ID\" </dev/null | head -1
stobe-auto health \"$NPC_ID\" 100 </dev/null | head -1" >> "$OUT/prep.txt"
}
pa_inv() {          # pa_inv <file>: one item name per stack unit (count/quantity field when present), sorted, Katana removed
  pa_h "stobe-auto inv \"$NPC_ID\" </dev/null 2>&1" | tr '{' '\n' | grep -a '"name":"' | grep -vi '"name":"[^"]*katana' | awk '{ n=$0; sub(/.*"name":"/,"",n); sub(/".*/,"",n); c=1; if (match($0,/"(count|quantity|amount|stack|qty)": ?[0-9]+/)) { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); c=s+0 } for(i=0;i<c;i++) print n }' | sort > "$1"
}
pa_follow() {       # pa_follow: RW_FOLLOW_N x (log the separation before the jump, teleport Shay onto Malzin, sleep RW_FOLLOW_STEP); prints the separations
  pa_h "for i in \$(seq 1 ${RW_FOLLOW_N:-5}); do stobe-auto where \"$NPC_ID\" </dev/null | head -1 | grep -oE 'dist=[0-9.]+'; stobe-auto teleport Shay \"$NPC_ID\" </dev/null >/dev/null; sleep ${RW_FOLLOW_STEP:-1}; done"
}
pa_rec() {          # newest Hunt record of the NPC that did not exist before this run: id|rev|status|failureReason|participation.status|resourceId|quantity
  lt_sql "select id||'|'||revision||'|'||coalesce(record->>'status','')||'|'||coalesce(record->>'failureReason','')||'|'||coalesce(record->'participationOutcome'->>'status','')||'|'||coalesce(record->'agreement'->>'resourceId','')||'|'||coalesce(record->'agreement'->>'quantity','') from stobe_activity_record where actor=$ACTOR and coalesce(record->'agreement'->>'kind','')='Hunt' and id not in ($OLDIDS) order by (record->>'createdAt')::numeric desc, revision desc limit 1" | head -1
}

pa_prep
OLDIDS=$(lt_sql "select id from stobe_activity_record where actor=$ACTOR" | grep -v '^$' | sed "s/.*/'&'/" | paste -sd, -); OLDIDS="${OLDIDS:-''}"
echo "$OLDIDS" > "$OUT/old_ids.txt"
pa_inv "$OUT/inv_before.txt"

tries="${RW_FIGHT_TRIES:-4}"; a=0; ok=0
while [ $a -lt "$tries" ]; do
  a=$((a+1)); T="$OUT/try$a"; mkdir -p "$T"
  arm=$(bash "${HUNT26A_INJECT:-$HR_HERE/inject-propose.sh}" "$LANE" "$ROW_NPC" Hunt --row 26-a --ttl 900 2>&1) || fin SETUP-FAIL "inject arm failed: $(echo "$arm" | head -1 | cut -c1-160)" 2
  echo "$arm" > "$T/inject_arm.txt"
  COUNT="${COUNT:-3}" NPC_ID="$NPC_ID" NPC_FULL="$NPC_FULL" REFACTION=0 APOLOGY=0 bash "$SCENE" "$T" > "$T/scene.out" 2>&1
  grep -aq 'SCENE-OK' "$T/log.txt" 2>/dev/null || fin SETUP-FAIL "scene not ok (try $a): $(grep -a 'SCENE-BAD' "$T/log.txt" 2>/dev/null | head -1 | cut -c1-160)" 2
  if grep -aq "middle of a fight" "$T/offer.txt" 2>/dev/null; then
    say "try $a: offer refused (middle of a fight); waiting ${RW_FIGHT_WAIT:-45}s and retrying"
    rw_sleep "${RW_FIGHT_WAIT:-45}"; pa_kill_goats; continue
  fi
  ok=1; break
done
[ $ok = 1 ] || fin SETUP-FAIL "Malzin answered 'in the middle of a fight' on all $tries tries (outlaw fight near The Hub; reload the lane with lane-setup.sh ... --with Malzin) (see $OUT/try$tries/offer.txt)" 2
grep -aq 'OFFER_SEEN=1' "$T/offer.txt" 2>/dev/null && grep -aq '^SAY2 ' "$T/offer.txt" || fin SETUP-FAIL "no Hunt offer/accept said (try $a; see $T/offer.txt)" 2

N0=$(echo "wc -l < $LT_STOBELOG" | lt_h 2>/dev/null | tail -1 | tr -dc 0-9); N0=${N0:-0}
pa_h "stobe-auto speed ${RW_HUNT_SPEED} </dev/null | head -1" >/dev/null
# op14 (2026-10-16, diagnosis imm26-investigate-26a-leg): the Hunt is bound to the EXACT agreed animal (ActivityRuntimeBindings.cpp:384-394), never to a spawned substitute, and the route goal is ~1280 u
# from the scene goats, so Malzin walks back to the scene goat while Shay (teleported onto her every ~1 s) leaves the scene empty: a race. Fix: no dest-goat spawn; after the Yes MOVE the agreed goat
# (record.discoveryRef.targetSerial -> #serial/idx from this try's spawn.txt) to the route goal and pin it, so Malzin sees it on arrival. Done inside the follow loop (pa_move_goat) as soon as the serial is in the record.
RW_DEST="${RW_DEST:--50676 1570 3559}"; moved=0   # inv26a 2026-10-16: moved 15 u east to the approach slope (dy<=12 even if lifted); was the Hunt route goal at ground height (y 1580 left the goat unseen: op14f attempted=0; 1566: target selected, attempted=1); : > "$OUT/goat_move.txt"
pa_move_goat() {    # moves the agreed goat to $RW_DEST + pin; sets moved=1 only when the teleport answered; logs to goat_move.txt
  local ser id out
  ser=$(lt_sql "select record->'discoveryRef'->>'targetSerial' from stobe_activity_record where actor=$ACTOR and coalesce(record->'agreement'->>'kind','')='Hunt' and id not in ($OLDIDS) order by (record->>'createdAt')::numeric desc, revision desc limit 1" | head -1 | tr -dc 0-9)
  [ -n "$ser" ] || { echo "$(date +%T) no targetSerial in the record yet" >> "$OUT/goat_move.txt"; return 1; }
  id=$(grep -ahoE "#${ser}/[0-9]+" "$T/spawn.txt" 2>/dev/null | head -1)
  [ -n "$id" ] || id=$(pa_h 'stobe-auto chars 400 "[Herbivore]|!dead" </dev/null | head -60' | grep -ahoE "#${ser}/[0-9]+" | head -1)
  [ -n "$id" ] || { echo "$(date +%T) targetSerial=$ser not found in $T/spawn.txt or chars 400" >> "$OUT/goat_move.txt"; return 1; }
  # the scene already pinned this goat: a bare teleport is put back by PinTick and a following bare pin re-pins the OLD spot (op14 run 1: "pinned Goat at -49454"), so re-pin AT the goal (replaces the old pin)
  out=$(pa_h "stobe-auto pin \"$id\" at $RW_DEST </dev/null | head -2")
  echo "$(date +%T) targetSerial=$ser agreed goat $id -> $RW_DEST: $(echo "$out" | tr '\n' ' ' | cut -c1-300)" >> "$OUT/goat_move.txt"
  moved=1
}
# the accept must land first (newest NEW record leaves 'proposed'); then Shay follows until the record is terminal
resent=0; rec=""; step="${RW_FOLLOW_STEP:-1}"; amax="${RW_ACCEPT_WAIT:-40}"; hmax="${RW_HUNT_WAIT:-300}"; ht=0; seen_acc=0; term=""
: > "$OUT/follow.log"
while :; do
  seps=$(pa_follow | grep -oE '[0-9.]+' | paste -sd, -); ht=$((ht + ${RW_FOLLOW_N:-5} * (${step%%.*} + 1)))   # estimated real seconds (sleep + ~0.5 s of harness round trips per jump)
  rec=$(pa_rec)
  # only AFTER the accept: the accept re-validates the agreed animal (visible/reachable); moving it earlier left the record at proposed (op14 runs b-e); run a landed only because the accept won the race by 1 s
  [ $moved = 0 ] && [ "$(echo "$rec" | cut -d'|' -f3)" = accepted ] && pa_move_goat
  far=$(echo "$seps" | tr ',' '\n' | awk '$1+0 > 35 {c++} END {print c+0}')
  echo "$(date +%T) t~${ht}s $rec sep_before=[$seps]$([ "$far" -gt 0 ] && echo " SEP>35 x$far")" >> "$OUT/follow.log"
  st=$(echo "$rec" | cut -d'|' -f3)
  # op14: Malzin's LLM sometimes answers the Yes with talk (Ukil / "last hunt fell through") and does not accept; the offer is still pending -> say Yes again (at most 2x, ~15 s apart), logged in resend.log
  if [ $seen_acc = 0 ] && [ "$st" = proposed ] && [ "$resent" -lt 2 ] && [ $ht -ge $((15 * (resent + 1))) ]; then
    resent=$((resent + 1)); echo "$(date +%T) resend Yes #$resent: $(pa_h "stobe-auto stobe_say \"$NPC_ID\" \"Yes, I mean it. Let's go hunting now.\" </dev/null | head -1" | cut -c1-120)" >> "$OUT/resend.log"; amax=$((amax + 20))
  fi
  case "$st" in accepted) seen_acc=1;; completed|failed|cancelled|expired) term="$st"; seen_acc=1; break;; esac
  if [ $seen_acc = 0 ] && [ $ht -ge "$amax" ]; then break; fi
  [ $ht -ge "$hmax" ] && break
done
echo "$rec" > "$OUT/rec_final.txt"
printf 'tail -n +%s %s 2>/dev/null | grep -a -i -E "participation|NATIVE_TRAVEL|ACTIVITY_END_DIAG" | cut -c1-320 | tail -14
' "$((N0 + 1))" "$LT_STOBELOG" | lt_h > "$OUT/native.txt" 2>&1
IFS='|' read -r rid rrev rst rfail rpart rres rqty <<<"$rec"
[ -n "$rid" ] || fin SETUP-FAIL "no new Hunt record after the Yes (try $a; $OUT/follow.log, $T/offer.txt)" 2
[ $seen_acc = 1 ] || fin SETUP-FAIL "the Yes did not move the Hunt record out of '$rst' within ${amax}s (accept did not land; $OUT/follow.log)" 2
pa_inv "$OUT/inv_after.txt"
added=$(comm -13 "$OUT/inv_before.txt" "$OUT/inv_after.txt" | grep -c .)
ob=$(lt_sql "select acknowledged from stobe_activity_outbox where agreement_id='$rid' order by sequence" | grep -v '^$' | paste -sd, -)
echo "record=$rec outbox_ack=[$ob] inv_added=$added" > "$OUT/rec_summary.txt"
if [ "$term" = completed ] && [ -n "$rpart" ] && [ "$rpart" != not_completed ] && [ "$added" -ge 1 ] && [ -n "$ob" ] && ! echo "$ob" | grep -qiE '(^|,)(f|false)'; then
  fin PASS "Hunt ${rid:0:17} proposed->accepted->completed, participationOutcome=$rpart, inventory +$added item(s) ($rres x$rqty), outbox acknowledged [$ob], Shay followed (follow.log)" 0
fi
[ -n "$term" ] || fin FAIL "Hunt ${rid:0:17} still '$rst' after ${hmax}s of following (no completion; participation='$rpart'; $OUT/follow.log)" 1
fin FAIL "Hunt ${rid:0:17} ended '$term' reason='$rfail' participation='$rpart' inv_added=$added outbox=[$ob] (not a completed, delivered hunt; $OUT/follow.log)" 1
