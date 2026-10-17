#!/usr/bin/env bash
# batch-health.sh <out-dir> [stall-minutes] (WSL): ONE line about a running batch, for the 10-minute check-in
# (Shay, 2026-10-03: don't wait hours on a batch that went wrong). Works for run-batch.sh batches and older
# hand-written ones (it looks at the newest file under <out-dir>).
#   HEALTH DONE  <last SUMMARY line>                      batch finished: read SUMMARY.txt
#   HEALTH OK    file=<newest output> age=<min> phase=world ...
#   HEALTH STALL <reason> file=... age=... phase=...      act now: game not running / not in the world (menu, loading
#                                                         stuck) / no new output for <stall-minutes> (default 20)
#                                                         / game time stuck since the last check (5+ min) while the
#                                                         newest output only repeats one line (m22 L)
# Use it from a background wait so you're woken every 10 min:  sleep 600; bash .../batch-health.sh <out-dir>
set -u
O="${1:?usage: batch-health.sh <out-dir> [stall-minutes]}"; STALL_MIN="${2:-20}"
[ -f "$O/DONE" ] && { echo "HEALTH DONE $(tail -1 "$O/SUMMARY.txt" 2>/dev/null)"; exit 0; }
# memory guard (rig-lane2.ps1): a batch waiting at a row boundary on <out>/HOLD (RAM short; run-batch.sh wrote
# "NOTE hh:mm HOLD before <row>" as its last HOLD line) is healthy, not stalled; a row still running under HOLD is checked as usual
if [ -f "$O/HOLD" ] && grep -a 'HOLD' "$O/SUMMARY.txt" 2>/dev/null | tail -1 | grep -q 'HOLD before'; then echo "HEALTH OK held: $(head -1 "$O/HOLD" | tr -d '\r')"; exit 0; fi
# multi-instance: an out dir with .instance (rig-runner lane 5090b) belongs to install copy n (its harness, game dir, pids)
if [ -f "$O/.instance" ]; then n_=$(tr -dc 0-9 <"$O/.instance"); if [ "${n_:-1}" -ge 2 ] 2>/dev/null; then export KAH_INSTANCE=$n_ KENSHI_DIR=/mnt/d/KenshiInst/$n_ KAH_DIR="D:\\KenshiInst\\$n_\\mods\\AutomationHarness"; fi; fi
# kenshi_pids (multi-instance 2026-10-11): kenshi_x64 PIDs of THIS install only: KAH_INSTANCE=n>=2 = D:\KenshiInst\<n>, else
# every install outside D:\KenshiInst (a second test game must not count as instance 1). wmic gives the exe path (0.2 s);
# no wmic answer (none running, or wmic missing/broken) = tasklist by name as before.
kenshi_pids() {
  local o; o=$(wmic.exe process where "name='kenshi_x64.exe'" get ExecutablePath,ProcessId </dev/null 2>/dev/null | tr -d '\r')
  if grep -q ExecutablePath <<<"$o"; then
    awk -v n="${KAH_INSTANCE:-1}" 'NR>1 && NF>=2 { p=tolower($0); m=(n+0>=2) ? index(p, "\\kenshiinst\\" n "\\")>0 : index(p, "\\kenshiinst\\")==0; if (m) print $NF }' <<<"$o"
  else tasklist.exe </dev/null 2>/dev/null | awk 'tolower($1)=="kenshi_x64.exe"{print $2}'; fi
}
f=$(find "$O" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
if [ -n "$f" ]; then age=$(( ( $(date +%s) - ${f%%.*} ) / 60 )); f="${f#* }"
else age=0; f="(no output yet in $O)"; fi
cur=$(grep -a -E '^[0-9]{2}:[0-9]{2} .*: (prepare|run) ' "$O/batch.log" 2>/dev/null | tail -1 | cut -c1-80)
# Cheaper (res-wait 2026-10-10): ask the harness first; a harness answer proves Kenshi runs, so tasklist.exe (a Windows
# process spawn) only runs when the harness is silent. Same verdicts as before.
st=$(STOBE_AUTO_LIVE=1 timeout 30 stobe-auto status </dev/null 2>&1 | tr -d '\r' | head -1)
if ! grep -q 'phase=' <<<"$st" && [ -z "$(kenshi_pids)" ]; then
  echo "HEALTH STALL Kenshi is not running file=$f age=${age}m ${cur:+now=\"$cur\"}"; exit 2
fi
# m50 5090 K: a crash leaves RE_Kenshi's handler on a hidden message box; the game ran on for 40 s and then froze
# (main thread waiting for a crashed worker), so "Kenshi is running" proved nothing. A crash dump written after the
# batch's first output file = crash, even while the harness still answers.
cd_="${KENSHI_DIR:-/mnt/d/Steam/steamapps/common/Kenshi}/crashDump1.0.65_x64.dmp"
first=$(find "$O" -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1)
if [ -f "$cd_" ] && [ -n "$first" ] && [ "$(stat -c %Y "$cd_")" -gt "${first%%.*}" ]; then
  echo "HEALTH STALL Kenshi crashed (crash dump $(date -d @"$(stat -c %Y "$cd_")" +%H:%M:%S); RE_Kenshi's handler blocks on a hidden dialog, the game may still look alive) file=$f age=${age}m ${cur:+now=\"$cur\"}"; exit 2
fi
phase=$(grep -oE 'phase=[a-z]+' <<<"$st"); speed=$(grep -oE 'speed=[0-9.]+' <<<"$st"); paused=$(grep -oE 'paused=[01]' <<<"$st")
why=""
[ -z "$phase" ] && why="harness did not answer ($(cut -c1-60 <<<"$st"))"
[ -n "$phase" ] && [ "$phase" != phase=world ] && why="game is not in the world ($phase)"
[ -z "$why" ] && [ "$age" -ge "$STALL_MIN" ] && why="no new output for ${age}m"
# m22 L: A8-grow-fb sat 25 min with the game paused by a raid dialog while its guard loop kept writing the same line,
# so the file age stayed fresh. Many dialogue rows run paused on purpose, so a paused game alone is no stall: STALL
# when game time did not move since the previous check (>= 5 min ago) AND every line the newest file got since then
# is the same (timestamps stripped). State lives outside <out-dir>, so it never becomes the newest file.
gh=$(STOBE_AUTO_LIVE=1 timeout 30 stobe-auto time </dev/null 2>/dev/null | tr -d '\r' | grep -oE 'game_hours=[0-9.]+' | head -1)
sf="/tmp/batch-health.$(echo "$O" | md5sum | cut -c1-8)"; now=$(date +%s)
nl=0; [ -f "$f" ] && nl=$(wc -l <"$f")
if [ -z "$why" ] && [ -n "$gh" ] && [ -f "$sf" ]; then
  read -r pt pgh pf pnl <"$sf"
  if [ "$pgh" = "$gh" ] && [ "$pf" = "$f" ] && [ $(( now - pt )) -ge 300 ] && [ "$nl" -gt "${pnl:-0}" ]; then
    new=$(tail -n +"$(( pnl + 1 ))" "$f" | sed -E 's/^\[[0-9:]+\] //' | sort -u | wc -l)
    [ "$new" -le 1 ] && why="game time stuck for $(( (now - pt) / 60 ))m (${gh#*=} h, $paused) and the output only repeats: $(tail -1 "$f" | cut -c1-60)"
  fi
fi
[ -n "$gh" ] && echo "$now $gh $f $nl" >"$sf"
if [ -n "$why" ]; then echo "HEALTH STALL $why file=$f age=${age}m $phase ${cur:+now=\"$cur\"}"; exit 2; fi
echo "HEALTH OK file=$f age=${age}m $phase $speed $paused ${cur:+now=\"$cur\"}"
