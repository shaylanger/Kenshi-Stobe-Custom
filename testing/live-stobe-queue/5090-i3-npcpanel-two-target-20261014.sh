#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_npcinfo open Ginkin Shay
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_npcinfo read
python3 /mnt/c/KenshiModding/tools/stobe-auto screenshot kah-npcpanel-5090-i3-ginkin-20261014
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_npcinfo open Persut Shay
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_npcinfo read
python3 /mnt/c/KenshiModding/tools/stobe-auto screenshot kah-npcpanel-5090-i3-persut-20261014
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_npcinfo close
python3 /mnt/c/KenshiModding/tools/stobe-auto input_isolation status