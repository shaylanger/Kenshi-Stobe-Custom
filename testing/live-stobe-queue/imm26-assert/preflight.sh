#!/usr/bin/env bash
# preflight.sh <lane> [npc]   shared clean-lane + distance preamble for every imm26 row helper (COORDINATOR_IMPROVEMENTS items 1/2).
#   lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4.  Also sourceable: pf_run <lane> [npc].
# Steps (each failure = one line `PREFLIGHT-FAIL <reason>` and exit 2; success prints `PREFLIGHT-OK <lane> dist=<n> ...`, exit 0):
#   1 game answers (stobe-auto status phase=world) and the lane backend answers (health.php)   [lane down -> FAIL]
#   2 lane-isolation-check.ps1 <rig> (cached 10 min in $LT_BASE/preflight-isolation-<rig>.txt; FAIL items that name this lane's id -> FAIL,
#     other lanes' FAIL items are only warnings; KAH_PF_ISOLATION=0 skips)
#   3 private DB: general_settings PLAYER_NAME='Shay'; stobe_social_contract PROPOSED/ACCEPTED -> EXPIRED (leftover deals e.g. the Metal Junk loan);
#     eventlog travel_agreement rows PROPOSED/ACCEPTED -> ENDED; core_npc.metadata imm26_anchor removed; verify nothing is left
#   4 distance: `where <npc>` (default Cind) dist >= 80 -> FAIL (the native people list drops NPCs beyond 80 units; social scope null)
# Env: KAH_PF_MAXDIST (80), KAH_PF_NOWRITE=1 (checks only, no DB writes), KAH_ROW_FAKE/DRY (see lane.sh).
PF_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$PF_HERE/rowtools/lane.sh"
pf_fail() { echo "PREFLIGHT-FAIL $*"; return 2; }
pf_isolation() {
  [ "${KAH_PF_ISOLATION:-1}" = 0 ] && { echo "isolation=skipped"; return 0; }
  local cache="$LT_BASE/preflight-isolation-$LT_RIG.txt" id="i$LT_N"
  if [ -n "${KAH_ROW_FAKE:-}" ]; then echo "isolation=fake"; return 0; fi
  if [ ! -s "$cache" ] || [ -n "$(find "$cache" -mmin +10 2>/dev/null)" ]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\lane-isolation-check.ps1' "$LT_RIG" > "$cache" 2>&1
  fi
  local bad; bad=$(grep -E '^RESULT lane-isolation .* FAIL' "$cache" | grep -E "(^|[^a-z0-9])$id([^0-9]|$)|lane $id|instance $LT_N")
  if [ -n "$bad" ]; then echo "isolation FAIL for $id: $(echo "$bad" | head -2 | cut -c1-200 | tr '\n' ';')"; return 1; fi
  echo "isolation=ok warn=$(grep -c -E '^RESULT lane-isolation .* FAIL' "$cache")"
}
pf_run() {
  local lane="$1" npc="${2:-Cind}" st dist ev=""
  lt_load "$lane" || return 2
  # 1 game + backend
  st=$(printf 'stobe-auto status </dev/null 2>&1 | head -3\n' | lt_h 2>&1)
  case "$st" in *STOP*|*ROUTE-FAIL*|*"inbox pending"*) pf_fail "lane harness busy/route: $(echo "$st" | head -1 | cut -c1-160)"; return 2;; esac
  echo "$st" | grep -q 'phase=world' || { pf_fail "game down or not in world on $lane: $(echo "$st" | head -1 | cut -c1-160)"; return 2; }
  local h; h=$(printf 'curl -s -m 8 http://127.0.0.1:%s/health.php | head -c 120\n' "$LT_PORT" | lt_w 2>&1)
  [ -n "$h" ] || { pf_fail "lane backend down on $lane (no answer from 127.0.0.1:$LT_PORT/health.php)"; return 2; }
  # 2 isolation
  local iso; iso=$(pf_isolation) || { pf_fail "$iso"; return 2; }
  # 3 clean lane
  if [ -z "${KAH_PF_NOWRITE:-}" ]; then
    lt_w <<EOS >/dev/null 2>&1
