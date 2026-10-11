#!/bin/bash
# dryrun.sh [--rig 5090|4080] [--out DIR] [--only NAME] <list-file>          (WSL, root; seconds per row, no game)
# dryrun.sh [--rig 5090|4080] [--out DIR] --row "<name> | <save> | <player> | <mate> | <timeout> | <command>"
# Runs every row of a run-batch.sh list (same line format) against a FAKE game: each row in its own throw-away sandbox
# (tools/automation/dryrun/sandbox.sh: overlay root + C:, fake Kenshi dir, pid namespace; nothing real is touched)
# with stub stobe-auto/kah.py, stobe-say, ffmpeg(.exe), powershell.exe (kenshi-ctl, display-keeper, 4080 ctl/itrun),
# quser/tasklist, python lab tools, wslpath/cygpath, and a virtual clock (sleep/date) so a 5-minute take runs in seconds.
# Prints one line per row:  DRYRUN <row> PASS|FAIL|SKIP <reason> (...) log=<dir>   and a last DRYRUN-SUMMARY line;
# exit 1 if any row FAILs. What fails a row: tools/automation/dryrun/lib/analyze.py header (unknown harness commands /
# bad args, shell errors, missing files, RESULT line missing / duplicated / FAIL, no recording call, labels out of order or
# outside the recording, chatter on / cursor not parked while recording, POSIX path to a Windows exe, unquoted paths).
# --rig 4080 (or a RIG=4080 word in the row's command) emulates the 4080: Git Bash paths (/c/..., no /mnt), no wslpath,
# Windows python, native ffmpeg that ignores 'q' on a fifo, rows run like C:\KAH\itrun.ps1 (fresh login shell +
# rig-env.sh). DRYRUN_NOREC=1 in a row (or "# dryrun: norec" in its script) = a row that legitimately records nothing.
# Rows running Stobe wrappers (tests/ingame/stobe, *.txt scenarios) get static checks only (SKIP + bash -n).
# run-batch.sh calls this before every batch and refuses a list that fails (override: --no-dryrun "<reason>").
# --fixture night|combat|<file.json>: replay a world that broke real takes (dryrun/fixtures/*.json: game at 22 h; bandit
# group + "X is attacking!" popup at the spot); a row must fix it in its preflight or stop with a setup FAIL before filming.
# swing-ko: a melee swing knocks the neutral out and a KO character cannot be pinned (op-swa4); no-melee: Malzin carries
# only a crossbow (op-comb2).
# Self-test (replayed 2026-10-10 bugs must FAIL, current scripts must PASS): tools/automation/dryrun/selftest.sh
set -u
H=/mnt/c/KenshiModding/tools/automation; D=$H/dryrun
RIG=5090; OUT=""; ONLY=""; ROW=""; FIX=""
while [ $# -gt 0 ]; do case "$1" in
  --rig) RIG=$2; shift 2 ;; --fixture) FIX=$2; shift 2 ;; --out) OUT=$2; shift 2 ;; --only) ONLY=$2; shift 2 ;; --row) ROW=$2; shift 2 ;; *) break ;; esac; done
L=${1:-}
[ -n "$L$ROW" ] || { sed -n '2,24p' "$0"; exit 2; }
if [ -n "$FIX" ]; then
  [ -f "$FIX" ] || FIX=$D/fixtures/$FIX.json
  [ -f "$FIX" ] || { echo "DRYRUN-SUMMARY FAIL fixture $FIX missing (dryrun/fixtures/*.json)"; exit 2; }
  export DR_FIXTURE_JSON=$FIX
fi
[ "$(id -u)" = 0 ] || { echo "DRYRUN-SUMMARY FAIL dryrun.sh needs root (wsl.exe -u root)"; exit 2; }
C=/root/.cache/kah-dryrun; mkdir -p "$C/canned"
if [ ! -s "$C/canned/frame.png" ] || [ ! -s "$C/canned/take.mp4" ] || [ ! -s "$C/canned/frame-night.png" ]; then
  /usr/bin/ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=0x14161e:s=1600x900" -frames:v 1 "$C/canned/frame-night.png"
  /usr/bin/ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=0x4e7283:s=1600x900" -frames:v 1 "$C/canned/frame.png"
  /usr/bin/ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc=s=1600x900:r=10:d=2" -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$C/canned/take.mp4"
