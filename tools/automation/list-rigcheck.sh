#!/bin/bash
# list-rigcheck.sh [--fix] [--quiet] <list file> <5090|4080>   (Git Bash on the 5090; ssh 4080 for the 4080 side)
# Can this run-batch list run on that rig? Flags a list that would fail at launch for a rig reason, BEFORE it is taken
# (Shay 2026-10-10: either rig takes any list; takes never wait behind one rig while the other runs filler).
# Checks:
#   save    the "# launch:" save (else the first row's) and every row save (not - / home / auto-home) exist on the rig
#           (5090: %LOCALAPPDATA%\kenshi\save; 4080: its save dir over ssh). 4080 copy differing from the 5090's
#           quick.save (md5) = WARN only (a 4080 test may have saved on purpose).
#   scripts every script path in the rows ({CR}|/mnt/c|/c ... .sh|.py|.ps1|.awk) exists on the 5090; for the 4080 it is
#           (plus, transitively, every helper a script names by bare file name that sits next to it, e.g. fp-control.sh ->
#           fp-yaw-free.awk) either a file rig4080/setup.sh --list syncs at every list start (components/KenshiFP/tests/ingame/*,
#           animlab/*.sh|py|txt, animlab/weapons/*, harness client/kah.py + tools/animlab/*.py, rig-env.sh,
#           review-pack.py, run-batch helpers) or already on the 4080 with the same md5. Ad-hoc scripts under
#           C:\KenshiTestRuns (and the ad-hoc scripts they call) are 5090-only unless identical on the 4080: move them into
#           components/KenshiFP/tests/ingame (rig-aware, rig-env.sh) so the runner syncs them.
#   rig     "# rig: X" header names another rig; Stobe rows (STOBE-*, tests/ingame/stobe, *.txt scenarios) on the 4080.
# --fix (4080): copy a save that exists on the 5090 but not on the 4080 (rig4080/setup.sh --saves-only), then recheck.
# Output: WARN lines, then one line  RIGCHECK <rig> OK <list>  |  RIGCHECK <rig> NO <list>: <reason>; <reason>...
# Exit 0 = OK, 1 = NO, 2 = usage / 4080 unreachable (reason printed; the caller treats it as "can't tell", not NO).
FIX=0; Q=0
while :; do case "$1" in --fix) FIX=1; shift ;; --quiet) Q=1; shift ;; *) break ;; esac; done
L=$1; RIG=$2
[ -f "$L" ] && { [ "$RIG" = 5090 ] || [ "$RIG" = 4080 ]; } || { sed -n '2,20p' "$0"; exit 2; }
M=/c/KenshiModding; SAVES=/c/Users/Shay/AppData/Local/kenshi/save; NAME=$(basename "$L")
SSH="ssh -n -o BatchMode=yes -o ConnectTimeout=10 4080"
hdr(){ grep -m1 -iE "^#\s*$1:" "$L" | sed -E "s/^#\s*$1:\s*//I; s/\s+$//"; }
rows(){ grep -vE '^\s*(#|$)' "$L"; }
reasons=(); warn(){ [ $Q = 1 ] || echo "WARN $RIG $NAME: $*"; }

# ---- rig header + Stobe rows
want=$(hdr rig); [ -n "$want" ] && [ "$want" != "$RIG" ] && reasons+=("list says rig: $want")
# a .txt counts as a Stobe scenario only in a row that runs no .sh/.py/.ps1 script (fp-pose-sweep.sh takes a variants .txt)
if [ "$RIG" = 4080 ] && rows | awk -F'|' '{c=$NF} c ~ /STOBE-|tests\/ingame\/stobe/ || (c ~ /\.txt([ \t]|$)/ && c !~ /\.(sh|py|ps1)([ \t]|$)/) {f=1} END {exit !f}'; then reasons+=("Stobe rows (no Stobe on the 4080)"); fi

# ---- saves
sv=$(hdr launch); declare -A SV=()
[ -n "$sv" ] && SV[$sv]=1
while IFS='|' read -r _ s _; do s=$(echo "$s" | tr -d ' \r'); [ -n "$s" ] && SV[$s]=1; done < <(rows)
for s in "${!SV[@]}"; do case "$s" in -|home|auto-home) unset "SV[$s]" ;; esac; done
[ -z "$sv" ] && [ -z "$(rows | head -1 | cut -d'|' -f2 | tr -d ' -')" ] && reasons+=("no save to launch (\"# launch: <save>\")")

