#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
[[ -f /mnt/d/KenshiInst/3/save/kah-5090c-ui-20261014/quick.save ]] || exit 1
python3 /mnt/c/KenshiModding/tools/stobe-auto load kah-5090c-ui-20261014
python3 /mnt/c/KenshiModding/tools/stobe-auto wait-world 90
python3 /mnt/c/KenshiModding/tools/stobe-auto status
python3 /mnt/c/KenshiModding/tools/stobe-auto select Shay
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_ping
python3 /mnt/c/KenshiModding/tools/stobe-auto input_isolation status