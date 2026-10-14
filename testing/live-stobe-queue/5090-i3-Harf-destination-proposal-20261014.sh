#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
python3 /mnt/c/KenshiModding/tools/stobe-auto status
python3 /mnt/c/KenshiModding/tools/stobe-auto where Harf
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_say Harf 'Do you know a place worth travelling to beyond Spring, perhaps the Armoury Ruin in Greyshelf? I am asking about a possible trip, not agreeing to start one yet.'