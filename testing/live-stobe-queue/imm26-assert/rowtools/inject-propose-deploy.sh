#!/usr/bin/env bash
# inject-propose-deploy.sh (imm26-sfO): install the activity PROPOSE test seam into isolated lane sites (one guarded call in ActivityChat.php +
# lib/activity/ActivityTestInject.php; inert without a lane marker). The coordinator/operator runs this ONCE per lane while the lane's Kenshi is closed
# or between rows (PHP opcache picks the change up within ~1 min; no restart needed).
#   inject-propose-deploy.sh <lane> [<lane> ...]      lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4 (lane.sh), or `all`
#   inject-propose-deploy.sh --check <lane> ...       report only
# Per lane: refuses anything not /tmp/stobe-*/site, backs up ActivityChat.php to <lane>/bak-pre-sfO/, applies apply.py (anchor-asserted, idempotent),
# php -l both files, copies tests/imm26_sfO_inject_propose.php, prints `DEPLOY <lane> OK|FAIL ...`. Files travel inside the command (works over ssh to the 4080).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$(cd "$HERE/../../../../pending-fixes/imm26-sfO" && pwd)"
. "$HERE/lane.sh"
CHECK=0; [ "${1:-}" = --check ] && { CHECK=1; shift; }
[ $# -ge 1 ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
lanes="$*"; [ "$lanes" = all ] && lanes="$(lt_lanes)"
b_inj=$(base64 -w0 "$FIX/ActivityTestInject.php"); b_app=$(base64 -w0 "$FIX/apply.py"); b_tst=$(base64 -w0 "$FIX/imm26_sfO_inject_propose.php")
rc=0
for l in $lanes; do
  lt_load "$l" >/dev/null || { echo "DEPLOY $l FAIL unknown lane"; rc=2; continue; }
  lt_w <<EOF
R=$LT_ROOT; S=\$R/site
case "\$S" in /tmp/stobe-*/site) ;; *) echo "DEPLOY $l FAIL refuse \$S"; exit 2;; esac
[ -f "\$S/lib/activity/ActivityChat.php" ] || { echo "DEPLOY $l FAIL no ActivityChat.php"; exit 2; }
d=\$(mktemp -d); echo '$b_app' | base64 -d > \$d/apply.py; echo '$b_inj' | base64 -d > \$d/ActivityTestInject.php; echo '$b_tst' | base64 -d > \$d/imm26_sfO_inject_propose.php
if [ $CHECK = 1 ]; then python3 \$d/apply.py "\$S" --check | sed "s|^|DEPLOY $l |"; rm -rf \$d; exit 0; fi
mkdir -p "\$R/bak-pre-sfO"; [ -e "\$R/bak-pre-sfO/ActivityChat.php" ] || cp -p "\$S/lib/activity/ActivityChat.php" "\$R/bak-pre-sfO/ActivityChat.php"
python3 \$d/apply.py "\$S" && cp \$d/ActivityTestInject.php "\$S/lib/activity/ActivityTestInject.php" && cp \$d/imm26_sfO_inject_propose.php "\$S/tests/" \
 && php -l "\$S/lib/activity/ActivityChat.php" >/dev/null && php -l "\$S/lib/activity/ActivityTestInject.php" >/dev/null \
 && echo "DEPLOY $l OK (\$(sha256sum "\$S/lib/activity/ActivityTestInject.php" | cut -c1-12) / ActivityChat \$(sha256sum "\$S/lib/activity/ActivityChat.php" | cut -c1-12))" || { echo "DEPLOY $l FAIL (backup in \$R/bak-pre-sfO)"; rm -rf \$d; exit 1; }
rm -rf \$d
EOF
  [ $? = 0 ] || rc=1
done
exit $rc
