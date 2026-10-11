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
# A failed copy prints "SCPFAIL <dest>: <files>" and the sync goes on (was: set -e aborted the rest, 2026-10-10 17:42).
M=/c/KenshiModding; R=/c/KenshiTestRuns; H=4080; HERE=$M/tools/automation/rig4080
SAVES=""; DEFER=""; DRY=0
while :; do case "$1" in --saves) SAVES=$2; shift 2 ;; --saves-only) SAVES=$2; SAVESONLY=1; shift 2 ;; --defer) DEFER=$2; shift 2 ;; --dry) DRY=1; shift ;; *) break ;; esac; done
[ -n "$DEFER" ] && [ ! -f "$DEFER" ] && DEFER=""
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
run ssh $H 'mkdir C:\KAH\bin C:\KenshiModding\tools\automation C:\KenshiModding\components\KenshiFP\animlab C:\KenshiModding\components\KenshiFP\animlab\weapons C:\KenshiModding\components\KenshiFP\tests\ingame C:\KenshiModding\Kenshi-Automation-Harness\client C:\KenshiModding\Kenshi-Automation-Harness\tools\animlab 2>NUL & exit 0'
run scp -q "$HERE/itrun.ps1" "$HERE/kcfg.ps1" $H:C:/KAH/
run scp -q "$HERE/python3" $H:C:/KAH/bin/python3
cp_to C:/KenshiModding/tools/automation/ "$M/tools/automation/rig-env.sh" "$M/tools/automation/review-pack.py"
cp_to C:/KenshiModding/components/KenshiFP/animlab/ "$M"/components/KenshiFP/animlab/*.sh "$M"/components/KenshiFP/animlab/*.py "$M"/components/KenshiFP/animlab/*.txt
# weapon sweep lists + catalogue (wm4080-diag: "list sweep-gated.list missing")
cp_to C:/KenshiModding/components/KenshiFP/animlab/weapons/ "$M"/components/KenshiFP/animlab/weapons/*.list "$M"/components/KenshiFP/animlab/weapons/*.json
cp_to C:/KenshiModding/components/KenshiFP/tests/ingame/ "$M"/components/KenshiFP/tests/ingame/*.sh "$M"/components/KenshiFP/tests/ingame/*.py
cp_to C:/KenshiModding/Kenshi-Automation-Harness/client/ "$M/Kenshi-Automation-Harness/client/kah.py"
cp_to C:/KenshiModding/Kenshi-Automation-Harness/tools/animlab/ "$M"/Kenshi-Automation-Harness/tools/animlab/*.py
for d in "$@"; do
  ssh $H "mkdir C:\\KenshiTestRuns\\$d 2>NUL & exit 0"
  ( cd "$R/$d" && ls | grep -E '\.(sh|py|txt|awk|ttf)$' | grep -v -E '^(ts|s3ts|ev|s3ev)\.txt' | tr '\n' '\0' | xargs -0 -r -I{} scp -q {} "$H:C:/KenshiTestRuns/$d/" )
done
for s in $SAVES; do
  ssh $H "powershell -NoProfile -Command \"Remove-Item -Recurse -Force \$env:LOCALAPPDATA\\kenshi\\save\\$s -EA 0\"" || true
  scp -q -r "/c/Users/Shay/AppData/Local/kenshi/save/$s" "$H:AppData/Local/kenshi/save/"
done
echo "4080 rig synced$( [ $DRY = 1 ] && echo " (DRY)"): helpers, repo files$( [ -n "$DEFER" ] && echo " ($(grep -c . "$DEFER") deferred)"), run dirs [$*], saves [$SAVES]"
