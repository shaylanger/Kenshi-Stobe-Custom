export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
test -d /c/Users/Shay/AppData/Local/kenshi/save/kah-stobe-4080-standalone-active
test -s /c/Users/Shay/AppData/Local/kenshi/save/kah-stobe-4080-standalone-active/quick.save
printf '=== EXISTING COPIED TEST SAVE ===\n'
sha256sum /c/Users/Shay/AppData/Local/kenshi/save/kah-stobe-4080-standalone-active/quick.save
printf '=== PRELOAD WORLD ===\n'
timeout 10 stobe-auto status </dev/null
printf '=== LOAD EXISTING COPIED TEST SAVE ===\n'
timeout 15 stobe-auto load kah-stobe-4080-standalone-active </dev/null
timeout 50 stobe-auto wait-world 45 </dev/null
printf '=== POSTLOAD WORLD ===\n'
timeout 10 stobe-auto status </dev/null
