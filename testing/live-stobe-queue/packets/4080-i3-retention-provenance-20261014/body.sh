export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
abort() { printf 'PROVENANCE_ABORT=%s\n' "$1"; exit 20; }

[[ "$(hostname)" == DESKTOP-NQQPA73 && "$RIG" == 4080 && "$KAH_INSTANCE" == 3 && "$KENSHI_DIR" == /c/KenshiInst/3 && "$KDIR" == /c/KenshiInst/3 && "$KAH_DIR" == 'C:\KenshiInst\3\mods\AutomationHarness' ]] || abort route_mismatch
[[ "$(sha256sum /c/KenshiModding/tools/automation/rig-env.sh | awk '{print toupper($1)}')" == A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D ]] || abort rig_env_hash_mismatch
rig4080_i3_preflight >/dev/null 2>&1 || abort rig_env_i3_route_or_inbox_gate

# Exact route-helper checks copied from the pinned local helper after rig-env
# initialization. This avoids depending on the missing remote helper file.
embedded_i3_route_guard() {
  if [[ "${KAH_INSTANCE:-}" != 3 ]]; then
    echo 'i3 route requires the preselected instance' >&2
    exit 2
  fi

  _want_game='/c/KenshiInst/3'
  _want_harness='C:\KenshiInst\3\mods\AutomationHarness'
  if [[ "$KDIR" != "$_want_game" || "$KENSHI_DIR" != "$_want_game" || "$KAH_DIR" != "$_want_harness" ]]; then
    echo 'i3 route path mismatch' >&2
    exit 2
  fi

  _harness_unix=$(cygpath -u "$KAH_DIR") || {
    echo 'i3 harness path unavailable' >&2
    exit 2
  }
  if [[ -e "$_harness_unix/inbox.txt" || -e "$_harness_unix/inbox.txt.lock" ]]; then
    echo 'i3 inbox pending or locked' >&2
    exit 3
  fi
  if [[ ! -d "$_harness_unix" ]]; then
    echo 'i3 harness directory missing' >&2
    exit 2
  fi
  echo 'i3 route pass'
}
embedded_i3_route_guard >/dev/null 2>&1 || abort embedded_i3_route_or_inbox_gate

expected_root=/tmp/stobe-standalone4080/site
ini=/c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini
ini_real=$(realpath -e -- "$ini" 2>/dev/null) || abort config_missing
[[ "$ini_real" == "$ini" && -f "$ini" && ! -L "$ini" ]] || abort config_redirected
read_key() {
  awk -v key="$1" -v expected="$2" '
    BEGIN { key=tolower(key); n=0; bad=0; value="" }
    { line=$0; sub(/\r$/, "", line); sub(/^[ \t]+/, "", line)
      if (line=="" || line ~ /^[#;]/) next
      lower=tolower(line)
      if (lower ~ ("^" key "([ \t]|=)")) {
        n++
        if (lower ~ ("^" key "[ \t]*=[ \t]*" expected "[ \t]*$")) value=expected
        else bad++
      }
    }
    END { if (n!=1 || bad!=0) exit 2; print value }
  ' "$ini"
}
cfg_host=$(read_key ServerHost '127\.0\.0\.1') || abort config_host_not_unique_loopback
cfg_port=$(read_key ServerPort '18084') || abort config_port_not_unique_18084
[[ "$cfg_host" == 127.0.0.1 && "$cfg_port" == 18084 ]] || abort config_route_mismatch

site_real=$(realpath -e -- "$expected_root" 2>/dev/null) || abort service_root_missing
[[ "$site_real" == "$expected_root" && -d "$site_real" && ! -L "$expected_root" ]] || abort service_root_redirected
listeners=$(ss -H -ltnp 'sport = :18084' 2>/dev/null) || abort listener_probe_failed
[[ -n "$listeners" && "$(printf '%s\n' "$listeners" | wc -l | tr -d ' ')" == 1 && "$listeners" == *'127.0.0.1:18084'* ]] || abort listener_not_unique_loopback
mapfile -t pids < <(printf '%s\n' "$listeners" | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
[[ ${#pids[@]} == 1 && "${pids[0]}" =~ ^[0-9]+$ ]] || abort listener_pid_missing_or_ambiguous
listener_pid=${pids[0]}
listener_args=$(ps -p "$listener_pid" -o args= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') || abort listener_process_unreadable
[[ "$listener_args" == 'php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site' ]] || abort listener_service_root_mismatch
same_count=$(ps -eo args= | awk '$0 == "php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site" {n++} END {print n+0}')
[[ "$same_count" == 1 ]] || abort duplicate_service_process

source_file=$site_real/lib/playthrough_retention.php
[[ ! -L "$source_file" && -f "$source_file" ]] || abort target_source_missing_or_redirected
source_real=$(realpath -e -- "$source_file" 2>/dev/null) || abort target_source_unresolvable
[[ "$source_real" == "$source_file" ]] || abort target_source_outside_root
source_sha=$(sha256sum "$source_file" | awk '{print tolower($1)}')
[[ "$source_sha" =~ ^[a-f0-9]{64}$ ]] || abort target_source_hash_failed
line40_sha=$(sed -n '40{s/\r$//;s/^[[:space:]]*//;s/[[:space:]]*$//;p;}' "$source_file" | sha256sum | awk '{print tolower($1)}')
[[ "$line40_sha" =~ ^[a-f0-9]{64}$ ]] || abort line40_fingerprint_failed
line40_matches=false
[[ "$line40_sha" == 791954730045326a47dd46fc9a6caba34748e53e2e710b0bab734dc4f1d47518 ]] && line40_matches=true

printf 'I3_ROUTE=pass host=DESKTOP-NQQPA73 instance=3\n'
printf 'LISTENER_PID=%s\nSERVICE_ROOT=%s\n' "$listener_pid" "$site_real"
printf 'TARGET_SOURCE_SHA256=%s\nLINE40_OPERATION_MATCHES_LOCAL_CANDIDATE=%s\n' "$source_sha" "$line40_matches"
