#!/usr/bin/env bash
# Prove the 4080 i3 helper patch fills the exact committed-HEAD gap, then run
# the route/fail-closed checks against the patched temporary copy only.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
PATCH="$ROOT/testing/live-stobe-queue/4080-i3-rig-env-helper.patch"
SELFTEST="$ROOT/tools/automation/rig4080/instance-route-selftest.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kah-i3-candidate.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/head/tools/automation" "$TMP/candidate/tools/automation"
git -C "$ROOT" show HEAD:tools/automation/rig-env.sh > "$TMP/head/tools/automation/rig-env.sh"
git -C "$ROOT" show HEAD:tools/automation/venc.sh > "$TMP/head/tools/automation/venc.sh"
cp "$TMP/head/tools/automation/rig-env.sh" "$TMP/candidate/tools/automation/rig-env.sh"
cp "$TMP/head/tools/automation/venc.sh" "$TMP/candidate/tools/automation/venc.sh"

set +e
KAH_RIG_ENV_FILE="$TMP/head/tools/automation/rig-env.sh" bash "$SELFTEST" >"$TMP/head.out" 2>&1
head_rc=$?
set -e
if [[ $head_rc -eq 0 ]] || ! grep -q 'rig4080_i3_preflight: command not found' "$TMP/head.out"; then
  cat "$TMP/head.out" >&2
  echo 'HEAD regression expectation failed: missing-helper failure was not reproduced' >&2
  exit 1
fi

git -C "$ROOT" apply --unsafe-paths --directory="$TMP/candidate" "$PATCH"
KAH_RIG_ENV_FILE="$TMP/candidate/tools/automation/rig-env.sh" bash "$SELFTEST"
echo 'RESULT 4080-I3-CANDIDATE-SELFTEST PASS head_missing_helper=1 patched_route=1 inbox_lock_preserved=2'
