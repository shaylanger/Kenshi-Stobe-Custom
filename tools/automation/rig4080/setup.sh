#!/bin/bash
# rig4080/setup.sh [--saves "kah-a kah-b"] [run dirs...]: make the 4080 a filming rig / refresh it (run on the 5090, Git Bash).
#  1. helpers -> C:\KAH: itrun.ps1 (desktop-session runner), kcfg.ps1 (windowed 1600x900 test cfg), bin\python3 shim
#  2. the repo files takes use -> the same paths under C:\KenshiModding on the 4080: tools/automation/rig-env.sh,
#     components/KenshiFP/animlab (scripts, rules), components/KenshiFP/tests/ingame/*.sh|*.py,
#     Kenshi-Automation-Harness/client/kah.py + tools/animlab/*.py
#  3. each run dir given (e.g. f36 f38 f24 f26) -> C:\KenshiTestRuns\<dir> on the 4080: scripts and small text/png only
#     (no mp4, no raw frames)
#  4. --saves: copy those save folders from this PC's %LOCALAPPDATA%\kenshi\save to the 4080's (replaces them)
# Kenshi may run on the 4080 meanwhile (no DLL is touched). Never run while a 4080 take is running (it replaces its scripts).
set -e
M=/c/KenshiModding; R=/c/KenshiTestRuns; H=4080; HERE=$M/tools/automation/rig4080
SAVES=""; [ "$1" = --saves ] && { SAVES=$2; shift 2; }
ssh $H 'mkdir C:\KAH\bin C:\KenshiModding\tools\automation C:\KenshiModding\components\KenshiFP\animlab C:\KenshiModding\components\KenshiFP\tests\ingame C:\KenshiModding\Kenshi-Automation-Harness\client C:\KenshiModding\Kenshi-Automation-Harness\tools\animlab 2>NUL & exit 0'
scp -q "$HERE/itrun.ps1" "$HERE/kcfg.ps1" $H:C:/KAH/
scp -q "$HERE/python3" $H:C:/KAH/bin/python3
scp -q "$M/tools/automation/rig-env.sh" $H:C:/KenshiModding/tools/automation/
scp -q "$M"/components/KenshiFP/animlab/*.sh "$M"/components/KenshiFP/animlab/*.py "$M"/components/KenshiFP/animlab/*.txt $H:C:/KenshiModding/components/KenshiFP/animlab/
scp -q "$M"/components/KenshiFP/tests/ingame/*.sh "$M"/components/KenshiFP/tests/ingame/*.py $H:C:/KenshiModding/components/KenshiFP/tests/ingame/
scp -q "$M/Kenshi-Automation-Harness/client/kah.py" $H:C:/KenshiModding/Kenshi-Automation-Harness/client/
scp -q "$M"/Kenshi-Automation-Harness/tools/animlab/*.py $H:C:/KenshiModding/Kenshi-Automation-Harness/tools/animlab/
for d in "$@"; do
  ssh $H "mkdir C:\\KenshiTestRuns\\$d 2>NUL & exit 0"
  ( cd "$R/$d" && ls | grep -E '\.(sh|py|txt|awk|ttf)$' | grep -v -E '^(ts|s3ts|ev|s3ev)\.txt' | tr '\n' '\0' | xargs -0 -r -I{} scp -q {} "$H:C:/KenshiTestRuns/$d/" )
done
for s in $SAVES; do
  ssh $H "powershell -NoProfile -Command \"Remove-Item -Recurse -Force \$env:LOCALAPPDATA\\kenshi\\save\\$s -EA 0\""
  scp -q -r "/c/Users/Shay/AppData/Local/kenshi/save/$s" "$H:AppData/Local/kenshi/save/"
done
echo "4080 rig synced: helpers, repo files, run dirs [$*], saves [$SAVES]"
