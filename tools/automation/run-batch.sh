#!/usr/bin/env bash
# run-batch.sh [--launch <save>] [--stop] <list-file> <out-dir> (WSL): runs a whole game batch from a short list
# file and leaves ONE file to read at the end, <out-dir>/SUMMARY.txt (RESULT lines, notes, batch start/end).
# Start it detached, then check in every 5 min with batch-health.sh <out-dir> (one line: OK / STALL / DONE):
#   wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -c 'setsid nohup bash /mnt/c/KenshiModding/tools/automation/run-batch.sh --launch auto-home --stop /mnt/c/KenshiTestRuns/m20/list.txt /mnt/c/KenshiTestRuns/m20/out >/dev/null 2>&1 </dev/null &'  (</dev/null: else the job dies when wsl.exe exits)
# Done when <out-dir>/DONE exists. Then: cat SUMMARY.txt; for a FAIL open only its excerpt (excerpt=...).
# Row status = the 3rd word of its RESULT line: PASS, PASS-REC (pass with a recording warning, `rec-warn=<checks>` at the
# end: only sampler gaps / video length / sync lag failed, product checks passed; takecheck.py) or FAIL. BATCH END counts
# pass (incl. PASS-REC) / fail / recwarn.
#
# List file: one test per line, "name | save | player | mate | timeout-seconds | command"; # comments, blank lines ok.
#   save:    a save name (loaded, then `select <player>`); "home" = auto-home + scenarios.sh fresh + select Shay;
#            kah-fullbase also runs fullbase-guard.sh after the load; "-" = keep the current world (no load)
#   command: leading VAR=value words are exported (e.g. GROW=1; quotes group a value with spaces: SPOT="1 2 3"); then a
#            script and its arguments. Not run by a shell: ; & | ` $ ( ) < > backslash are refused (RESULT <row> FAIL list: ...;
#            dryrun.sh refuses them too): a multi-step row goes in a .sh script.
#            *.sh  -> bash <script> (relative paths are under tests/ingame/stobe)
#            *.txt -> stobe-auto run <file> --csv <out>/<name>.csv (run-as.sh <file> <player> <mate> for other squads)
#            {OUT} in the command becomes <out-dir> ({RIG} becomes the rig, RIG or 5090)
#   e.g.  21-fullbase | kah-fullbase | Beaks | Avarek | 1500 | STOBE-21-paylater-breach.sh
#         C25         | home         | Shay  | Malzin | 1800 | STOBE-C25-renamed-surrender.sh
#         A8-grow     | kah-fullbase | Beaks | Avarek | 3000 | GROW=1 STOBE-A8-bread-chain-fullbase.sh
# Every test runs with PLAYER, MATE and RESULT_LOG=<out>/<name>.txt set. Its RESULT lines go to SUMMARY.txt; a
# test with no RESULT line gets one built from its VERDICT lines, the `== N passed, M failed` line or its exit code.
# Every FAIL gets an excerpt (batch-excerpts.sh). If the game stops answering or Kenshi died, it is relaunched on the
# next row's save (at most RECOVER=2 times, NOTE line); after that the rest of the batch is skipped.
# Memory: before every row the Windows commit headroom is checked; below MIN_COMMIT_GB (default 3) Kenshi is
# restarted first (NOTE line). m22: Kenshi crashed on a NULL texture allocation with the commit charge at its limit.
# Dry-run gate (Speed plan 1, Shay 2026-10-10): before the game is touched the whole list runs through
# tools/automation/dryrun.sh (fake game, seconds per row; output <out>/dryrun.txt + <out>/dryrun/); any dry-run FAIL
# refuses the batch (one `RESULT <row> FAIL dryrun: ...` line per failing row + BATCH REFUSED, then DONE).
# --no-dryrun "<reason>" skips the gate (NOTE line with the reason): only for a dry-run bug, logged for take-dryrun.
# Rigs: runs on the 5090 (WSL) and on the 4080 (Git Bash, via C:\KAH\itrun.ps1; rig-env.sh paths, game control through
# C:\KAH\ctl.ps1 -Owner $KAH_OWNER). Relative scripts are looked up in tests/ingame/stobe, then components/KenshiFP/tests/ingame.
# The running row's `timeout` pid is in <out>/step.pid: rig-runner.ps1 kills a stuck step with it (row FAIL, batch goes on).
# rig-runner.ps1 runs a snapshot copy of this file from the out dir, so editing it never kills a running batch.
# Dialog guard (2026-10-10): before every row an open NPC conversation is closed (tools/automation/dialog-guard.sh check;
# still open = RESULT <row> FAIL setup: dialog <speaker>), during the row a watcher closes new ones (<out>/<row>.dialogs,
# NOTE line); DIALOG_GUARD=0 in a row's command turns both off.
# <out>/PREEMPT (rig-runner: a filler gives way to a real list): the batch stops at the next row boundary (BATCH PREEMPTED
# line + NOTE with the rows not run), then GAMEDONE / background analyses / BATCH END / DONE as usual.
# <out>/HOLD (rig-lane2.ps1 memory guard): the batch waits at the next row boundary while it exists (NOTE on hold + resume).
# Row env (setup-speed 2026-10-11): every row also gets KAH_ROW=<name> (take-preflight.sh names its setup-FAIL RESULT line
# after it) and RELAUNCH_FILE=<out>/.relaunch.<name>. A row that leaves a reason in that file (take-preflight.sh
# pf_combat_on: fp_combat on still refused = a latched native fault only a game restart clears; 40-rangedrows lost 15 rows
# to it) gets the game relaunched on the next row's save before that row (NOTE relaunch ...: row <name> asked ...; counts
# against RECOVER), instead of every later row failing the same way.
# TDR guard (2026-10-11 5090 BSOD; every GPU driver reset that day was on a crossbow frame; a TDR is a crash warning, never
# noise): after every row (and once after the launch) the rig's Windows System log is read for nvlddmkm/Display events
# 4101 or 153 since the last check. A hit = BATCH ABORTED ... TDR line, <out>/TDR (row, list, time, event), the game is
# stopped, the rest of the list is not run (NOTE TDR stop: not run: ...); on the 5090 it also writes
# C:\KenshiTestRuns\ALERT-5090-tdr.txt and stops the 5090 runner (rig-runner.ps1 -Stop -Rig 5090). rig-runner.ps1 reads
# <out>/TDR + the event log itself (4080 too) and stops that rig's loop. TDR_FAKE=<file> replaces the event log with
# "epoch|provider|id|message" lines (tests). Self-test: run-batch.sh --selftest (no game, no files; dryrun/selftest.sh runs it).
set -u
if grep -qi microsoft /proc/version 2>/dev/null; then CR=/mnt/c; else RIG=${RIG:-}; . /c/KenshiModding/tools/automation/rig-env.sh; fi   # the 4080 Git Bash mounts /mnt/c too
KD=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}
A=$CR/KenshiModding/tools/automation; T=$CR/KenshiModding/tests/ingame/stobe; KT=$CR/KenshiModding/components/KenshiFP/tests/ingame
CTL='C:\KenshiModding\tools\automation\kenshi-ctl.ps1'; CTLO=()
[ "${RIG:-5090}" = 4080 ] && { CTL='C:\KAH\ctl.ps1'; CTLO=(-Owner "${KAH_OWNER:-rig4080}" -Instance "${KAH_INSTANCE:-1}"); }   # -Instance: lane 4080b (C:\KenshiInst\<n>)
LAUNCH=""; STOP=0; RESUME=0; NODRY=""; REUSE=0
# --reuse (rig-runner, 2026-10-10 no relaunch gap): with --launch, a game that is already up and in the world loads <save>
# in place (stobe-auto load) instead of a stop + relaunch; launches as usual when Kenshi is not running / not answering
# TDR guard (see header). tdr_events <since-epoch>: "epoch|provider|id|message" of System-log events 4101/153 since then
tdr_events() {
  if [ -n "${TDR_FAKE:-}" ]; then cat "$TDR_FAKE" 2>/dev/null; return 0; fi
  timeout 60 powershell.exe -NoProfile -Command "\$s=[DateTimeOffset]::FromUnixTimeSeconds($1).LocalDateTime; Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,153; StartTime=\$s} -ErrorAction SilentlyContinue | ForEach-Object { '{0}|{1}|{2}|{3}' -f ([DateTimeOffset]\$_.TimeCreated).ToUnixTimeSeconds(), \$_.ProviderName, \$_.Id, (([string]\$_.Message -replace '\s+',' ') -replace '\|','/') }" </dev/null 2>/dev/null | tr -d '\r'
}
# tdr_filter <since-epoch>: only GPU driver resets (Display 4101 / nvlddmkm 4101|153; a disk's event 153 is not one)
tdr_filter() { awk -F'|' -v s="$1" '$1+0 >= s+0 && ($3 == 4101 || $3 == 153) && tolower($2) ~ /^(nvlddmkm|display)$/ { print substr($0, 1, 240) }'; }
# tdr_check <since-epoch>: 1 + TDR_HIT="<n> event(s), latest: <line>" on a hit, 0 = none
tdr_check() { local h; TDR_HIT=""; h=$(tdr_events "$1" | tdr_filter "$1"); [ -n "$h" ] || return 0
  TDR_HIT="$(wc -l <<<"$h" | tr -d ' ') event(s), latest: $(head -1 <<<"$h")"; return 1; }
