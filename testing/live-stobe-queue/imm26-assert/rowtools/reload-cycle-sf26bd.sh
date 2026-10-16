#!/usr/bin/env bash
# reload-cycle-sf26bd.sh <lane> [save-name] [near|far]   (imm26-sf26bd) = `ROW_NPC=Malzin reload-cycle.sh` + a check that regroup.txt names Malzin.
#   reload-cycle.sh itself is unchanged; its default ROW_NPC is Cind (rowdefs.sh:6), so a bare run re-placed CIND after the load and Malzin stayed at her saved spot (imm26-inv26, row 26-d).
#   Prints reload-cycle's line, then ONE verdict line:  RELOAD-CYCLE-SF26BD <lane> PASS|FAIL|SETUP-FAIL <detail>   exit 0 / 2.
#   Override the NPC with ROW_NPC=<name> (the check then looks for that name).
SC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE="${1:-}"; [ -n "$LANE" ] || { echo "usage: reload-cycle-sf26bd.sh <lane> [save-name] [near|far]" >&2; exit 2; }
export ROW_NPC="${ROW_NPC:-Malzin}"; base="${ROW_NPC%% \[*}"
out=$(bash "$SC_HERE/reload-cycle.sh" "$@"); rc=$?; echo "$out"
last=$(echo "$out" | grep -a '^RELOAD-CYCLE ' | tail -1)
[ $rc = 0 ] || { echo "RELOAD-CYCLE-SF26BD $LANE FAIL reload-cycle.sh failed: $(echo "$last" | cut -c1-200)"; exit 2; }
ev=$(echo "$last" | sed -nE 's/.*evidence=([^] ]+)\].*/\1/p' | head -1)
echo "$last" | grep -qF " npc=$base" || { echo "RELOAD-CYCLE-SF26BD $LANE SETUP-FAIL test artefact: re-placed NPC is not $base ($(echo "$last" | grep -o 'npc=[^ ]*' | head -1)), see imm26-inv26"; exit 2; }
if [ -s "$ev/regroup.txt" ]; then
  grep -aq "^teleported: $base " "$ev/regroup.txt" || { echo "RELOAD-CYCLE-SF26BD $LANE SETUP-FAIL test artefact: regroup.txt does not name $base (see $ev/regroup.txt), see imm26-inv26"; exit 2; }
  echo "RELOAD-CYCLE-SF26BD $LANE PASS regroup.txt names $base"; exit 0
fi
echo "RELOAD-CYCLE-SF26BD $LANE PASS $base needed no regroup (already within range)"; exit 0
