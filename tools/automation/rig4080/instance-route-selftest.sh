#!/usr/bin/env bash
# Offline 4080/i3 route guard regression. Uses a fake cygpath/Python and temp
# harness; never invokes a real KAH client, rig, game, or inbox.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ENV_FILE="${KAH_RIG_ENV_FILE:-$ROOT/tools/automation/rig-env.sh}"
SHIM="$ROOT/tools/automation/rig4080/stobe-auto"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kah-i3-route.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/harness"

cat >"$TMP/bin/cygpath" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$KAH_TEST_HARNESS"
MOCK
cat >"$TMP/bin/python" <<'MOCK'
#!/usr/bin/env bash
printf 'PYTHON_CALLED KAH_INSTANCE=%s KENSHI_DIR=%s KAH_DIR=%s argv=%s\n' \
  "${KAH_INSTANCE:-}" "${KENSHI_DIR:-}" "${KAH_DIR:-}" "$*"
MOCK
chmod +x "$TMP/bin/cygpath" "$TMP/bin/python"
export PATH="$TMP/bin:$PATH" KAH_TEST_HARNESS="$TMP/harness"

route_env() {
  # Exercise the same payload transport as 4080-i3-command-route.md. This
  # catches a missing helper in the sourced rig-env.sh before any remote row.
  local body payload
  body=$(printf 'export RIG=4080 KAH_INSTANCE=3\n. %q\nrig4080_i3_preflight || exit $?\n' "$ENV_FILE")
  payload=$(printf '%s' "$body" | base64 -w0)
  env PATH="$PATH" KAH_TEST_HARNESS="$KAH_TEST_HARNESS" \
    bash -c 'printf "%s" "$1" | base64 -d | bash -s' _ "$payload"
}

preflight=$(route_env)
[[ "$preflight" == *'KAH_INSTANCE=3'* &&
   "$preflight" == *'KENSHI_DIR=/c/KenshiInst/3'* &&
   "$preflight" == *'KDIR=/c/KenshiInst/3'* &&
   "$preflight" == *'KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness'* &&
   "$preflight" == *'RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only'* ]] || {
  printf 'route preflight output mismatch: %s\n' "$preflight" >&2; exit 1;
}

_run_shim() {
  env PATH="$PATH" KAH_TEST_HARNESS="$KAH_TEST_HARNESS" "$@" bash "$SHIM" status
}

valid=$( _run_shim KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3 'KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness' )
[[ "$valid" == *'PYTHON_CALLED KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3'* &&
   "$valid" == *'argv=C:/KAH/client/kah.py status'* ]] || {
  printf 'valid i3 route did not reach fake client: %s\n' "$valid" >&2; exit 1;
}

_expect_reject() {
  set +e
  rejected=$( _run_shim "$@" 2>&1 )
  rc=$?
  set -e
  [[ $rc -eq 2 && "$rejected" == *'refusing'* && "$rejected" != *'PYTHON_CALLED'* ]] || {
    printf 'unsafe route was not rejected (rc=%s): %s\n' "$rc" "$rejected" >&2; exit 1;
  }
}
_expect_reject KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3
_expect_reject KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3 'KAH_DIR=C:\Program Files (x86)\Steam\steamapps\common\Kenshi\mods\AutomationHarness'
_expect_reject KENSHI_DIR=/c/KenshiInst/3 'KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness'

for pending in inbox.txt inbox.txt.lock; do
  printf 'preserve-me\n' >"$TMP/harness/$pending"
  before=$(sha256sum "$TMP/harness/$pending" | awk '{print $1}')
  set +e
  stopped=$(route_env 2>&1)
  rc=$?
  set -e
  after=$(sha256sum "$TMP/harness/$pending" | awk '{print $1}')
  [[ $rc -eq 3 && "$stopped" == *'STOP inbox pending or locked'* && "$before" == "$after" ]] || {
    printf 'pending %s was not preserved/fail-closed (rc=%s): %s\n' "$pending" "$rc" "$stopped" >&2; exit 1;
  }
  set +e
  rejected=$( _run_shim KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3 'KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness' 2>&1 )
  rc=$?
  set -e
  after_shim=$(sha256sum "$TMP/harness/$pending" | awk '{print $1}')
  [[ $rc -eq 3 && "$rejected" == *'refusing without reading or changing it'* && "$after_shim" == "$before" ]] || {
    printf 'shim did not preserve pending %s (rc=%s): %s\n' "$pending" "$rc" "$rejected" >&2; exit 1;
  }
  rm -f "$TMP/harness/$pending"
done

echo 'RESULT 4080-I3-ROUTE-SELFTEST PASS cases=8 checks=9 fail_closed=7 inbox_preserved=2 fake_client_only=1'
