#!/bin/bash
# stobe-lane-backend.sh <lane> provision|start|stop|status|supervise   (WSL root on the rig that owns the lane, i.e. the 4080's
# DwemerAI4Skyrim3). One PRIVATE STOBE backend per isolated test lane, completely separate from every other lane and from the
# live server (/var/www/html/StobeServer, db "stobe"): own site copy, own Postgres CLUSTER (own port + unix socket dir + pgdata),
# own database, own php -S port, own LLM bridge port, own manager loop, own activity-transport key, own env.sh, own /tmp root.
# Lane parameters come from lane-defs.<rig>.json (python3 json), nothing is hard-coded here.
#   provision : build the lane's backend from lane i3's reviewed site tree (same release, copied without logs), fresh cluster+DB
#               (schema.sql + bootstrap-database.php + activity schema), fresh transport key, then lane-llm-apply-4080.sh. Refuses if
#               the lane's root exists. Only lanes with "owner_note" starting "built by" may be provisioned (i3 is read-only here).
#   start     : idempotent: pg, bridge, php -S, manager loop (each only if not running).
#   stop      : manager, php, bridge, pg (this lane only; pids from the lane root, ownership checked against /proc cmdline).
#   status    : one line per component + health.php body.
#   supervise : start, then sleep forever (the Windows scheduled task <task> runs this so the WSL session and children stay up).
# Env: LANE_DEFS (default /mnt/c/KenshiTestRuns/lane-i4/lane-defs.4080.json), LANE_SRC_LANE (site source lane, default i3).
set -eu
lane=${1:-}; cmd=${2:-status}
defs=${LANE_DEFS:-/mnt/c/KenshiTestRuns/lane-i4/lane-defs.4080.json}; srclane=${LANE_SRC_LANE:-i3}
here=$(cd "$(dirname "$0")" && pwd)
[ -n "$lane" ] || { sed -n 2,19p "$0"; exit 2; }
eval "$(python3 - "$defs" "$lane" "$srclane" <<'PY'
import json,sys,shlex
d=json.load(open(sys.argv[1])); L=d['lanes'][sys.argv[2]]; S=d['lanes'][sys.argv[3]]
v={'ROOT':L['backend_root'],'PHPP':L['php_port'],'BRP':L['bridge_port'],'PGP':L['pg_port'],'DB':L['db'],'TASK':L['task'],
   'NOTE':L.get('owner_note',''),'SRC':S['backend_root']}
def w(p): p=p.replace(chr(92),'/'); return '/mnt/'+p[0].lower()+p[2:]
d=w(L['dir']); v['SLOG']=d+'/RE_Kenshi/mods/Stobe/stobe.log'; v['KLOG']=d+'/KenshiFP.log'; v['AREQ']=d+'/RE_Kenshi/mods/Stobe/stobe_action.request'
for k,x in v.items(): print('%s=%s'%(k,shlex.quote(str(x))))
PY
)"
case "$DB" in *test*) ;; *) echo "refusing db '$DB'"; exit 3;; esac
PGBIN=/usr/lib/postgresql/15/bin
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
pgup() { runuser -u postgres -- $PGBIN/pg_ctl -D "$ROOT/pgdata" status >/dev/null 2>&1; }

do_start() {
  [ -d "$ROOT/site" ] || { echo "lane $lane not provisioned ($ROOT)"; exit 1; }
  pgup || runuser -u postgres -- $PGBIN/pg_ctl -D "$ROOT/pgdata" -l "$ROOT/pgdata/server.log" -o "-c listen_addresses='' -c unix_socket_directories='$ROOT/socket' -p $PGP" start >/dev/null
  bash "$here/lane-neg-env.sh" "$ROOT/env.sh" "$SLOG" "$KLOG" "$AREQ" >/dev/null
  # shellcheck disable=SC1091
  ( set +x; . "$ROOT/env.sh"
    alive "$ROOT/bridge.pid" || { nohup python3 "$here/stobe-lane-bridge.py" "$BRP" "${LANE_MODEL_PORT:-18095}" "$ROOT" > "$ROOT/bridge.log" 2>&1 < /dev/null & }
    if ! alive "$ROOT/php.pid"; then
      PHP_CLI_SERVER_WORKERS=4 nohup php -S 127.0.0.1:$PHPP -t "$ROOT/site" > "$ROOT/php.log" 2>&1 < /dev/null &
      echo $! > "$ROOT/php.pid"
    fi
  )
  cat > "$ROOT/manager.sh" <<EOF
#!/bin/bash
set -eu
b=$ROOT
source "\$b/env.sh"
exec 9>"\$b/manager.lock"
flock -n 9 || exit 0
echo \$\$ > "\$b/manager.pid"
while true; do timeout --signal=TERM --kill-after=5s 120s php "\$b/site/service/manager.php" >> "\$b/manager.log" 2>&1 || true; sleep 1; done
EOF
  chmod 700 "$ROOT/manager.sh"
  alive "$ROOT/manager.pid" || { nohup "$ROOT/manager.sh" >/dev/null 2>&1 < /dev/null & }
  sleep 2
  echo "lane $lane backend started (php $PHPP, bridge $BRP, pg $PGP, db $DB)"
}

