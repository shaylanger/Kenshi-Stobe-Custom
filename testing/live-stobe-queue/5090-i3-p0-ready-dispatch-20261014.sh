#!/usr/bin/env bash
# Sole operator dispatch. Run only after explicit current provider release.
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
: "${PROVIDER_RELEASE_RECEIPT:?Set actual current provider release receipt path}"
: "${CURRENT_BUILD_RECEIPT:?Set freshly verified mapped native build and manifest receipt}"
: "${CURRENT_AUTH_RECEIPT:?Set genuine current session READY receipt}"
[[ -f "$PROVIDER_RELEASE_RECEIPT" && -f "$CURRENT_BUILD_RECEIPT" && -f "$CURRENT_AUTH_RECEIPT" ]] || exit 1
grep -q 'provider_hold_released=true' "$PROVIDER_RELEASE_RECEIPT"
grep -q 'request_active=false' "$PROVIDER_RELEASE_RECEIPT"
grep -q '^provider_profile=' "$PROVIDER_RELEASE_RECEIPT"
grep -q '^provider_model_sha256=' "$PROVIDER_RELEASE_RECEIPT"
grep -q '^provider_release_utc=' "$PROVIDER_RELEASE_RECEIPT"
grep -qi 'AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C' "$CURRENT_BUILD_RECEIPT"
grep -qi '974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D' "$CURRENT_BUILD_RECEIPT"
grep -qi '54BBB7DF235BA851D4341B9B49B0AB7589C0B6BC0C0EB3A542A3B1B3E3BB7FE7' "$CURRENT_BUILD_RECEIPT"
grep -q 'session_ready=true' "$CURRENT_AUTH_RECEIPT"
grep -q 'token_length=32' "$CURRENT_AUTH_RECEIPT"
grep -q 'manager_ready_generation_match=true' "$CURRENT_AUTH_RECEIPT"
root=/mnt/c/KenshiModding
driver="$root/testing/live-stobe-queue/current-build-travel-driver"
[[ $(sha256sum "$driver/driver.py" | cut -d' ' -f1) == eb0ba4c4f3b3f7091d1a8ed79e7ccd356823b23850b6b6885172c6b366213c70 ]] || exit 1
auto=(python3 "$root/tools/stobe-auto")
prep=$(mktemp -d /tmp/5090-i3-p0-preflight.XXXXXX)
"${auto[@]}" status | tee "$prep/world.txt"
grep -q 'phase=world save=kah-5090c-ui-20261014.*paused=0' "$prep/world.txt"
"${auto[@]}" input_isolation status | tee "$prep/isolation.txt"
grep -q 'isolation=on' "$prep/isolation.txt"
grep -q 'focused=0' "$prep/isolation.txt"
"${auto[@]}" where Ginkin | tee "$prep/where-before-player-position.txt"
# Move only the copied player; never order, pin, or teleport the target NPC.
"${auto[@]}" teleport Shay Ginkin | tee "$prep/copied-player-position.txt"
"${auto[@]}" where Ginkin | tee "$prep/where-current.txt"
"${auto[@]}" stobe_state '#3947387648/1' | tee "$prep/state-current.txt"
"${auto[@]}" towns 'Armoury Ruin Greyshelf N' max 5 | tee "$prep/destination.txt"
cat "$prep/world.txt" "$prep/isolation.txt" "$prep/where-current.txt" "$prep/state-current.txt" "$prep/destination.txt" "$CURRENT_BUILD_RECEIPT" "$CURRENT_AUTH_RECEIPT" "$PROVIDER_RELEASE_RECEIPT" > "$prep/preflight.txt"
export NPC=Ginkin TRAVEL_DESTINATION='Armoury Ruin Greyshelf N'
export PREFLIGHT_RECEIPT="$prep/preflight.txt" DESTINATION_RECEIPT="$prep/destination.txt"
export NATIVE_LOG=/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log
export OUT="$prep/start-movement" WAIT_SECONDS=180 POLL_SECONDS=3
bash "$driver/driver.sh"
printf 'receipt_dir=%s\n' "$prep"
