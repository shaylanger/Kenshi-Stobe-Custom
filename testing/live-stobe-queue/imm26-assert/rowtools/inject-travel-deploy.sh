#!/usr/bin/env bash
# inject-travel-deploy.sh (imm26-sfTrav): install the travel PROPOSE test seam into isolated lane sites (one guarded call in processor/chat.php +
# lib/imm26_travel_test_inject.php; inert without a lane marker). Independent of inject-propose-deploy.sh (sfO activity seam); run both after a lane-deploy.
# lane-deploy.sh REMOVES the seam (it replaces the tree): rerun this after EVERY lane-deploy. PHP opcache picks the change up within ~1 min; no restart needed.
#   inject-travel-deploy.sh <lane> [<lane> ...]      lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4 (lane.sh), or `all`
#   inject-travel-deploy.sh --check <lane> ...       report only
# Per lane: refuses anything not /tmp/stobe-*/site, backs up processor/chat.php to <lane>/bak-pre-sfTrav/, applies apply.py (anchor-asserted, idempotent),
# php -l both files, copies tests/imm26_sfTrav_inject_travel.php, prints `DEPLOY <lane> OK|FAIL ...`. Files travel inside the command (works over ssh to the 4080).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$(cd "$HERE/../../../../pending-fixes/imm26-sfTrav" && pwd)"
. "$HERE/lane.sh"
CHECK=0; [ "${1:-}" = --check ] && { CHECK=1; shift; }
[ $# -ge 1 ] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
lanes="$*"; [ "$lanes" = all ] && lanes="$(lt_lanes)"
b_inj=$(base64 -w0 "$FIX/imm26_travel_test_inject.php"); b_app=$(base64 -w0 "$FIX/apply.py"); b_tst=$(base64 -w0 "$FIX/imm26_sfTrav_inject_travel.php")
rc=0
for l in $lanes; do
  lt_load "$l" >/dev/null || { echo "DEPLOY $l FAIL unknown lane"; rc=2; continue; }
  lt_w <<EOF
R=$LT_ROOT; S=\$R/site
case "\$S" in /tmp/stobe-*/site) ;; *) echo "DEPLOY $l FAIL refuse \$S"; exit 2;; esac
[ -f "\$S/processor/chat.php" ] || { echo "DEPLOY $l FAIL no processor/chat.php"; exit 2; }
d=\$(mktemp -d); echo '$b_app' | base64 -d > \$d/apply.py; echo '$b_inj' | base64 -d > \$d/imm26_travel_test_inject.php; echo '$b_tst' | base64 -d > \$d/imm26_sfTrav_inject_travel.php
if [ $CHECK = 1 ]; then python3 \$d/apply.py "\$S" --check | sed "s|^|DEPLOY $l |"; rm -rf \$d; exit 0; fi
mkdir -p "\$R/bak-pre-sfTrav"; [ -e "\$R/bak-pre-sfTrav/chat.php" ] || cp -p "\$S/processor/chat.php" "\$R/bak-pre-sfTrav/chat.php"
python3 \$d/apply.py "\$S" && cp \$d/imm26_travel_test_inject.php "\$S/lib/imm26_travel_test_inject.php" && cp \$d/imm26_sfTrav_inject_travel.php "\$S/tests/" \
 && php -l "\$S/processor/chat.php" >/dev/null && php -l "\$S/lib/imm26_travel_test_inject.php" >/dev/null \
 && echo "DEPLOY $l OK (\$(sha256sum "\$S/lib/imm26_travel_test_inject.php" | cut -c1-12) / chat.php \$(sha256sum "\$S/processor/chat.php" | cut -c1-12))" || { echo "DEPLOY $l FAIL (backup in \$R/bak-pre-sfTrav)"; rm -rf \$d; exit 1; }
rm -rf \$d
EOF
  [ $? = 0 ] || rc=1
done
exit $rc
