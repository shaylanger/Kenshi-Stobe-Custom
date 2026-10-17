#!/usr/bin/env bash
# hxrun_02bd3.sh (imm26-fix02dxroute): hxrun_02bd.sh unchanged except the assert dir = v3 (v3/assert_principle.py 02-bx AND 02-dx skip an echo of the request before the refusal).
# Same argv/exit codes as hxrun_02bd.sh.  New file; hxrun_02bd.sh (v2 asserters) is not edited.
HX_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HX_ASSERT_DIR="${HX_ASSERT_DIR:-$(cd "$HX_HERE/../v3" && pwd)}"
exec bash "$HX_HERE/hxrun_02bd.sh" "$@"