# ---- script paths (normalized to /c/...)
declare -A SC=()
add_sc(){ local p=$1; p=${p//\{CR\}/\/c}; p=${p/#\/mnt\/c\//\/c\/}; SC[$p]=1; }
while read -r p; do add_sc "$p"; done < <(rows | awk -F'|' '{print $NF}' | grep -oE "(\{CR\}|/mnt/c|/c)/[^ \"'|;)]+\.(sh|py|ps1|awk)")
# ad-hoc closure: KenshiTestRuns scripts named inside ad-hoc KenshiTestRuns scripts (cd <dir> + bare "bash x.sh" too)
todo=("${!SC[@]}"); seen=()
while [ ${#todo[@]} -gt 0 ]; do
  p=${todo[0]}; todo=("${todo[@]:1}")
  [ -f "$p" ] || continue
  d=$(dirname "$p")
  # helpers named by bare file name and present next to the script (repo or ad-hoc): fp-control.sh -> fp-yaw-free.awk
  # (rg-02-control-stealth-1011-0927: the 4080 sync never copied *.awk, the take failed at setup)
  for n in $(grep -oE "[A-Za-z0-9_][A-Za-z0-9_.-]*\.(sh|py|awk|ps1|txt|json|tsv|csv|list|sed|jq)\b" "$p" | sort -u); do
    q="$d/$n"; [ -f "$q" ] && [ -z "${SC[$q]:-}" ] || continue
    case "$q" in $M/tools/automation/run-batch.sh|$M/tools/automation/kenshi-ctl.ps1|$M/tools/automation/rig-runner.ps1) continue ;; esac
    SC[$q]=1; todo+=("$q")
  done
  case "$p" in /c/KenshiTestRuns/*) ;; *) continue ;; esac
  for q in $(grep -oE "(/mnt/c|/c|\\\$\{CR:-/mnt/c\})/KenshiTestRuns/[^ \"'|;)]+\.(sh|py|awk)" "$p" | sed -E 's#^\$\{CR:-/mnt/c\}#/c#; s#^/mnt/c/#/c/#') \
           $(grep -oE "(^|[;&|] *|^ *)(bash|\.|python3) +[A-Za-z0-9_.-]+\.(sh|py)" "$p" | awk '{print $NF}' | sed "s#^#$d/#"); do
    [ -n "${SC[$q]:-}" ] && continue
    [ -f "$q" ] || continue
    SC[$q]=1; todo+=("$q")
  done
done

# ---- 5090 side: everything must exist here (it is the source of every sync)
for p in "${!SC[@]}"; do [ -f "$p" ] || reasons+=("script $p missing on the 5090"); done
if [ "$RIG" = 5090 ]; then
  for s in "${!SV[@]}"; do [ -d "$SAVES/$s" ] || reasons+=("save $s missing"); done
else
  # ---- 4080 side
  # synced = in the sync's own file list (rig4080/setup.sh --list, one definition) or a run-batch helper rig-runner copies
  declare -A SY=(); while read -r f; do SY[$M/$f]=1; done < <(bash $M/tools/automation/rig4080/setup.sh --list)
  synced(){ [ -n "${SY[$1]:-}" ] && return 0; case "$1" in
    $M/tools/automation/run-batch.sh|$M/tools/automation/batch-excerpts.sh|$M/tools/automation/batch-health.sh) return 0 ;;
    *) return 1 ;; esac; }
  ask=()
  for p in "${!SC[@]}"; do synced "$p" || ask+=("$p"); done
  # one ssh round: save dirs + md5 of every not-synced script + the saves' quick.save
  q='cd ~/AppData/Local/kenshi/save 2>/dev/null && for s in */; do echo "SAVE ${s%/} $(md5sum "${s%/}/quick.save" 2>/dev/null | cut -c1-32)"; done'
  for p in "${ask[@]}"; do q="$q; echo \"FILE $p \$(md5sum '$p' 2>/dev/null | cut -c1-32)\""; done
  out=$(printf '%s\n' "$q" | ssh -o BatchMode=yes -o ConnectTimeout=10 4080 'C:\PROGRA~1\Git\bin\bash.exe -ls' 2>/dev/null | tr -d '\r')
  echo "$out" | grep -q '^SAVE ' || { echo "RIGCHECK 4080 UNKNOWN $NAME: 4080 unreachable over ssh"; exit 2; }
  for s in "${!SV[@]}"; do
    if ! echo "$out" | grep -q "^SAVE $s "; then
      if [ ! -d "$SAVES/$s" ]; then reasons+=("save $s missing on both rigs")
      elif [ $FIX = 1 ]; then
        r=$(bash $M/tools/automation/rig4080/setup.sh --saves-only "$s" 2>&1 | tail -1)
        printf '%s\n' "test -d ~/AppData/Local/kenshi/save/$s && echo COPIED" | ssh -o BatchMode=yes 4080 'C:\PROGRA~1\Git\bin\bash.exe -ls' 2>/dev/null | grep -q COPIED \
          && warn "save $s copied to the 4080 ($r)" || reasons+=("save $s not on the 4080, copy failed ($r)")
      else reasons+=("save $s only on the 5090 (list-rigcheck.sh --fix or rig4080/setup.sh --saves-only $s copies it)"); fi
    else
      m4=$(echo "$out" | grep "^SAVE $s " | head -1 | awk '{print $3}'); m5=$(md5sum "$SAVES/$s/quick.save" 2>/dev/null | cut -c1-32)
      [ -n "$m5" ] && [ "$m4" != "$m5" ] && warn "save $s differs on the 4080 (quick.save md5 ${m4:0:8} vs 5090 ${m5:0:8})"
    fi
  done
  for p in "${ask[@]}"; do
    [ -f "$p" ] || continue
    m4=$(echo "$out" | grep -F "FILE $p " | awk '{print $3}'); m5=$(md5sum "$p" | cut -c1-32)
    if [ -z "$m4" ]; then
      case "$p" in /c/KenshiTestRuns/*) reasons+=("ad-hoc script $p is 5090-only (move it into components/KenshiFP/tests/ingame, rig-aware via rig-env.sh, so the runner syncs it)") ;;
                   *) reasons+=("script $p is not synced to the 4080 and not on it (rig4080/setup.sh --list: tests/ingame, animlab, harness client/animlab helpers)") ;; esac
    elif [ "$m4" != "$m5" ]; then reasons+=("script $p differs on the 4080 (not synced: ad-hoc copy, md5 ${m4:0:8} vs ${m5:0:8})")
    else case "$p" in /c/KenshiTestRuns/*) warn "ad-hoc script $p identical on the 4080 (not synced by the runner: move it into the repo)" ;; esac; fi
  done
fi
if [ ${#reasons[@]} -eq 0 ]; then echo "RIGCHECK $RIG OK $NAME"; exit 0; fi
( IFS=';'; echo "RIGCHECK $RIG NO $NAME: $(printf '%s; ' "${reasons[@]}" | sed 's/; $//')" ); exit 1