cat > /tmp/rowtools-pf.sql <<'EOQ'
DELETE FROM general_settings WHERE id='PLAYER_NAME';
INSERT INTO general_settings (id,value) VALUES ('PLAYER_NAME','Shay');
UPDATE stobe_social_contract SET status='EXPIRED' WHERE status IN ('PROPOSED','ACCEPTED');
UPDATE eventlog SET data=replace(replace(data,'"status":"PROPOSED"','"status":"ENDED"'),'"status":"ACCEPTED"','"status":"ENDED"') WHERE type='travel_agreement' AND (data LIKE '%"status":"PROPOSED"%' OR data LIKE '%"status":"ACCEPTED"%');
DO \$\$ DECLARE t text; BEGIN SELECT data_type INTO t FROM information_schema.columns WHERE table_name='core_npc' AND column_name='metadata' LIMIT 1;
 IF t='jsonb' THEN UPDATE core_npc SET metadata=metadata-'imm26_anchor' WHERE metadata::text LIKE '%imm26_anchor%';
 ELSIF t='json' THEN UPDATE core_npc SET metadata=(metadata::jsonb-'imm26_anchor')::json WHERE metadata::text LIKE '%imm26_anchor%';
 ELSIF t IS NOT NULL THEN UPDATE core_npc SET metadata=(metadata::jsonb-'imm26_anchor')::text WHERE metadata LIKE '%imm26_anchor%'; END IF; END \$\$;
EOQ
chmod 644 /tmp/rowtools-pf.sql; runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -q -v ON_ERROR_STOP=0 -f /tmp/rowtools-pf.sql 2>&1 | head -5
EOS
  fi
  local pn left
  pn=$(lt_sql "select value from general_settings where id='PLAYER_NAME'" | head -1)
  left=$(lt_sql "select (select count(*) from stobe_social_contract where status in ('PROPOSED','ACCEPTED'))||'/'||(select count(*) from eventlog where type='travel_agreement' and (data like '%\"status\":\"PROPOSED\"%' or data like '%\"status\":\"ACCEPTED\"%'))" | head -1)
  if [ -z "${KAH_PF_NOWRITE:-}" ]; then
    [ "$pn" = Shay ] || { pf_fail "PLAYER_NAME is '$pn' after set (general_settings write failed)"; return 2; }
    [ "${left:-0/0}" = "0/0" ] || { pf_fail "leftover open deals/travel agreements after clear (contracts/agreements=$left)"; return 2; }
  fi
  # 4 distance
  local w; w=$(printf 'stobe-auto where "%s" </dev/null 2>&1 | head -1\n' "$npc" | lt_h 2>&1)
  dist=$(echo "$w" | sed -nE 's/.* dist=([0-9.]+).*/\1/p' | head -1)
  [ -n "$dist" ] || { pf_fail "cannot read dist_to_target for '$npc' on $lane: $(echo "$w" | cut -c1-160)"; return 2; }
  awk -v d="$dist" -v m="${KAH_PF_MAXDIST:-80}" 'BEGIN{exit !(d<m)}' || { pf_fail "dist_to_target=$dist >= ${KAH_PF_MAXDIST:-80} for '$npc' on $lane (native people list drops NPCs beyond 80; run the scene setup: lane-setup.sh / cx_scene)"; return 2; }
  echo "PREFLIGHT-OK $lane dist=$dist player_name=$pn open_deals/agreements=$left $iso"
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ $# -ge 1 ] || { echo "usage: preflight.sh <5090-i3|5090-i4|5090-i5|4080-i3|4080-i4> [npc]"; exit 2; }
  pf_run "$@"; exit $?
fi
