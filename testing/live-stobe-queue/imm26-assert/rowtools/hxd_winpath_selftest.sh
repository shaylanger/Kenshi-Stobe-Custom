#!/usr/bin/env bash
# hxd_winpath_selftest.sh: offline test of hxd_winpath (hxdefs.sh.candidate): bundle_dir.txt must hold a path the Windows verdict python can open (C:/..), imm26-inv01cx.
# Usage: bash rowtools/hxd_winpath_selftest.sh [hxdefs.sh|hxdefs.sh.candidate]   -> prints SELFTEST hxwp-<name> PASS|FAIL and SELFTEST HXWP ALL PASS|FAIL n/m
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; F="${1:-$H/hxdefs.sh.candidate}"; [ -f "$F" ] || F="$H/$F"
n=0; ok=0; chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST hxwp-$1 PASS ${3:-}"; else echo "SELFTEST hxwp-$1 FAIL ${3:-}"; fi; }
eval "$(sed -n '/^hxd_winpath() {/,/^}/p' "$F")"
declare -F hxd_winpath >/dev/null && chk defined ok || { chk defined bad "no hxd_winpath in $F"; echo "SELFTEST HXWP ALL FAIL $ok/$n"; exit 1; }
if grep -q 'hxd_winpath "$HXD" > "$EV/bundle_dir.txt"' "$F"; then chk cfg-uses-it ok; else chk cfg-uses-it bad; fi
# no cygpath (WSL / plain Linux): unchanged; stubbed cygpath: its output is used
cygpath() { return 1; }
r=$(hxd_winpath /tmp/x/rows/01-cx); [ "$r" = "/tmp/x/rows/01-cx" ] && chk no-cygpath-unchanged ok || chk no-cygpath-unchanged bad "$r"
cygpath() { [ "$1" = -m ] && echo "C:/KenshiTestRuns/stub"; }
r=$(hxd_winpath /c/KenshiTestRuns/stub); [ "$r" = "C:/KenshiTestRuns/stub" ] && chk cygpath-output-used ok || chk cygpath-output-used bad "$r"
unset -f cygpath
if command -v cygpath >/dev/null; then r=$(hxd_winpath /c/KenshiTestRuns/y); case "$r" in [A-Za-z]:/*) chk real-cygpath ok "$r";; *) chk real-cygpath bad "$r";; esac; fi
[ "$ok" = "$n" ] && echo "SELFTEST HXWP ALL PASS $ok/$n" || echo "SELFTEST HXWP ALL FAIL $ok/$n"