do_stop() {
  [ "${NOTE#built by}" != "$NOTE" ] || { echo "lane $lane is not owned by this script ($NOTE): refusing to stop"; exit 3; }
  if [ -f "$ROOT/manager.pid" ] && alive "$ROOT/manager.pid" && tr '\0' ' ' < /proc/$(cat "$ROOT/manager.pid")/cmdline | grep -q "$ROOT/manager.sh"; then
    p=$(cat "$ROOT/manager.pid"); for k in $(pgrep -P "$p" || true); do pkill -TERM -P "$k" || true; kill -TERM "$k" || true; done; kill -TERM "$p" || true
  fi
  for f in php bridge; do
    if alive "$ROOT/$f.pid"; then
      p=$(cat "$ROOT/$f.pid")
      if [ $f = php ]; then pkill -TERM -f "^php -S 127.0.0.1:$PHPP -t $ROOT/site\$" || true; else kill -TERM "$p" || true; fi
    fi
  done
  pgup && runuser -u postgres -- $PGBIN/pg_ctl -D "$ROOT/pgdata" -m fast stop >/dev/null || true
  rm -f "$ROOT/php.pid" "$ROOT/bridge.pid" "$ROOT/manager.pid"
  echo "lane $lane backend stopped"
}

do_restart_web() {
  # re-reads env.sh (rewrites the lane's STOBE_NEG_* lines first); restarts ONLY this lane's php -S and manager loop (pg/bridge/game untouched)
  [ -d "$ROOT/site" ] || { echo "lane $lane not provisioned ($ROOT)"; exit 1; }
  bash "$here/lane-neg-env.sh" "$ROOT/env.sh" "$SLOG" "$KLOG" "$AREQ"
  if [ -f "$ROOT/manager.pid" ] && alive "$ROOT/manager.pid"; then p=$(cat "$ROOT/manager.pid"); for k in $(pgrep -P "$p" || true); do pkill -TERM -P "$k" || true; kill -TERM "$k" || true; done; kill -TERM "$p" || true; fi
  pkill -TERM -f "^php -S 127.0.0.1:$PHPP -t $ROOT/site\$" || true
  for i in 1 2 3 4 5 6 7 8 9 10; do ss -ltn | grep -qE "127.0.0.1:$PHPP\b" || break; sleep 1; done
  rm -f "$ROOT/php.pid" "$ROOT/manager.pid"
  do_start
  for i in 1 2 3 4 5 6 7 8 9 10; do c=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PHPP/health.php" || true); [ "$c" = 200 ] && break; sleep 1; done
  echo "RESTARTED-WEB lane=$lane php=$PHPP health.php http=$c"; [ "$c" = 200 ]
}

do_status() {
  s() { alive "$ROOT/$1.pid" && echo "$1=up($(cat "$ROOT/$1.pid"))" || echo "$1=DOWN"; }
  echo "lane $lane root=$ROOT db=$DB pg=$(pgup && echo up || echo DOWN):$PGP $(s php):$PHPP $(s bridge):$BRP $(s manager)"
  curl -s --max-time 5 "http://127.0.0.1:$PHPP/health.php" | head -c 200; echo
}

