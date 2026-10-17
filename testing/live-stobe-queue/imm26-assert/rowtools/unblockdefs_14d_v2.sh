#!/usr/bin/env bash
# unblockdefs_14d_v2.sh (imm26-fix14dtool F3, 2026-10-16): v2 of unblockdefs_14d.sh; the v1 file is untouched (a queued/running list may use it). Differences:
#   (1) the FAR bandit is spawned by its OWN `spawn` call as a different faction (D14_FAR_FACTION, default "Starving Bandits"; or a squad template D14_FAR_SPAWNT = its own Platoon,
#       Commands.cpp:2260). Reason (inv14d, 14-d run 2): all 6 bandits spawned by ONE `spawn ... count 6` landed in ONE platoon and the native ClearGroup set is the visible platoon-mates
#       with no distance rule (ActivityRuntimeBindings.cpp ~696-712), so the offered set held the FAR bandit and dropped near Dalx. Near five: one `spawn ... count 5` (D14_COUNT).
#   (2) the scene gate compares SERIALS: the probe round only passes when the offered agreedTargets equal exactly the 5 NEAR serials (no FAR serial, none missing); otherwise
#       "SCENE-BAD agreedTargets set != near five (...)" -> SETUP-FAIL with the cause (unblockcheck_14d.py names the member diag), never an unwinnable FAIL.
# ---- original header (v1) follows ----
# unblockdefs_14d.sh (imm26-sfFixB2, 2026-10-16): row 14-d (ClearGroup for a hostile bandit group of exactly 5, distant 6th untouched) as a go-row.sh row. NEW file.
# Sourced by unblockrun_14d.sh AFTER go-row.sh / reloaddefs_a.sh / tripdefs (tr_cfg). Port of cleargroup14c-scene.sh (GRID5=1 recipe of inv-14e) onto the lane-generic lt_* transport,
# so it runs on any lane whose loaded save has Cind + Shay (the scene teleports both to Rebirth, x/y/z in D14_BASE). Nothing existing is edited.
# Steps (evidence in $EV):
#   prep    wake/heal, pins off, Shay + NPC to Rebirth, sheathe, Sentinels friendly (relation), affinity D14_AFF (60), NPC into the player faction Nameless when she is not (re-serial -> re-resolve)
#   spawn   D14_COUNT(5)+D14_FAR(1) Dust Bandits (D14_SPAWNT = one-platoon squad template); bandits.txt = NEAR (first 5 in spawn order) / FAR (the rest); relation -100; near on a flat 5-point grid,
#           far D14_FAR_DZ (170) u north, all pinned; senses polls (sees=1 on >= D14_SEES_MIN near bandits)
#   probe   sp1..spN (D14_ROUNDS 3): say "Cind, can you see those bandits?" and read the newest prompt's "agreedTargets":[...]; < 5 serials -> bandits moved closer (z+6*round), next round.
#           cleargroup_member_lines.txt = the ACTIVITY_CLEARGROUP_MEMBER lines (selected/visible/protected/protReason + NC22 ownerSerial/slaveState/chained/prison)
#           Still < 5 after the rounds: scene.txt = "SCENE-BAD agreedTargets=n of 5" and the row ends there (the checker names the cause = SETUP-FAIL).
#   ask     s1: D14_ASK ("Hunt the 5 bandits."); rec_ask.txt = the NPC's new activity records (id|rev|status|kind|candidateId|agreedTargets); atk_pre.txt = attack-order lines logged BEFORE the accept
#   accept  s2: D14_ACCEPT ("Yes, let's do it."), then up to D14_HOLD (90) real s of polling the record (rec_final.txt, rec_poll.txt); atk_post.txt / act_lines.txt = attack + ACTIVITY lines since the accept;
#           outbox_rows.txt = the agreement's outbox revisions; chars_after.txt = Dust Bandits still alive (`chars ... !dead`)
# Env: D14_COUNT D14_FAR D14_BASE ("-47333 730 -55600") D14_GRIDZ (-55624) D14_FAR_DZ (170) D14_SPAWNT D14_AFF D14_ROUNDS D14_SEES_MIN (3) D14_ASK D14_ACCEPT D14_HOLD D14_POLL_S (6)
#      D14_ATK_RE (attack-order regex over stobe.log) D14_SENT (Holy Sentinel id; default auto) D14_CLEAN (1: cancel stale proposed/accepted activity records of the NPC on the PRIVATE lane DB)
#      D14_REFACTION (auto|0|1).  Needs a lane DLL with the NC22 ownership fix (NC30 / NC31 contain it) and the ACTIVITY_CLEARGROUP_MEMBER diag line.
: "${D14_COUNT:=5}"; : "${D14_FAR:=1}"; : "${D14_BASE:=-47333 730 -55600}"; : "${D14_GRIDZ:=-55624}"; : "${D14_FAR_DZ:=170}"; : "${D14_AFF:=60}"
: "${D14_ROUNDS:=3}"; : "${D14_SEES_MIN:=3}"; : "${D14_ASK:=Hunt the 5 bandits.}"; [ -n "${D14_ACCEPT:-}" ] || D14_ACCEPT="Yes, let's do it."; : "${D14_HOLD:=90}"; : "${D14_POLL_S:=6}"; : "${D14_CLEAN:=1}"
: "${D14_REFACTION:=auto}"
: "${D14_FAR_FACTION:=Starving Bandits}"   # the FAR bandit's faction (another faction cannot be a platoon-mate of the near five); D14_FAR_SPAWNT = a squad template (own Platoon) instead
: "${D14_ATK_RE:=UNPROVOKED_FOCUSED_MELEE_ATTACK|ACTION_EXEC: *Attack|ACTIVITY_ATTACK|ACTIVITY_COMBAT_ORDER}"
D14_ACT_RE='ACTIVITY_(GRANT|PROGRESS|CANCEL|END|VERIFY|HOSTILE)[A-Z_]*|outside_fixed_hostile_set|target_outside_fixed_agreement|ClearGroup'
D14_REC_SQL="select id||'|'||revision||'|'||coalesce(record->>'status','')||'|'||coalesce(record->'agreement'->>'kind','')||'|'||coalesce(record->'agreement'->'campZone'->>'candidateId','')||'|'||coalesce(record->'agreement'->>'agreedTargets','') from stobe_activity_record"