# relaunch_req <file>: the reason a row left in its RELAUNCH_FILE (empty = none)
relaunch_req() { [ -s "$1" ] && head -1 "$1" | tr -d '\r' | cut -c1-200; return 0; }
if [ "${1:-}" = --selftest ]; then   # run-batch.sh --selftest: TDR filter/check + relaunch request on fixed cases
  st_bad=0; st_n=0; tf=$(mktemp); rq=$(mktemp)
  st() { st_n=$((st_n + 1)); if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; st_bad=$((st_bad + 1)); fi; }
  printf '%s\n' "1000|Display|4101|Display driver nvlddmkm stopped responding and has successfully recovered." \
    "1100|nvlddmkm|153|Error occurred on GPUID: 100" "1200|disk|153|The IO operation at logical block address 0x1 was retried." \
    "900|Display|4101|old reset before the row" "1300|Microsoft-Windows-Kernel-Power|4101|other provider" > "$tf"
  st "filter: Display 4101 + nvlddmkm 153 since 950, not disk 153 / older / other provider" "$(tdr_filter 950 <"$tf" | cut -d'|' -f1 | paste -sd,)" "1000,1100"
  st "filter: nothing after the last GPU event" "$(tdr_filter 1101 <"$tf" | wc -l | tr -d ' ')" "0"
  TDR_FAKE=$tf; tdr_check 950; st "check: hit returns 1" "$?" "1"
  st "check: TDR_HIT names count + first event" "${TDR_HIT%%|*}" "2 event(s), latest: 1000"
  tdr_check 1101; st "check: only a disk 153 later = no hit" "$?:$TDR_HIT" "0:"
  printf '' > "$tf"; tdr_check 0; st "check: empty log = no hit" "$?" "0"
  TDR_FAKE=/nonexistent/tdr; tdr_check 0; st "check: unreadable fake log = no hit (no false stop)" "$?" "0"
  unset TDR_FAKE
  : > "$rq"; st "relaunch_req: empty file = none" "$(relaunch_req "$rq")" ""
  st "relaunch_req: missing file = none" "$(relaunch_req /nonexistent/rq)" ""
  printf 'fp_combat on refused after 7 tries (native_ready=0 fault=4; latched)\r\nsecond\n' > "$rq"
  st "relaunch_req: first line, CR stripped" "$(relaunch_req "$rq")" "fp_combat on refused after 7 tries (native_ready=0 fault=4; latched)"
  rm -f "$tf" "$rq"
  # lanes (lane-5090c 2026-10-11): launch() kills only its own proxy tree, never another lane's launch by name
  st "launch: no pkill by name of kenshi-ctl.ps1" "$(grep -c '^[^#]*pkill -f .*kenshi-ctl' "$0")" "0"
  ( exec -a "kenshi-ctl.ps1 launch otherlane" sleep 30 ) & ol=$!
  ( sleep 30 | cat ) & lp=$!; sleep 0.3
  pkill -P $lp 2>/dev/null; kill $lp 2>/dev/null; wait $lp 2>/dev/null
  st "launch: own proxy tree killed, the other lane's launch alive" "$(kill -0 $lp 2>/dev/null && echo own-alive || echo own-gone):$(kill -0 $ol 2>/dev/null && echo other-alive || echo other-gone)" "own-gone:other-alive"
  kill $ol 2>/dev/null; wait $ol 2>/dev/null
  echo "RUNBATCH-SELFTEST $([ $st_bad = 0 ] && echo PASS || echo "FAIL $st_bad") $st_n cases"; exit $((st_bad > 0))
