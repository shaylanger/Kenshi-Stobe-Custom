#!/usr/bin/env bash
# next-row.sh <lane> [--n N] [--ids] [--claim] [--cards]   the next claimable row for a lane (5090-i3 5090-i4 5090-i5 4080-i3 4080-i4) as ONE card (<= 600 chars)
# + one "also:" line. Order: inbox\operators\<lane>-ready-<row>.txt, newest lane handoff TODO ids, the lane queue in the newest lane-plan, other open rows with a
# runner. Skips PASS rows and claimed rows (claims\<row>); rows whose last attempt on the lane failed (PI-06) or GATED rows come last, flagged.
# --claim mkdir's claims\<row> for the first free candidate (the lane-plan claim rule) and prints CLAIMED <row>. Read-only otherwise. Impl: rowcard.py.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
[ -n "$1" ] || { sed -n 2,5p "$0" | cut -c1-220; exit 2; }
exec "$PY" -I "$HERE/rowcard.py" next "$@"
