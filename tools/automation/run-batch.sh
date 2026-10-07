#!/usr/bin/env bash
# run-batch.sh [--launch <save>] [--stop] <list-file> <out-dir> (WSL): runs a whole game batch from a short list
# file and leaves ONE file to read at the end, <out-dir>/SUMMARY.txt (RESULT lines, notes, batch start/end).
# Start it detached, then check in every 5 min with batch-health.sh <out-dir> (one line: OK / STALL / DONE):
#   wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -c 'setsid nohup bash /mnt/c/KenshiModding/tools/automation/run-batch.sh --launch auto-home --stop /mnt/c/KenshiTestRuns/m20/list.txt /mnt/c/KenshiTestRuns/m20/out >/dev/null 2>&1 </dev/null &'  (</dev/null: else the job dies when wsl.exe exits)
# Done when <out-dir>/DONE exists. Then: cat SUMMARY.txt; for a FAIL open only its excerpt (excerpt=...).
#
# List file: one test per line, "name | save | player | mate | timeout-seconds | command"; # comments, blank lines ok.
#   save:    a save name (loaded, then `select <player>`); "home" = auto-home + scenarios.sh fresh + select Shay;
#            kah-fullbase also runs fullbase-guard.sh after the load; "-" = keep the current world (no load)
#   command: leading VAR=value words are exported (e.g. GROW=1); then a script and its arguments:
#            *.sh  -> bash <script> (relative paths are under tests/ingame/stobe)
#            *.txt -> stobe-auto run <file> --csv <out>/<name>.csv (run-as.sh <file> <player> <mate> for other squads)
#            {OUT} in the command becomes <out-dir>
#   e.g.  21-fullbase | kah-fullbase | Beaks | Avarek | 1500 | STOBE-21-paylater-breach.sh
#         C25         | home         | Shay  | Malzin | 1800 | STOBE-C25-renamed-surrender.sh
#         A8-grow     | kah-fullbase | Beaks | Avarek | 3000 | GROW=1 STOBE-A8-bread-chain-fullbase.sh
# Every test runs with PLAYER, MATE and RESULT_LOG=<out>/<name>.txt set. Its RESULT lines go to SUMMARY.txt; a
# test with no RESULT line gets one built from its VERDICT lines, the `== N passed, M failed` line or its exit code.
# Every FAIL gets an excerpt (batch-excerpts.sh). If the game stops answering or Kenshi died, it is relaunched on the
# next row's save (at most RECOVER=2 times, NOTE line); after that the rest of the batch is skipped.
# Memory: before every row the Windows commit headroom is checked; below MIN_COMMIT_GB (default 3) Kenshi is
# restarted first (NOTE line). m22: Kenshi crashed on a NULL texture allocation with the commit charge at its limit.
set -u
A=/mnt/c/KenshiModding/tools/automation; T=/mnt/c/KenshiModding/tests/ingame/stobe
CTL='C:\KenshiModding\tools\automation\kenshi-ctl.ps1'
LAUNCH=""; STOP=0; RESUME=0
while [ $# -gt 0 ]; do case "$1" in --launch) LAUNCH="$2"; shift 2 ;; --stop) STOP=1; shift ;; --resume) RESUME=1; shift ;; *) break ;; esac; done
L="${1:?usage: run-batch.sh [--launch <save>] [--stop] [--resume] <list-file> <out-dir>}"; O="${2:?out-dir}"
mkdir -p "$O"; rm -f "$O/DONE"
exec >>"$O/batch.log" 2>&1
S="$O/SUMMARY.txt"; R="$O/ranges.tsv"
# same order as LOGS in batch-excerpts.sh
LOGPATHS="/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log /mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log /mnt/d/Steam/steamapps/common/Kenshi/mods/AutomationHarness/harness.log /var/www/html/StobeServer/log/stobeserver.log /var/www/html/StobeServer/log/php_error.log /mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_goals.log"
STOBELOG=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log

say() { echo "$*" | tee -a "$S"; }
offsets() { local p; for p in $LOGPATHS; do stat -c %s "$p" 2>/dev/null || echo 0; done | paste -sd'\t'; }
world() { stobe-auto wait-world "${1:-300}" >/dev/null 2>&1; }
# timeout: the WSL powershell proxy can hang after a launch (pipe held by Kenshi, m23); launch output lines
# are printed before it hangs, so killing it after 420 s loses nothing
ctl() { timeout 420 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTL" "$@" </dev/null | tr -d '\r'; }
# launch <save>: the proxy often never exits after a launch (m32: 3 of 5 launches sat the full 420 s although
# the game was in the world in 10 s) and its output arrives only when it exits: run it in the background, wait
# for its exit or the harness log written by THIS launch (kenshi-ctl deletes the old one) to show the autoload,
# kill the stuck proxy, then wait for the world
HLOG=/mnt/d/Steam/steamapps/common/Kenshi/mods/AutomationHarness/harness.log
launch() {
  local t0 i; t0=$(date +%s)
  ctl launch -Save "$1" > "$O/launch.out" 2>&1 &
  for i in $(seq 1 140); do
    kill -0 $! 2>/dev/null || break
    [ -f "$HLOG" ] && [ "$(stat -c %Y "$HLOG")" -ge "$t0" ] && grep -a -q "KAH: autoload $1" "$HLOG" && { sleep 5; break; }
    sleep 3
  done
  pkill -f "kenshi-ctl.ps1 launch" 2>/dev/null; wait 2>/dev/null
  tail -3 "$O/launch.out"
}
reload() {   # reload <save> <player>; 1 = the game didn't come back
  stobe-auto load "$1" >/dev/null 2>&1; sleep 12
  world 300 || { sleep 30; world 300 || return 1; }
  sleep 10; stobe-auto select "$2" >/dev/null 2>&1; return 0
}
memline() {  # "<free-commit-GB> <kenshi-private-GB>" (kenshi "-" when not running)
  powershell.exe -NoProfile -Command '$o=Get-CimInstance Win32_OperatingSystem; $k=Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Select-Object -First 1; "{0:N1} {1}" -f ($o.FreeVirtualMemory/1MB), $(if ($k) { "{0:N1}" -f ($k.PrivateMemorySize64/1GB) } else { "-" })' </dev/null 2>/dev/null | tr -d '
,' | tail -1
}
kenshi_up() { tasklist.exe /FI "IMAGENAME eq kenshi_x64.exe" /NH </dev/null 2>/dev/null | grep -qi kenshi_x64; }
relaunch() { # relaunch <save> <why>: (re)start Kenshi on <save> ("home"/"-" = auto-home); 1 = it didn't come back
  local s="$1"; case "$s" in home|-) s=auto-home ;; esac
  recovered=$((recovered + 1)); say "NOTE relaunch $recovered/$RECOVER on $s: $2"
  ctl stop >/dev/null 2>&1; stobe-say on >/dev/null 2>&1
  launch "$s" | tail -1; world 900
}
prepare() {  # prepare <save> <player> <mate>
  case "$1" in
    -) return 0 ;;
    home) reload auto-home Shay || return 1
          bash "$A/scenarios.sh" fresh >/dev/null 2>&1 </dev/null; stobe-auto select Shay >/dev/null 2>&1 ;;
    *) reload "$1" "$2" || return 1
       [ "$1" = kah-fullbase ] && PLAYER="$2" MATE="$3" bash "$T/fullbase-guard.sh" >/dev/null 2>&1 </dev/null ;;
  esac
  return 0
}

