#!/usr/bin/env bash
# hxrun_v3cx.sh 01-cx <lane> [options]   (imm26-fix01cx) = hxrun_v2.sh for the row 01-cx, verdict from imm26-assert/v3cx/assert_stance.py (HX_ASSERT_DIR=v3cx):
#   hostile_guarded / allied_not_guarded judge the NPC's whole reply to the player's turn by content markers (v3cx docstring), not the regex over the first sentence.
#   Scene (hxdefs_a.sh rd_01cx), options and exit codes exactly as hxrun_v2.sh/hxrun.sh.  hxrun_v2.sh, hxdefs*.sh, hxcheck*.py and v2/* are NOT edited.
#   Offline selftest: python -I imm26-assert/v3cx/selftest_01cx.py
HX_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in 01-cx|IMM-01-cx) ;; *) echo "RESULT ${1:-?} SETUP-FAIL hxrun_v3cx.sh handles 01-cx only (use hxrun_v2.sh / hxrun_v3.sh for other rows)"; exit 2;; esac
export HX_ASSERT_DIR="$(cd "$HX_HERE/../v3cx" && pwd)"
exec bash "$HX_HERE/hxrun_v2.sh" "$@"
