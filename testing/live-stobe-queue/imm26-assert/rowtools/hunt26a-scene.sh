#!/usr/bin/env bash
# hunt26a-scene.sh: build the passing E-ground Hunt scene on lane 5090-i5 (recipe agents/out/imm26-26a-recipe/latest.md) and run the 26-a offer+accept.
#   bash hunt26a-scene.sh <outdir>         prints SCENE-OK|SCENE-BAD, then OFFER/ACCEPT timing, then record + diag lines; evidence in <outdir>
# Needs: lane i5 up (lib-i5.sh), game at speed 0.5, Cind+Shay in squad. Private lane only.
OUT="${1:-/c/KenshiTestRuns/imm26-5090-i5/26a/run-$(date +%H%M%S)}"; mkdir -p "$OUT"
source /c/KenshiTestRuns/imm26-5090-i5/lib-i5.sh
CIND="${NPC_ID:-#2529907200/2}"; SHAY='#971557632/1'; CINDFULL="${NPC_FULL:-Cind [Hungry Bandit]}"   # NPC_ID/NPC_FULL pick another NPC (then REFACTION=0; non-NPC speakers log as (PC))
SAY1V=${SAY1:-"Look at all these goats. Let's hunt for raw meat."}; SAY2V=${SAY2:-"Yes, let's do it."}   # (quotes inside the default: a bare apostrophe inside "${v:-..}" breaks Git Bash 'bad substitution')
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/log.txt"; }
L1=$(i3 <<<'wc -l < /mnt/d/KenshiInst/5/RE_Kenshi/mods/Stobe/stobe.log' | tail -1)
say "stobe.log mark $L1"
# personal enmity baked in Cind (ACTIVITY_HOSTILE_DIAG actorEnemyOfReq=1 even at relation 50 -> requester_now_hostile): faction re-serials her and clears it (op8 finding). REFACTION=0 to skip
refaction() {
  [ -n "$nid_done" ] && return; nid_done=1
  fo=$(i3 <<<"stobe-auto faction \"$CIND\" \"${REFAC_FACTION:-Traders Guild}\" </dev/null | head -2"); echo "faction: $fo" >> "$OUT/log.txt"
  nid=$(echo "$fo" | grep -oE '#[0-9]+/[0-9]+' | head -1); [ -n "$nid" ] && CIND="$nid"
  say "Cind id now $CIND"; sleep 3
}
[ "${REFACTION:-late}" = early ] && refaction
# scene: pins off, teleports, onmesh wait, clean travel rows, aff 60, ctxpush
i3 <<EOT > "$OUT/scene.txt" 2>&1
stobe-auto wake "$CIND" </dev/null | head -1; stobe-auto health "$CIND" 100 </dev/null | head -1; sleep 3
stobe-auto pin "$CIND" off </dev/null | head -1; stobe-auto pin "$SHAY" off </dev/null | head -1
stobe-auto teleport "$SHAY" -49400 1660 3625 </dev/null | head -2
stobe-auto teleport "$CIND" -49422 1661 3643 </dev/null | head -2
stobe-auto select Shay </dev/null | head -1
stobe-auto relation "$CIND" 50 </dev/null | head -2
for w in Shay Malzin; do stobe-auto stobe_drawn sheathe \$w </dev/null | head -1; done
EOT
cat "$OUT/scene.txt" | tee -a "$OUT/log.txt"
sleep 10
i3_sql "delete from eventlog where type='travel_agreement'" >> "$OUT/log.txt" 2>&1
i3w <<<"php /mnt/c/KenshiTestRuns/imm26-5090-i5/haff-i5.php \"$CINDFULL\" Shay 60 friend" | cut -c1-200 >> "$OUT/log.txt" 2>&1
i3 <<EOT >> "$OUT/log.txt" 2>&1
stobe-auto stobe_ctxpush "$CINDFULL" </dev/null | head -2
EOT
# quarrel memory ("blade in my face"): one apology clears it for a few turns (recipe step e); skip with APOLOGY=0
if [ "${APOLOGY:-1}" = 1 ]; then
  i3_say "$CIND" "It was a mistake, I'm sorry." 40 2>&1 | grep -E "\((NPC|PC)\)" | cut -c1-300 | tee -a "$OUT/log.txt"
  i3 <<EOT >> "$OUT/log.txt" 2>&1