fi
while [ $# -gt 0 ]; do case "$1" in --launch) LAUNCH="$2"; shift 2 ;; --reuse) REUSE=1; shift ;; --stop) STOP=1; shift ;; --resume) RESUME=1; shift ;; --no-dryrun) NODRY="${2:?--no-dryrun needs a reason}"; shift 2 ;; *) break ;; esac; done
L="${1:?usage: run-batch.sh [--launch <save>] [--stop] [--resume] [--no-dryrun <reason>] <list-file> <out-dir>}"; O="${2:?out-dir}"
mkdir -p "$O"; rm -f "$O/DONE" "$O/GAMEDONE"
# Batch end: DONE + drop every inflight marker naming this out dir, so idle detection (rig5090-state.ps1) sees the
# slot free at once (Shay 2026-10-10: a marker left on a DONE batch kept the 5090 reading BUSY).
finish() { touch "$O/DONE"; local m oa; oa=$(cd "$O" && pwd); for m in $CR/KenshiTestRuns/inflight/*; do [ -f "$m" ] || continue
  case "$(head -1 "$m" | tr -d '\r' | sed 's:/*$::')" in "$O"|"$oa") rm -f "$m" ;; esac; done; }
exec >>"$O/batch.log" 2>&1
echo "$$ $(cat /proc/$$/winpid 2>/dev/null)" > "$O/batch.pid"   # rig-runner-probe.sh: is this batch still alive (4080: Windows pid)
S="$O/SUMMARY.txt"; R="$O/ranges.tsv"
# same order as LOGS in batch-excerpts.sh
LOGPATHS="$KD/RE_Kenshi/mods/Stobe/stobe.log $KD/KenshiFP.log $KD/mods/AutomationHarness/harness.log /var/www/html/StobeServer/log/stobeserver.log /var/www/html/StobeServer/log/php_error.log $KD/RE_Kenshi/mods/Stobe/stobe_goals.log"
STOBELOG=$KD/RE_Kenshi/mods/Stobe/stobe.log

say() { echo "$*" | tee -a "$S"; }
offsets() { local p; for p in $LOGPATHS; do stat -c %s "$p" 2>/dev/null || echo 0; done | paste -sd'\t'; }
# world <sec>: 0 once status says phase=world (0.5 s polls; stobe-auto wait-world polls every 2 s)
# fails at once while <out>/.noload exists (launch(): the harness autoload found no such save; m102 96-agree-rec sat 6 min
# on the main menu because instance 2 lacked kah-fpstudio)
world() { local end=$((SECONDS + ${1:-300})); while [ $SECONDS -lt $end ]; do [ -f "$O/.noload" ] && { echo "world: $(head -1 "$O/.noload")" >&2; return 1; }; timeout 15 stobe-auto status </dev/null 2>/dev/null | grep -q "phase=world" && return 0; sleep 0.5; done; return 1; }
# world_live <sec>: 0 = in the world, 1 = Kenshi up but not in the world after <sec>, 2 = Kenshi gone (checked every 20 s)
world_live() { local end=$((SECONDS + ${1:-120})); while [ $SECONDS -lt $end ]; do kenshi_up || return 2; world 20 && return 0; done; kenshi_up || return 2; return 1; }
# timeout: the WSL powershell proxy can hang after a launch (pipe held by Kenshi, m23); launch output lines
# are printed before it hangs, so killing it after 420 s loses nothing
ctl() { timeout 420 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTL" "$@" "${CTLO[@]}" </dev/null | tr -d '\r'; }
# launch <save>: the proxy often never exits after a launch (m32: 3 of 5 launches sat the full 420 s although
# the game was in the world in 10 s) and its output arrives only when it exits: run it in the background, wait
# for its exit or the harness log written by THIS launch (kenshi-ctl deletes the old one) to show the autoload,
# kill the stuck proxy, then wait for the world
HLOG=$KD/mods/AutomationHarness/harness.log
launch() {
  local t0 i lp; t0=$(date +%s); rm -f "$O/.noload"
  ctl launch -Save "$1" > "$O/launch.out" 2>&1 &
  lp=$!
  for i in $(seq 1 140); do
    kill -0 $! 2>/dev/null || break
    [ -f "$HLOG" ] && [ "$(stat -c %Y "$HLOG")" -ge "$t0" ] && grep -a -q "KAH: autoload $1" "$HLOG" && break
    sleep 1
  done
  # the autoload found no such save: say so now (world() fails at once) instead of waiting minutes on the main menu
  if [ -f "$HLOG" ] && [ "$(stat -c %Y "$HLOG")" -ge "$t0" ] && grep -a "KAH: autoload $1" "$HLOG" | tail -1 | grep -q 'no save named'; then
    echo "autoload $1 failed: no save named $1 in this install (copy it into its save folder)" > "$O/.noload"; say "NOTE $(date +%H:%M) launch: $(cat "$O/.noload")"; fi
  # fast launch (hotswap2 2026-10-11): no fixed sleeps; the save loads while the proxy finishes its foreground unlock +
  # re-place loop, then the proxy is killed once the world is in (or after 120 s) and postlaunch fits the window
  # window place + render fit while the save loads (hotswap2 2026-10-11: postlaunch after the world cost up to ~10 s when it
  # had to resize; the final postlaunch below then only verifies: ~1.5 s when the window is already right)
  local pp=""; [ "${RIG:-5090}" = 4080 ] || { timeout 120 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTL" postlaunch </dev/null 2>&1 | tr -d '\r' > "$O/launch.pre.out" & pp=$!; }
  kill -0 $lp 2>/dev/null && world 120
  [ -n "$pp" ] && { wait $pp 2>/dev/null; sed 's/^/early /' "$O/launch.pre.out" >> "$O/launch.out"; rm -f "$O/launch.pre.out"; }
  # only THIS launch's proxy (lanes 5090b/5090c run their own run-batch.sh in the same WSL: a pkill -f by name killed theirs too)
  pkill -P $lp 2>/dev/null; kill $lp 2>/dev/null; wait $lp 2>/dev/null
  # the killed proxy never ran kenshi-ctl's re-place + render fit (studio-fixture 2026-10-10: 798x413 on DISPLAY1): do it now
  [ "${RIG:-5090}" = 4080 ] || { timeout 180 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTL" postlaunch </dev/null 2>&1 | tr -d '\r' >> "$O/launch.out"; }
  tail -3 "$O/launch.out"
}
reload() {   # reload <save> <player>; 1 = the game didn't come back
  stobe-auto load "$1" >/dev/null 2>&1   # the harness reports phase=loading from the load reply on (g_loadPending)
  world 300 || { sleep 30; world 300 || return 1; }
  local i; for i in $(seq 1 20); do stobe-auto select "$2" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 0
}
memline() {  # "<free-commit-GB> <kenshi-private-GB>" (kenshi "-" when not running)
  powershell.exe -NoProfile -Command '$o=Get-CimInstance Win32_OperatingSystem; $i=[int]$env:KAH_INSTANCE; $k=Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { if ($i -ge 2) { $_.Path -like "*\KenshiInst\$i\*" } else { $_.Path -notlike "*\KenshiInst\*" } } | Select-Object -First 1;"{0:N1} {1}" -f ($o.FreeVirtualMemory/1MB), $(if ($k) { "{0:N1}" -f ($k.PrivateMemorySize64/1GB) } else { "-" })' </dev/null 2>/dev/null | tr -d '
,' | tail -1
}
# kenshi_pids (multi-instance 2026-10-11): kenshi_x64 PIDs of THIS install only: KAH_INSTANCE=n>=2 = D:\KenshiInst\<n>, else
# every install outside D:\KenshiInst (a second test game must not count as instance 1). wmic gives the exe path (0.2 s);
# no wmic answer (none running, or wmic missing/broken) = tasklist by name as before.
kenshi_pids() {
  local o; o=$(wmic.exe process where "name='kenshi_x64.exe'" get ExecutablePath,ProcessId </dev/null 2>/dev/null | tr -d '\r')
  if grep -q ExecutablePath <<<"$o"; then
    awk -v n="${KAH_INSTANCE:-1}" 'NR>1 && NF>=2 { p=tolower($0); m=(n+0>=2) ? index(p, "\\kenshiinst\\" n "\\")>0 : index(p, "\\kenshiinst\\")==0; if (m) print $NF }' <<<"$o"
  else tasklist.exe </dev/null 2>/dev/null | awk 'tolower($1)=="kenshi_x64.exe"{print $2}'; fi
}
kenshi_up() { [ -n "$(kenshi_pids)" ]; }
relaunch() { # relaunch <save> <why>: (re)start Kenshi on <save> ("home"/"-" = auto-home); 1 = it didn't come back
  local s="$1"; case "$s" in home|-) s=auto-home ;; esac
  recovered=$((recovered + 1)); say "NOTE relaunch $recovered/$RECOVER on $s: $2"
  ctl stop >/dev/null 2>&1; stobe-say on >/dev/null 2>&1
  launch "$s" | tail -1; world 900
}
TDR_SINCE=$(date +%s)   # TDR guard: events from the batch start on (launch included)
tdr_guard() {  # tdr_guard <row|launch>: 1 = GPU driver reset since the last check: batch stopped (header)
  local now; now=$(date +%s); tdr_check "$((TDR_SINCE - 5))" && { TDR_SINCE=$now; return 0; }
  local msg="TDR (GPU driver reset) on rig ${RIG:-5090} at/after $1 of $L: $TDR_HIT"
  say "BATCH ABORTED $(date '+%F %H:%M'): $msg (rest of the list not run, game stopped)"
  printf '%s\nrow=%s\nlist=%s\nout=%s\ntime=%s\n' "$msg" "$1" "$L" "$O" "$(date '+%F %H:%M:%S')" > "$O/TDR"
  PRE=TDR
  if [ "${RIG:-5090}" != 4080 ]; then
    { echo "ALERT 5090 $(date +%H:%M) $msg. Runner stopped; delete this file only once Shay cleared the cause."; cat "$O/TDR"; } > "$([ -n "${TDR_FAKE:-}" ] && echo "$O" || echo "$CR/KenshiTestRuns")/ALERT-5090-tdr.txt"   # fake: into the out dir
    [ -n "${TDR_FAKE:-}" ] || timeout 120 powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\rig-runner.ps1' -Stop -Rig 5090 </dev/null 2>&1 | tr -d '\r' | tail -1
  fi
  [ -n "${TDR_FAKE:-}" ] || { kenshi_up && ctl stop | tail -1; }
  return 1
}
# Load dedupe (speed-scout 2026-10-11, harness.log: every KenshiFP take row loaded twice, prepare kah-fpxbow then the
# script's pf_load kah-fpstudio, ~30 s/row; a list start loaded 3x). FRESH = "<save> <epoch>" of the load prepare just
# did; the row gets KAH_FRESH=$FRESH and take-preflight.sh pf_load uses that load instead of loading again (once, < 120 s);
# removed after every row (the row changed the world).
FRESH="$O/.fresh-load"; rm -f "$FRESH"
# load_target <save>: the save the row ends up on. A take script that calls pf_load loads PF_SAVE, else kah-fpstudio when
# installed, else kah-fpxbow (take-preflight.sh pf_load) -> prepare loads that one (rows on kah-fpxbow/kah-fpstudio only)
load_target() {
  local s="$1" w sc="" ps=""
  case "$s" in kah-fpxbow|kah-fpstudio) ;; *) echo "$s"; return ;; esac
  for w in "${WORDS[@]}"; do case "$w" in PF_SAVE=*) ps=${w#PF_SAVE=} ;; [A-Za-z_]*=*|bash|sh) ;; *) sc=$w; break ;; esac; done
  case "$sc" in /*) ;; *) [ -e "$KT/$sc" ] && sc="$KT/$sc" ;; esac
  # a wrapper that ends in `exec bash ".../<take>.sh"` (fp-s1pt30-confirm.sh -> fp-e6-strokes.sh): look at that script
  local nx; nx=$(grep -oE '^[[:space:]]*exec bash "?[^" ]*/[A-Za-z0-9_.-]+\.sh' "$sc" 2>/dev/null | head -1 | sed 's|.*/||')
  grep -qE '^[[:space:]]*pf_load([[:space:]]|$)' "$sc" 2>/dev/null || { [ -n "$nx" ] && grep -qE '^[[:space:]]*pf_load([[:space:]]|$)' "$KT/$nx" 2>/dev/null; } || { echo "$s"; return; }
  if [ -n "$ps" ]; then echo "$ps"; elif [ -d "$CR/Users/Shay/AppData/Local/kenshi/save/kah-fpstudio" ]; then echo kah-fpstudio; else echo kah-fpxbow; fi
}
prepare() {  # prepare <save> <player> <mate>
  case "$1" in
    -) return 0 ;;
    home) reload auto-home Shay || return 1
          bash "$A/scenarios.sh" fresh >/dev/null 2>&1 </dev/null; stobe-auto select Shay >/dev/null 2>&1 ;;
    *) local tg; tg=$(load_target "$1"); [ "$tg" != "$1" ] && echo "$(date +%H:%M) prepare: $tg instead of $1 (the row script's pf_load loads $tg; one load, not two)"
       if [ -f "$FRESH" ] && read -r fs ft < "$FRESH" && [ "$fs" = "$tg" ] && [ $(( $(date +%s) - ${ft:-0} )) -lt 120 ]; then
         echo "$(date +%H:%M) prepare: $tg was loaded $(( $(date +%s) - ft )) s ago by the batch start (no reload)"
         local i; for i in $(seq 1 20); do stobe-auto select "$2" >/dev/null 2>&1 && break; sleep 0.5; done
       else reload "$tg" "$2" || return 1; echo "$tg $(date +%s)" > "$FRESH"; fi
       [ "$1" = kah-fullbase ] && PLAYER="$2" MATE="$3" bash "$T/fullbase-guard.sh" >/dev/null 2>&1 </dev/null ;;
  esac
  return 0
}

