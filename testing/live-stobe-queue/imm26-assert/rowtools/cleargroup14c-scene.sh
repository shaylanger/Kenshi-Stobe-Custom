#!/usr/bin/env bash
# cleargroup14c-scene.sh (PROPOSED by imm26-inv-14c, not yet in rowtools): row 14-c on lane 5090-i5 (NC15/NC16 installed).
#   bash cleargroup14c-scene.sh [outdir]      prints SCENE-OK|SCENE-BAD, then per-attempt reply, then ROW 14-c PASS|FAIL
# Needs: lane i5 up (lib-i5.sh), game speed 0.5, Shay (+Malzin) in squad, Cind alive and NOT in combat (teleport leaves the Hub outlaws 59 km behind).
# Env: NPC_ID (current Cind id; REFACTION=0 if she is already Nameless), SENTINEL (Rebirth Holy Sentinel id, else auto), COUNT (default 4), TRIES (default 4).
OUT="${1:-/c/KenshiTestRuns/imm26-5090-i5/14c/run-$(date +%H%M%S)}"; mkdir -p "$OUT"
source /c/KenshiTestRuns/imm26-5090-i5/lib-i5.sh
CIND="${NPC_ID:-#2529907200/2}"; SHAY='#971557632/1'; CINDFULL="${NPC_FULL:-Cind [Hungry Bandit]}"
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/log.txt"; }
# 1. Cind into the player faction Nameless (op9h: re-serial clears her personal enmity; Dust Bandits are not enemies of Traders Guild). Prints the NEW id.
if [ "${REFACTION:-1}" = 1 ]; then
  fo=$(i3 <<<"stobe-auto faction \"$CIND\" Nameless </dev/null | head -2"); echo "faction: $fo" >> "$OUT/log.txt"
  nid=$(echo "$fo" | grep -oE '#[0-9]+/[0-9]+' | head -1); [ -n "$nid" ] && CIND="$nid"; sleep 3
fi
say "Cind id $CIND"
CSER="${CIND#\#}"; CSER="${CSER%%/*}"
# 2. wake/heal, pins off, move Shay+Cind into Rebirth (type 5 formal zone, centre -47333,-55600; ground ~724). Cind 6 u NORTH of Shay so she faces SOUTH to the bandits when she turns to the speaker.
i3 <<EOT > "$OUT/scene.txt" 2>&1
stobe-auto wake "$CIND" </dev/null | head -1; stobe-auto health "$CIND" 100 </dev/null | head -1; sleep 2
stobe-auto pin "$CIND" off </dev/null | head -1; stobe-auto pin "$SHAY" off </dev/null | head -1
stobe-auto teleport "$SHAY" -47333 730 -55600 </dev/null | head -2
stobe-auto teleport "$CIND" -47333 730 -55594 </dev/null | head -2
stobe-auto select Shay </dev/null | head -1
for w in Shay Malzin; do stobe-auto stobe_drawn sheathe \$w </dev/null | head -1; done
EOT
cat "$OUT/scene.txt" | tee -a "$OUT/log.txt"
# 3. Rebirth's Holy Sentinels friendly to the player faction (else they fight the bandits/us): relation <sentinel> 100 sets that NPC's faction <-> player faction.
SENT="${SENTINEL:-$(i3 <<<'stobe-auto chars 150 "Holy Sentinel|!dead" </dev/null | head -3' | grep -oE '#[0-9]+/[0-9]+' | head -1)}"
[ -n "$SENT" ] && i3 <<<"stobe-auto relation \"$SENT\" 100 </dev/null | head -2" | tee -a "$OUT/log.txt" || say "WARN no sentinel id found (set SENTINEL=); Rebirth may engage"
# 4. affinity 60 (Fond) so she is willing
i3w <<<"php /mnt/c/KenshiTestRuns/imm26-5090-i5/haff-i5.php \"$CINDFULL\" Shay 60 friend" | cut -c1-200 >> "$OUT/log.txt" 2>&1
# 5. bandits 40 u SOUTH of Shay (op9h coordinates), hostile to the player faction, pinned AFTER they have settled on the ground
i3 <<EOT > "$OUT/spawn.txt" 2>&1
stobe-auto spawn "Dust Bandit" "Dust Bandits" at -47335 725 -55640 count ${COUNT:-4} </dev/null | head -3
EOT
cat "$OUT/spawn.txt" | cut -c1-300 | tee -a "$OUT/log.txt"
BANDITS=$(grep -oE '#[0-9]+/[0-9]+' "$OUT/spawn.txt" | grep -v "^$CIND$" | sort -u | head -6)
[ -n "$BANDITS" ] || { say "SCENE-BAD no bandits spawned"; exit 3; }
B1=$(echo $BANDITS | awk '{print $1}')
i3 <<<"stobe-auto relation \"$B1\" -100 </dev/null | head -2" | tee -a "$OUT/log.txt"   # Dust Bandits <-> player faction -100
sleep 12   # let them land: while falling the candidate flickers (op9h: 2 then 3 of 4 members, token :6 -> :7, digest changed)
for b in $BANDITS; do i3 <<<"stobe-auto pin \"$b\" </dev/null | head -1" >> "$OUT/log.txt" 2>&1; done
i3 <<<"stobe-auto face \"$CIND\" \"$B1\" </dev/null | head -1; sleep 1" >> "$OUT/log.txt" 2>&1
# 6. go/no-go: Cind must SEE >= 3 bandits on two polls 4 s apart (sightDrops otherwise: the candidate list stays [])
ok=0
for poll in 1 2; do
  SEES=0
  for b in $BANDITS; do s=$(i3 <<<"stobe-auto senses \"$CIND\" \"$b\" </dev/null | head -2"); echo "senses $b: $s" >> "$OUT/log.txt"; echo "$s" | grep -qE 'sees=1' && SEES=$((SEES+1)); done
  say "poll $poll senses sees=1 count=$SEES of $(echo $BANDITS | wc -w)"; [ $SEES -ge 3 ] && ok=$((ok+1)); sleep 4
