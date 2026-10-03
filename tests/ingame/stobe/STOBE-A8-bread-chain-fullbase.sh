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
export PLAYER="${PLAYER:-Beaks}" MATE="${MATE:-Avarek}" REAL_POWER=1 SPEED="${SPEED:-50}" WELL="${WELL:-Well}"
exec bash "$(dirname "$0")/STOBE-A8-bread-chain.sh"