D="$O/done.txt"   # names of the tests that ran to the end (any result); --resume skips them
if [ "$RESUME" = 1 ]; then say "BATCH RESUME $(date '+%F %H:%M') list=$L done=$(wc -l <"$D" 2>/dev/null || echo 0)"
else : > "$S"; : > "$R"; : > "$D"; : > "$O/rows.tsv"; say "BATCH START $(date '+%F %H:%M') list=$L"; fi
if [ -n "$NODRY" ]; then say "NOTE dryrun gate skipped (--no-dryrun): $NODRY"
else
  DRO=$(bash "$A/dryrun.sh" --out "$O/dryrun" "$L" 2>&1); DRC=$?
  printf '%s
' "$DRO" > "$O/dryrun.txt"
  say "$(printf '%s
' "$DRO" | grep '^DRYRUN-SUMMARY' | tail -1 | cut -c1-300)"
  if [ "$DRC" != 0 ]; then
    printf '%s
' "$DRO" | grep '^DRYRUN [^ ]* FAIL' | while IFS= read -r l; do n=$(awk '{print $2}' <<<"$l"); say "RESULT $n FAIL dryrun: $(cut -c1-400 <<<"${l#DRYRUN $n FAIL }")"; done
    say "BATCH REFUSED $(date '+%F %H:%M'): the list failed tools/automation/dryrun.sh ($O/dryrun.txt); fix the scripts and restart (a dry-run bug: --no-dryrun \"<reason>\")"
    finish; exit 1
  fi
