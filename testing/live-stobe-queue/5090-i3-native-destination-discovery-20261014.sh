#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
python3 /mnt/c/KenshiModding/tools/stobe-auto towns 'Squin,Stenn,Spring,Black Scratch,ruin' max 12
python3 /mnt/c/KenshiModding/tools/stobe-auto buildings 600 iron
python3 /mnt/c/KenshiModding/tools/stobe-auto chars 300 '!ko|!dead'
python3 /mnt/c/KenshiModding/tools/stobe-auto status