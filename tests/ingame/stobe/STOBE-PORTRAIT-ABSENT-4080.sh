#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/portrait-row-lib.sh"
ROW=STOBE-PRT-4080-ABSENT-HEADGEAR
SAVE="${PORTRAIT_SAVE:-kah-stobe-travel-validation-20261013}"
ACTOR="${PORTRAIT_ABSENT_ACTOR:-Stennic}"
SPEAKER=Shay
portrait_integrity_preflight "$ROW" "$0"
portrait_preflight "$ROW" 4080 3 "$SAVE" "$ACTOR" "$SPEAKER"
items=$(portrait_equipped "$ACTOR")
[[ "$items" == *'Helm'* || "$items" == *'Hat'* || "$items" == *'Hood'* || "$items" == *'Mask'* ]] || \
  portrait_setup_fail "$ROW" "actor has no equipped headgear; cannot test absent attachment path actor=$ACTOR items=${items:0:220}"
portrait_open_capture "$ROW" "$ACTOR" "$SPEAKER" yes yes
