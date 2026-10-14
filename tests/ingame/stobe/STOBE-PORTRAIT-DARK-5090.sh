#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/portrait-row-lib.sh"
ROW=STOBE-PRT-5090-DARK
SAVE="${PORTRAIT_SAVE:-kah-profile-5090-20261013}"
ACTOR="${PORTRAIT_ACTOR:-Malzin}"
SPEAKER=Shay
portrait_integrity_preflight "$ROW" "$0"
portrait_preflight "$ROW" 5090 1 "$SAVE" "$ACTOR" "$SPEAKER"
portrait_open_capture "$ROW" "$ACTOR" "$SPEAKER" 0 yes
