#!/bin/bash
# install-lane-site.sh <lane_root> <pgport> <db>   (WSL; isolated imm26 lane site ONLY; refuses live paths)
# backs up code (tar) + DB (pg_dump), applies compose.patch onto site (i3 travel fix restored to base first), lints, migrates, restarts php backend
set -euo pipefail
BASE=${BASE:-/root/imm26/base}; COMPOSE=${COMPOSE:-/root/imm26/compose}; XTRA=${XTRA:-}
root=$1; pgport=$2; db=$3; patchf=${4:-$COMPOSE.patch}
case "$root" in /tmp/stobe-*) ;; *) echo "refuse root $root"; exit 2;; esac
site=$root/site; tag=bak-pre-compose-20261015
[ -d "$site" ] || { echo "no site"; exit 2; }
[ -e "$root/$tag.tar.gz" ] || tar czf "$root/$tag.tar.gz" -C "$root" --exclude=site/data/portraits --exclude=site/soundcache --exclude=site/log site
source "$root/env.sh"
[ -e "$root/$tag.sql.gz" ] || runuser -u postgres -- pg_dump -h "$root/socket" -p $pgport "$db" | gzip > "$root/$tag.sql.gz"
# base-identical check except known travel fix
if ! cmp -s $BASE/lib/travel_companionship.php "$site/lib/travel_companionship.php"; then
  if grep -q stobeTravelActorSerial "$site/lib/travel_companionship.php"; then cp $BASE/lib/travel_companionship.php "$site/lib/travel_companionship.php"; echo "restored base travel_companionship.php (travel fix is in compose)"; fi
fi
rm -f "$site/lib/travel_companionship.php.bak-pre-travelfix-20261015"
extra=$(diff -rq $BASE "$site" -x log -x .git -x StobeServer -x '*.log' -x portraits -x voices -x soundcache -x '*.bak-pre-compose*' $XTRA || true)
[ -z "$extra" ] || { echo "site not base-identical:"; echo "$extra"; exit 3; }
cd "$site"
if [ -f lib/imm26_plans.php ]; then echo "already patched"; else
patch -p1 --no-backup-if-mismatch < "$patchf" > "$root/compose-patch.log" 2>&1 || { tail -20 "$root/compose-patch.log"; exit 4; }
fi
n=0; for f in $(grep -E '^\+\+\+ b/.*\.php' "$patchf" | sed 's#^+++ b/##; s#\t.*##'); do [ -f "$f" ] && { php -l "$f" >/dev/null || { echo "LINT FAIL $f"; exit 5; }; n=$((n+1)); }; done
echo "lint ok $n php files"
if [ -d "$COMPOSE" ]; then diff -rq $COMPOSE "$site" -x log -x .git -x StobeServer -x '*.log' -x portraits -x voices -x soundcache -x '*.bak-pre-compose*' -x '*.orig' $XTRA && echo "site identical to compose tree" || echo "DIFF vs compose tree (see above)"
elif [ -n "${COMPOSE_MANIFEST:-}" ]; then bad=$(sha256sum -c "$COMPOSE_MANIFEST" 2>/dev/null | grep -v ': OK' | grep -v 'data/voices' || true); [ -z "$bad" ] && echo "site matches compose manifest" || { echo "MANIFEST MISMATCH:"; echo "$bad"; }; fi
php tools/bootstrap-database.php | tail -3