do_provision() {
  [ "${NOTE#built by}" != "$NOTE" ] || { echo "lane $lane is not provisionable here ($NOTE)"; exit 3; }
  [ ! -e "$ROOT" ] || { echo "lane root $ROOT exists; refusing overwrite"; exit 1; }
  [ -d "$SRC/site" ] || { echo "no source site $SRC/site"; exit 1; }
  install -d "$ROOT/site" "$ROOT/socket" "$ROOT/pgdata"
  # same reviewed server release as the source lane; runtime logs/state are not copied (fresh log dir)
  tar -C "$SRC/site" --exclude='./log/*' -cf - . | tar -C "$ROOT/site" -xf -
  mkdir -p "$ROOT/site/log"; chmod 777 "$ROOT/site" "$ROOT/site/log"
  [ "$(cd "$SRC/site" && find . -path ./log -prune -o -type f -print | wc -l)" = "$(cd "$ROOT/site" && find . -path ./log -prune -o -type f -print | wc -l)" ] || { echo 'site copy file count mismatch'; exit 1; }
  chown -R postgres:postgres "$ROOT/pgdata" "$ROOT/socket"
  runuser -u postgres -- $PGBIN/initdb -D "$ROOT/pgdata" --encoding=UTF8 --locale=C --auth-local=trust --auth-host=reject > "$ROOT/initdb.log"
  runuser -u postgres -- $PGBIN/pg_ctl -D "$ROOT/pgdata" -l "$ROOT/pgdata/server.log" -o "-c listen_addresses='' -c unix_socket_directories='$ROOT/socket' -p $PGP" start >/dev/null
  runuser -u postgres -- createuser -h "$ROOT/socket" -p "$PGP" dwemer
  runuser -u postgres -- createdb -h "$ROOT/socket" -p "$PGP" -O dwemer "$DB"
  runuser -u postgres -- psql -h "$ROOT/socket" -p "$PGP" -d "$DB" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION vector' > "$ROOT/extension.log"
  umask 077
  openssl rand -hex 32 | tr -d '\n' > "$ROOT/activity-transport.key"
  cat > "$ROOT/env.sh" <<EOF
set +x # Never trace private secrets
export PGPORT=$PGP STOBE_DB_PORT=$PGP STOBE_DB_HOST=$ROOT/socket STOBE_DB_NAME=$DB STOBE_DB_USER=dwemer STOBE_NO_BACKGROUND_PROCESSOR=1 STOBE_ACTIVITY_ENABLED=1
export STOBE_ACTIVITY_TRANSPORT_SECRET="\$(cat $ROOT/activity-transport.key)"
EOF
  bash "$here/lane-neg-env.sh" "$ROOT/env.sh" "$SLOG" "$KLOG" "$AREQ"
  umask 022
  ( . "$ROOT/env.sh"
    export STOBE_NO_BACKGROUND_PROCESSOR=1
    psql -h "$ROOT/socket" -U dwemer -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/site/data/schema.sql" > "$ROOT/schema.log" 2>&1
    php "$ROOT/site/tools/bootstrap-database.php" > "$ROOT/bootstrap.log" 2>&1
    psql -h "$ROOT/socket" -U dwemer -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/site/lib/activity/schema.sql" > "$ROOT/activity-schema.log" 2>&1
    # lane settings (same as standalone4080-config.php minus the connector rows, which lane-llm-apply-4080.sh owns), parameterized
    cat > "$ROOT/config.php" <<PHPEOF
<?php
require '$ROOT/site/lib/bootstrap.php';
require_once '$ROOT/site/lib/social_runtime.php';
require_once '$ROOT/site/lib/playthrough_switching.php';
\$db=\$GLOBALS['db'];
if((\$db->fetchOne('select current_database() as d')['d']??'')!=='$DB')throw new RuntimeException('wrong database');
\$columns=\$db->fetchAll("SELECT column_name FROM information_schema.columns WHERE table_name='core_profiles' AND (column_name LIKE '%llm%' OR column_name LIKE '%connector') AND data_type='integer'");
foreach(\$columns as \$c){\$n=\$c['column_name'];if(!preg_match('/^[a-z_]+\$/',\$n))throw new RuntimeException('column');\$db->exec('UPDATE core_profiles SET '.\$n.'=1');}
\$db->exec("UPDATE core_profiles SET metadata=jsonb_set(COALESCE(metadata,'{}'::jsonb),'{CONTEXT_HISTORY}','10'::jsonb)");
setSetting('SOCIAL_RELATIONSHIP_MODE','enabled','general','Authorized isolated 4080 lane $lane full REL');
setSetting('DYNAMIC_PROFILE_ENABLED','false','general','Authorized isolated 4080 lane $lane bounded smoke');
\$c=ptp_connect();ptr_ensure_schema(\$c);ptr_write(\$c,'PLAYTHROUGH_AUTO_SWITCH',true);
echo json_encode(['database'=>\$db->fetchOne('select current_database() as d'),'roles'=>\$columns,'social_mode'=>stobeSocialMode(),'profiles'=>\$db->fetchAll('select id from core_profiles')],JSON_PRETTY_PRINT),"\n";
PHPEOF
    php "$ROOT/config.php" > "$ROOT/config-proof.json"
  )
  bash "$here/lane-llm-apply-4080.sh" "$lane" --defs "$defs"
  echo "PRIVATE BOOTSTRAP COMPLETE lane $lane"
}

case "$cmd" in
  provision) do_provision;;
  start) do_start;;
  stop) do_stop;;
  status) do_status;;
  restart-web) do_restart_web;;
  supervise) do_start; do_status; exec sleep infinity;;
  *) sed -n 2,19p "$0"; exit 2;;
esac
