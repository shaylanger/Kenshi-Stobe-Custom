export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh

set -euo pipefail
abort() { printf 'RESULT 4080-I3-INSPECT ABORT %s\n' "$1"; exit 20; }
[[ "$(hostname)" == DESKTOP-NQQPA73 ]] || abort wrong_host
[[ "$RIG" == 4080 && "$KAH_INSTANCE" == 3 && "$KENSHI_DIR" == /c/KenshiInst/3 && "$KAH_DIR" == 'C:\KenshiInst\3\mods\AutomationHarness' ]] || abort route_mismatch

expected_install=/c/KenshiInst/3
install_real=$(realpath -e -- "$expected_install" 2>/dev/null) || abort i3_install_root_missing
[[ "$install_real" == "$expected_install" && -d "$install_real" ]] || abort i3_install_root_not_canonical
ini=$expected_install/RE_Kenshi/mods/Stobe/StobeCustom.ini
ini_real=$(realpath -e -- "$ini" 2>/dev/null) || abort ini_missing_or_redirected
[[ "$ini_real" == "$ini" && -f "$ini" ]] || abort ini_missing_or_redirected
parse_ini_key() {
  local key=$1 expected=$2 result
  result=$(awk -v key="$key" -v expected="$expected" '
    BEGIN { key=tolower(key); count=0; invalid=0; value="" }
    {
      line=$0
      sub(/\r$/, "", line)
      sub(/^[ \t]+/, "", line)
      if (line == "" || line ~ /^[#;]/) next
      lower=tolower(line)
      if (lower ~ ("^" key "([ \t]|=)")) {
        count++
        if (lower ~ ("^" key "[ \t]*=[ \t]*" expected "[ \t]*$")) value=expected
        else invalid++
      }
    }
    END {
      if (count != 1 || invalid != 0) exit 2
      print value
    }' "$ini") || return 1
  printf '%s' "$result"
}
host=$(parse_ini_key ServerHost '127\.0\.0\.1') || abort ini_host_missing_duplicate_or_malformed
port=$(parse_ini_key ServerPort '18084') || abort ini_port_missing_duplicate_or_malformed
[[ "$host" == 127.0.0.1 && "$port" == 18084 ]] || abort ini_not_unique_loopback_18084

expected_root=/tmp/stobe-standalone4080/site
expected_data=/tmp/stobe-standalone4080/pgdata
expected_socket=/tmp/stobe-standalone4080/socket
site_real=$(realpath -e -- "$expected_root" 2>/dev/null) || abort site_root_missing
[[ "$site_real" == "$expected_root" && -d "$site_real" && ! -L "$expected_root" ]] || abort site_root_not_canonical
data_real=$(realpath -e -- "$expected_data" 2>/dev/null) || abort test_data_root_missing
socket_real=$(realpath -e -- "$expected_socket" 2>/dev/null) || abort test_socket_missing
[[ "$data_real" == "$expected_data" && "$socket_real" == "$expected_socket" ]] || abort test_data_root_not_canonical

listeners=$(ss -H -ltnp 'sport = :18084' 2>/dev/null) || abort listener_probe_failed
[[ -n "$listeners" && "$(printf '%s\n' "$listeners" | wc -l | tr -d ' ')" == 1 ]] || abort listener_not_unique
[[ "$listeners" == *'127.0.0.1:18084'* ]] || abort listener_not_loopback
mapfile -t listener_pids < <(printf '%s\n' "$listeners" | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
[[ ${#listener_pids[@]} -eq 1 ]] || abort listener_pid_missing_or_ambiguous
php_pid=${listener_pids[0]}
php_args=$(ps -p "$php_pid" -o args= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[[ "$php_args" == 'php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site' ]] || abort listener_arguments_mismatch
same_args=$(ps -eo args= | awk '$0 == "php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site" {n++} END {print n+0}')
[[ "$same_args" == 1 ]] || abort duplicate_php_server_process

# Read only the three explicitly allowlisted metadata keys. Never dump process variables.
safe_env_value() {
  local key=$1 out
  out=$(tr '\0' '\n' < "/proc/$php_pid/environ" | awk -F= -v k="$key" '$1==k {n++; v=substr($0,index($0,"=")+1)} END {if(n==1) print v; else exit 2}') || return 1
  printf '%s' "$out"
}
db_host=$(safe_env_value STOBE_DB_HOST) || abort db_host_metadata_missing
db_name=$(safe_env_value STOBE_DB_NAME) || abort db_name_metadata_missing
pgdata=$(safe_env_value PGDATA) || abort pgdata_metadata_missing
[[ "$db_host" == "$expected_socket" && "$db_name" == stobe_standalone4080_test && "$pgdata" == "$expected_data" ]] || abort backend_not_test_only
[[ -s "$expected_data/postmaster.pid" ]] || abort test_postgres_marker_missing
pg_pid=$(head -n 1 "$expected_data/postmaster.pid" | tr -d '\r\n')
[[ "$pg_pid" =~ ^[0-9]+$ ]] || abort test_postgres_pid_invalid
pg_args=$(ps -p "$pg_pid" -o args= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[[ "$pg_args" == *"postgres -D $expected_data"* || "$pg_args" == *"/postgres -D $expected_data"* ]] || abort postgres_data_process_mismatch

# No PHP bytes are opened before this point; the allowlist below is fixed.
python3 - "$site_real" <<'PY'
import hashlib, pathlib, re, sys
root = pathlib.Path(sys.argv[1]).resolve(strict=True)
relpaths = ('lib/playthrough_preferences.php', 'lib/playthrough_retention.php', 'playthrough_session.php')
paths = []
for rel in relpaths:
    p = root / rel
    parts = [root]
    cur = root
    for piece in pathlib.PurePosixPath(rel).parts:
        cur = cur / piece
        parts.append(cur)
    if any(part.is_symlink() for part in parts) or not p.is_file():
        print('RESULT 4080-I3-INSPECT ABORT fixed_file_missing_or_redirected')
        raise SystemExit(21)
    resolved = p.resolve(strict=True)
    if not resolved.is_relative_to(root) or resolved != p:
        print('RESULT 4080-I3-INSPECT ABORT fixed_file_outside_root')
        raise SystemExit(21)
    paths.append((rel, p, p.read_bytes()))

blob = b'\n'.join(item[2] for item in paths)
secret_patterns = (
    rb'(?i)(?:authorization\s*:\s*bearer|-----BEGIN [A-Z ]*PRIVATE KEY-----)',
    rb'(?i)(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[=:>]\s*[\'\"][^\'\"]{8,}[\'\"]',
    rb'(?i)(?:session[_-]?id|client[_-]?id|load[_-]?id|token)\s*[=:>]\s*[\'\"][a-f0-9-]{16,}[\'\"]',
    rb'(?i)https?://[^\s/]+:[^\s/@]+@',
)
if any(re.search(rx, blob) for rx in secret_patterns):
    print('RESULT 4080-I3-INSPECT ABORT possible_secret_detected')
    raise SystemExit(22)

allow_fields = ('campaign_id','client_id','character_id','load_id','timeline_epoch','native_session_id','gamets','status','player_name')
texts = {rel: raw.decode('utf-8', 'replace') for rel, _, raw in paths}
all_text = '\n'.join(texts.values())
retention = texts['lib/playthrough_retention.php']
prefs = texts['lib/playthrough_preferences.php']
endpoint = texts['playthrough_session.php']
facts = {
  'ptp_connect_token': bool(re.search(r'(?i)\bptp_connect\b', prefs)),
  'ptr_read_token': bool(re.search(r'(?i)\bptr_read\b', retention)),
  'session_table_token': bool(re.search(r'(?i)\bPLAYTHROUGH_SESSION\b', retention + endpoint)),
  'db_host_name_tokens': bool(re.search(r'(?i)STOBE_DB_HOST', prefs) and re.search(r'(?i)STOBE_DB_NAME', prefs)),
  'pg_connect_token': bool(re.search(r'(?i)\bpg_connect\b', prefs)),
  'generation_token': bool(re.search(r'(?i)\bgeneration\b', all_text)),
  'manager_ready_token': 'manager.ready' in all_text,
  'lock_lease_tokens': bool(re.search(r'(?i)\b(flock|LOCK_EX|pg_advisory_lock|runtime_lease|lease_acquire|with_lease)\b', all_text)),
  'rename_token': bool(re.search(r'(?i)\brename\s*\(', all_text)),
  'transaction_tokens': bool(re.search(r'(?i)\b(beginTransaction|begin transaction|commit|rollBack)\b', all_text)),
}
table_ops = {
  'select_pattern': bool(re.search(r'(?is)\bselect\b.{0,500}\bPLAYTHROUGH_SESSION\b|\bPLAYTHROUGH_SESSION\b.{0,500}\bselect\b', retention)),
  'insert_pattern': bool(re.search(r'(?is)\binsert\s+into\s+PLAYTHROUGH_SESSION\b', endpoint)),
  'update_pattern': bool(re.search(r'(?is)\bupdate\s+PLAYTHROUGH_SESSION\b', endpoint)),
}
print('ROUTE_METADATA=expected; database_connection=unverified_until_static_binding')
for rel, p, raw in paths:
    txt = texts[rel]
    lines = txt.splitlines()
    fields = sorted({f for f in allow_fields if re.search(r'(?i)(?:[\'\"]'+re.escape(f)+r'[\'\"]|\b'+re.escape(f)+r'\b)', txt)})
    refs = [n for n, line in enumerate(lines, 1) if 'PLAYTHROUGH_SESSION' in line or 'manager.ready' in line or 'generation' in line.lower() or 'lease' in line.lower() or 'flock' in line.lower()]
    print(f'FILE basename={p.name} sha256={hashlib.sha256(raw).hexdigest()} bytes={len(raw)}')
    print('  schema_fields=' + ','.join(fields))
    print('  relevant_lines=' + ','.join(map(str,refs[:80])))
print('LEXICAL_PRESENCE_ONLY=' + ','.join(f'{key}:{str(value).lower()}' for key,value in facts.items()))
print('TABLE_PATTERNS_ONLY=' + ','.join(f'{key}:{str(value).lower()}' for key,value in table_ops.items()))
print('RESULT 4080-I3-INSPECT INCOMPLETE semantics=not-proven db_binding=not-proven marker_behavior=not-proven lease_atomicity=not-proven')
PY
