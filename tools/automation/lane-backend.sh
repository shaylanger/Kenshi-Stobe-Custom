#!/usr/bin/env bash
# lane-backend.sh <provision|start|stop|status|selftest> <lane>     (run in WSL DwemerAI4Skyrim3 as root; 5090 imm26 isolated lanes)
# Generalises C:\KenshiTestRuns\imm26-5090\{provision,start}.sh (lane i3) for any lane in the rig registry
# C:\KenshiTestRuns\lanes\lanes-5090.json (ports, DB, private root per lane). One lane = its own
#   /tmp/stobe-imm26-5090[-iN] root: copy of /root/imm26/base site, own Postgres cluster (socket only, own port), own DB,
#   own activity-transport key, env.sh, php -S 127.0.0.1:<backend_port>, manager loop, local-model bridge on <bridge_port>.
# Never touches the live tree /var/www/html/StobeServer, ss-merge, the live DB (5432), ports 80/443/8083, Shay's install.
# i3 (the lane the 5090 operator is using) can be provisioned never (exists) and stopped only with LANE_I3_STOP=yes.
set -euo pipefail
cmd=${1:-}; lane=${2:-}
REG=/mnt/c/KenshiTestRuns/lanes/lanes-5090.json
TOOLS=/mnt/c/KenshiModding/tools/automation
[ -n "$cmd" ] && [ -n "$lane" ] || { sed -n 2,3p "$0"; exit 2; }
eval "$(python3 - "$REG" "$lane" <<'PY'
import json,sys,shlex
reg=json.load(open(sys.argv[1],encoding='utf-8-sig'))
l=[x for x in reg['lanes'] if x['id']==sys.argv[2]]
if not l: print('echo "no such lane in registry" >&2; exit 2'); sys.exit()
l=l[0]
for k,v in dict(BP=l['backend_port'],BR=l['bridge_port'],PG=l['pg_port'],DB=l['db'],ROOT=l['wsl_root'],INST=l['instance']).items(): print(f'{k}={shlex.quote(str(v))}')
PY
)"
b=$ROOT; PGBIN=/usr/lib/postgresql/15/bin
pgrun() { runuser -u postgres -- "$@"; }
pg_up() { pgrun $PGBIN/pg_ctl -D "$b/pgdata" status >/dev/null 2>&1; }
case "$cmd" in
selftest)
  [ "$b" != /tmp/stobe-imm26-5090 ] || [ "$lane" = i3 ] || { echo 'SELFTEST FAIL root clash'; exit 1; }
  echo "SELFTEST PASS lane=$lane root=$b backend=$BP bridge=$BR pg=$PG db=$DB"; exit 0;;
provision)
  [ "$lane" != i3 ] || { echo 'i3 exists; refusing'; exit 1; }
  test ! -e "$b" || { echo "private root $b exists; refusing overwrite"; exit 1; }
  for p in $BP $BR $PG; do ss -ltn | grep -qE "[:.]$p\b" && { echo "port $p busy; refusing"; exit 1; }; done
  install -d "$b/site" "$b/socket" "$b/pgdata"
  cp -a /root/imm26/base/. "$b/site/"
  rm -rf "$b/site/.git"; rm -rf "$b/site/log"; install -d -m 777 "$b/site/log"; : > "$b/site/log/php_error.log"; chmod 666 "$b/site/log/php_error.log"
  ln -s . "$b/site/StobeServer"
  chown -R postgres:postgres "$b/pgdata" "$b/socket"
  pgrun $PGBIN/initdb -D "$b/pgdata" --encoding=UTF8 --locale=C --auth-local=trust --auth-host=reject > "$b/initdb.log"
  pgrun $PGBIN/pg_ctl -D "$b/pgdata" -l "$b/pgdata/server.log" -o "-c listen_addresses='' -c unix_socket_directories='$b/socket' -p $PG" -w start
  export PGPORT=$PG STOBE_DB_PORT=$PG STOBE_DB_HOST="$b/socket" STOBE_DB_NAME=$DB STOBE_DB_USER=dwemer STOBE_NO_BACKGROUND_PROCESSOR=1
  pgrun createuser -h "$b/socket" -p $PG dwemer
  pgrun createdb -h "$b/socket" -p $PG -O dwemer "$DB"
  pgrun psql -h "$b/socket" -p $PG -d "$DB" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION vector' > "$b/extension.log"
  psql -h "$b/socket" -p $PG -U dwemer -d "$DB" -v ON_ERROR_STOP=1 -f "$b/site/data/schema.sql" > "$b/schema.log" 2>&1
  php "$b/site/tools/bootstrap-database.php" > "$b/bootstrap.log" 2>&1
  psql -h "$b/socket" -p $PG -U dwemer -d "$DB" -v ON_ERROR_STOP=1 -f "$b/site/lib/activity/schema.sql" > "$b/activity-schema.log" 2>&1
  ( umask 077; openssl rand -hex 32 | tr -d '\n' > "$b/activity-transport.key" )
  cat > "$b/env.sh" <<EOT
