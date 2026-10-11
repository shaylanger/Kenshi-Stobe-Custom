#!/bin/bash
# rig4080/setup.sh [--saves "kah-a kah-b"] [--saves-only "kah-a"] [run dirs...]: make the 4080 a filming rig / refresh it (run on the 5090, Git Bash).
#  1. helpers -> C:\KAH: itrun.ps1 (desktop-session runner), kcfg.ps1 (windowed 1600x900 test cfg), bin\python3 shim
#  2. the repo files takes use -> the same paths under C:\KenshiModding on the 4080: tools/automation/rig-env.sh,
#     components/KenshiFP/animlab (scripts, rules), components/KenshiFP/tests/ingame/*.sh|*.py,
#     Kenshi-Automation-Harness/client/kah.py + tools/animlab/*.py
#  3. each run dir given (e.g. f36 f38 f24 f26) -> C:\KenshiTestRuns\<dir> on the 4080: scripts and small text/png only
#     (no mp4, no raw frames)
#  4. --saves: copy those save folders from this PC's %LOCALAPPDATA%\kenshi\save to the 4080's (replaces them)
# Kenshi may run on the 4080 meanwhile (no DLL is touched). Never run while a 4080 take is running (it replaces its scripts).
#  --defer <file>: repo-relative paths (one per line) NOT to copy: files a still-running 4080 background analysis uses
#    (rig-runner.ps1 computes it; they sync at a later boundary). Every skipped file prints "DEFERRED <path>".
#  --dry: print what would be copied (COPY <path> / DEFERRED <path>), no ssh/scp (rig-runner -Fake test).
#  --list: print the repo-relative paths the sync copies (no ssh). --check: every helper a synced script names (sibling
#    sh/py/awk/ps1/txt/json/tsv/csv/list/sed/jq) is synced too ("UNSYNCED <helper> (named in <script>)", exit 1).
# A failed copy prints "SCPFAIL <dest>: <files>" and the sync goes on (was: set -e aborted the rest, 2026-10-10 17:42).
M=/c/KenshiModding; R=/c/KenshiTestRuns; H=4080; HERE=$M/tools/automation/rig4080
SAVES=""; DEFER=""; DRY=0
while :; do case "$1" in --saves) SAVES=$2; shift 2 ;; --saves-only) SAVES=$2; SAVESONLY=1; shift 2 ;; --defer) DEFER=$2; shift 2 ;; --dry) DRY=1; shift ;; *) break ;; esac; done
[ -n "$DEFER" ] && [ ! -f "$DEFER" ] && DEFER=""
# The synced repo file sets (dest dir under C:\KenshiModding | files), the ONE definition used for copying, for --list
# (rig-runner SyncCandidates, list-rigcheck.sh) and for --check. Script dirs sync EVERY helper type next to the scripts
# (sh py awk ps1 txt json tsv csv list sed jq): rg-02-control-stealth-1011-0927 fp-control.sh needs fp-yaw-free.awk,
# which only *.sh|*.py globs never copied ("helper fp-yaw-free.awk missing").
shopt -s nullglob
HX='sh,py,awk,ps1,txt,json,tsv,csv,list,sed,jq'
SETD=(); SETF=()
addset(){ local d=$1; shift; local f fs=""; for f in "$@"; do [ -f "$f" ] && fs+="$f "; done; SETD+=("$d"); SETF+=("$fs"); }
addset tools/automation $M/tools/automation/{rig-env.sh,venc.sh,review-pack.py,dialog-guard.sh,row-reaper.sh,rig-runner-probe.sh,batch-excerpts.sh,batch-health.sh}
addset components/KenshiFP/animlab $(eval echo "$M/components/KenshiFP/animlab/*.{$HX}")
# weapon sweep lists + catalogue (wm4080-diag: "list sweep-gated.list missing")
addset components/KenshiFP/animlab/weapons $(eval echo "$M/components/KenshiFP/animlab/weapons/*.{$HX}")
addset components/KenshiFP/tests/ingame $(eval echo "$M/components/KenshiFP/tests/ingame/*.{$HX}")
addset Kenshi-Automation-Harness/client "$M/Kenshi-Automation-Harness/client/kah.py"
addset Kenshi-Automation-Harness/tools/animlab $(eval echo "$M/Kenshi-Automation-Harness/tools/animlab/*.{$HX}")
# weapons --run (take RESULT matrix) imports visual/ogre.py: without it every 4080 sweep row read matrix=[] (twohand-4080 2026-10-10)
addset Kenshi-Automation-Harness/tools/animlab/visual $(eval echo "$M/Kenshi-Automation-Harness/tools/animlab/visual/*.{$HX}")
synced_list(){ local i f; for i in "${!SETF[@]}"; do for f in ${SETF[$i]}; do echo "${f#$M/}"; done; done; }
# --list: every repo-relative path the sync copies, one per line (no ssh)
[ "${1:-}" = --list ] && { synced_list; exit 0; }
# --check: every helper a synced script names (bare file name, any helper type, sibling in its own dir) must be synced too.
# Prints "UNSYNCED <helper> (named in <script>)" per gap; exit 1 if any. rig-runner -SelfTest + list-rigcheck.sh use it.
if [ "${1:-}" = --check ]; then
  declare -A IN=(); while read -r f; do IN[$f]=1; done < <(synced_list); bad=0
  # named but deliberately not synced: run-batch.sh goes into each out dir as .run-batch.sh (rig-runner); kenshi-ctl.ps1 and
  # rig-runner.ps1 are 5090-side (the 4080 uses C:\KAH\ctl.ps1); animlab *.c/*.h build the lab in WSL on the 5090 only
  for f in tools/automation/run-batch.sh tools/automation/kenshi-ctl.ps1 tools/automation/rig-runner.ps1; do IN[$f]=1; done
  for f in $(synced_list); do case "$f" in *.sh|*.py|*.awk|*.ps1) ;; *) continue ;; esac; d=$(dirname "$f")
    for n in $(grep -oE "[A-Za-z0-9_][A-Za-z0-9_.-]*\.(sh|py|awk|ps1|txt|json|tsv|csv|list|sed|jq)\b" "$M/$f" | sort -u); do
      [ -f "$M/$d/$n" ] && [ -z "${IN[$d/$n]:-}" ] && { echo "UNSYNCED $d/$n (named in $f)"; bad=1; }
    done; done
  [ $bad = 0 ] && echo "SYNCCHECK OK $(synced_list | wc -l) files"; exit $bad