d14_say() { echo "[$(date +%T)] $*" >> "$EV/run.log"; }
d14_serial() { local s="${1#\#}"; echo "${s%%/*}"; }
d14_serials() {   # d14_serials <text> -> the sorted unique serials (5-10 digits) in it, one line, space separated
  echo "$*" | grep -o '[0-9]\{5,10\}' | sort -u | tr '\n' ' ' | sed 's/ $//'
}
d14_minus() {   # d14_minus "<a b c>" "<b>" -> the words of the first list that are not in the second
  local w r=""; for w in $1; do case " $2 " in *" $w "*) ;; *) r="$r$w ";; esac; done; echo "${r% }"
}

d14_rec() {   # d14_rec <file>: the NPC's activity records that did not exist before this run
  lt_sql "$D14_REC_SQL where actor=$D14_ACTOR and id not in ($D14_OLDIDS) order by 1" 2>&1 | grep -a '|' > "$1"
}
d14_count_set() {   # d14_count_set <prompt.txt>  -> prints the newest agreedTargets array text and its number of serials in the form "<n> <array>"
  local a n; a=$(grep -a -o '"agreedTargets":\[[0-9, ]*\]' "$1" 2>/dev/null | tail -1)
  n=$(echo "$a" | grep -o '[0-9]\{5,\}' | sort -u | wc -l | tr -d ' ')
  echo "$n ${a:-none}"
}
d14_ring() {   # d14_ring <dz>: re-place the near bandits on the grid (x = bx-8+4k) at z = D14_GRIDZ+dz, unpin -> teleport -> pin
  local k=0 b bx dz="$1"; set -- $D14_BASE; bx=$1
  for b in $D14_NEAR; do
    printf 'stobe-auto pin "%s" off </dev/null | head -1; stobe-auto teleport "%s" %s 725 %s </dev/null | head -1; stobe-auto pin "%s" </dev/null | head -1 # d14:ring\n' "$b" "$b" "$(( bx - 8 + 4 * k ))" "$(( D14_GRIDZ + dz ))" "$b" | lt_h >> "$EV/place.txt" 2>&1
    k=$((k + 1))
  done
}

