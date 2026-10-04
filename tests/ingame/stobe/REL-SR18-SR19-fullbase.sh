#!/usr/bin/env bash
# id: REL-SR18-SR19-fullbase
# covers: REL SR18 (KO'd outsider carried into a bed: safe-rescue credit) and SR19 (carried into a cage) on a second
#   base: the server's REL-p4-02/p4-03 scenarios run for the Full-Base squad (run-as.sh: Shay/Malzin -> PLAYER/MATE).
# usage: OUT=<dir> REL-SR18-SR19-fullbase.sh [p4-02|p4-03|all]   (run-batch.sh sets PLAYER/MATE/RESULT_LOG)
# fixture: kah-fullbase (Beaks/Avarek), already loaded by run-batch.sh; Capture=1 in StobeCustom.ini
# verify: social_relationship_inspect.php --expect-effect "<outsider>" "<MATE>" (same ranges as the .txt headers);
#   mode shadow for the run, off on exit.
PLAYER="${PLAYER:-Beaks}"; MATE="${MATE:-Avarek}"
OUT="${OUT:-/mnt/c/KenshiTestRuns/rel-sr18}"; mkdir -p "$OUT"
S=/var/www/html/StobeServer
I=$S/tests/social_relationship/ingame
H=$(cd "$(dirname "$0")" && pwd)
insp(){ (cd $S && sudo -u www-data php tools/social_relationship_inspect.php "$@"); }
res(){ echo "RESULT $*" | tee -a "${RESULT_LOG:-$OUT/results.txt}"; }
trap 'insp --set-mode off >/dev/null' EXIT
grep -q '^Capture=1' /mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/StobeCustom.ini \
  || { res "SR18-19 FAIL setup: Capture is not 1 in StobeCustom.ini"; exit 4; }
insp --set-mode shadow >/dev/null
# row <id> <file> <name-var> <lo> <hi>
row(){ local id=$1 b; b=$(basename "$2" .txt)
  bash "$H/run-as.sh" "$I/$2" "$PLAYER" "$MATE" --csv "$OUT/$b.csv" > "$OUT/$b.out" 2>&1
  local n; n=$(grep -o "$3=.*" "$OUT/$b.out" | head -1 | sed "s/$3=//")
  local sum; sum=$(grep -m1 '== .* passed' "$OUT/$b.out")
  [ -z "$n" ] && { res "$id FAIL scenario gave no $3 ($sum) log=$OUT/$b.out"; return; }
  sleep 20
  if insp --pair-effects --incidents 10 --check-shadow --expect-effect "$n" "$MATE" "$4" "$5" > "$OUT/$b.inspect.txt" 2>&1
  then res "$id PASS effect $n -> $MATE in [$4,$5] ($sum)"
  else res "$id FAIL effect $n -> $MATE not in [$4,$5] ($sum) log=$OUT/$b.inspect.txt"; fi
}
case "${1:-all}" in
  p4-02) row SR18 REL-p4-02-carry-to-bed.txt CNAME 8 35;;
  p4-03) row SR19 REL-p4-03-carry-to-cage.txt KNAME -40 -20;;
  all)   row SR18 REL-p4-02-carry-to-bed.txt CNAME 8 35; row SR19 REL-p4-03-carry-to-cage.txt KNAME -40 -20;;
esac
