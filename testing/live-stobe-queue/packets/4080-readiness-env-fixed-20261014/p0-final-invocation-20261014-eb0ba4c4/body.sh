export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight

# Before invocation, refresh these two source paths with current native receipts.
# Actor gate: exact name Cind [Hungry Bandit], serial 2529907200/2; player Shay.
# Destination gate: The Hub, catalog ordinal 378 (not a candidateID).
: "${FRESH_PREFLIGHT_RECEIPT:?set to the newly captured native actor/session receipt}"
: "${FRESH_DESTINATION_RECEIPT:?set to the newly captured native destination receipt}"
test -f "$FRESH_PREFLIGHT_RECEIPT"
test -f "$FRESH_DESTINATION_RECEIPT"
grep -Fq 'Cind [Hungry Bandit]' "$FRESH_PREFLIGHT_RECEIPT"
grep -Fq '2529907200/2' "$FRESH_PREFLIGHT_RECEIPT"
grep -Fq 'The Hub' "$FRESH_DESTINATION_RECEIPT"

PARENT='/c/KenshiTestRuns/stobe-validation/4080-p0-current-driver-20261014-final'
mkdir "$PARENT"  # atomic unique claim; fail if this package parent already exists
mkdir "$PARENT/receipts"
cp "$FRESH_PREFLIGHT_RECEIPT" "$PARENT/receipts/preflight.receipt.md"
cp "$FRESH_DESTINATION_RECEIPT" "$PARENT/receipts/destination.receipt.md"
cp '/c/KenshiModding/testing/live-stobe-queue/packets/4080-readiness-env-fixed-20261014/p0-final-invocation-20261014-eb0ba4c4/receipts/preflight-historical.md' "$PARENT/receipts/"
cp '/c/KenshiModding/testing/live-stobe-queue/packets/4080-readiness-env-fixed-20261014/p0-final-invocation-20261014-eb0ba4c4/receipts/destination-historical.md' "$PARENT/receipts/"
export NPC='Cind [Hungry Bandit]' TRAVEL_DESTINATION='The Hub'
export OUT='C:/KenshiTestRuns/stobe-validation/4080-p0-current-driver-20261014-final/run'
export NATIVE_LOG='C:/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log'
export PREFLIGHT_RECEIPT='C:/KenshiTestRuns/stobe-validation/4080-p0-current-driver-20261014-final/receipts/preflight.receipt.md'
export DESTINATION_RECEIPT='C:/KenshiTestRuns/stobe-validation/4080-p0-current-driver-20261014-final/receipts/destination.receipt.md'
export ROW_ID='P0-TRAVEL-START-MOVE-4080-001'
export TRAVEL_DRIVER_BASH='C:/Program Files/Git/bin/bash.exe'
export WAIT_SECONDS=300 POLL_SECONDS=5
DRIVER_DIR='/c/KenshiModding/testing/live-stobe-queue/packets/4080-readiness-env-fixed-20261014/p0-final-invocation-20261014-eb0ba4c4'
test ! -e "$OUT"  # driver.py alone atomically creates OUT after receipt checks
test "$(command -v python3)" = '/c/KAH/bin/python3'
"$TRAVEL_DRIVER_BASH" "$DRIVER_DIR/driver.sh"
