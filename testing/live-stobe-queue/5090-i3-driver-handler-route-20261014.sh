#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
resolved=$(readlink -f "$(command -v stobe-auto)")
printf 'handler=%s\n' "$resolved"
sha256sum "$resolved"
sha256sum /mnt/c/KenshiModding/tools/stobe-auto
python3 /mnt/c/KenshiModding/tools/stobe-auto status