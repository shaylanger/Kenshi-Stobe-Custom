#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
python3 /mnt/c/KenshiModding/tools/stobe-auto where Harf
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_state Harf
python3 /mnt/c/KenshiModding/tools/stobe-auto towns 'Armoury Ruin Greyshelf N' max 2