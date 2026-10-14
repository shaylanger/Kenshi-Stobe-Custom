export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh

set -euo pipefail

fail() {
  local message="$1" code="$2"
  printf 'RESULT 4080-I3-PING-GATE FAIL setup: %s\n' "$message"
  exit "$code"
}

check_route() {
  local report
  if ! report=$(rig4080_i3_preflight 2>&1); then
    printf 'ROUTE_GATE_STOP=%s\n' "${report//$'\n'/; }" >&2
    return 1
  fi
  if [[ "$report" != *'RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only'* ]]; then
    printf 'ROUTE_GATE_STOP=unexpected isolated route proof\n' >&2
    return 1
  fi
}

lock_is_free() {
  [[ "$1" == 'free' ]]
}

expected_world() {
  [[ "$1" =~ ^phase=world\ save=newgame:Empire\ Citizen\ .*paused=0\ .*player=Bark$ ]]
}

if [[ "${PACKET_SELFTEST:-0}" == 1 ]]; then
  lock_is_free 'free' || { echo 'SELFTEST_FAIL lock_free'; exit 90; }
  lock_is_free '' && { echo 'SELFTEST_FAIL lock_missing'; exit 91; }
  lock_is_free $'rig4080\n2026-10-14T00:00:00' && { echo 'SELFTEST_FAIL lock_owned'; exit 92; }
  lock_is_free $'free\nother-owner' && { echo 'SELFTEST_FAIL lock_ambiguous'; exit 93; }
  sample_world='phase=world save=newgame:Empire Citizen last_saved=never paused=0 speed=1.0 squad=1 player=Bark'
  changed_world='phase=world save=newgame:Empire Citizen last_saved=never paused=1 speed=1.0 squad=1 player=Bark'
  expected_world "$sample_world" || { echo 'SELFTEST_FAIL world_valid'; exit 94; }
  expected_world "$changed_world" && { echo 'SELFTEST_FAIL world_pause_change'; exit 95; }
  [[ "$sample_world" == "$sample_world" ]] || { echo 'SELFTEST_FAIL unchanged_world'; exit 96; }
  [[ "$sample_world" == "$changed_world" ]] && { echo 'SELFTEST_FAIL changed_world'; exit 97; }
  sample_process=$'PID=3452\nLOADED_MODULE=Stobe.dll\nON_DISK_SHA256=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'
  changed_process=$'PID=3453\nLOADED_MODULE=Stobe.dll\nON_DISK_SHA256=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'
  [[ "$sample_process" == "$sample_process" ]] || { echo 'SELFTEST_FAIL unchanged_process'; exit 98; }
  [[ "$sample_process" == "$changed_process" ]] && { echo 'SELFTEST_FAIL process_pid_change'; exit 99; }
  [[ 'isolation=on frames=24 focused=1' == isolation=on* ]] || { echo 'SELFTEST_FAIL isolation_on'; exit 100; }
  [[ 'isolation=off frames=24 focused=1' == isolation=on* ]] && { echo 'SELFTEST_FAIL isolation_off'; exit 101; }
  echo 'RESULT 4080-I3-PING-GATE-SELFTEST PASS cases=12 lock=owned|missing|ambiguous process_change=detected world_change=detected isolation=checked rig_contact=0'
  exit 0
fi

printf 'PACKET=4080-I3-NATIVE-PING-GATE-v1\nUTC='; date -u +%Y-%m-%dT%H:%M:%SZ
if ! check_route; then fail 'isolated i3 route/inbox gate stopped' 20; fi
printf 'ROUTE_BASELINE=4080 i3; inbox and inbox lock absent (presence-only)\n'

read_game_lock() {
  powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File 'C:\KenshiModding\tools\automation\rig4080\ctl.ps1' lock -Instance 3 | tr -d '\r'
}

printf '\n=== ISOLATED GAME LOCK (READ ONLY) ===\n'
if ! lock_before=$(read_game_lock); then fail 'read-only instance-3 game-lock query failed' 21; fi
printf 'GAME_LOCK_BEFORE=%s\n' "$lock_before"
lock_is_free "$lock_before" || fail 'instance-3 game lock is held, missing, or ambiguous; no ping sent' 21

