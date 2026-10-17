#!/bin/bash
# fix26ffix-selftest.sh [checker]: OFFLINE. Real 4080-i4 op19 evidence (pending-fixes/imm26-fix26ffix/fixture) must be judged by the REAL reason, not by the per-member
# ACTIVITY_CAMP_DIAG group_targets_rejected noise. Old reloadcheck_sfe.py -> message blames requester_now_hostile (check fails); reloadcheck_sfe.py.candidate2 -> passes.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; C="${1:-$H/reloadcheck_sfe.py.candidate2}"; FX="$H/../../../../pending-fixes/imm26-fix26ffix/fixture"
T=$(mktemp -d); fails=0
run() { python3 - "$H" "$C" "$1" <<'PYEOF' 2>&1 | head -1
import sys
from importlib.machinery import SourceFileLoader
from importlib.util import spec_from_loader, module_from_spec
sys.path.insert(0, sys.argv[1])
s = spec_from_loader('reloadcheck_sfe', SourceFileLoader('reloadcheck_sfe', sys.argv[2])); m = module_from_spec(s); s.loader.exec_module(m)
sys.exit(m.main(['x', '26-f', sys.argv[3]]))
PYEOF
}
chk() { if [ "$2" = ok ]; then echo "PASS $1"; else echo "FAIL $1 $3"; fails=$((fails+1)); fi; }
r=$(run "$FX")
echo "$r" | grep -q '^RESULT 26-f SETUP-FAIL' && chk setup-fail-kind ok || chk setup-fail-kind bad "$r"
echo "$r" | grep -q 'No currently grounded route candidate' && echo "$r" | grep -q 'carried a campZone' && chk names-real-server-reason ok || chk names-real-server-reason bad "$r"
echo "$r" | grep -q 'requester_now_hostile' && chk no-wrong-26a-blame bad "$r" || chk no-wrong-26a-blame ok
# an accepted record still goes through the unchanged c_job (no assertion weakened): without server.txt the old message is kept
mkdir -p "$T/ev2"; cp -r "$FX"/. "$T/ev2/"; rm -f "$T/ev2/s2/server.txt"
r2=$(run "$T/ev2"); echo "$r2" | grep -q 'known blocker 26-a' && chk no-server-line-keeps-old-path ok || chk no-server-line-keeps-old-path bad "$r2"
rm -rf "$T"; echo "fix26ffix-selftest: fails=$fails"; [ "$fails" = 0 ]
