#!/usr/bin/env bash
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
cmd(){ python3 /mnt/c/KenshiModding/tools/stobe-auto "$@"; }
cmd status
gate=$(cmd input_isolation status)
printf '%s\n' "$gate"
[[ "$gate" == isolation=on* && "$gate" == *focused=0* && "$gate" == *held=none* ]] || exit 20
baseline=$(cmd ui tree Stobe_ChatWindow up 0 2>&1 || true)
printf '%s\n' "$baseline"
[[ "$baseline" == *"no visible widget named or captioned 'Stobe_ChatWindow'"* ]] || exit 21
cmd key_inject / tap 120
cmd ui tree Stobe_ChatWindow up 0
cmd screenshot kah-int-001-5090-i3-20261014-01-open
cmd input_isolation status