fi
# LT = the save row 1 really starts on: its script's pf_load target (load_target) when row 1 is on -/kah-fpxbow/kah-fpstudio
# and the batch launches one of those two (speed-scout 2026-10-11: a launch on kah-fpxbow, then pf_load kah-fpstudio = 2 loads)
LT=$LAUNCH
case "$LAUNCH" in kah-fpxbow|kah-fpstudio)
  l1=$(grep -v "^[[:space:]]*\(#\|$\)" "$L" | head -1); s1=$(cut -d"|" -f2 <<<"$l1" | tr -d " \r")
  case "$s1" in -|kah-fpxbow|kah-fpstudio)
    read -ra WORDS <<<"$(cut -d"|" -f6- <<<"$l1" | tr -d '\r')"; t1=$(load_target kah-fpxbow)
    [ "$t1" != kah-fpxbow ] && [ "$t1" != "$LAUNCH" ] && { LT=$t1; say "NOTE launch save $LT instead of $LAUNCH (row 1's pf_load loads it; one load)"; } ;;
  esac ;;
esac
if [ -n "$LAUNCH" ] && [ "$REUSE" = 1 ] && kenshi_up && timeout 30 stobe-auto status </dev/null 2>/dev/null | grep -q "phase=world"; then
  p1=$(grep -v "^[[:space:]]*\(#\|$\)" "$L" | head -1 | cut -d"|" -f3 | tr -d " \r")
  say "NOTE reuse: Kenshi already up, loading $LT in place (no relaunch)"
  stobe-say on >/dev/null 2>&1
  s1=$(grep -v "^[[:space:]]*\(#\|$\)" "$L" | head -1 | cut -d"|" -f2 | tr -d " \r")
  if [ -n "$s1" ] && [ "$s1" != "-" ]; then say "NOTE reuse: the first row loads its own save ($s1): no extra in-place load of $LAUNCH"   # speed-scout: was 2-3 loads
  elif reload "$LT" "${p1:-Shay}"; then echo "$LT $(date +%s)" > "$FRESH"
  else say "NOTE reuse: in-place load failed, relaunching"; launch "$LAUNCH"; world 900 || { say "BATCH ABORTED: game did not reach the world after launch ($LAUNCH)"; finish; exit 1; }; fi
