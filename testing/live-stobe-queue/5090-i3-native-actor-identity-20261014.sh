#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
python3 /mnt/c/KenshiModding/tools/stobe-auto status
python3 /mnt/c/KenshiModding/tools/stobe-auto where Xiaomei
python3 /mnt/c/KenshiModding/tools/stobe-auto where '#3393676800/1'
python3 /mnt/c/KenshiModding/tools/stobe-auto where Quant
python3 /mnt/c/KenshiModding/tools/stobe-auto where '#3796630784/2'
python3 /mnt/c/KenshiModding/tools/stobe-auto input_isolation status