fi
# fast sleep/date (lib/drclock.c); falls back to the python fakeexe ones if no C compiler
if [ ! -x "$C/drclock" ] || [ "$D/lib/drclock.c" -nt "$C/drclock" ]; then
  gcc -O2 -o "$C/drclock.$$" "$D/lib/drclock.c" 2>/dev/null && mv -f "$C/drclock.$$" "$C/drclock" || rm -f "$C/drclock.$$"; fi
python3 "$D/lib/gen_spec.py" "$C/spec.tsv" >/dev/null || { echo "DRYRUN-SUMMARY FAIL command spec generation failed"; exit 2; }
ls /mnt/c/Users/Shay/AppData/Local/kenshi/save > "$C/saves.txt" 2>/dev/null
[ -n "$OUT" ] || OUT=/mnt/c/KenshiTestRuns/dryrun/$(basename "${L:-row}" .list | tr -c 'A-Za-z0-9_.\n-' _)-$(date +%m%d-%H%M%S)
mkdir -p "$OUT"
# keep the newest 8 dry-run dirs
ls -1dt /mnt/c/KenshiTestRuns/dryrun/*/ 2>/dev/null | tail -n +9 | xargs -r rm -rf
t() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }
# row_split <command>: the row's words as a shell would split them (quotes group a value with spaces: X="a b"), with no
# expansion and no execution (rows are not run by a shell). Rejects (return 1, reason in ROWERR) shell operators and
# expansions (; & | backtick $ ( ) < > backslash), a word starting with # and unbalanced quotes: a multi-step row goes in a .sh script.
row_split() { ROWERR=""; WORDS=(); local re='[;&|`$()<>\]' f=$- r
  [[ $1 =~ $re ]] && { ROWERR='shell operator/expansion in the command (one of ; & | ` $ ( ) < > \): rows are not run by a shell, put a multi-step row in a .sh script'; return 1; }
  [[ " $1" =~ [[:space:]]# ]] && { ROWERR="a word starts with # in the command (would be dropped as a comment)"; return 1; }
  set -f; eval "WORDS=($1)" 2>/dev/null; r=$?; [[ $f == *f* ]] || set +f
  [ $r = 0 ] || { ROWERR="unbalanced quotes in the command"; WORDS=(); return 1; }; }
pass=0; fail=0; skip=0
one() {
  local line="$1" name save player mate to cmd rig norec dir script
  IFS='|' read -r name save player mate to cmd <<<"$line"
  name=$(t "$name"); save=$(t "$save"); player=$(t "$player"); mate=$(t "$mate"); to=$(t "$to"); cmd=$(t "$cmd")
  [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && return 0
  rig=$RIG; [[ " $cmd " =~ [[:space:]]RIG=4080[[:space:]] ]] && rig=4080
  norec=""; [[ " $cmd " =~ [[:space:]]DRYRUN_NOREC=1[[:space:]] ]] && norec=--norec
  local sbx=/mnt/c/KenshiTestRuns/dryrun-sbx/$name; [ "$rig" = 4080 ] && sbx=/c/KenshiTestRuns/dryrun-sbx/$name
  cmd="${cmd//\{OUT\}/$sbx}"
  # {CR} = POSIX root of C: on the rig (rig-runner.ps1 queue lists): /mnt/c on the 5090, /c on the 4080
  if [ "$rig" = 4080 ]; then cmd="${cmd//\{CR\}//c}"; else cmd="${cmd//\{CR\}//mnt/c}"; fi
  dir=$OUT/$name; rm -rf "$dir"; mkdir -p "$dir"
  # same split as run-batch.sh (quotes ok, shell operators refused): a row run-batch would refuse FAILs here
  row_split "$cmd" || { echo "DRYRUN $name FAIL list: $ROWERR log=$dir"; fail=$((fail+1)); return; }
  # the script = first word that isn't VAR=val or a launcher (bash/sh/env/nice/timeout + its number): "bash x.sh" -> x.sh
  script=$(for w in "${WORDS[@]}"; do [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue; case "$w" in bash|sh|env|nice|timeout|-n|[0-9]*) continue;; esac; echo "$w"; break; done)
  case "$script" in /*) ;; *) [ -e "/mnt/c/KenshiModding/tests/ingame/stobe/$script" ] && script=/mnt/c/KenshiModding/tests/ingame/stobe/$script ;; esac
  local real=${script/#\/c\//\/mnt\/c\/}
  [ -f "$real" ] && grep -q '^# *dryrun: *norec' "$real" && norec=--norec
  case "$real" in
    */tests/ingame/stobe/*|*.txt)
      if [ ! -e "$real" ]; then echo "DRYRUN $name FAIL script $script missing log=$dir"; fail=$((fail+1)); return; fi
      if [ "${real##*.}" = sh ] && ! e=$(bash -n "$real" 2>&1); then echo "DRYRUN $name FAIL bash -n: ${e:0:150} log=$dir"; fail=$((fail+1)); return; fi
      echo "DRYRUN $name SKIP Stobe row: static checks only (exists, bash -n ok) log=$dir"; skip=$((skip+1)); return ;;
  esac
  [ "$rig" = 4080 ] && [ -z "${FETCHED:-}" ] && { FETCHED=1; bash "$D/fetch4080.sh" >&2; }
  unshare --mount --pid --fork --propagation private bash "$D/sandbox.sh" "$rig" "$dir" "$name" "$save" "$player" "$mate" "${DR_ROW_TIMEOUT:-240}" "$cmd" > "$dir/sandbox.txt" 2>&1
  local v; v=$(python3 "$D/lib/analyze.py" "$dir" "$name" "$rig" "$cmd" $norec)
  grep -q '^DRYRUN .* FAIL sandbox' "$dir/sandbox.txt" && v=$(grep -m1 '^DRYRUN' "$dir/sandbox.txt")
  echo "$v"
  case "$v" in "DRYRUN $name PASS"*) pass=$((pass+1)) ;; *) fail=$((fail+1)) ;; esac
}
if [ -n "$ROW" ]; then one "$ROW"
else
  [ -f "$L" ] || { echo "DRYRUN-SUMMARY FAIL list $L missing"; exit 2; }
  # "# nodryrun: <row>[/<row>,...] <reason>" (rig-runner.ps1 leaves those rows out): SKIP with the reason
  declare -A NODRY=()
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*#[[:space:]]*nodryrun[[:space:]]*:[[:space:]]*([^[:space:]]+)[[:space:]]*(.*)$ ]] || continue
    for n in $(tr '/,' '  ' <<<"${BASH_REMATCH[1]%:}"); do NODRY[$n]=${BASH_REMATCH[2]:-no reason given}; done
  done < <(tr -d '\r' < "$L")
  # rows run in parallel (each has its own sandbox; DR_JOBS, default 4), verdicts printed in list order
  VD=$OUT/.verdicts; rm -rf "$VD"; mkdir -p "$VD"; k=0
  grep -q 'RIG=4080' "$L" || [ "$RIG" = 4080 ] && { FETCHED=1; bash "$D/fetch4080.sh" >&2; }
  while IFS= read -r line <&3 || [ -n "$line" ]; do
    line="${line%%$'\r'}"; case "$line" in ''|'#'*) continue ;; esac
    k=$((k+1)); n=$(t "${line%%|*}")
    if [ -n "${NODRY[$n]:-}" ]; then echo "DRYRUN $n SKIP nodryrun: ${NODRY[$n]}" > "$VD/$k"; continue; fi
    while [ "$(jobs -rp | wc -l)" -ge "${DR_JOBS:-4}" ]; do wait -n; done
    ( one "$line" > "$VD/$k" ) &
  done 3<"$L"
  wait
  for i in $(seq 1 $k); do v=$(cat "$VD/$i" 2>/dev/null); [ -n "$v" ] || continue; echo "$v"
    # verdict = the 3rd word ("DRYRUN <row> FAIL ... RESULT take PASS ..." matched the old "DRYRUN * PASS*" glob: a FAIL
    # row counted as pass, 2026-10-10 td-t6)
    case "$(cut -d' ' -f3 <<<"$v")" in PASS) pass=$((pass+1)) ;; SKIP) skip=$((skip+1)) ;; *) fail=$((fail+1)) ;; esac; done
  rm -rf "$VD"
fi
W=""; [ $((pass + fail)) = 0 ] && { W=" WARN=0-rows-checked"; echo "DRYRUN-WARN 0 rows checked (every row skipped: nodryrun / Stobe static / --only): this list is NOT dry-run"; }
echo "DRYRUN-SUMMARY pass=$pass fail=$fail skip=$skip rig=$RIG${FIX:+ fixture=$(basename "$FIX" .json)} out=$OUT$W"
[ "$fail" = 0 ]
