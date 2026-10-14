#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
python3 /mnt/c/KenshiModding/tools/stobe-auto where Ginkin
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_state '#3947387648/1'
python3 /mnt/c/KenshiModding/tools/stobe-auto where 'Jonin Kacey'
python3 /mnt/c/KenshiModding/tools/stobe-auto stobe_state '#3169311488/2'
