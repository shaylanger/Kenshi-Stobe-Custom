#!/usr/bin/env bash
# id: STOBE-16-bench-shortfall-fullbase
# covers: STOBE 16 with completion on real power: "<mate>, make 2 Junkbows" (Hinge crafted at the Arrow Making
#         Bench, Junkbow at the Crossbow Crafting Bench); bench queues grow only by what's missing, COMPLETE 2/2
# fixture: Testing-Save-Full-Base (copy kah-fullbase); squad Beaks + Avarek
# reset: fresh load of the copy
# needs: KenshiFP E64B1BD5+, Stobe EF62563B+, harness 12F5CE0B+
# usage: [PLAYER=Beaks] [MATE=Avarek] [OUT=<dir>] STOBE-16-bench-shortfall-fullbase.sh
# How: runs STOBE-16-bench-shortfall.txt through run-as.sh with the squad names and --real-power (the base's own
#   power; the `out_of_power=0` steps must pass without supply). If the base has an Arrow Making Bench, the
#   scenario's `build` is dropped; if not, it builds one and keeps the supply cheat for that one building only
#   (a built bench is outside the base grid).
# verify: the .txt criteria (Arrow queue <= 1, Crossbow queue <= 2, queued_root=2, subs Hinge=1, `Hinge used 1`)
#   PLUS completion: `WORK_GOAL complete ... item=Junkbow qty=2` and Junkbows in `inv <mate>`; no `power wait`.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
PLAYER="${PLAYER:-Beaks}"; MATE="${MATE:-Avarek}"; OUT="${OUT:-/tmp}"
b=$(stobe-auto benches 400 | tr '|' '\n')
echo "$b" | grep -q "Crossbow Crafting Bench" || { echo "VERDICT 16-fullbase: SETUP FAIL no Crossbow Crafting Bench within 400"; exit 1; }
if echo "$b" | grep -q "Arrow Making Bench"; then
  extra=(--drop '^build 96184-Newwworld.mod')
  echo "base has an Arrow Making Bench: using it (real power)"
else
  extra=(--keep-supply "Arrow Making Bench")
  echo "no Arrow Making Bench in the base: the scenario builds one (supply cheat for it only)"
fi
bash "$D/run-as.sh" "$D/STOBE-16-bench-shortfall.txt" "$PLAYER" "$MATE" --real-power "${extra[@]}" --csv "$OUT/STOBE-16-fullbase.csv"
