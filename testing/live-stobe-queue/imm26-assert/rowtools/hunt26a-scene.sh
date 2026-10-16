#!/usr/bin/env bash
# hunt26a-scene.sh: build the passing E-ground Hunt scene on lane 5090-i5 (recipe agents/out/imm26-26a-recipe/latest.md) and run the 26-a offer+accept.
#   bash hunt26a-scene.sh <outdir>         prints SCENE-OK|SCENE-BAD, then OFFER/ACCEPT timing, then record + diag lines; evidence in <outdir>
# Needs: lane i5 up (lib-i5.sh), game at speed 0.5, Cind+Shay in squad. Private lane only.
OUT="${1:-/c/KenshiTestRuns/imm26-5090-i5/26a/run-$(date +%H%M%S)}"; mkdir -p "$OUT"
source /c/KenshiTestRuns/imm26-5090-i5/lib-i5.sh
CIND='#2529907200/2'; SHAY='#971557632/1'; CINDFULL='Cind [Hungry Bandit]'
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/log.txt"; }
L1=$(i3 <<<'wc -l < /mnt/d/KenshiInst/5/RE_Kenshi/mods/Stobe/stobe.log' | tail -1)
say "stobe.log mark $L1"
# scene: pins off, teleports, onmesh wait, clean travel rows, aff 60, ctxpush
i3 <<EOT > "$OUT/scene.txt" 2>&1
stobe-auto pin "$CIND" off </dev/null | head -1; stobe-auto pin "$SHAY" off </dev/null | head -1
stobe-auto teleport "$SHAY" -49400 1660 3625 </dev/null | head -2
stobe-auto teleport "$CIND" -49422 1661 3643 </dev/null | head -2
stobe-auto select Shay </dev/null | head -1
EOT
cat "$OUT/scene.txt" | tee -a "$OUT/log.txt"
sleep 10
i3_sql "delete from eventlog where type='travel_agreement'" >> "$OUT/log.txt" 2>&1
i3w <<<"php /mnt/c/KenshiTestRuns/imm26-5090-i5/haff-i5.php \"$CINDFULL\" Shay 60 friend" | cut -c1-200 >> "$OUT/log.txt" 2>&1
i3 <<EOT >> "$OUT/log.txt" 2>&1
stobe-auto stobe_ctxpush "$CINDFULL" </dev/null | head -2
EOT
# spawn goats, t+2 chars check, senses gate
i3 <<EOT > "$OUT/spawn.txt" 2>&1
stobe-auto spawn "wild goats" Herbivore at -49405 1664 3645 count 3 size 0.2 </dev/null | head -3
sleep 2
stobe-auto chars 80 "[Herbivore]|!dead" </dev/null | head -6
EOT
cat "$OUT/spawn.txt" | cut -c1-300 | tee -a "$OUT/log.txt"
GOATS=$(grep -oE '#[0-9]+/[0-9]+' "$OUT/spawn.txt" | grep -v "^$CIND$" | sort -u | head -5)
[ -n "$GOATS" ] || { say "SCENE-BAD no goats found"; exit 3; }
SEES=0
for g in $GOATS; do
  s=$(i3 <<<"stobe-auto senses \"$CIND\" \"$g\" </dev/null | head -2"); echo "senses $g: $s" >> "$OUT/log.txt"
  echo "$s" | grep -qE 'sees=1' && SEES=$((SEES+1))
done
say "senses sees=1 count=$SEES of $(echo $GOATS | wc -w)"
[ $SEES -ge 1 ] || { say "SCENE-BAD cind sees no goat (see $OUT/log.txt)"; exit 3; }
say "SCENE-OK"
# t+5 say; accept as soon as the offer's first NPC sentence shows (<=5 s)
i3 <<'EOT' > "$OUT/offer.txt" 2>&1
L="/mnt/d/KenshiInst/5/RE_Kenshi/mods/Stobe/stobe.log"; n0=$(wc -l < "$L")
sleep 1
echo "SAY1 $(date +%T.%N)"
stobe-auto stobe_say "#2529907200/2" "Look at all these goats. Let's hunt for raw meat." </dev/null | head -2
end=$((SECONDS+45)); got=0
while [ $SECONDS -lt $end ]; do
  if tail -n +$((n0+1)) "$L" | grep -qE "ACTION_EXEC: SAY \[[^]]*\](.*)\(NPC\)"; then got=1; break; fi
  sleep 0.5
done
echo "OFFER_SEEN=$got $(date +%T.%N)"
tail -n +$((n0+1)) "$L" | grep -E "ACTION_EXEC: SAY|REJECTED|ACTIVITY_SIGHT_DIAG|ACTIVITY_PROPOSAL" | cut -c1-300 | head -6
if [ $got = 1 ]; then
  echo "SAY2 $(date +%T.%N)"
  stobe-auto stobe_say "#2529907200/2" "Yes, let's do it." </dev/null | head -2
fi
EOT
cat "$OUT/offer.txt" | tee -a "$OUT/log.txt"
echo "$L1" > "$OUT/logmark.txt"