export PGPORT=$PG STOBE_DB_PORT=$PG STOBE_DB_HOST=$b/socket STOBE_DB_NAME=$DB STOBE_DB_USER=dwemer STOBE_NO_BACKGROUND_PROCESSOR=1 STOBE_ACTIVITY_ENABLED=1
export STOBE_ACTIVITY_TRANSPORT_SECRET="\$(cat $b/activity-transport.key)"
export LANE_ROOT=$b LANE_DB=$DB
EOT
  cat > "$b/manager.sh" <<EOT
#!/bin/bash
set -eu
b=$b
source "\$b/env.sh"
exec 9>"\$b/manager.lock"
flock -n 9 || exit 0
echo \$\$ > "\$b/manager.pid"
while true; do timeout --signal=TERM --kill-after=5s 120s php "\$b/site/service/manager.php" >> "\$b/manager.log" 2>&1 || true; sleep 1; done
EOT
  chmod 700 "$b/manager.sh"
  source "$b/env.sh"
  php "$TOOLS/lane-config.php" > "$b/config-proof.json"
  echo "PROVISION COMPLETE lane=$lane root=$b"; exit 0;;
start)
  [ -d "$b" ] || { echo "lane root $b missing: provision first"; exit 1; }
  if ss -ltn | grep -qE "127.0.0.1:$BP\b"; then echo "php already listening on $BP"; else
    pg_up || pgrun $PGBIN/pg_ctl -D "$b/pgdata" -l "$b/pgdata/server.log" -o "-c listen_addresses='' -c unix_socket_directories='$b/socket' -p $PG" -w start
    source "$b/env.sh"
    PHP_CLI_SERVER_WORKERS=4 setsid nohup php -S 127.0.0.1:$BP -t "$b/site" > "$b/php.log" 2>&1 < /dev/null &
    echo $! > "$b/php.pid"
    setsid nohup "$b/manager.sh" >/dev/null 2>&1 < /dev/null &
  fi
  if ! ss -ltn | grep -qE "127.0.0.1:$BR\b"; then
    setsid nohup python3 "$TOOLS/lane-bridge.py" $BR 18098 "$b/bridge.pid" "$b/bridge-current.log" > "$b/bridge.log" 2>&1 < /dev/null &
  fi
  sleep 3; echo "STARTED lane=$lane backend=$BP bridge=$BR pg=$PG"; exit 0;;
stop)
  [ "$lane" != i3 ] || [ "${LANE_I3_STOP:-}" = yes ] || { echo 'refusing to stop i3 (set LANE_I3_STOP=yes)'; exit 1; }
  pkill -f "$b/manager.sh" || true; pkill -f "$b/site/service/manager.php" || true
  pkill -f "php -S 127.0.0.1:$BP -t $b/site" || true
  pkill -f "lane-bridge.py $BR " || true
  pg_up && pgrun $PGBIN/pg_ctl -D "$b/pgdata" -m fast -w stop || true
  echo "STOPPED lane=$lane"; exit 0;;
status)
  echo "lane=$lane root=$b exists=$([ -d "$b" ] && echo yes || echo no)"
  for p in $BP $BR; do echo "port $p listening=$(ss -ltn | grep -qE "127.0.0.1:$p\b" && echo yes || echo no)"; done
  echo "pg=$(pg_up && echo up || echo down) port=$PG db=$DB"
  curl -s -m 5 -o /dev/null -w "health.php http=%{http_code}\n" "http://127.0.0.1:$BP/health.php" || true
  exit 0;;
*) echo 'usage: lane-backend.sh provision|start|stop|status|selftest <lane>'; exit 2;;
esac
