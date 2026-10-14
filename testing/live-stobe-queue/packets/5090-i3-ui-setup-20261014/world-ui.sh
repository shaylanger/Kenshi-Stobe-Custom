#!/usr/bin/env bash
# Candidate: exact i3 KAH world/UI setup only; no backend/session/NPC/chat operation.
set -euo pipefail
export RIG=5090
export KAH_INSTANCE=3
export KENSHI_DIR=/mnt/d/KenshiInst/3
export KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
[[ $(hostname | tr '[:lower:]' '[:upper:]') == DESKTOP-JFLPK99 ]] || { echo 'FAIL setup: wrong host'; exit 1; }
[[ $(sha256sum /mnt/c/KenshiModding/tools/stobe-auto | cut -d' ' -f1) == b808e14f1f88c014fdd715eb860ab488a049e121f9452f08c5c4c746e05bfad9 ]] || { echo 'FAIL setup: official KAH wrapper changed'; exit 1; }
python3 /mnt/c/KenshiModding/tools/stobe-auto wait-world
python3 /mnt/c/KenshiModding/tools/stobe-auto status
python3 /mnt/c/KenshiModding/tools/stobe-auto time
python3 /mnt/c/KenshiModding/tools/stobe-auto input_isolation on
python3 /mnt/c/KenshiModding/tools/stobe-auto input_isolation status
echo 'SETUP_OUTPUT_ONLY gameplay_result=UNPROVEN backend_session=NOT_REQUIRED_LOCAL_UI'
