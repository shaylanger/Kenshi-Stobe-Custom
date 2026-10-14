#!/usr/bin/env bash
# Read-only route proof for direct 4080 instance-3 KAH commands.
# Does not invoke stobe-auto or read, write, clear, or consume inbox contents.
set -u

if [[ "${KAH_INSTANCE:-}" != 3 ]]; then
  echo 'RESULT 4080-I3-ROUTE FAIL setup: export KAH_INSTANCE=3 explicitly first' >&2
  exit 2
fi

export RIG=4080
_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_here/../rig-env.sh"

_want_game='/c/KenshiInst/3'
_want_harness='C:\KenshiInst\3\mods\AutomationHarness'
if [[ "$KDIR" != "$_want_game" || "$KENSHI_DIR" != "$_want_game" || "$KAH_DIR" != "$_want_harness" ]]; then
  printf 'KAH_INSTANCE=%s\nKENSHI_DIR=%s\nKDIR=%s\nKAH_DIR=%s\n' \
    "$KAH_INSTANCE" "$KENSHI_DIR" "$KDIR" "$KAH_DIR" >&2
  echo 'RESULT 4080-I3-ROUTE FAIL setup: instance paths do not resolve to C:\KenshiInst\3' >&2
  exit 2
fi

printf 'KAH_INSTANCE=%s\nKENSHI_DIR=%s (C:\\KenshiInst\\3)\nKDIR=%s (C:\\KenshiInst\\3)\nKAH_DIR=%s\n' \
  "$KAH_INSTANCE" "$KENSHI_DIR" "$KDIR" "$KAH_DIR"

_harness_unix=$(cygpath -u "$KAH_DIR") || {
  echo 'RESULT 4080-I3-ROUTE FAIL setup: cannot resolve isolated harness directory' >&2
  exit 2
}
if [[ -e "$_harness_unix/inbox.txt" || -e "$_harness_unix/inbox.txt.lock" ]]; then
  echo 'RESULT 4080-I3-ROUTE STOP inbox pending or locked; no contents read and no files changed' >&2
  exit 3
fi
if [[ ! -d "$_harness_unix" ]]; then
  echo 'RESULT 4080-I3-ROUTE FAIL setup: isolated harness directory is missing' >&2
  exit 2
fi
echo 'RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only'