D="$O/done.txt"   # names of the tests that ran to the end (any result); --resume skips them
if [ "$RESUME" = 1 ]; then say "BATCH RESUME $(date '+%F %H:%M') list=$L done=$(wc -l <"$D" 2>/dev/null || echo 0)"
else : > "$S"; : > "$R"; : > "$D"; say "BATCH START $(date '+%F %H:%M') list=$L"; fi
if [ -n "$LAUNCH" ]; then
  stobe-say on >/dev/null 2>&1
  launch "$LAUNCH"
  world 900 || { say "BATCH ABORTED: game did not reach the world after launch ($LAUNCH)"; touch "$O/DONE"; exit 1; }
fi
pass=0; fail=0; dead=0; recovered=0; RECOVER=${RECOVER:-2}; MIN_COMMIT_GB=${MIN_COMMIT_GB:-3}
while IFS= read -r line <&3 || [ -n "$line" ]; do   # list on fd 3: Windows tools (powershell, tasklist) eat stdin
  line="${line%%$'\r'}"; case "$line" in ''|'#'*) continue ;; esac
  IFS='|' read -r name save player mate to cmd <<<"$line"
  t() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }
  name=$(t "$name"); save=$(t "$save"); player=$(t "$player"); mate=$(t "$mate"); to=$(t "$to"); cmd=$(t "$cmd")
  cmd="${cmd//\{OUT\}/$O}"; out="$O/$name.txt"
  if [ "$RESUME" = 1 ] && grep -qxF "$name" "$D" 2>/dev/null; then echo "$(date +%H:%M) $name: ran before, skipped (--resume)"; continue; fi
  read -r freec kpriv <<<"$(memline)"
  echo "$(date +%H:%M) $name: commit free ${freec:-?} GB, kenshi private ${kpriv:-?} GB"
  if [ "$dead" = 0 ] && [ "${kpriv:-x}" = - ]; then dead=1; say "NOTE Kenshi is not running before $name"; fi
  if [ "$dead" = 1 ] && [ "$recovered" -lt "$RECOVER" ]; then
    if relaunch "$save" "game dead before $name (commit free ${freec:-?} GB)"; then dead=0; else say "NOTE relaunch failed"; fi
  elif [ "$dead" = 0 ] && [ -n "${freec:-}" ] && [ "$recovered" -lt "$RECOVER" ] && awk -v f="$freec" -v m="$MIN_COMMIT_GB" 'BEGIN{exit !(f+0 < m+0)}'; then
    relaunch "$save" "commit free $freec GB < $MIN_COMMIT_GB GB (kenshi private $kpriv GB)" || { say "NOTE relaunch failed"; dead=1; }
  fi
  if [ "$dead" = 1 ]; then say "RESULT $name FAIL skipped: game not responding"; fail=$((fail + 1)); continue; fi
  echo "$(date +%H:%M) $name: prepare $save"
  if ! prepare "$save" "$player" "$mate"; then
    say "RESULT $name FAIL game not responding after loading $save (rest of the batch skipped)"
    fail=$((fail + 1)); dead=1; continue
  fi
  # split the command: VAR=value words, then the script and its arguments
  read -r -a words <<<"$cmd"; envs=(); i=0
  while [ $i -lt ${#words[@]} ] && [[ "${words[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do envs+=("${words[$i]}"); i=$((i + 1)); done
  script="${words[$i]:-}"; args=("${words[@]:$((i + 1))}")
  case "$script" in /*) ;; *) [ -e "$T/$script" ] && script="$T/$script" ;; esac
  case "$script" in
    *.sh) run=(bash "$script" "${args[@]}") ;;
    *.txt) if [ "$player" = Shay ] && [ "$mate" = Malzin ]; then run=(stobe-auto run "$script" --csv "$O/$name.csv" "${args[@]}")
           else run=(bash "$T/run-as.sh" "$script" "$player" "$mate" --csv "$O/$name.csv" "${args[@]}"); fi ;;
    *) run=("$script" "${args[@]}") ;;
  esac
  before=$(offsets); sl=$(stat -c %s "$STOBELOG" 2>/dev/null || echo 0)
  # m41: fullbase-guard only calms raiders once after the load; raids that arrive later in a long row (gate-90
  # farming: Hill Marauders pulled Beaks off the farm) need the lib's raid_guard sweep for the whole row.
  # The lib's EXIT trap pauses the game, so the guard subshell clears it.
  rg=""
  if [ "$save" = kah-fullbase ] && [ "${NO_RAID_GUARD:-0}" != 1 ]; then
    ( export PLAYER="$player" MATE="$mate"; . "$T/stobe-fight-lib.sh"; trap - EXIT
      trap 'raid_guard_stop; exit 0' TERM; raid_guard_start; while :; do sleep 5 & wait $!; done )       >/dev/null 2>>"$O/$name.raids" </dev/null &
    rg=$!
  fi
  echo "$(date +%H:%M) $name: run ${run[*]}"
  env PLAYER="$player" MATE="$mate" RESULT_LOG="$out" "${envs[@]}" timeout "$to" "${run[@]}" >"$out" 2>&1 </dev/null
  rc=$?
  [ -n "$rg" ] && { kill "$rg" 2>/dev/null; wait "$rg" 2>/dev/null; }
  stobe-auto speed 0 >/dev/null 2>&1
  printf '%s\t%s\t' "$name" "$save" >>"$R"; paste <(echo "$before" | tr '\t' '\n') <(offsets | tr '\t' '\n') | paste -sd'\t' >>"$R"
  # result lines: the test's own RESULT lines, else built from VERDICT / scenario summary / exit code
  res=$(grep -a '^RESULT ' "$out")
  if [ -z "$res" ]; then
    if [ $rc = 124 ]; then res="RESULT $name FAIL timed out after ${to}s"
    elif v=$(grep -a '^VERDICT' "$out") && [ -n "$v" ]; then
      res=$(while IFS= read -r l; do r="${l#VERDICT }"; row="${r%%:*}"; txt="${r#*: }"
              case "$txt" in PASS*) echo "RESULT $row PASS ${txt#PASS }" ;; *) echo "RESULT $row FAIL $txt" ;; esac
            done <<<"$v")
    elif s=$(grep -a -oE '== [0-9]+ passed, [0-9]+ failed.*' "$out") && [ -n "$s" ]; then
      # m22: also mid-line (run-pg.sh prints "<file> rc=0 == N passed, 0 failed"); any file with failures = FAIL
      bad=$(grep -v -E '== [0-9]+ passed, 0 failed' <<<"$s" | head -1)
      if [ -z "$bad" ]; then res="RESULT $name PASS $(tail -1 <<<"$s")"; else res="RESULT $name FAIL $bad"; fi
    else res="RESULT $name FAIL no RESULT/VERDICT line (exit $rc): $(tail -1 "$out" | cut -c1-150)"; fi
  fi
  # Partial row successes never hide a killed/timed-out wrapper.
  if [ $rc -ne 0 ] && ! grep -q ' FAIL' <<<"$res"; then
    res="$res
RESULT $name FAIL wrapper did not complete (exit $rc)"
  fi
  res=$(cut -c1-300 <<<"$res")
  if grep -q ' FAIL' <<<"$res"; then
    ex=$(bash "$A/batch-excerpts.sh" "$O" "$name" 2>/dev/null)
    res=$(sed "/ FAIL/{/ log=/!s|\$| out=$out|;s|\$|${ex:+ excerpt=$ex}|}" <<<"$res")
  fi
  echo "$res" | tee -a "$S"; echo "$name" >>"$D"
  pass=$((pass + $(grep -c ' PASS' <<<"$res"))); fail=$((fail + $(grep -c ' FAIL' <<<"$res")))
  # combat/knockout/death toward the squad while the test ran: a note (fight tests cause it on purpose)
  hit=$(tail -c +"$((sl + 1))" "$STOBELOG" 2>/dev/null | grep -a -E "\[EVENT\] (combat[^]]*-> ($player|$mate) \(|knockout: ($player|$mate) |death: ($player|$mate) )" | head -2 | cut -c1-160 | paste -sd';')
  [ -n "$hit" ] && say "NOTE $name: combat/KO toward the squad: $hit"
  # m37: a crashed/killed Kenshi = dead now, no 4.5 min of waits on a game that is gone (the next row relaunches)
  if kenshi_up; then
    world 120 || { sleep 30; world 120 || { say "NOTE game not responding after $name (rest of the batch skipped)"; dead=1; }; }
  else dead=1; fi
done 3<"$L"
# m37: skip `ctl stop` (up to 420 s) when Kenshi is already gone
[ "$STOP" = 1 ] && if kenshi_up; then ctl stop | tail -2; else echo "Kenshi not running, no stop needed"; fi
say "BATCH END $(date '+%F %H:%M') pass=$pass fail=$fail"
touch "$O/DONE"