sleep ${APOLOGY_WAIT:-8}
stobe-auto stobe_ctxpush "$CINDFULL" </dev/null | head -2
EOT
fi
# spawn goats, t+2 chars check, senses gate
i3 <<EOT > "$OUT/spawn.txt" 2>&1
stobe-auto spawn "wild goats" Herbivore at -49405 1664 3645 count ${COUNT:-8} size 0.2 </dev/null | head -3
sleep 2
stobe-auto chars 80 "[Herbivore]|!dead" </dev/null | head -6
EOT
cat "$OUT/spawn.txt" | cut -c1-300 | tee -a "$OUT/log.txt"
GOATS=$(grep -oE '#[0-9]+/[0-9]+' "$OUT/spawn.txt" | grep -v "^$CIND$" | sort -u | head -5)
[ -n "$GOATS" ] || { say "SCENE-BAD no goats found"; exit 3; }
# hold the goats (they flee at 10-25 u/s and the offer takes ~10-15 s): pin each in place; PIN=0 to skip
if [ "${PIN:-1}" = 1 ]; then for g in $GOATS; do i3 <<<"stobe-auto pin \"$g\" </dev/null | head -1" >> "$OUT/log.txt" 2>&1; done; fi
if [ "${REFACTION:-late}" = late ]; then refaction; i3 <<EOT >> "$OUT/log.txt" 2>&1
stobe-auto stobe_ctxpush "$CINDFULL" </dev/null | head -2
EOT
fi
# turn Cind toward the first goat (sees=0/fov=0 while she faces away), then the go/no-go below
G1=$(echo $GOATS | awk '{print $1}'); i3 <<<"stobe-auto face \"$CIND\" \"$G1\" </dev/null | head -1; sleep 1" >> "$OUT/log.txt" 2>&1
SEES=0
for g in $GOATS; do
  s=$(i3 <<<"stobe-auto senses \"$CIND\" \"$g\" </dev/null | head -2"); echo "senses $g: $s" >> "$OUT/log.txt"
  echo "$s" | grep -qE 'sees=1' && SEES=$((SEES+1))
done
say "senses sees=1 count=$SEES of $(echo $GOATS | wc -w)"
[ $SEES -ge 1 ] || { say "SCENE-BAD cind sees no goat (see $OUT/log.txt)"; exit 3; }
say "SCENE-OK"
# t+5 say; accept as soon as the offer's first NPC sentence shows (<=5 s)
i3 <<EOT > "$OUT/offer.txt" 2>&1
L="/mnt/d/KenshiInst/5/RE_Kenshi/mods/Stobe/stobe.log"; n0=\$(wc -l < "\$L")
sleep 1
echo "SAY1 \$(date +%T.%N)"
stobe-auto stobe_say "$CIND" "$SAY1V" </dev/null | head -2
end=\$((SECONDS+45)); got=0
while [ \$SECONDS -lt \$end ]; do
  if tail -n +\$((n0+1)) "\$L" | sed -n '/SAY \[Shay\]: Look at all/,\$p' | tail -n +2 | grep -qE "ACTION_EXEC: SAY \[[^]]*\](.*)\((NPC|PC)\)"; then got=1; break; fi
  sleep 0.5
done
echo "OFFER_SEEN=\$got \$(date +%T.%N)"
tail -n +\$((n0+1)) "\$L" | grep -E "ACTION_EXEC: SAY|REJECTED|ACTIVITY_SIGHT_DIAG|ACTIVITY_PROPOSAL" | cut -c1-300 | head -6
if [ \$got = 1 ]; then
  # op9l (NC17 run): saying "Yes" while the offer speech is still being delivered cancels it ("RECHAT_TIMING: follow-up suppressed ... cancelled_or_interrupted"),
  # so the offer is never bound as displayed and the accept fails with "Explicit scoped consent was not verified". Wait for the delivery confirmation first.
  wend=\$((SECONDS+${DELIVERY_WAIT:-40}))
  while [ \$SECONDS -lt \$wend ]; do tail -n +\$((n0+1)) "\$L" | grep -qE "RECHAT_TIMING: follow-up (dispatch scheduled|suppressed)" && break; sleep 0.5; done
  echo "DELIVERY_CONFIRMED \$(tail -n +\$((n0+1)) "\$L" | grep -E "RECHAT_TIMING: follow-up" | head -1 | cut -c1-120)"
  sleep ${ACCEPT_DELAY:-1}
  echo "SAY2 \$(date +%T.%N)"
  stobe-auto stobe_say "$CIND" "$SAY2V" </dev/null | head -2
  # row 26-b: CANCEL_AFTER=<s> says "Cancel that." (CANCEL_TEXT) that many seconds after the Yes (the accept reply must have been delivered first, ~10-15 s)
  if [ -n "${CANCEL_AFTER:-}" ]; then
    sleep ${CANCEL_AFTER}
    echo "CANCEL \$(date +%T.%N)"
    stobe-auto stobe_say "$CIND" "${CANCEL_TEXT:-Cancel that.}" </dev/null | head -2
  fi
fi
EOT
cat "$OUT/offer.txt" | tee -a "$OUT/log.txt"
echo "$L1" > "$OUT/logmark.txt"
