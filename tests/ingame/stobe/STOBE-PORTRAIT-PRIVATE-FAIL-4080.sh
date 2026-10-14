#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/portrait-row-lib.sh"
portrait_integrity_preflight STOBE-PRT-4080-PRIVATE-FAIL-NATIVE "$0"
portrait_fault_setup_block STOBE-PRT-4080-PRIVATE-FAIL-NATIVE 4080 3 "${PORTRAIT_SAVE:-kah-stobe-travel-validation-20261013}" "${PORTRAIT_ACTOR:-Malzin}" Shay private