done
[ $ok -ge 2 ] || { say "SCENE-BAD cind does not stably see >=3 bandits (see $OUT/log.txt)"; exit 3; }
i3 <<<"stobe-auto stobe_ctxpush \"$CINDFULL\" </dev/null | head -2" >> "$OUT/log.txt" 2>&1
say "SCENE-OK"
# 7. the ask. NEVER the bare 'Clear the bandit camp.' (6/6 NONE: 'which camp?'). Name the group, the place and the joint intent like the 26-a Hunt phrase (PROPOSE 5/6).
P1="Look at those Dust Bandits here in Rebirth. Cind, I want you to clear them out with me."
P2="Cind, will you help me clear out the bandits you can see in front of us here in Rebirth?"
P3="Those Dust Bandits are raiding Rebirth and you can see them. Let's clear out that group together."
P4="Cind, I want you to help me kill the Dust Bandits standing in Rebirth. Just those ones."
PROPOSED=0; n=0
for P in "$P1" "$P2" "$P3" "$P4"; do
  n=$((n+1)); [ $n -gt "${TRIES:-4}" ] && break
  say "ATTEMPT $n: $P"
  i3_say "$CIND" "$P" 60 2>&1 | grep -E "\((NPC|PC)\)" | cut -c1-320 | tee -a "$OUT/log.txt"
  sleep 4
  ROW=$(i3_sql "select record->>'status',record->'agreement'->>'kind',record->'agreement'->'campZone'->>'candidateId',record->'agreement'->>'scopeVersion',record->'agreement'->>'agreedTargets' from stobe_activity_record where actor=$CSER order by 1")
  echo "record: $ROW" | tee -a "$OUT/log.txt"
  echo "$ROW" | grep -q '^proposed|ClearGroup|v1:' && { PROPOSED=1; break; }
  sleep 8
done
# 8. negative leg: nobody was attacked before acceptance
i3 <<<'stobe-auto chars 120 "Dust Bandit|!dead" </dev/null | head -8' | cut -c1-200 | tee -a "$OUT/log.txt"
if [ $PROPOSED = 1 ]; then say "ROW 14-c PASS (ClearGroup offer with campZone, status proposed, attempt $n); negative leg: check bandits alive/full health above and no Attack ACTION_EXEC"
else say "ROW 14-c FAIL no ClearGroup proposal in $((n-1)) attempts (read the model reply above; check the newest 'Current optional activity facts' still lists ClearGroup)"; fi
