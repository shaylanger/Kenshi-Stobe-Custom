#!/usr/bin/env bash
# id: REL-SR18-SR19-fullbase
# covers: REL SR18 (KO'd outsider carried into a bed: safe-rescue credit) and SR19 (carried into a cage) on a second
#   base: the server's REL-p4-02/p4-03 scenarios run for the Full-Base squad (run-as.sh: Shay/Malzin -> PLAYER/MATE).
# usage: OUT=<dir> REL-SR18-SR19-fullbase.sh [p4-02|p4-03|all]   (run-batch.sh sets PLAYER/MATE/RESULT_LOG)
# fixture: kah-fullbase (Beaks/Avarek), already loaded by run-batch.sh; Capture=1 in StobeCustom.ini
# setup (m22 batch M: both rows failed on setup, not product): the save has the mate lying in the base's only Bed
#   (buildings: Bed dist=0.0 from her), and the spawned bandit was ~1900 from her when KO'd, so LIFT_PERSON never
#   reached him. Before each row a setup scenario gets the mate up, out of the bed (teleport leaves the bed), healed,
#   and checks a free Bed / a Prisoner Cage nearby; in the row, run-as --after puts the KO'd outsider 4 from the mate
#   (teleport ... ~ moved=1) and logs where he was before the KO. A failed setup step = "FAIL setup: <reason>".
# verify: social_relationship_inspect.php --expect-effect "<outsider>" "<MATE>" (same ranges as the .txt headers);
#   mode shadow for the run, off on exit.
PLAYER="${PLAYER:-Beaks}"; MATE="${MATE:-Avarek}"
OUT="${OUT:-/mnt/c/KenshiTestRuns/rel-sr18}"; mkdir -p "$OUT"
S=/var/www/html/StobeServer
I=$S/tests/social_relationship/ingame
H=$(cd "$(dirname "$0")" && pwd)
insp(){ (cd $S && sudo -u www-data php tools/social_relationship_inspect.php "$@"); }
# run-batch.sh collects RESULT lines from stdout (RESULT_LOG is that same file): print once
res(){ if [ -n "${RESULT_LOG:-}" ]; then echo "RESULT $*"; else echo "RESULT $*" | tee -a "$OUT/results.txt"; fi; }
trap 'insp --set-mode off >/dev/null' EXIT
grep -q '^Capture=1' /mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/StobeCustom.ini \
  || { res "SR18-19 FAIL setup: Capture is not 1 in StobeCustom.ini"; exit 4; }
insp --set-mode shadow >/dev/null
# setup <b> <place regex line>: mate awake, out of the bed, healthy; the target furniture exists and is not under her
setup(){ local f="$OUT/$1.setup.txt"
  cat > "$f" <<EOF
@wait-world
speed 0
select $PLAYER
wake $MATE
speed 1
@sleep 3
speed 0
health $MATE 100
@until 20 teleport $MATE building Bed dist 30 ~ moved=1
health $MATE 100
where $MATE ~ $MATE #\d+/\d+ \[[^]]*\] pos=[-0-9.,]+ dist=[0-9.]+$
$2
EOF
  stobe-auto run "$f" --csv "$OUT/$1.setup.csv" > "$OUT/$1.setup.out" 2>&1
  grep -m1 '^FAIL' "$OUT/$1.setup.out" | cut -c1-160
}
# row <id> <file> <name-var> <lo> <hi> <setup check line>
row(){ local id=$1 b v=${3%NAME}; b=$(basename "$2" .txt)
  # m22 batch O SR19: KO'd raiders lying in the base woke after SR18 and knocked the mate out (teleport moved=0):
  # protect + calm raiders + both awake before every row's setup
  local g; g=$(PLAYER="$PLAYER" MATE="$MATE" bash "$H/fullbase-guard.sh" "$id" 2>&1) \
    || { res "$id FAIL setup: fullbase-guard: $(echo "$g" | grep -m1 -i -E 'fail' | cut -c1-140) log=$OUT/$b.guard.txt"
         echo "$g" > "$OUT/$b.guard.txt"; return; }
  echo "$g" > "$OUT/$b.guard.txt"
  local bad; bad=$(setup "$b" "$6")
  [ -n "$bad" ] && { res "$id FAIL setup: $MATE not ready / no free furniture: $bad log=$OUT/$b.setup.out"; return; }
  bash "$H/run-as.sh" "$I/$2" "$PLAYER" "$MATE" \
    --after "^@set ${3} where " "where \${$v}" \
    --after "^ko [\$][{]$v[}] " "@until 20 teleport \${$v} $MATE dist 4 ~ moved=1" \
    --csv "$OUT/$b.csv" > "$OUT/$b.out" 2>&1
  local n; n=$(grep -o "$3=.*" "$OUT/$b.out" | head -1 | sed "s/$3=//")
  local sum; sum=$(grep -m1 '== .* passed' "$OUT/$b.out")
  [ -z "$n" ] && { res "$id FAIL scenario gave no $3 ($sum) log=$OUT/$b.out"; return; }
  grep -qE "^FAIL +[0-9]+ @until 20 teleport" "$OUT/$b.out" \
    && { res "$id FAIL setup: KO'd $n could not be put next to $MATE (teleport moved=0) log=$OUT/$b.out"; return; }
  sleep 20
  if insp --pair-effects --incidents 10 --check-shadow --expect-effect "$n" "$MATE" "$4" "$5" > "$OUT/$b.inspect.txt" 2>&1
  then res "$id PASS effect $n -> $MATE in [$4,$5] ($sum)"
  else res "$id FAIL effect $n -> $MATE not in [$4,$5] ($sum) log=$OUT/$b.inspect.txt"; fi
}
BED="buildings 200 Bed near $MATE ~ \| Bed dist=([1-9]|0\.[1-9])"
CAGE="buildings 400 Cage near $MATE ~ Cage[A-Za-z ]* dist="
case "${1:-all}" in
  p4-02) row SR18 REL-p4-02-carry-to-bed.txt CNAME 8 35 "$BED";;
  p4-03) row SR19 REL-p4-03-carry-to-cage.txt KNAME -40 -20 "$CAGE";;
  all)   row SR18 REL-p4-02-carry-to-bed.txt CNAME 8 35 "$BED"; row SR19 REL-p4-03-carry-to-cage.txt KNAME -40 -20 "$CAGE";;
esac
