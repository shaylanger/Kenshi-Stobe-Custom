#!/bin/bash
# diag-weapon-give.sh <out dir>   (5090 WSL or 4080 Git Bash via rig-env.sh; Kenshi in the world, harness up)
# Diagnosis for the harness weapon factory refusal (2026-10-10: `give` of every weapon -> "the game could not create <w>
# (maker Homemade, model Rusted Junk)", wm5090-2 + wm4080-diag2). Tries non-weapon items (baseline), base weapons with the
# default maker/model, and base weapons with explicit base-game makers/models; prints every reply + one RESULT line
# (PASS = at least one weapon was created: names the combination that works). No game state is judged beyond the replies.
OUT=$1; [ -n "$OUT" ] || { echo "usage: diag-weapon-give.sh <out dir>"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-weapon-matrix}
RE=${CR:-/mnt/c}/KenshiModding/tools/automation/rig-env.sh; [ -f "$RE" ] && . "$RE"
mkdir -p "$OUT" && cd "$OUT" || { echo "RESULT WEAPONGIVE-DIAG FAIL setup: out dir"; exit 2; }
A(){ stobe-auto "$@" </dev/null 2>&1; }
SH=${SH:-Axima}
A inv $SH | grep -q name || { echo "RESULT WEAPONGIVE-DIAG FAIL setup: no $SH"; exit 2; }
ok=""; n=0
try(){ local r; r=$(A give $SH "$@" | head -1); n=$((n + 1)); echo "TRY give $SH $* -> $r" | tee -a diag.txt
  echo "$r" | grep -q " got [1-9]" && [ "$W" = 1 ] && ok="$ok [$*]"; }
W=0; try "Dried Meat" 1; try "Bandage" 1
W=1
for w in "Katana" "Iron Club" "Nodachi" "Wakizashi" "Desert Sabre"; do try "$w" 1; done
for mk in "Edgewalkers" "Cross" "Skeleton Smiths" "Catun" "Unknown Smith"; do
  for md in "Mid-Grade Salvage" "Refitted Blade" "Catun No.1" "Edge Type 1"; do try "Katana" 1 maker "$mk" model "$md"; done
done
A inv $SH | tr ',' '\n' | grep -i '"name"' | head -20 > inv.txt
if [ -n "$ok" ]; then echo "RESULT WEAPONGIVE-DIAG PASS tries=$n created:$ok (log $OUT/diag.txt)"
else echo "RESULT WEAPONGIVE-DIAG FAIL tries=$n no weapon created by any maker/model (log $OUT/diag.txt)"; fi
