#!/bin/bash
# Offline tests for imm26-sfT (WSL). Usage: bash run-tests.sh [compose-root]
cd "${1:-/root/imm26/compose}" || exit 1
rc=0
for t in imm26_wpC2_followups_comm_regression imm26_batch3_regression imm26_batch2_followup_gate_regression imm26_batch4_bored_regression; do
  echo "== $t"
  STOBE_DB_NAME=stobe_test flock /tmp/stobe-tests.lock php tests/$t.php 2>&1 | tail -3
  [ "${PIPESTATUS[0]}" = 0 ] || rc=1
done
ls tests | grep -i "lifelike\|roster" | head
exit $rc
