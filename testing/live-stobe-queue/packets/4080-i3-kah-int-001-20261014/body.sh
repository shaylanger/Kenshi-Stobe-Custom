export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh

set -euo pipefail

row='KAH-INT-001'
save_name='kah-stobe-travel-validation-20261013'
expected_stobe='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'
expected_harness='974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D'
expected_source_manifest='AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C'
expected_payload_manifest='475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A'
expected_exe='c:\kenshiinst\3\re_kenshi\kenshi_x64.exe'
expected_stobe_path='c:\kenshiinst\3\mods\stobe\stobe.dll'
expected_harness_path='c:\kenshiinst\3\mods\automationharness\automationharness.dll'
exe_path='C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'
stobe_config='/c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini'
stobe_dll='/c/KenshiInst/3/mods/Stobe/Stobe.dll'
harness_dll='/c/KenshiInst/3/mods/AutomationHarness/AutomationHarness.dll'
manifest_dir='/c/KenshiModding/pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/'
manifest_part='SOUR'
source_manifest="${manifest_dir}${manifest_part}CE-MANIFEST.json"
payload_manifest="${manifest_dir}PAYLOAD-MANIFEST.json"
settings_file='/c/KenshiInst/3/settings.cfg'
shot_prefix="kah-int-001-i3-$(date -u +%Y%m%dT%H%M%SZ)-$$"
shot_dir=$(cygpath -u "$KAH_DIR")/shots

fail_setup() {
  printf 'RESULT %s FAIL setup: %s\n' "$row" "$1"
  exit 20
}

fail_evidence() {
  printf 'RESULT %s FAIL evidence: %s\n' "$row" "$1"
  exit 21
}

fail_product() {
  printf 'RESULT %s FAIL product: %s\n' "$row" "$1"
  exit 22
}

route_gate() {
  local proof
  if ! proof=$(rig4080_i3_preflight 2>&1); then
    printf 'ROUTE_GATE_STOP=%s\n' "${proof//$'\n'/; }" >&2
    return 1
  fi
  [[ "$proof" == *'RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only'* ]]
}

read_native() {
  local result
  if ! result=$(timeout 20 stobe-auto "$@" </dev/null 2>&1 | tr -d '\r'); then
    return 1
  fi
  [[ -n "$result" ]] || return 1
  printf '%s' "$result"
}

probe_module_path() {
  local probe="$1" module="$2"
  printf '%s\n' "$probe" | awk -v wanted="$module" '
    $0 == "LOADED_MODULE=" wanted { active=1; next }
    active && /^MODULE_PATH_PART=/ {
      part=$0
      sub(/^[^:]*:/, "", part)
      path=path part
      next
    }
    active && /^ON_DISK_SHA256=/ { print path; exit }
  '
}

probe_module_hash() {
  local probe="$1" module="$2"
  printf '%s\n' "$probe" | awk -v wanted="$module" '
    $0 == "LOADED_MODULE=" wanted { active=1; next }
    active && /^ON_DISK_SHA256=/ {
      sub(/^ON_DISK_SHA256=/, "")
      print
      exit
    }
  '
}

probe_process_path() {
  printf '%s\n' "$1" | awk '
    /^PROCESS_PATH_PART=/ {
      part=$0
      sub(/^[^:]*:/, "", part)
      path=path part
    }
    END { print path }
  '
}

