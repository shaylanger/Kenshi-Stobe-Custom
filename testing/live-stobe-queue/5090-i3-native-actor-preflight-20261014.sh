#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
[[ $(hostname | tr '[:lower:]' '[:upper:]') == DESKTOP-JFLPK99 ]] || exit 1
python3 /mnt/c/KenshiModding/tools/stobe-auto status
python3 /mnt/c/KenshiModding/tools/stobe-auto input_isolation status
python3 /mnt/c/KenshiModding/tools/stobe-auto time
python3 /mnt/c/KenshiModding/tools/stobe-auto where @player
python3 /mnt/c/KenshiModding/tools/stobe-auto chars 100
python3 /mnt/c/KenshiModding/tools/stobe-auto currentTown