fi
# --saves-only "<saves>": copy only those saves (list-rigcheck.sh --fix: a list's save missing on the 4080), nothing else
if [ "${SAVESONLY:-0}" = 1 ]; then
  for s in $SAVES; do [ -d "/c/Users/Shay/AppData/Local/kenshi/save/$s" ] || { echo "SAVEFAIL $s: not on the 5090"; continue; }
    [ $DRY = 1 ] && { echo "COPY save $s"; continue; }
    [ -n "$s" ] || continue   # never an empty name: the Remove-Item path would be the whole save dir
    ssh $H "powershell -NoProfile -Command \"Remove-Item -Recurse -Force \$env:LOCALAPPDATA\\kenshi\\save\\$s -EA 0\"" || true
    scp -q -r "/c/Users/Shay/AppData/Local/kenshi/save/$s" "$H:AppData/Local/kenshi/save/" || echo "SAVEFAIL $s: scp"
  done
  echo "4080 saves synced$( [ $DRY = 1 ] && echo " (DRY)"): [$SAVES]"; exit 0
fi
run() { if [ $DRY = 1 ]; then :; else "$@"; fi; }
# cp_to <dest> <files...>: scp the files that exist and aren't deferred
cp_to() {
  local d=$1 f rel keep=(); shift
  for f in "$@"; do
    [ -f "$f" ] || continue; rel=${f#$M/}
    if [ -n "$DEFER" ] && tr -d '' < "$DEFER" | grep -qxF "$rel"; then echo "DEFERRED $rel"; continue; fi
    keep+=("$f")
  done
  [ ${#keep[@]} -eq 0 ] && return 0
  if [ $DRY = 1 ]; then for f in "${keep[@]}"; do echo "COPY ${f#$M/}"; done; return 0; fi
  scp -q "${keep[@]}" "$H:$d" || echo "SCPFAIL $d: ${keep[*]#$M/}"
}
run ssh $H 'mkdir C:\KAH\bin C:\KenshiModding\tools\automation C:\KenshiModding\components\KenshiFP\animlab C:\KenshiModding\components\KenshiFP\animlab\weapons C:\KenshiModding\components\KenshiFP\tests\ingame C:\KenshiModding\Kenshi-Automation-Harness\client C:\KenshiModding\Kenshi-Automation-Harness\tools\animlab C:\KenshiModding\Kenshi-Automation-Harness\tools\animlab\visual 2>NUL & exit 0'
run scp -q "$HERE/itrun.ps1" "$HERE/kcfg.ps1" "$HERE/../kenshi-gfx.ps1" $H:C:/KAH/
run scp -q "$HERE/python3" $H:C:/KAH/bin/python3
for i in "${!SETD[@]}"; do cp_to "C:/KenshiModding/${SETD[$i]}/" ${SETF[$i]}; done
for d in "$@"; do
  ssh $H "mkdir C:\\KenshiTestRuns\\$d 2>NUL & exit 0"
  ( cd "$R/$d" && ls | grep -E '\.(sh|py|txt|awk|ttf)$' | grep -v -E '^(ts|s3ts|ev|s3ev)\.txt' | tr '\n' '\0' | xargs -0 -r -I{} scp -q {} "$H:C:/KenshiTestRuns/$d/" )
done
for s in $SAVES; do
  ssh $H "powershell -NoProfile -Command \"Remove-Item -Recurse -Force \$env:LOCALAPPDATA\\kenshi\\save\\$s -EA 0\"" || true
  scp -q -r "/c/Users/Shay/AppData/Local/kenshi/save/$s" "$H:AppData/Local/kenshi/save/"
done
echo "4080 rig synced$( [ $DRY = 1 ] && echo " (DRY)"): helpers, repo files$( [ -n "$DEFER" ] && echo " ($(grep -c . "$DEFER") deferred)"), run dirs [$*], saves [$SAVES]"
