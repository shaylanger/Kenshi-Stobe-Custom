#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
python3 /mnt/c/KenshiModding/tools/stobe-auto key_inject / tap 120
python3 /mnt/c/KenshiModding/tools/stobe-auto ui tree Stobe_ChatWindow up 0 || true
python3 /mnt/c/KenshiModding/tools/stobe-auto screenshot kah-int-001-5090-i3-20261014-02-close
python3 /mnt/c/KenshiModding/tools/stobe-auto chars 100