elif [ -n "$LAUNCH" ]; then
  stobe-say on >/dev/null 2>&1
  launch "$LT"
  world 900 || { say "BATCH ABORTED: game did not reach the world after launch ($LT)"; finish; exit 1; }
  echo "$LT $(date +%s)" > "$FRESH"
fi
# a window that never reached the Video Mode size keeps getting resized = a glitching screen (Shay 2026-10-11): stop, don't run rows on it
if [ -f "$O/launch.out" ] && grep -q "postlaunch FAIL" "$O/launch.out"; then
  say "BATCH ABORTED: game window not at the Video Mode size (postlaunch FAIL, see launch.out)"
  [ "${RIG:-5090}" = 4080 ] || powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTL" stop </dev/null >/dev/null 2>&1
  finish; exit 1
fi
PRE=""; NOTRUN=(); pass=0; fail=0; recwarn=0; dead=0; recovered=0; RECOVER=${RECOVER:-2}; MIN_COMMIT_GB=${MIN_COMMIT_GB:-3}; relreq=""; relrow=""
tdr_guard launch || true   # a reset during the launch/first load: no row runs (PRE=TDR)
# Recording and analysis split (Shay 2026-10-10: the 5090 game sat idle 5 min while a take's lab checks ran): a row script
# calls pf_game_done (take-preflight.sh: touches $GAME_DONE_FILE) once it no longer uses the game; the batch then goes on
# with the next row while that script finishes its analysis in the background (normal priority). Its RESULT lines are
# collected when it exits. <out>/GAMEDONE = every row is past its game part (Kenshi stopped with --stop; rig-runner may
# start the next batch); DONE only after every background analysis has ended.
declare -A ROWSEC=()   # row -> seconds it held the game (rows.tsv 3rd column)
PEND=()   # "pid|name|save|player|mate|out|timeout|stobe-log offset" of rows analysing in the background
row_result() {  # row_result <name> <save> <player> <mate> <out> <timeout> <rc> <stobe-log offset>
  local name=$1 save=$2 player=$3 mate=$4 out=$5 to=$6 rc=$7 sl=$8 res v s bad ex hit
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
  if [ $rc -ne 0 ] && ! grep -qE '^RESULT [^ ]+ FAIL' <<<"$res"; then
    res="$res
RESULT $name FAIL wrapper did not complete (exit $rc)"
  fi
  # long evidence is cut at 300 chars, but a trailing rec-warn=<x> (PASS-REC) survives the cut
  res=$(awk '{ w=""; if (match($0, / rec-warn=[^ ]+$/)) { w=substr($0, RSTART); $0=substr($0, 1, RSTART-1) } print substr($0, 1, 300) w }' <<<"$res")
  if grep -qE '^RESULT [^ ]+ FAIL' <<<"$res"; then
    ex=$(bash "$A/batch-excerpts.sh" "$O" "$name" 2>/dev/null)
    res=$(sed "/^RESULT [^ ]* FAIL/{/ log=/!s|\$| out=$out|;s|\$|${ex:+ excerpt=$ex}|}" <<<"$res")
  fi
  echo "$res" | tee -a "$S"; echo "$name" >>"$D"
  # rows.tsv: one status per list row (rig-runner's filler ledger: a row reruns only when its build/script changed or it failed)
  # 3rd column: seconds the row held the game (its pre-row checks to the end of its game part; speed-audit 2026-10-11)
  if grep -qE '^RESULT [^ ]+ FAIL' <<<"$res"; then printf '%s\tFAIL\t%s\n' "$name" "${ROWSEC[$name]:-}"; else printf '%s\tPASS\t%s\n' "$name" "${ROWSEC[$name]:-}"; fi >>"$O/rows.tsv"
  # count by the row's status word (3rd field): a PASS row quoting an inner "RESULT take FAIL" counted as both (tur-b-2)
  # PASS-REC = pass with a recording warning (only sampler gaps / video length / sync lag failed; takecheck.py)
  pass=$((pass + $(grep -cE '^RESULT [^ ]+ PASS(-REC)? ' <<<"$res"))); fail=$((fail + $(grep -cE '^RESULT [^ ]+ FAIL' <<<"$res")))
  recwarn=$((recwarn + $(grep -cE '^RESULT [^ ]+ PASS-REC ' <<<"$res")))
  # combat/knockout/death toward the squad while the test ran: a note (fight tests cause it on purpose)
  hit=$(tail -c +"$((sl + 1))" "$STOBELOG" 2>/dev/null | grep -a -E "\[EVENT\] (combat[^]]*-> ($player|$mate) \(|knockout: ($player|$mate) |death: ($player|$mate) )" | head -2 | cut -c1-160 | paste -sd';')
  [ -n "$hit" ] && say "NOTE $name: combat/KO toward the squad: $hit"
}
collect() {  # collect [wait]: RESULT lines of background analyses that ended (wait: wait for all of them)
  local i p rc n sv pl mt ou tt slv keep=()
  for i in "${PEND[@]}"; do p=${i%%|*}
    if [ "${1:-}" = wait ] || ! kill -0 "$p" 2>/dev/null; then
      wait "$p"; rc=$?; IFS='|' read -r _ n sv pl mt ou tt slv <<<"$i"
      echo "$(date +%H:%M) $n: background analysis ended (exit $rc)"; row_result "$n" "$sv" "$pl" "$mt" "$ou" "$tt" "$rc" "$slv"
    else keep+=("$i"); fi
  done
  PEND=(${keep[@]+"${keep[@]}"})
}
# row_split <command>: the row's words as a shell would split them (quotes group a value with spaces: X="a b"), with no
# expansion and no execution (rows are not run by a shell). Rejects (return 1, reason in ROWERR) shell operators and
# expansions (; & | backtick $ ( ) < > backslash), a word starting with # and unbalanced quotes: a multi-step row goes in a .sh script.
row_split() { ROWERR=""; WORDS=(); local re='[;&|`$()<>\]' f=$- r
  [[ $1 =~ $re ]] && { ROWERR='shell operator/expansion in the command (one of ; & | ` $ ( ) < > \): rows are not run by a shell, put a multi-step row in a .sh script'; return 1; }
  [[ " $1" =~ [[:space:]]# ]] && { ROWERR="a word starts with # in the command (would be dropped as a comment)"; return 1; }
  set -f; eval "WORDS=($1)" 2>/dev/null; r=$?; [[ $f == *f* ]] || set +f
  [ $r = 0 ] || { ROWERR="unbalanced quotes in the command"; WORDS=(); return 1; }; }
while IFS= read -r line <&3 || [ -n "$line" ]; do   # list on fd 3: Windows tools (powershell, tasklist) eat stdin
  line="${line%%$'\r'}"; case "$line" in ''|'#'*) continue ;; esac
  IFS='|' read -r name save player mate to cmd <<<"$line"
  t() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }
  name=$(t "$name"); save=$(t "$save"); player=$(t "$player"); mate=$(t "$mate"); to=$(t "$to"); cmd=$(t "$cmd")
  cmd="${cmd//\{OUT\}/$O}"; out="$O/$name.txt"
  cmd="${cmd//\{RIG\}/${RIG:-5090}}"   # {RIG}: rig-runner fills it in; a hand run uses this rig
  if [ "$RESUME" = 1 ] && grep -qxF "$name" "$D" 2>/dev/null; then echo "$(date +%H:%M) $name: ran before, skipped (--resume)"; continue; fi
  # memory guard (rig-lane2.ps1, lane-5090c 2026-10-11): <out>/HOLD = RAM is short, wait at this row boundary until the
  # lane removes it (RAM free again) or a PREEMPT arrives; one NOTE line on hold and on resume
  if [ -f "$O/HOLD" ] && [ ! -f "$O/PREEMPT" ]; then
    say "NOTE $(date +%H:%M) HOLD before $name: $(head -1 "$O/HOLD" 2>/dev/null | tr -d '\r')"
    while [ -f "$O/HOLD" ] && [ ! -f "$O/PREEMPT" ]; do sleep 15; done
    say "NOTE $(date +%H:%M) HOLD released before $name"
  fi
  # rig-runner preemption (a filler gives way to real work): <out>/PREEMPT = stop at this row boundary; the running row has
  # its RESULT line, the rest are listed as not run (not in done.txt: --resume would run them), GAMEDONE/DONE as usual
  if [ -z "$PRE" ] && [ -f "$O/PREEMPT" ]; then PRE=$(head -1 "$O/PREEMPT" | tr -d '\r'); PRE=${PRE:-preempted}; say "BATCH PREEMPTED $(date '+%F %H:%M') before $name: $PRE"; fi
  if [ -n "$PRE" ]; then NOTRUN+=("$name"); continue; fi
  # row_split (2026-10-10): quotes group a value with spaces; shell operators are refused here, before the save loads
  if ! row_split "$cmd"; then say "RESULT $name FAIL list: $ROWERR"; fail=$((fail + 1)); continue; fi
  read -r freec kpriv <<<"$(memline)"
  rs0=$SECONDS; echo "$(date +%H:%M) $name: commit free ${freec:-?} GB, kenshi private ${kpriv:-?} GB"
  if [ "$dead" = 0 ] && [ "${kpriv:-x}" = - ]; then dead=1; say "NOTE Kenshi is not running before $name"; fi
  # a row asked for a fresh game (RELAUNCH_FILE: latched fp_combat fault): relaunch on this row's save first
  if [ -n "$relreq" ] && [ "$dead" = 0 ]; then
    if [ "$recovered" -lt "$RECOVER" ]; then relaunch "$save" "row $relrow asked for a relaunch: $relreq" || { say "NOTE relaunch failed"; dead=1; }
    else say "NOTE $name: row $relrow asked for a relaunch ($relreq) but RECOVER=$RECOVER relaunches are used up: runs on the same game"; fi
  fi
  relreq=""; relrow=""
  if [ "$dead" = 1 ] && [ "$recovered" -lt "$RECOVER" ]; then
    if relaunch "$save" "game dead before $name (commit free ${freec:-?} GB)"; then dead=0; else say "NOTE relaunch failed"; fi
  elif [ "$dead" = 0 ] && [ -n "${freec:-}" ] && [ "$recovered" -lt "$RECOVER" ] && awk -v f="$freec" -v m="$MIN_COMMIT_GB" 'BEGIN{exit !(f+0 < m+0)}'; then
    relaunch "$save" "commit free $freec GB < $MIN_COMMIT_GB GB (kenshi private $kpriv GB)" || { say "NOTE relaunch failed"; dead=1; }
  fi
  if [ "$dead" = 1 ]; then say "RESULT $name FAIL skipped: game not responding"; fail=$((fail + 1)); continue; fi
  # leftover game drivers of earlier rows/batches (killtree 2026-10-11: a runner-killed 4080 crossbow row kept running 42 min
  # and sent fp_combat aim inputs into three later batches): kill them before the row loads its save (row-reaper.sh)
  if [ -f "$A/row-reaper.sh" ]; then
    while IFS= read -r l; do case "$l" in NOTE*) say "${l/NOTE /NOTE $name: }" ;; NEUTRAL*) echo "$l" ;; esac; done < <(bash "$A/row-reaper.sh" sweep "$O" 2>&1 </dev/null)
  fi
  echo "$(date +%H:%M) $name: prepare $save"
  if ! prepare "$save" "$player" "$mate"; then
    say "RESULT $name FAIL game not responding after loading $save (rest of the batch skipped)"
    fail=$((fail + 1)); dead=1; continue
  fi
  # split the command: VAR=value words, then the script and its arguments
  words=("${WORDS[@]}"); envs=(); i=0
  while [ $i -lt ${#words[@]} ] && [[ "${words[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do envs+=("${words[$i]}"); i=$((i + 1)); done
  script="${words[$i]:-}"; args=("${words[@]:$((i + 1))}")
  case "$script" in /*) ;; *) if [ -e "$T/$script" ]; then script="$T/$script"; elif [ -e "$KT/$script" ]; then script="$KT/$script"; fi ;; esac
  case "$script" in
    *.sh) run=(bash "$script" "${args[@]}") ;;
    *.txt) if [ "$player" = Shay ] && [ "$mate" = Malzin ]; then run=(stobe-auto run "$script" --csv "$O/$name.csv" "${args[@]}")
           else run=(bash "$T/run-as.sh" "$script" "$player" "$mate" --csv "$O/$name.csv" "${args[@]}"); fi ;;
    *) run=("$script" "${args[@]}") ;;
  esac
  # dialog guard (2026-10-10 20-rg04 M08: a Dust Bandit's talk left the dialogue window open, KenshiFP ui_open=1 refused
  # every click, the row stalled until closed by hand): close an open conversation before the row (setup FAIL if it
  # stays open) and watch for new ones during it (tools/automation/dialog-guard.sh; DIALOG_GUARD=0 in the command = off)
  dgw=""; dgl="$O/$name.dialogs"; rm -f "$dgl"
  if [[ " ${envs[*]} " != *" DIALOG_GUARD=0 "* ]] && [ -f "$A/dialog-guard.sh" ]; then
    dg=$(bash "$A/dialog-guard.sh" check 2>&1) || {
      say "RESULT $name FAIL setup: dialog ${dg#DIALOG stuck } (before the row)"; fail=$((fail + 1)); continue; }
    case "$dg" in "DIALOG closed"*) say "NOTE $name: preflight closed an open conversation (${dg#DIALOG closed })" ;; esac
  fi
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
  gd="$O/.gamedone.$name"; rm -f "$gd"; rlf="$O/.relaunch.$name"; rm -f "$rlf"
  env PLAYER="$player" MATE="$mate" RESULT_LOG="$out" GAME_DONE_FILE="$gd" KAH_ROW="$name" RELAUNCH_FILE="$rlf" KAH_FRESH="$FRESH" "${envs[@]}" timeout "$to" "${run[@]}" >"$out" 2>&1 </dev/null &
  sp=$!; echo "$sp $name $(cat /proc/$sp/winpid 2>/dev/null)" > "$O/step.pid"
  [[ " ${envs[*]} " != *" DIALOG_GUARD=0 "* ]] && [ -f "$A/dialog-guard.sh" ] && { bash "$A/dialog-guard.sh" watch "$sp" "$dgl" >/dev/null 2>&1 </dev/null & dgw=$!; }
  bg=0; while kill -0 "$sp" 2>/dev/null; do [ -f "$gd" ] && { bg=1; break; }; sleep 2; done
  rm -f "$O/step.pid"; rc=0; [ $bg = 0 ] && { wait "$sp"; rc=$?; }; ROWSEC[$name]=$((SECONDS - rs0)); rm -f "$FRESH"
  # the row is over (or its step was killed: rig-runner kill-step / a hand taskkill): nothing of it may keep driving the
  # game. timeout's process group (MSYS/WSL pids), then every process naming the row dir (Windows tree walks miss MSYS forks)
  if [ $bg = 0 ]; then kill -TERM -- "-$sp" 2>/dev/null
    [ -f "$A/row-reaper.sh" ] && { kr=$(bash "$A/row-reaper.sh" kill "$O/$name" 2>&1 </dev/null | grep '^REAPED' | wc -l); [ "$kr" -gt 0 ] && say "NOTE $name: $kr leftover process(es) of the row killed after it ended (rc=$rc)"; }
  fi
  [ -n "$rg" ] && { kill "$rg" 2>/dev/null; wait "$rg" 2>/dev/null; }
  [ -n "$dgw" ] && { kill "$dgw" 2>/dev/null; wait "$dgw" 2>/dev/null; }
  [ -s "$dgl" ] && say "NOTE $name: dialog guard closed $(grep -c 'DIALOG GUARD: closed' "$dgl") conversation(s) mid-row, stuck $(grep -c 'DIALOG GUARD: stuck' "$dgl"): $(awk '{sub(/^[^ ]+ DIALOG GUARD: /,""); print}' "$dgl" | sort -u | head -3 | paste -sd';' | cut -c1-200) (clicks during it were refused: check the row's ui_open gates)"
  stobe-auto speed 0 >/dev/null 2>&1
  printf '%s\t%s\t' "$name" "$save" >>"$R"; paste <(echo "$before" | tr '\t' '\n') <(offsets | tr '\t' '\n') | paste -sd'\t' >>"$R"
  if [ $bg = 1 ]; then echo "$(date +%H:%M) $name: game part done, analysis goes on in the background (pid $sp)"; PEND+=("$sp|$name|$save|$player|$mate|$out|$to|$sl")
  else row_result "$name" "$save" "$player" "$mate" "$out" "$to" "$rc" "$sl"; fi
  collect
  relreq=$(relaunch_req "$rlf"); [ -n "$relreq" ] && { relrow=$name; say "NOTE $name: asked for a game relaunch before the next row: $relreq"; }
  tdr_guard "row $name" || continue   # GPU driver reset: batch stopped, no liveness wait on the stopped game
  # m37: a crashed/killed Kenshi = dead now, no 4.5 min of waits on a game that is gone (the next row relaunches)
  # 2026-10-11 (67-xbr-r11-hit): the runner killed the hung game DURING these waits and the batch sat 4.5 min on a game that
  # was gone: world_live re-checks Kenshi every 20 s and returns 2 the moment it is gone (dead now, no NOTE: next row relaunches)
  lw=2; if kenshi_up; then world_live 120; lw=$?; [ $lw = 1 ] && { for _ in $(seq 15); do kenshi_up || break; sleep 2; done; world_live 120; lw=$?; }; fi
  case $lw in 0) ;; 2) dead=1 ;; *) say "NOTE game not responding after $name (rest of the batch skipped)"; dead=1 ;; esac
done 3<"$L"
[ -n "$PRE" ] && say "NOTE $([ "$PRE" = TDR ] && echo 'TDR stop' || echo preempted): not run: ${NOTRUN[*]}"
# m37: skip `ctl stop` (up to 420 s) when Kenshi is already gone
[ "$STOP" = 1 ] && if kenshi_up; then ctl stop | tail -2; else echo "Kenshi not running, no stop needed"; fi
touch "$O/GAMEDONE"; [ ${#PEND[@]} -gt 0 ] && echo "$(date +%H:%M) game part done; waiting for ${#PEND[@]} background analyses"
collect wait
say "BATCH END $(date '+%F %H:%M') pass=$pass fail=$fail recwarn=$recwarn"
finish