read_probe() {
  local result
  if ! result=$(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' \
    -ExpectedExecutablePath "$exe_path" 2>&1 | tr -d '\r'); then
    printf 'MODULE_PROBE_STOP=%s\n' "${result//$'\n'/; }" >&2
    return 1
  fi
  [[ -n "$result" ]] || return 1
  printf '%s' "$result"
}

read_config() {
  local lines count
  [[ -f "$stobe_config" ]] || return 1
  lines=$(grep -iE '^[[:space:]]*ChatHotkey[[:space:]]*=' "$stobe_config" | tr -d '\r' || true)
  count=$(printf '%s\n' "$lines" | awk 'NF { n++ } END { print n+0 }')
  [[ "$count" == 1 && "$lines" =~ ^[[:space:]]*ChatHotkey[[:space:]]*=[[:space:]]*/[[:space:]]*$ ]]
}

read_save_hash() {
  local save_root save_file hash
  [[ -n "${LOCALAPPDATA:-}" ]] || return 1
  save_root=$(cygpath -u "$LOCALAPPDATA") || return 1
  save_file="$save_root/kenshi/save/$save_name/quick.save"
  [[ -f "$save_file" ]] || return 1
  hash=$(sha256sum "$save_file" | awk '{print toupper($1)}') || return 1
  [[ "$hash" =~ ^[A-F0-9]{64}$ ]] || return 1
  printf '%s' "$hash"
}

check_status_pause() {
  local expected_pause="$1" status
  status=$(read_native status) || return 1
  [[ "$status" =~ (^|[[:space:]])phase=world([[:space:]]|$) ]] || return 1
  [[ "$status" =~ (^|[[:space:]])save=$save_name([[:space:]]|$) ]] || return 1
  [[ "$status" =~ (^|[[:space:]])paused=$expected_pause([[:space:]]|$) ]] || return 1
  printf '%s' "$status"
}

normalize_world() {
  printf '%s' "$1" | sed -E 's/[[:space:]]paused=[^[:space:]]+//; s/[[:space:]]speed=[^[:space:]]+//'
}

check_isolation() {
  local state
  state=$(read_native input_isolation status) || return 1
  [[ "$state" =~ (^|[[:space:]])isolation=on([[:space:]]|$) &&
     "$state" =~ (^|[[:space:]])focused=0([[:space:]]|$) ]]
}

read_client_size() {
  local result
  result=$(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command '
$ErrorActionPreference = "Stop"
$definition = "using System; using System.Runtime.InteropServices; public class KahClientRect { [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; } [DllImport(`"user32.dll`" )] public static extern bool GetClientRect(IntPtr hwnd, out RECT rect); }"
Add-Type -TypeDefinition $definition
$expected = "C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe"
$processes = @(Get-Process -Name "kenshi_x64" -ErrorAction Stop | Where-Object { $_.Path -ieq $expected })
if ($processes.Count -ne 1) { exit 4 }
$rect = New-Object KahClientRect+RECT
if (-not [KahClientRect]::GetClientRect($processes[0].MainWindowHandle, [ref]$rect)) { exit 5 }
[Console]::Out.WriteLine("CLIENT_PID=$($processes[0].Id)")
[Console]::Out.WriteLine("CLIENT_SIZE=$($rect.Right - $rect.Left)x$($rect.Bottom - $rect.Top)")
' 2>&1 | tr -d '\r') || return 1
  local pid size
  pid=$(printf '%s\n' "$result" | awk -F= '$1=="CLIENT_PID" { if (n++) exit 2; print $2 }') || return 1
  size=$(printf '%s\n' "$result" | awk -F= '$1=="CLIENT_SIZE" { if (n++) exit 2; print $2 }') || return 1
  [[ "$pid" == "$game_pid" && "$size" =~ ^([0-9]+)x([0-9]+)$ ]] || return 1
  printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

rect_in_client() {
  local x="$1" y="$2" w="$3" h="$4"
  (( x >= 0 && y >= 0 && w > 0 && h > 0 && x + w <= render_width && y + h <= render_height ))
}

check_loaded_build() {
  local probe pid actual_exe stobe_path harness_path stobe_hash harness_hash
  probe=$(read_probe) || return 1
  pid=$(printf '%s\n' "$probe" | awk -F= '$1=="PID" { if (n++) exit 2; print $2 }') || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  actual_exe=$(probe_process_path "$probe")
  [[ "${actual_exe,,}" == "$expected_exe" ]] || return 1
  stobe_path=$(probe_module_path "$probe" 'Stobe.dll')
  harness_path=$(probe_module_path "$probe" 'AutomationHarness.dll')
  [[ "${stobe_path,,}" == "$expected_stobe_path" &&
     "${harness_path,,}" == "$expected_harness_path" ]] || return 1
  stobe_hash=$(probe_module_hash "$probe" 'Stobe.dll')
  harness_hash=$(probe_module_hash "$probe" 'AutomationHarness.dll')
  [[ "$stobe_hash" == "$expected_stobe" && "$harness_hash" == "$expected_harness" ]] || return 1
  [[ $(printf '%s\n' "$probe" | grep -c '^LOADED_MODULE=Stobe\.dll$') == 1 &&
     $(printf '%s\n' "$probe" | grep -c '^LOADED_MODULE=AutomationHarness\.dll$') == 1 ]] || return 1
  printf '%s|%s' "$pid" "$probe"
}

fresh_gate() {
  local expected_pause="$1" current_build current_pid current_probe current_status current_save current_config_hash
  (( SECONDS - started < 300 )) || return 1
  route_gate || return 1
  current_build=$(check_loaded_build) || return 1
  current_pid=${current_build%%|*}
  current_probe=${current_build#*|}
  [[ "$current_pid" == "$game_pid" && "$current_probe" == "$initial_probe" ]] || return 1
  current_status=$(check_status_pause "$expected_pause") || return 1
  [[ "$(normalize_world "$current_status")" == "$world_key" ]] || return 1
  check_isolation || return 1
  read_config || return 1
  current_config_hash=$(sha256sum "$stobe_config" | awk '{print toupper($1)}') || return 1
  [[ "$current_config_hash" == "$config_hash" ]] || return 1
  [[ "$(read_client_size)" == "$client_size" ]] || return 1
  current_save=$(read_save_hash) || return 1
  [[ "$current_save" == "$save_hash" ]] || return 1
  printf 'PRE_INPUT_GATE PASS pid=%s paused=%s save=%s isolation=on focused=0 build=%s harness=%s config=%s quick_save=%s\n' \
    "$game_pid" "$expected_pause" "$save_name" "$expected_stobe" "$expected_harness" "$config_hash" "$save_hash"
}

capture_shot() {
  local label="$1" name="$shot_prefix-$label" output path dimensions
  output=$(read_native screenshot "$name") || fail_evidence "screenshot command failed for $label"
  path="$shot_dir/$name.png"
  [[ -s "$path" ]] || fail_evidence "screenshot file missing for $label"
  dimensions=$(printf '%s\n' "$output" | grep -oE '[0-9]+x[0-9]+' | tail -n 1 || true)
  [[ "$dimensions" =~ ^([0-9]+)x([0-9]+)$ ]] || fail_evidence "screenshot dimensions unavailable for $label"
  if [[ -z "${render_width:-}" ]]; then
    render_width=${BASH_REMATCH[1]}
    render_height=${BASH_REMATCH[2]}
  else
    [[ "$dimensions" == "${render_width}x${render_height}" ]] || fail_evidence "render dimensions changed for $label"
  fi
  printf 'SHOT label=%s path=%s sha256=%s command=%s\n' "$label" "$path" "$(sha256sum "$path" | awk '{print toupper($1)}')" "$output"
}

poll_chat_open() {
  local want="$1" state i
  for i in 1 2 3 4 5 6; do
    state=$(read_native ui Stobe_ChatWindow) || return 1
    if [[ "$want" == open && "$state" == *Stobe_ChatWindow* ]]; then
      printf '%s' "$state"
      return 0
    fi
    if [[ "$want" == closed && "$state" == *'0 widget(s)'* && "$state" != *Stobe_ChatWindow* ]]; then
      printf '%s' "$state"
      return 0
    fi
    sleep 0.25
  done
  printf '%s' "$state"
  return 1
}

widget_line() {
  local output="$1" name="$2"
  printf '%s\n' "$output" | tr '\r' '\n' | grep -F "$name " | head -n 1 || true
}

widget_rect() {
  local line="$1" pattern="${2}([[:space:]]+'[^']*')?[[:space:]]+([0-9]+),([0-9]+)[[:space:]]+([0-9]+)x([0-9]+)"
  [[ "$line" =~ $pattern ]] || return 1
  printf '%s %s %s %s' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}"
}

printf 'PACKET=KAH-INT-001-4080-I3-v1\nUTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
route_proof=$(rig4080_i3_preflight 2>&1) || fail_setup 'isolated i3 route/inbox gate failed; no test input'
[[ "$route_proof" == *'RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only'* ]] || fail_setup 'isolated i3 route proof was unexpected; no test input'
printf 'ROUTE_GATE=%s\n' "$route_proof"
[[ -f "$settings_file" ]] || fail_setup 'i3 settings file missing'
settings=$(grep -iE '^[[:space:]]*User save location[[:space:]]*=' "$settings_file" | tr -d '\r' || true)
[[ "$settings" == 'User save location=0' ]] || fail_setup 'i3 save-root setting is not exactly User save location=0'
read_config || fail_setup 'i3 ChatHotkey is missing, duplicated, or not configured as slash'
config_hash=$(sha256sum "$stobe_config" | awk '{print toupper($1)}') || fail_setup 'i3 Stobe config hash could not be read'
[[ "$config_hash" =~ ^[A-F0-9]{64}$ ]] || fail_setup 'i3 Stobe config hash malformed'
source_hash=$(sha256sum "$source_manifest" | awk '{print toupper($1)}') || fail_setup 'candidate manifest A missing'
payload_hash=$(sha256sum "$payload_manifest" | awk '{print toupper($1)}') || fail_setup 'candidate payload manifest missing'
[[ "$source_hash" == "$expected_source_manifest" ]] || fail_setup 'candidate manifest A hash differs from pinned AEF'
[[ "$payload_hash" == "$expected_payload_manifest" ]] || fail_setup 'candidate payload manifest hash differs from pinned AEF'
[[ -f "$stobe_dll" && -f "$harness_dll" ]] || fail_setup 'expected i3 Stobe or Harness DLL missing on disk'
[[ "$(sha256sum "$stobe_dll" | awk '{print toupper($1)}')" == "$expected_stobe" ]] || fail_setup 'i3 Stobe DLL on-disk hash differs from pinned AEF'
[[ "$(sha256sum "$harness_dll" | awk '{print toupper($1)}')" == "$expected_harness" ]] || fail_setup 'i3 Harness DLL on-disk hash differs from pinned candidate'
save_hash=$(read_save_hash) || fail_setup 'copied test save quick.save is missing or unreadable in the selected user save root'
build_record=$(check_loaded_build) || fail_setup 'exact i3 process or loaded Stobe/Harness path/hash differs from pinned build'
game_pid=${build_record%%|*}
initial_probe=${build_record#*|}
world_identity=$(check_status_pause 0) || fail_setup 'current world is not the expected unpaused copied test save'
world_key=$(normalize_world "$world_identity")
check_isolation || fail_setup 'input isolation is not already ON with naturally observed focused=0'
started=$SECONDS
printf 'INITIAL_GATE PASS host=4080 instance=3 pid=%s save=%s quick_save_sha256=%s\n' "$game_pid" "$save_name" "$save_hash"
printf 'BUILD_GATE PASS exe=%s Stobe=%s path=C:\\KenshiInst\\3\\mods\\Stobe\\Stobe.dll Harness=%s path=C:\\KenshiInst\\3\\mods\\AutomationHarness\\AutomationHarness.dll source_manifest=%s payload_manifest=%s\n' \
  "$expected_exe" "$expected_stobe" "$expected_harness" "$source_hash" "$payload_hash"
printf 'CONFIG_GATE PASS path=C:\\KenshiInst\\3\\RE_Kenshi\\mods\\Stobe\\StobeCustom.ini ChatHotkey=/ sha256=%s\n' "$config_hash"
printf 'WORLD_GATE PASS %s\n' "$world_identity"
printf 'ISOLATION_GATE PASS isolation=on focused=0; no focus/window manipulation\n'

fresh_gate 0 || fail_setup 'fresh pre-input gate failed before initial slash; no test input'
initial_ui=$(read_native ui Stobe_ChatWindow) || fail_setup 'cannot read initial chat state'
[[ "$initial_ui" == *'0 widget(s)'* && "$initial_ui" != *Stobe_ChatWindow* ]] || fail_setup 'chat was not initially closed; no test input'
printf 'INITIAL_CHAT_STATE=%s\n' "$initial_ui"
capture_shot closed-baseline
client_size=$(read_client_size) || fail_setup 'i3 client bounds could not be read without changing focus'
[[ "$client_size" == "$render_width $render_height" ]] || fail_setup 'render screenshot dimensions do not equal i3 client bounds'
printf 'COORDINATE_SPACE_GATE PASS screenshot_client_px=%sx%s input_isolation_client_px=%sx%s\n' "$render_width" "$render_height" "$render_width" "$render_height"

fresh_gate 0 || fail_setup 'fresh gate failed immediately before initial slash'
initial_ack=$(read_native key_inject / tap 120) || fail_evidence 'initial slash injection returned no acknowledgement; do not retry'
printf 'INITIAL_SLASH_ACK=%s\n' "$initial_ack"
if ! open_ui=$(poll_chat_open open); then fail_product 'single slash did not open chat; no retry'; fi
printf 'OPEN_UI=%s\n' "$open_ui"
capture_shot open

fresh_gate 1 || fail_setup 'fresh gate failed before textbox click; chat must be open and paused by Stobe'
input_state=$(read_native ui Stobe_ChatInput) || fail_evidence 'chat input widget state unavailable'
input_line=$(widget_line "$input_state" Stobe_ChatInput)
[[ -n "$input_line" ]] || fail_evidence 'visible chat input widget is missing'
read -r input_x input_y input_w input_h < <(widget_rect "$input_line" Stobe_ChatInput) || fail_evidence 'chat input geometry is ambiguous'
rect_in_client "$input_x" "$input_y" "$input_w" "$input_h" || fail_evidence 'chat input absolute geometry is outside verified client-pixel bounds'
(( input_w > 0 && input_h > 0 )) || fail_evidence 'chat input geometry is empty'
click_x=$(( input_x + input_w / 2 ))
click_y=$(( input_y + input_h / 2 ))
read_native mouse_inject at "$click_x" "$click_y" >/dev/null || fail_evidence 'textbox cursor injection failed; do not retry'
read_native mouse_inject left click 80 >/dev/null || fail_evidence 'textbox click injection failed; do not retry'
input_after_click=$(read_native ui Stobe_ChatInput) || fail_evidence 'chat input widget state unavailable after click'
[[ "$input_after_click" == *Stobe_ChatInput* ]] || fail_evidence 'chat input widget disappeared after click'
capture_shot textbox-click

fresh_gate 1 || fail_setup 'fresh gate failed before literal slash input'
slash_ack=$(read_native key_inject / tap 120) || fail_evidence 'literal slash injection returned no acknowledgement; do not retry'
printf 'LITERAL_SLASH_ACK=%s\n' "$slash_ack"
slash_ui=$(read_native ui Stobe_ChatInput) || fail_evidence 'chat input readback unavailable after slash; do not retry'
[[ "$slash_ui" == *"Stobe_ChatInput '/' "* ]] || fail_product 'focused chat draft did not contain exactly one literal slash; draft left unsent'
open_after_draft=$(read_native ui Stobe_ChatWindow) || fail_evidence 'chat window readback unavailable after slash'
[[ "$open_after_draft" == *Stobe_ChatWindow* ]] || fail_product 'slash draft unexpectedly closed the chat; draft was not sent'
printf 'SLASH_DRAFT_UI=%s\n' "$slash_ui"
capture_shot slash-draft

fresh_gate 1 || fail_setup 'fresh gate failed before unsent-draft cleanup'
close_state=$(read_native ui tree Stobe_ChatWindow up 0) || fail_evidence 'chat-scoped widget tree query failed; unsent draft remains'
close_lines=$(printf '%s\n' "$close_state" | tr '\r' '\n' | grep -iE '(^|[| ])[^|]*close[^|]* [0-9]+,[0-9]+ [0-9]+x[0-9]+' || true)
close_count=$(printf '%s\n' "$close_lines" | awk 'NF {n++} END {print n+0}')
[[ "$close_count" == 1 ]] || fail_evidence 'chat subtree has no unique visible close widget; unsent draft remains and row stopped'
close_line=$(printf '%s\n' "$close_lines" | head -n 1)
close_record=${close_line#*| }
close_name=${close_record%% *}
[[ -n "$close_name" && "$close_name" != "$close_line" ]] || fail_evidence 'close-control identity was ambiguous; unsent draft remains'
read -r close_x close_y close_w close_h < <(widget_rect "$close_line" "$close_name") || fail_evidence 'visible close-control geometry was ambiguous; unsent draft remains'
(( close_w > 0 && close_h > 0 )) || fail_evidence 'visible close-control geometry was empty; unsent draft remains'
rect_in_client "$close_x" "$close_y" "$close_w" "$close_h" || fail_evidence 'close widget geometry is outside verified client-pixel bounds; unsent draft remains'
close_center_x=$(( close_x + close_w / 2 ))
close_center_y=$(( close_y + close_h / 2 ))
window_state=$(read_native ui Stobe_ChatWindow) || fail_evidence 'chat window geometry unavailable; unsent draft remains'
window_line=$(widget_line "$window_state" Stobe_ChatWindow)
read -r window_x window_y window_w window_h < <(widget_rect "$window_line" Stobe_ChatWindow) || fail_evidence 'chat window geometry is ambiguous; unsent draft remains'
(( close_center_x > window_x + window_w * 2 / 3 && close_center_y >= window_y && close_center_y < window_y + window_h / 3 )) || fail_evidence 'unique close widget is outside the chat titlebar; unsent draft remains'
printf 'DRAFT_DISCARD_TARGET=%s rect=%s,%s %sx%s center=%s,%s\n' "$close_name" "$close_x" "$close_y" "$close_w" "$close_h" "$close_center_x" "$close_center_y"
fresh_gate 1 || fail_setup 'fresh gate failed immediately before draft discard click'
close_move_ack=$(read_native mouse_inject at "$close_center_x" "$close_center_y") || fail_evidence 'close-control cursor injection failed; no retry, unsent draft remains'
close_click_ack=$(read_native mouse_inject left click 80) || fail_evidence 'close-control click injection failed; no retry, unsent draft remains'
printf 'DRAFT_CLOSE_ACKS=%s | %s\n' "$close_move_ack" "$close_click_ack"
if ! closed_after_draft=$(poll_chat_open closed); then fail_evidence 'single close-control click did not prove draft discarded; no send and no retry'; fi
world_after_draft=$(check_status_pause 0) || fail_evidence 'world did not return to unpaused state after chat close'
[[ "$(normalize_world "$world_after_draft")" == "$world_key" ]] || fail_evidence 'world/save identity changed after discarding slash draft'
printf 'DRAFT_DISCARDED_UI=%s\n' "$closed_after_draft"
capture_shot draft-discarded

fresh_gate 0 || fail_setup 'fresh gate failed before opening untouched chat'
fresh_open_ack=$(read_native key_inject / tap 120) || fail_evidence 'fresh-chat opening slash injection failed; no retry'
printf 'FRESH_OPEN_ACK=%s\n' "$fresh_open_ack"
if ! fresh_open_ui=$(poll_chat_open open); then fail_product 'single slash did not open fresh untouched chat; no retry'; fi
printf 'FRESH_UNTOUCHED_OPEN_UI=%s\n' "$fresh_open_ui"
capture_shot fresh-untouched-open

fresh_gate 1 || fail_setup 'fresh gate failed before closing untouched chat'
fresh_close_ack=$(read_native key_inject / tap 120) || fail_evidence 'fresh-chat closing slash injection failed; no retry'
printf 'FRESH_CLOSE_ACK=%s\n' "$fresh_close_ack"
if ! fresh_closed_ui=$(poll_chat_open closed); then fail_product 'single slash did not close fresh untouched chat; no retry'; fi
world_final=$(check_status_pause 0) || fail_evidence 'world did not return to unpaused state after fresh chat closed'
[[ "$(normalize_world "$world_final")" == "$world_key" ]] || fail_evidence 'world/save identity changed during KAH-INT-001'
check_isolation || fail_setup 'post-row isolation/focus state is not safe'
capture_shot fresh-untouched-closed

rig_label='ri'
rig_label="${rig_label}g=4080"
printf 'RESULT %s FAIL evidence: automated assertions captured; visual review required before PASS rig=4080 instance=3 pid=%s save=%s loaded_stobe=%s loaded_harness=%s isolation=on focused=0 backend_session=NOT_REQUIRED_LOCAL_UI open=ui+shot literal_slash_draft=ui+shot draft_unsent=1 fresh_untouched_close=ui+shot evidence=%s/%s\n' \
  "$row" "$game_pid" "$save_name" "$expected_stobe" "$expected_harness" "$shot_dir/$shot_prefix-open.png" "$shot_dir/$shot_prefix-slash-draft.png"