printf '\n=== EXACT I3 PROCESS / LOADED BUILD ===\n'
if ! probe_before=$(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
  -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' \
  -ExpectedExecutablePath 'C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'); then
  printf '%s\n' "$probe_before"
  fail 'exact i3 game process/module probe failed' 22
fi
printf '%s\n' "$probe_before"
[[ "$probe_before" == *$'PID='* ]] || fail 'exact i3 process PID proof is missing' 22
stobe_hash=$(printf '%s\n' "$probe_before" | awk '$0=="LOADED_MODULE=Stobe.dll"{want=1;next} want&&/^ON_DISK_SHA256=/{sub(/^ON_DISK_SHA256=/,"");print;exit}')
harness_hash=$(printf '%s\n' "$probe_before" | awk '$0=="LOADED_MODULE=AutomationHarness.dll"{want=1;next} want&&/^ON_DISK_SHA256=/{sub(/^ON_DISK_SHA256=/,"");print;exit}')
[[ "$stobe_hash" == 'AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C' ]] || fail 'loaded Stobe build differs from pinned AEF' 23
[[ "$harness_hash" == '974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D' ]] || fail 'loaded Harness build differs from pinned candidate' 24

printf '\n=== PRIVATE I3 BACKEND CONFIG ===\n'
if ! config=$(grep -iE '^(ServerHost|ServerPort)=' /c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini | tr -d '\r'); then
  fail 'isolated i3 Stobe config could not be read' 25
fi
printf '%s\n' "$config"
[[ "$config" == *'ServerHost=127.0.0.1'* && "$config" == *'ServerPort=18084'* ]] || fail 'isolated loopback backend config mismatch' 26
config_before="$config"

read_native() {
  local kind="$1"; shift
  local output
  if ! check_route; then return 1; fi
  if ! output=$(timeout 25 stobe-auto "$@" </dev/null | tr -d '\r'); then
    printf 'KAH_READ_FAILED kind=%s\n' "$kind" >&2
    return 1
  fi
  printf '%s' "$output"
}

printf '\n=== FRESH WORLD / SAVE / PAUSE BASELINE ===\n'
if ! status_before=$(read_native status status); then fail 'world/save baseline request failed' 28; fi
printf 'STATUS_BEFORE=%s\n' "$status_before"
expected_world "$status_before" || fail 'expected unpaused Empire Citizen city-start world with player Bark' 29

printf '\n=== INPUT ISOLATION BASELINE (NO FOCUS CHANGES) ===\n'
if ! isolation=$(read_native isolation input_isolation status); then fail 'input-isolation status request failed' 30; fi
printf 'ISOLATION=%s\n' "$isolation"
[[ "$isolation" == isolation=on* ]] || fail 'isolated input guard is not on' 31
isolation_before="$isolation"

printf '\n=== ONE NATIVE PING; CORRELATED ACK REQUIRED ===\n'
if ! check_route; then fail 'isolated i3 route/inbox gate stopped before ping' 20; fi
outbox=$(cygpath -u "$KAH_DIR")/outbox.txt
if ! outbox_start=$(wc -c < "$outbox"); then fail 'cannot capture pre-ping outbox byte offset' 32; fi
if ! ping_detail=$(timeout 25 stobe-auto stobe_ping </dev/null | tr -d '\r'); then
  fail 'the single stobe_ping did not return an ACK' 33
fi
printf 'PING_DETAIL=%s\n' "$ping_detail"
if ! python - "$outbox" "$outbox_start" "$ping_detail" <<'PY'
import re, sys
path, offset, expected = sys.argv[1], int(sys.argv[2]), sys.argv[3]
with open(path, 'rb') as stream:
    stream.seek(offset)
    appended = stream.read()
lines = [line.rstrip(b'\r') for line in appended.splitlines() if line]
if len(lines) != 1:
    raise SystemExit('ACK_CORRELATION_FAIL expected exactly one new outbox reply')
parts = lines[0].decode('utf-8', 'replace').split('\t', 2)
if len(parts) != 3 or not re.fullmatch(r'k[0-9]+_[0-9]+_[0-9]+', parts[0]):
    raise SystemExit('ACK_CORRELATION_FAIL malformed or missing request id')
if parts[1] != 'ok' or parts[2] != expected:
    raise SystemExit('ACK_CORRELATION_FAIL outbox reply differs from stobe-auto response')
if not re.fullmatch(r'mode=chat speaker=Bark nearest=(?:none|.+)', parts[2]):
    raise SystemExit('PING_GATE_FAIL expected chat mode and player Bark as speaker')
print('CORRELATED_ACK request_id=%s status=%s detail=%s' % (parts[0], parts[1], parts[2]))
PY
then
  fail 'ping ACK could not be correlated to exactly one new outbox record' 34
fi

printf '\n=== SAME WORLD AFTER PING ===\n'
if ! status_after=$(read_native status status); then fail 'post-ping world/save request failed' 35; fi
printf 'STATUS_AFTER=%s\n' "$status_after"
expected_world "$status_after" || fail 'world/save changed across native ping' 36
[[ "$status_before" == "$status_after" ]] || fail 'world/save status changed across native ping' 36

printf '\n=== POST-PING PROCESS / BUILD / CONFIG / ISOLATION / LOCK ===\n'
if ! probe_after=$(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
  -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' \
  -ExpectedExecutablePath 'C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'); then
  printf '%s\n' "$probe_after"
  fail 'post-ping exact i3 process/module probe failed' 37
fi
[[ "$probe_before" == "$probe_after" ]] || fail 'process/PID/module-path/on-disk hash changed across ping' 37
config_after=$(grep -iE '^(ServerHost|ServerPort)=' /c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini | tr -d '\r') || fail 'post-ping i3 config read failed' 38
[[ "$config_before" == "$config_after" ]] || fail 'i3 backend config changed across ping' 38
if ! isolation_after=$(read_native isolation input_isolation status); then fail 'post-ping isolation request failed' 39; fi
printf 'ISOLATION_AFTER=%s\n' "$isolation_after"
[[ "$isolation_after" == isolation=on* && "$isolation_before" == isolation=on* ]] || fail 'input isolation is no longer on' 39
if ! lock_after=$(read_game_lock); then fail 'post-ping instance-3 game-lock query failed' 40; fi
printf 'GAME_LOCK_AFTER=%s\n' "$lock_after"
lock_is_free "$lock_after" && [[ "$lock_before" == "$lock_after" ]] || fail 'instance-3 game lock changed or became held during ping' 40
if ! check_route; then fail 'isolated i3 route/inbox gate stopped after ping' 41; fi

echo 'RESULT 4080-I3-PING-GATE PASS native_gate=PlaythroughSession.Allowed_generation_ack_only backend_auth=unverified save_identity_binding=unproven gameplay=0 chat=0 input=0 world_save_mutation=0 retries=0'
