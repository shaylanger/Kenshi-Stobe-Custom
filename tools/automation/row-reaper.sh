#!/usr/bin/env bash
# row-reaper.sh: kill every process left of a batch row (5090: WSL; 4080: Git Bash, also over ssh)
#   row-reaper.sh kill <row-dir>        every process whose command line names <row-dir> (<out>/<row>, boundary-aware:
#                                       <out>/M never matches <out>/M08), any kind (bash forks, timeout, python checks)
#   row-reaper.sh sweep <current-out>   leftover game drivers of EARLIER rows/batches: a test script (bash .../tests/ingame/*.sh,
#                                       run-as.sh, kah.py/stobe-auto run) whose command line names a KenshiTestRuns/<batch>/<row>
#                                       with <batch> != the current out dir and no <batch>/.gamedone.<row> (= a row that never
#                                       finished its game part: killed step, killed batch) in a run-batch.sh out dir (batch.pid;
#                                       dry runs / predry / agent dirs never qualify); one NOTE line per kill (REAPER_DRY=1: report only)
#   row-reaper.sh selftest              fake orphans under a private root (never touches real rows); RESULT ROW-REAPER-SELFTEST
# After a kill (unless REAPER_NEUTRAL=0) the game gets a neutral `fp_combat input 0 0 0` + `fp_combat physical`.
# Why (killtree 2026-10-11): the runner's kill-step `taskkill /T /F` of a 4080 row's timeout.exe left fp-manual-hits.sh
# (59-hits-r09b HIT) running 42 min: Git Bash/MSYS processes often have a dead Windows parent (fork/exec stubs), so the
# Windows tree walk misses them. The orphan kept sending `fp_combat input 1 ...` into three later batches (rg-04 M08:
# "SETUP FAIL foreign harness client"). Matching on the row's out dir in the command line finds every fork of the script.
set -u
ROOT=${REAPER_ROOT:-KenshiTestRuns}
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
iswsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# pid<TAB>command line (backslashes -> /), every process naming $ROOT except this tool / the listing itself
procs() {
  if iswsl || ! command -v powershell.exe >/dev/null 2>&1; then
    ps -eo pid=,args= 2>/dev/null | sed -E 's/^ *([0-9]+) +/\1\t/'
  else
    local ps1='Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and [string]$_.CommandLine -like "*@ROOT@*" -and $_.Name -notmatch "^(powershell|pwsh|cmd|conhost|ssh|sshd|WMIC)\.exe$" } | ForEach-Object { [string]$_.ProcessId + [char]9 + ([string]$_.CommandLine -replace "[\r\n]"," ") }'
    timeout 60 powershell.exe -NoProfile -NonInteractive -Command "${ps1//@ROOT@/$ROOT}" </dev/null 2>/dev/null | tr -d '\r'
  fi | tr '\\' '/' | grep -F "$ROOT/" | grep -vE 'row-reaper\.sh|Get-CimInstance' |
    grep -vE $'^[0-9]+\t("[^"]*/|[^ "]*/)?(grep|egrep|fgrep|tail|sed|awk)(\\.exe)?"? '   # pipelines/watchers that only name a path
}
killpids() {   # pids...; WSL: TERM (EXIT traps run), 3 s, then KILL; Git Bash: taskkill (Windows pids, any session)
  [ $# -gt 0 ] && [ "${REAPER_DRY:-0}" != 1 ] || return 0   # REAPER_DRY=1: report only
  if iswsl || ! command -v taskkill.exe >/dev/null 2>&1; then
    kill -TERM "$@" 2>/dev/null; local i; for i in 1 2 3 4 5 6; do kill -0 "$@" 2>/dev/null || break; sleep 0.5; done
    kill -KILL "$@" 2>/dev/null
  else local p; for p in "$@"; do taskkill.exe //F //T //PID "$p" </dev/null >/dev/null 2>&1; done; fi
  return 0
}
neutral() {
  [ "${REAPER_NEUTRAL:-1}" = 0 ] || [ "${REAPER_DRY:-0}" = 1 ] && return 0
  command -v stobe-auto >/dev/null 2>&1 || return 0
  local r; r=$(timeout 15 stobe-auto fp_combat input 0 0 0 </dev/null 2>&1 | tr -d '\r' | head -1)
  timeout 15 stobe-auto fp_combat physical </dev/null >/dev/null 2>&1
  echo "NEUTRAL fp_combat input 0 0 0 + physical: ${r:0:80}"
}
key() { local p=${1//\\//}; p=${p%/}; case "$p" in *"$ROOT/"*) echo "$ROOT/${p#*"$ROOT/"}" ;; *) echo "$p" ;; esac; }

do_kill() {   # row-dir
  local k; k=$(key "$1"); [ -n "$k" ] && [[ "$k" == "$ROOT/"*/* ]] || { echo "REAP refused: not a <$ROOT>/<batch>/<row> dir: $1"; return 1; }
  local pids=() line pid cl rest c
  while IFS=$'\t' read -r pid cl; do
    [ -n "$pid" ] && [ "$pid" != $$ ] || continue
    rest=$cl
    while [[ "$rest" == *"$k"* ]]; do   # boundary: the char after the row dir must end the path component
      rest=${rest#*"$k"}; c=${rest:0:1}
      case "$c" in ''|' '|'/'|'"'|"'") pids+=("$pid"); echo "REAPED $pid $k ${cl:0:140}"; break ;; esac
    done
  done < <(procs)
  killpids "${pids[@]}"
  [ ${#pids[@]} -gt 0 ] && neutral
  return 0
}

do_sweep() {   # current out dir
  local cur; cur=$(key "$1"); cur=${cur#"$ROOT/"}; cur=${cur%%/*}
  local base=${1//\\//}; base=${base%/}; base=${base%"/$cur"*}   # the rig's .../KenshiTestRuns
  local pids=() pid cl refs r b w
  while IFS=$'\t' read -r pid cl; do
    [ -n "$pid" ] && [ "$pid" != $$ ] || continue
    [[ "$cl" =~ /tests/ingame/[^\ ]*\.sh|run-as\.sh|kah\.py\"?\ run\ |stobe-auto\ run\  ]] || continue
    [[ "$cl" =~ run-batch\.sh|dialog-guard\.sh|rig-runner-probe\.sh|batch-excerpts\.sh|batch-health\.sh ]] && continue
    refs=$(grep -oE "$ROOT/[^/ \"']+/[A-Za-z0-9_+-]+([/ \"']|\$)" <<<"$cl" | sed -E "s#^$ROOT/##; s#[/ \"']\$##" | sort -u)
    [ -n "$refs" ] || continue
    w=""
    for r in $refs; do b=${r%%/*}
      [ "$b" = "$cur" ] && { w=""; break; }               # the current batch's own rows: never here
      [ -e "$base/$b/.gamedone.${r#*/}" ] && { w=""; break; }   # finished its game part: background analysis, keep
      [ -e "$base/$b/batch.pid" ] || continue   # not a run-batch.sh out dir (dry runs, runner/predry, agent work dirs): never
      # a batch that is still running (no DONE, its run-batch.sh alive) owns its rows: never (multi-instance 2026-10-11: lane
      # 5090b's sweep killed lane A's live fp-fists.sh row fist5090w/fq3)
      [ -e "$base/$b/DONE" ] || { read -r bp_ _ < "$base/$b/batch.pid" 2>/dev/null; [ -n "${bp_:-}" ] && kill -0 "$bp_" 2>/dev/null && { w=""; break; }; }
      w=$r
    done
    [ -n "$w" ] || continue
    pids+=("$pid"); echo "NOTE leftover process of $w $([ "${REAPER_DRY:-0}" = 1 ] && echo "found (dry run, not killed)" || echo killed) before the next row (pid $pid: ${cl:0:140})"
  done < <(procs)
  killpids "${pids[@]}"
  [ ${#pids[@]} -gt 0 ] && neutral
  return 0
}

do_selftest() {
  local R="kahreap$$" T bad="" n=0
  T=$(mktemp -d); mkdir -p "$T/$R/old" "$T/$R/cur" "$T/$R/laneb" "$T/tests/ingame"
  printf '#!/bin/bash\ntrap "exit 143" TERM\n( while :; do sleep 1; done ) &\nwhile :; do sleep 1; done\n' > "$T/tests/ingame/holder.sh"
  start() { nohup bash "$T/tests/ingame/holder.sh" "$1" x >/dev/null 2>&1 </dev/null & echo $!; }
  alive() { ROOT=$R procs | grep -qF "$T/$R/$1 x"; }
  : > "$T/$R/old/.gamedone.R2"; : > "$T/$R/old/batch.pid"; mkdir -p "$T/$R/predry"
  start "$T/$R/predry/R4" >/dev/null   # no batch.pid: a dry run, never swept
  # laneb = another lane's batch still running (batch.pid names a live process, no DONE): its rows are never swept
  local lb; lb=$(start "$T/$R/laneb/R5"); echo "$lb 0" > "$T/$R/laneb/batch.pid"
  start "$T/$R/old/R1" >/dev/null; start "$T/$R/old/R2" >/dev/null; start "$T/$R/cur/R3" >/dev/null; start "$T/$R/cur/R30" >/dev/null
  sleep 2
  chk() { n=$((n + 1)); if eval "$2"; then echo "SELFTEST $1 ok"; else echo "SELFTEST $1 WRONG"; bad="$bad $1"; fi; }
  chk started 'alive old/R1 && alive old/R2 && alive cur/R3 && alive cur/R30'
  local o; o=$(REAPER_ROOT=$R REAPER_NEUTRAL=0 bash "$SELF" sweep "$T/$R/cur"); sleep 1
  chk sweep-kills-orphan '! alive old/R1 && grep -q "leftover process of old/R1" <<<"$o"'
  chk sweep-keeps-gamedone 'alive old/R2'
  chk sweep-keeps-current 'alive cur/R3 && alive cur/R30'
  chk sweep-keeps-nonbatch 'alive predry/R4'
  chk sweep-keeps-live-other-lane 'alive laneb/R5'
  o=$(REAPER_ROOT=$R REAPER_NEUTRAL=0 bash "$SELF" kill "$T/$R/cur/R3"); sleep 1
  chk kill-row '! alive cur/R3 && grep -q REAPED <<<"$o"'
  chk kill-boundary 'alive cur/R30 && alive old/R2'
  REAPER_ROOT=$R REAPER_NEUTRAL=0 bash "$SELF" kill "$T/$R/cur/R30" >/dev/null; REAPER_ROOT=$R REAPER_NEUTRAL=0 bash "$SELF" kill "$T/$R/old/R2" >/dev/null
  REAPER_ROOT=$R REAPER_NEUTRAL=0 bash "$SELF" kill "$T/$R/predry/R4" >/dev/null; REAPER_ROOT=$R REAPER_NEUTRAL=0 bash "$SELF" kill "$T/$R/laneb/R5" >/dev/null; sleep 1
  chk cleanup '! alive cur/R30 && ! alive old/R2 && ! alive predry/R4'
  rm -rf "$T"
  echo "RESULT ROW-REAPER-SELFTEST $([ -z "$bad" ] && echo PASS || echo FAIL) cases=$n bad=[${bad# }]"
  [ -z "$bad" ]
}

case "${1:-}" in
  kill) do_kill "${2:?row dir}" ;;
  sweep) do_sweep "${2:?current out dir}" ;;
  selftest) do_selftest ;;
  list) procs ;;   # debug: what kill/sweep see (REAPER_ROOT=... to narrow)
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
