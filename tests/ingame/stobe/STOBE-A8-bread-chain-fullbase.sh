#!/usr/bin/env bash
# id: STOBE-A8-bread-chain-fullbase
# covers: STOBE A8 on the base's own power (no supply cheat): "<mate>, make 2 bread" -> COMPLETE
# fixture: Testing-Save-Full-Base (copy kah-fullbase); squad Beaks + Avarek
# reset: fresh load of the copy
# needs: KenshiFP E64B1BD5+, Stobe EF62563B+, harness 12F5CE0B+
# usage: [PLAYER=Beaks] [MATE=Avarek] [WELL=<well name part>] [SPEED=50] STOBE-A8-bread-chain-fullbase.sh
# verify: as STOBE-A8-bread-chain.sh, plus: it stops with SETUP FAIL when `building "Grain Silo"` has no real power
#   (out_of_power must be 0 without any `power ... supply`); at 50x the goal-watch check pauses on any combat
#   against / knockout of the squad (VERDICT ALERT, exit 3: reload the fixture, don't continue).
# Never build a Biofuel Distillery in this mod setup (crash).
export RAID_CALM=1 PLAYER="${PLAYER:-Beaks}" MATE="${MATE:-Avarek}" REAL_POWER=1 SPEED="${SPEED:-50}" WELL="${WELL:-Well}"
D="$(cd "$(dirname "$0")" && pwd)"
bash "$D/fullbase-guard.sh" A8 || exit $?  # m24: SETUP FAIL when the squad is not protected/awake
. "$D/stobe-fight-lib.sh"
# m24: a Bele'coz raid reached Beaks ~1 min into the 50x run (m22 batch G ALERT); the in-loop calm (every 10 polls)
# was too slow at 50x. Like 16-fullbase: knock out raiders near the squad every 15 s while it runs (the alert is unchanged).
( while sleep 15; do calm_raiders 1500 >/dev/null 2>&1; done ) & CALM=$!
trap 'kill $CALM 2>/dev/null; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
bash "$D/STOBE-A8-bread-chain.sh"
exit $?
