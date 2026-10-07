#!/usr/bin/env bash
# fp-m09.sh <outdir> [loadouts]: M09 animation compatibility (COMBAT_TEST_PLAN.md): the manual melee rows once per
# combat animation loadout, "vanilla first, individual MCA/DodgeStrafe/Great Anims, then full loadout".
# Per loadout: stop Kenshi, `anim-mods.sh set <loadout>` (data/mods.cfg; the game reads it at launch), launch on $SAVE,
# check kenshi_info.log loaded exactly that loadout, then (fresh load of $SAVE before each script)
# fp-manual-melee.sh (M00 M01 M02 M07 M09-CHASE M03 M05 M06) and fp-manual-melee-life.sh (M08-*).
# Output: <outdir>/SUMMARY.txt with ONE line per loadout x row: `RESULT M09-<loadout>-<row> PASS|FAIL <evidence>`;
# a loadout whose setup failed gets `RESULT M09-<loadout>-SETUP FAIL <why>` and its rows are skipped. <outdir>/DONE at the end.
# At the end (and on any exit) Kenshi is stopped and `anim-mods.sh restore` puts Shay's full list back.
# Loadouts (default): vanilla mca dodge gam full (anim-mods.sh header: which lines each one keeps).
# Rigs: the 4080 (Git Bash; copy this, anim-mods.sh, fp-manual-melee.sh, fp-manual-melee-life.sh into C:\KAH\fp) uses
# C:\KAH\ctl.ps1; the 5090 (WSL) uses tools/automation/kenshi-ctl.ps1. Env: SAVE (kah-fpxbow), FI (Malzin), TG (Skaera),
# OT (Axima, M08-ACTOR), ANIM (anim-mods.sh path), CTLPS (ctl script, Windows path), WORLD_S (600, launch -> world).
# Only one runner per machine; Kenshi must not be needed by anyone else for the whole run (~5 launches).
set -u
O=${1:?usage: fp-m09.sh <outdir> [loadouts]}; LOADOUTS=${2:-"vanilla mca dodge gam full"}
SAVE=${SAVE:-kah-fpxbow}; FI=${FI:-Malzin}; TG=${TG:-Skaera}; OT=${OT:-Axima}; WORLD_S=${WORLD_S:-600}
D=$(cd "$(dirname "$0")" && pwd)
ANIM=${ANIM:-}; for a in "$D/anim-mods.sh" /mnt/c/KenshiModding/tools/automation/anim-mods.sh /c/KenshiModding/tools/automation/anim-mods.sh; do
  [ -z "$ANIM" ] && [ -f "$a" ] && ANIM=$a; done
if [ -z "${CTLPS:-}" ]; then if [ -f /c/KAH/ctl.ps1 ]; then CTLPS='C:\KAH\ctl.ps1'; else CTLPS='C:\KenshiModding\tools\automation\kenshi-ctl.ps1'; fi; fi
command -v stobe-auto >/dev/null || export PATH=/c/KAH/bin:$PATH
mkdir -p "$O"; rm -f "$O/DONE"; S="$O/SUMMARY.txt"; : > "$S"
say() { echo "$*" | tee -a "$S"; }
note() { echo "$(date +%T) $*" >> "$O/progress.txt"; }
ctl() { timeout 900 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CTLPS" "$@" </dev/null >> "$O/ctl.log" 2>&1; }
[ -n "$ANIM" ] || { say "RESULT M09-SETUP FAIL anim-mods.sh not found (set ANIM=)"; touch "$O/DONE"; exit 1; }
finish() { ctl stop; note "restore: $(bash "$ANIM" restore 2>&1)"; touch "$O/DONE"; }
trap finish EXIT
say "M09 start $(date '+%F %T') save=$SAVE fighter=$FI target=$TG loadouts='$LOADOUTS' anim=$ANIM ctl=$CTLPS before: $(bash "$ANIM" status)"
# expected `loaded:` line of anim-mods.sh for a loadout
want_loaded() { case $1 in vanilla) echo "loaded: mca=off dodge=off gam=off standup=off" ;; full) echo "loaded: mca=on dodge=on gam=on standup=on" ;;
  *) local g s=""; for g in mca dodge gam standup; do [ $g = "$1" ] && s+=" $g=on" || s+=" $g=off"; done; echo "loaded:$s" ;; esac; }
# runrows <loadout> <name> <script> <args...> ({OUT} = its out dir): fresh load, run, prefix its RESULT lines with M09-<loadout>-
runrows() { local lo=$1 n=$2 f=$3 out="$O/$1/$2" rc a args=(); shift 3; mkdir -p "$out"; for a in "$@"; do args+=("${a//\{OUT\}/$out}"); done
  stobe-auto load "$SAVE" >/dev/null 2>&1; if ! stobe-auto wait-world 300 >/dev/null 2>&1; then say "RESULT M09-$lo-$n FAIL setup load $SAVE never reached the world"; return; fi
  sleep 3; note "$lo $n start"; bash "$D/$f" "${args[@]}" > "$out/RESULT.txt" 2>&1; rc=$?; note "$lo $n done rc=$rc"
  if grep -q '^RESULT ' "$out/RESULT.txt"; then sed -n "s/^RESULT /RESULT M09-$lo-/p" "$out/RESULT.txt" | tee -a "$S"
  else say "RESULT M09-$lo-$n FAIL no RESULT line (rc=$rc) log=$out/RESULT.txt"; fi; }
for lo in $LOADOUTS; do
  note "loadout $lo"; ctl stop
  st=$(bash "$ANIM" set "$lo" 2>&1) || { say "RESULT M09-$lo-SETUP FAIL anim-mods.sh set $lo: $st"; continue; }
  if ! ctl launch -Save "$SAVE" || ! stobe-auto wait-world "$WORLD_S" >/dev/null 2>&1; then
    say "RESULT M09-$lo-SETUP FAIL launch on $SAVE never reached the world (ctl.log; $st)"; continue; fi
  got=$(bash "$ANIM" loaded | grep '^loaded:'); exp=$(want_loaded "$lo")
  if [ "$got" != "$exp" ]; then say "RESULT M09-$lo-SETUP FAIL kenshi_info.log '$got', wanted '$exp' ($st)"; continue; fi
  say "M09 $lo: $st | $got"
  runrows "$lo" melee fp-manual-melee.sh "$FI" "$TG" "{OUT}"
  runrows "$lo" life fp-manual-melee-life.sh "$FI" "$TG" "{OUT}" "$OT"
done
say "M09 end $(date '+%F %T')"
