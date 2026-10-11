#!/bin/bash
# fp-e6-tables.sh <out dir> <name> <tables file> [strokes] [reps]   (WSL/4080 bash; stobe-auto on PATH; Kenshi running)
# sword-judge 2026-10-11: film the E6 sword strokes (fp-e6-strokes.sh: sword only, crossbow crash guard, preflight, lab
# checks, one RESULT line) with a live-tables variant loaded first (`fp_tables load`, no rebuild). A load that fails or
# reports bad lines = one `RESULT E6-<name> FAIL setup:` line and no take. The variant stays loaded after the take (a
# following live-tune row in the same list starts from it); `LT_RESET=1` resets the tables at the end instead.
HERE=$(cd "$(dirname "$0")" && pwd); N=${2:-e6tab}; TF=$3
case "$TF" in /mnt/[a-zA-Z]/*) W="${TF:5:1}:/${TF:7}";; /[a-zA-Z]/*) W="${TF:1:1}:/${TF:3}";; *) W=$TF;; esac
[ -f "$TF" ] || { echo "RESULT E6-$N FAIL setup: tables file missing $TF"; exit 1; }
r=$(stobe-auto fp_tables load "$W" </dev/null 2>&1)
echo "$r" | grep -q ' bad=0' && echo "$r" | grep -q 'hash=' || { echo "RESULT E6-$N FAIL setup: fp_tables load $W: $(echo "$r" | tr '\n' ' ' | cut -c1-160)"; exit 1; }
echo "note: tables loaded: $(echo "$r" | grep -o 'hash=[0-9a-f]*' | head -1) file=$W"
set -- "$1" "$2" "${@:4}"
# LT_RESET=1: reset BEFORE the game is released (pf_game_done runs PF_PRE_DONE), never after the background analysis (it
# raced the next row's fp_tables load, 105f); the trailing reset only covers takes that stopped before pf_game_done.
MK=$(mktemp); rm -f "$MK"
[ "${LT_RESET:-0}" = 1 ] && export PF_PRE_DONE="stobe-auto fp_tables reset </dev/null >/dev/null 2>&1" PF_PRE_DONE_MARK="$MK"
bash "$HERE/fp-e6-strokes.sh" "$@"; rc=$?
[ "${LT_RESET:-0}" = 1 ] && [ ! -e "$MK" ] && stobe-auto fp_tables reset </dev/null >/dev/null 2>&1; rm -f "$MK"
exit $rc
