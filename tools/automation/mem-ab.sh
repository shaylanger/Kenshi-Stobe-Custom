#!/usr/bin/env bash
# mem-ab.sh: which plugin costs Kenshi's memory? For each variant: turn the listed plugins off,
# launch on <save>, load <save> N more times, and after each load (+settle) log one probe line
# (private/working set, File/Semaphore/Thread handles, private-commit regions; memprobe.ps1).
# Plugins are turned off by renaming mods\<Mod>\RE_Kenshi.json -> RE_Kenshi.json.memoff
# (RE_Kenshi then skips the DLL; the .mod data stays active). Always restored on exit (trap),
# also restored by: bash mem-ab.sh --restore
# Kenshi must be closed and the game lock free/ours. The harness stays on (it drives the loads).
# Usage (detached, from Windows):
#   wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -c 'setsid nohup bash /mnt/c/KenshiModding/tools/automation/mem-ab.sh /mnt/c/KenshiTestRuns/memab auto-home 5 >/dev/null 2>&1 &'
# Variants (edit VARIANTS to change): all on | -Stobe | -KenshiFP | -PG | -Dust | -KEP | -GearCompare | only harness
# Output: <out>/mem.csv (label = variant/loadN), <out>/SUMMARY.txt (one RESULT line per variant), <out>/DONE
set -u
K=/mnt/d/Steam/steamapps/common/Kenshi/mods
CTL='C:\KenshiModding\tools\automation\kenshi-ctl.ps1'
PROBE='C:\KenshiModding\tools\automation\memprobe.ps1'
ALL="Stobe KenshiFP ProfessionGearProgression Dust KenshiExtensionPlugin GearCompare"
VARIANTS=("all:" "noStobe:Stobe" "noKenshiFP:KenshiFP" "noPG:ProfessionGearProgression" "noDust:Dust" "noKEP:KenshiExtensionPlugin" "noGearCompare:GearCompare" "harnessOnly:$ALL")

restore() { for m in $ALL; do [ -e "$K/$m/RE_Kenshi.json.memoff" ] && mv -f "$K/$m/RE_Kenshi.json.memoff" "$K/$m/RE_Kenshi.json"; done; return 0; }
if [ "${1:-}" = --restore ]; then restore; echo restored; exit 0; fi
O=${1:?out dir}; SAVE=${2:-auto-home}; N=${3:-5}; SETTLE=${SETTLE:-90}
mkdir -p "$O"; rm -f "$O/DONE"; : > "$O/SUMMARY.txt"
WO=$(wslpath -w "$O")
ctl() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTL" "$@" </dev/null | tr -d '\r'; }
probe() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PROBE" -Label "$1" -Csv "$WO\\mem.csv" </dev/null | tr -d '\r'; }
world() { stobe-auto wait-world "${1:-300}" >/dev/null 2>&1; }
trap 'ctl stop >/dev/null 2>&1; restore' EXIT
restore
for v in "${VARIANTS[@]}"; do
  name=${v%%:*}; off=${v#*:}
  for m in $off; do [ -e "$K/$m/RE_Kenshi.json" ] && mv -f "$K/$m/RE_Kenshi.json" "$K/$m/RE_Kenshi.json.memoff"; done
  stobe-say on >/dev/null 2>&1
  ctl launch -Save "$SAVE" >/dev/null
  if ! world 900; then echo "RESULT $name FAIL game did not reach the world" >> "$O/SUMMARY.txt"; ctl stop >/dev/null; restore; continue; fi
  sleep "$SETTLE"; first=$(probe "$name/load0")
  last=$first
  for i in $(seq 1 "$N"); do
    stobe-auto load "$SAVE" >/dev/null 2>&1; sleep 12; world 300 || { sleep 30; world 300; }
    sleep "$SETTLE"; last=$(probe "$name/load$i")
  done
  # fields: time,label,privMB,wsMB,threads,handles,File,Semaphore,Event,Thread,privCommitMB,nAllocs,big16MB,bigMB
  p0=$(echo "$first" | cut -d, -f3); p1=$(echo "$last" | cut -d, -f3); f0=$(echo "$first" | cut -d, -f7); f1=$(echo "$last" | cut -d, -f7)
  echo "RESULT $name privMB load0=$p0 load$N=$p1 perLoad=$(( (p1-p0)/N )) FileHandles $f0->$f1 big16MB=$(echo "$last" | cut -d, -f13)/$(echo "$last" | cut -d, -f14)MB" >> "$O/SUMMARY.txt"
  ctl stop >/dev/null; restore
done
touch "$O/DONE"
