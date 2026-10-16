#!/bin/bash
# tail-autorelay.sh <tail-session-id> [extra tail-autorelay.ps1 args]: background wrapper (PI-25). Run it with run_in_background right after `tail-mode.ps1 enter`.
[ -n "$1" ] || { echo "usage: tail-autorelay.sh <tail-session-id> [-PollSec n] [-MaxMinutes n] [-Skip a,b]"; exit 2; }
sess="$1"; shift
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\KenshiModding\tools\automation\tail-autorelay.ps1" -TailSession "$sess" "$@"
