#!/usr/bin/env bash
# id: STOBE-16-bench-shortfall-fullbase
# covers: STOBE 16 with completion on real power: "<mate>, make 2 Junkbows" (Hinge crafted at the Arrow Making
#         Bench, Junkbow at the Crossbow Crafting Bench); bench queues grow only by what's missing, COMPLETE 2/2
# fixture: Testing-Save-Full-Base (copy kah-fullbase); squad Beaks + Avarek
# reset: fresh load of the copy
# needs: KenshiFP E64B1BD5+, Stobe EF62563B+, harness 12F5CE0B+
# usage: [PLAYER=Beaks] [MATE=Avarek] [OUT=<dir>] STOBE-16-bench-shortfall-fullbase.sh
# How: runs STOBE-16-bench-shortfall.txt through run-as.sh with the squad names and --real-power (the base's own
#   power for benches the base has). Missing crossbow/arrow benches are built and get the supply cheat (a built
#   bench is outside the base grid); an Arrow Making Bench the base has replaces the scenario's `build`.
# verify: the .txt criteria (Arrow queue <= 1, Crossbow queue <= 2, queued_root=2, subs Hinge=1, `Hinge used 1`)
#   PLUS completion: `WORK_GOAL complete ... item=Junkbow qty=2` and Junkbows in `inv <mate>`; no `power wait`.
set -u
bash "$(dirname "$0")/fullbase-guard.sh" 16-fullbase || exit $?  # m24: SETUP FAIL when the squad is not protected/awake
D="$(cd "$(dirname "$0")" && pwd)"
export PLAYER="${PLAYER:-Beaks}" MATE="${MATE:-Avarek}"; OUT="${OUT:-/tmp}"
mkdir -p "$OUT"  # m22: OUT=<batch>/bench16 did not exist (FileNotFoundError on the scenario copy)
# m23: setup checks first (Full-Base lists Avarek first in the squad: the selection is checked via @selected)
. "$D/stobe-fight-lib.sh"
preflight 16-fullbase save=kah-fullbase
# m23: a Band of Bones raid hit Avarek mid-goal (m22 batch E): knock out raiders near the squad every 30 s while it runs
( while sleep 30; do calm_raiders 1500 >/dev/null 2>&1; done ) & CALM=$!
trap 'kill $CALM 2>/dev/null; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
b=$(stobe-auto benches 200 | tr '|' '\n')  # m18: same radius as the scenario checks (a bench 300-400 m away made it skip the build)
extra=()
# m16 next: Full-Base has no Crossbow Crafting Bench (in this load order only the crossbow/arrow and the robotics
# limb benches form a bench -> bench chain). A missing bench is built next to <mate> (sids 96183/96184-Newwworld.mod;
# never the Biofuel Distillery) and gets the supply cheat, since a built bench is outside the base grid. Benches the
# base already has run on its real power.
if echo "$b" | grep -q "Crossbow Crafting Bench"; then
  echo "base has a Crossbow Crafting Bench: using it (real power)"
else
  stobe-auto build 96183-Newwworld.mod near "$MATE" dist 18 | cut -c1-160
  extra+=(--keep-supply "Crossbow Crafting Bench")
  echo "built a Crossbow Crafting Bench (supply cheat for it)"
fi
if echo "$b" | grep -q "Arrow Making Bench"; then
  extra+=(--drop '^build 96184-Newwworld.mod')
  echo "base has an Arrow Making Bench: using it (real power)"
else
  extra+=(--keep-supply "Arrow Making Bench")
  echo "no Arrow Making Bench in the base: the scenario builds one (supply cheat for it)"
fi
# m19: the Full-Base mate already wears a backpack, so a given Large Backpack lands in her main inventory and fills it
# (Iron Plates haul blocked: "her pack is full"): skip the backpack steps here.
extra+=(--drop "Large Backpack")
bash "$D/run-as.sh" "$D/STOBE-16-bench-shortfall.txt" "$PLAYER" "$MATE" --real-power "${extra[@]}" --csv "$OUT/STOBE-16-fullbase.csv"
