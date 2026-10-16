#!/usr/bin/env bash
# logwin.sh <log> <pattern|since:<regex>|at:HH:MM:SS[+SEC]> [maxchars=2500]   filtered window into stobe.log / harness.log / stobeserver.log with a built-in noise
# filter (TOWNS_DIAG CAMP_DIAG SIGHT_DIAG CHAT_SEND_STAGE HOOK_MSG EVENT_STREAM SOCIAL_CAPTURE ...) and a hard cap. RESULT / SETUP-FAIL / PREFLIGHT-FAIL lines are
# never dropped or cut by the cap; when the cap bites the footer prints the omitted counts, the FULL filtered output file and the source log path.
# Env: LOGWIN_AND=<regex> LOGWIN_KEEP_NOISE=1 LOGWIN_I=1 LOGWIN_CUT=220 LOGWIN_SCAN_MB=128. Full help: python -I logwin.py. Impl: logwin.py.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
[ $# -ge 2 ] || { sed -n 2,5p "$0" | cut -c1-230; exit 2; }
exec "$PY" -I "$HERE/logwin.py" "$@"