rd_14d() {
  local n sent spawnout ids total all k b o ok poll sees round r cnt arr N0 N1 elapsed rst rid npcq line setx sz nearset gotset
  ROW_NATIVE=1; rd_need_npc || return 3
  npcq=$(rl_q "$RL_NPC_FULL"); set -- $D14_BASE; sz=$3
  : > "$EV/scene.txt"; : > "$EV/place.txt"; : > "$EV/set_probe.txt"; : > "$EV/cleargroup_member_lines.txt"
  # ---- prep
  if [ "$D14_REFACTION" = 1 ] || { [ "$D14_REFACTION" = auto ] && ! printf 'stobe-auto where %s </dev/null | head -1 # d14:where\n' "$npcq" | lt_h 2>&1 | grep -q '\[Nameless\]'; }; then
    printf 'stobe-auto faction %s Nameless </dev/null | head -2 # d14:faction\n' "$npcq" | lt_h > "$EV/faction.txt" 2>&1
    rw_sleep 3; RL_NPC_ID=""; rd_need_npc || return 3; npcq=$(rl_q "$RL_NPC_FULL")
  fi
  D14_ACTOR=$(d14_serial "$RL_NPC_ID"); echo "npc=$RL_NPC_FULL id=$RL_NPC_ID actor=$D14_ACTOR" >> "$EV/scene.txt"
  if [ "$D14_CLEAN" = 1 ]; then   # a stale proposed/accepted record of the NPC (unique index per actor) would block the new offer: cancel it on the PRIVATE lane DB only
    lt_sql "select id||'|'||coalesce(record->>'status','') from stobe_activity_record where actor=$D14_ACTOR and record->>'status' in ('proposed','accepted')" > "$EV/stale_records.txt" 2>&1
    if grep -qa '|' "$EV/stale_records.txt"; then lt_sqlx "update stobe_activity_record set record=jsonb_set(record,'{status}','\"cancelled\"') where actor=$D14_ACTOR and record->>'status' in ('proposed','accepted')" >> "$EV/stale_records.txt" 2>&1; fi
  fi
  D14_OLDIDS=$(lt_sql "select id from stobe_activity_record where actor=$D14_ACTOR" | grep -a -v '^$' | sed "s/.*/'&'/" | paste -sd, -); D14_OLDIDS="${D14_OLDIDS:-''}"
  lt_h <<EOT > "$EV/prep.txt" 2>&1
# d14:prep
stobe-auto wake $npcq </dev/null | head -1; stobe-auto health $npcq 100 </dev/null | head -1; sleep 2
stobe-auto pin $npcq off </dev/null | head -1; stobe-auto pin Shay off </dev/null | head -1
stobe-auto teleport Shay $D14_BASE </dev/null | head -2
stobe-auto teleport $npcq $1 $2 $(( sz + 6 )) </dev/null | head -2
stobe-auto select Shay </dev/null | head -1
for w in Shay Malzin; do stobe-auto stobe_drawn sheathe \$w </dev/null | head -1; done
EOT
  sent="${D14_SENT:-$(printf 'stobe-auto chars 150 "Holy Sentinel|!dead" </dev/null | head -3 # d14:sentinel\n' | lt_h 2>&1 | grep -a -o '#[0-9]*/[0-9]*' | head -1)}"
  if [ -n "$sent" ]; then printf 'stobe-auto relation "%s" 100 </dev/null | head -2 # d14:relsent\n' "$sent" | lt_h >> "$EV/prep.txt" 2>&1; else echo "WARN no Holy Sentinel id (set D14_SENT=): Rebirth may engage" >> "$EV/prep.txt"; fi
  rd_aff "$D14_AFF"
  # ---- spawn: the near five by one call (one platoon), the FAR bandit by its own call as another faction / its own squad (never a platoon-mate of the near five)
  total=$(( D14_COUNT + D14_FAR ))
  if [ -n "${D14_SPAWNT:-}" ]; then
    printf 'stobe-auto spawn "%s" "Dust Bandits" at %s 725 %s count %s </dev/null | head -3; sleep 2; stobe-auto chars 300 "Dust Bandit|!dead" </dev/null | head -3 # d14:spawn\n' "$D14_SPAWNT" "$1" "$(( sz - 40 ))" "$D14_COUNT" | lt_h > "$EV/spawn.txt" 2>&1
  else
    printf 'stobe-auto spawn "Dust Bandit" "Dust Bandits" at %s 725 %s count %s </dev/null | head -3 # d14:spawn\n' "$1" "$(( sz - 40 ))" "$D14_COUNT" | lt_h > "$EV/spawn.txt" 2>&1
  fi
  ids=$(grep -a -o '#[0-9]*/[0-9]*' "$EV/spawn.txt" | grep -v -x -F "$RL_NPC_ID" | awk '!s[$0]++' | head -$((D14_COUNT + 3)))
  D14_NEAR=$(echo $ids | tr ' ' '\n' | head -n "$D14_COUNT" | tr '\n' ' ' | sed 's/ $//')
  n=$(echo $D14_NEAR | wc -w | tr -d ' ')
  if [ "$n" -lt "$D14_COUNT" ]; then
    { echo "NEAR $D14_NEAR"; echo "FAR "; echo "SPAWNED $n of $total"; } > "$EV/bandits.txt"
    echo "SCENE-BAD spawn: only $n of $D14_COUNT near Dust Bandits spawned, of $total (see spawn.txt)" >> "$EV/scene.txt"; return 0
  fi
  : > "$EV/spawn_far.txt"
  for k in $(seq 1 "$D14_FAR"); do   # a separate spawn call per far bandit, created at the far point from the start
    if [ -n "${D14_FAR_SPAWNT:-}" ]; then
      printf 'stobe-auto spawn "%s" "%s" at %s 725 %s count 1 </dev/null | head -3; sleep 2; stobe-auto chars 300 "Dust Bandit|!dead" </dev/null | head -3 # d14:spawnfar\n' "$D14_FAR_SPAWNT" "$D14_FAR_FACTION" "$1" "$(( sz + D14_FAR_DZ ))" | lt_h >> "$EV/spawn_far.txt" 2>&1
    else
      printf 'stobe-auto spawn "Dust Bandit" "%s" at %s 725 %s count 1 </dev/null | head -3 # d14:spawnfar\n' "$D14_FAR_FACTION" "$1" "$(( sz + D14_FAR_DZ ))" | lt_h >> "$EV/spawn_far.txt" 2>&1
    fi
  done
  D14_FARIDS=$(d14_minus "$(grep -a -o '#[0-9]*/[0-9]*' "$EV/spawn_far.txt" | grep -v -x -F "$RL_NPC_ID" | awk '!s[$0]++' | tr '\n' ' ')" "$D14_NEAR" | tr ' ' '\n' | head -n "$D14_FAR" | tr '\n' ' ' | sed 's/ $//')
  all=$(( n + $(echo $D14_FARIDS | wc -w | tr -d ' ') ))
  { echo "NEAR $D14_NEAR"; echo "FAR $D14_FARIDS"; echo "SPAWNED $all of $total"; } > "$EV/bandits.txt"
  if [ "$all" -lt "$total" ]; then echo "SCENE-BAD spawn: only $all of $total Dust Bandits spawned (near $n, far $((all - n)); see spawn.txt, spawn_far.txt)" >> "$EV/scene.txt"; return 0; fi
  b=$(echo $D14_NEAR | awk '{print $1}'); printf 'stobe-auto relation "%s" -100 </dev/null | head -2 # d14:relhost\n' "$b" | lt_h >> "$EV/place.txt" 2>&1
  d14_ring 0
  for b in $D14_FARIDS; do
    printf 'stobe-auto pin "%s" off </dev/null | head -1; stobe-auto teleport "%s" %s 725 %s </dev/null | head -1; stobe-auto pin "%s" </dev/null | head -1 # d14:far\n' "$b" "$b" "$(( $1 + 0 ))" "$(( sz + D14_FAR_DZ ))" "$b" | lt_h >> "$EV/place.txt" 2>&1
  done
  printf 'stobe-auto face %s "%s" </dev/null | head -1; sleep 1 # d14:face\n' "$npcq" "$(echo $D14_NEAR | awk '{print $1}')" | lt_h >> "$EV/place.txt" 2>&1
  # ---- senses go/no-go (sees=1 on >= D14_SEES_MIN near bandits on two polls 4 s apart; one good poll is enough)
  ok=0
  for poll in 1 2; do
    sees=0
    for b in $D14_NEAR; do
      o=$(printf 'stobe-auto senses %s "%s" </dev/null | head -2 # d14:senses\n' "$npcq" "$b" | lt_h 2>&1); echo "poll$poll $b: $o" >> "$EV/senses.txt"
      echo "$o" | grep -q 'sees=1' && sees=$((sees + 1))
    done
    echo "poll $poll sees=1 count=$sees of $D14_COUNT" >> "$EV/scene.txt"; [ "$sees" -ge "$D14_SEES_MIN" ] && ok=$((ok + 1)); rw_sleep 4
  done
  if [ "$ok" -lt 1 ]; then echo "SCENE-BAD senses: the NPC does not see >= $D14_SEES_MIN of $D14_COUNT bandits (see senses.txt)" >> "$EV/scene.txt"; return 0; fi
  # ---- probe: the native ClearGroup set must list all D14_COUNT serials BEFORE the ask
  N0=$(echo "wc -l < $LT_STOBELOG" | lt_h 2>/dev/null | tail -1 | tr -dc 0-9); N0="${N0:-0}"
  setx="0 none"; gotset=""; nearset=$(d14_serials $(for b in $D14_NEAR; do d14_serial "$b"; done))
  for round in $(seq 1 "$D14_ROUNDS"); do
    rl_say "p$round" "Cind, can you see those bandits?" 40 || return $?
    setx=$(d14_count_set "$EV/sp$round/prompt.txt"); echo "round $round: $setx" >> "$EV/set_probe.txt"
    printf 'tail -n +%s %s 2>/dev/null | grep -a ACTIVITY_CLEARGROUP_MEMBER | cut -c1-520 | tail -12 # d14:members\n' "$((N0 + 1))" "$LT_STOBELOG" | lt_h > "$EV/cl_round$round.txt" 2>&1
    { echo "# round $round"; cat "$EV/cl_round$round.txt"; } >> "$EV/cleargroup_member_lines.txt"
    gotset=$(d14_serials "${setx#* }"); [ "$gotset" = "$nearset" ] && break   # the offered set must be EXACTLY the near five (inv14d F3), not just any 5
    [ "$round" -lt "$D14_ROUNDS" ] && { d14_ring $((6 * round)); rw_sleep 3; }
  done
  if [ "$gotset" != "$nearset" ]; then
    if [ "${setx%% *}" -ge "$D14_COUNT" ]; then   # right count, wrong members: the platoon rule put a far bandit in the set / a near member is invisible
      echo "SCENE-BAD agreedTargets set != near five (not near: [$(d14_minus "$gotset" "$nearset")] missing near: [$(d14_minus "$nearset" "$gotset")]; set_probe.txt, cleargroup_member_lines.txt)" >> "$EV/scene.txt"
    else
      echo "SCENE-BAD agreedTargets=${setx%% *} of $D14_COUNT (set_probe.txt, cleargroup_member_lines.txt)" >> "$EV/scene.txt"
    fi
    return 0
  fi
  echo "SCENE-OK agreedTargets=${setx%% *} == near five" >> "$EV/scene.txt"
  # ---- ask
  N0=$(echo "wc -l < $LT_STOBELOG" | lt_h 2>/dev/null | tail -1 | tr -dc 0-9); N0="${N0:-0}"
  rl_say 1 "$D14_ASK" || return $?
  rw_sleep 4; d14_rec "$EV/rec_ask.txt"
  printf 'tail -n +%s %s 2>/dev/null | grep -a -E "%s" | cut -c1-360 | head -40 # d14:atkpre\n' "$((N0 + 1))" "$LT_STOBELOG" "$D14_ATK_RE" | lt_h > "$EV/atk_pre.txt" 2>&1
  printf 'tail -n +%s %s 2>/dev/null | grep -a ACTIVITY_CLEARGROUP_MEMBER | cut -c1-520 | tail -12 # d14:members\n' "$((N0 + 1))" "$LT_STOBELOG" | lt_h > "$EV/cl_ask.txt" 2>&1
  if ! grep -a -q '^[^|]*|[0-9]*|proposed|ClearGroup|' "$EV/rec_ask.txt"; then return 0; fi   # no ClearGroup offer: the checker names what the NPC did instead
  # ---- accept + watch
  N1=$(echo "wc -l < $LT_STOBELOG" | lt_h 2>/dev/null | tail -1 | tr -dc 0-9); N1="${N1:-0}"
  rl_say 2 "$D14_ACCEPT" || return $?
  elapsed=0; : > "$EV/rec_poll.txt"
  while [ "$elapsed" -le "$D14_HOLD" ]; do
    rw_sleep "$D14_POLL_S"; elapsed=$((elapsed + D14_POLL_S + 1)); d14_rec "$EV/rec_final.txt"
    { echo "t~${elapsed}s"; cat "$EV/rec_final.txt"; } >> "$EV/rec_poll.txt"
    rst=$(head -1 "$EV/rec_final.txt" | cut -d'|' -f3)
    case "$rst" in completed|failed|cancelled|expired) break;; esac
  done
  rid=$(head -1 "$EV/rec_final.txt" | cut -d'|' -f1); rid="${rid:-none}"
  printf 'tail -n +%s %s 2>/dev/null | grep -a -E "%s" | cut -c1-360 | head -80 # d14:atkpost\n' "$((N1 + 1))" "$LT_STOBELOG" "$D14_ATK_RE" | lt_h > "$EV/atk_post.txt" 2>&1
  printf 'tail -n +%s %s 2>/dev/null | grep -a -E "%s" | cut -c1-360 | head -80 # d14:actlines\n' "$((N1 + 1))" "$LT_STOBELOG" "$D14_ACT_RE" | lt_h > "$EV/act_lines.txt" 2>&1
  lt_sql "select sequence||'|'||revision||'|'||acknowledged||'|'||left(envelope::text,260) from stobe_activity_outbox where agreement_id='$rid' order by sequence" > "$EV/outbox_rows.txt" 2>&1
  printf 'stobe-auto chars 400 "Dust Bandit|!dead" </dev/null | head -12 # d14:alive\n' | lt_h > "$EV/chars_after.txt" 2>&1
  return 0
}
