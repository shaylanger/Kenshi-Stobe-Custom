#!/usr/bin/env bash
# KAH-INT-001 local-only candidate. Requires exact review and fresh row-specific clearance.
# Coordinates are derived only from the fresh scoped UI tree and screenshot dimensions.
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail

readonly ROW=KAH-INT-001
readonly EXPECTED_EXE='C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'
readonly EXPECTED_STOBE='C:\KenshiInst\3\mods\Stobe\Stobe.dll'
readonly EXPECTED_HARNESS='C:\KenshiInst\3\mods\AutomationHarness\AutomationHarness.dll'
readonly EXPECTED_SAVE='kah-stobe-travel-validation-20261013'
readonly STOBE_SHA='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'
readonly HARNESS_SHA='974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D'
readonly SOURCE_MANIFEST_SHA='AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C'
readonly PAYLOAD_MANIFEST_SHA='475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A'
readonly BODY_DIR='/c/KenshiModding/testing/live-stobe-queue/packets/4080-i3-kah-int-001-20261014-parallel'
readonly EVIDENCE_ROOT='/c/KenshiTestRuns/kah-int-001-4080-i3'

fail_setup() { printf 'RESULT %s FAIL setup: %s input_count=%s\n' "$ROW" "$1" "${INPUT_COUNT:-0}"; exit 20; }
fail_evidence() { printf 'RESULT %s FAIL evidence: %s input_count=%s\n' "$ROW" "$1" "${INPUT_COUNT:-0}"; exit 21; }
fail_product() { printf 'RESULT %s FAIL product: %s input_count=%s\n' "$ROW" "$1" "${INPUT_COUNT:-0}"; exit 22; }

# Non-invasive dry selfcheck is useful only when running a local copy, never via the 4080 wrapper.
if [[ "${PACKET_SELFTEST:-0}" == 1 ]]; then
  [[ "$RIG:$KAH_INSTANCE:$KENSHI_DIR:$KDIR:$KAH_DIR" == '4080:3:/c/KenshiInst/3:/c/KenshiInst/3:C:\KenshiInst\3\mods\AutomationHarness' ]] || { echo SELFTEST_FAIL_route; exit 90; }
  [[ "$STOBE_SHA" =~ ^[A-F0-9]{64}$ && "$HARNESS_SHA" =~ ^[A-F0-9]{64}$ ]] || { echo SELFTEST_FAIL_hash_constants; exit 91; }
  [[ "phase=world save=$EXPECTED_SAVE paused=0 speed=1.0" == *"phase=world"*"save=$EXPECTED_SAVE"*"paused=0"* ]] || { echo SELFTEST_FAIL_world_accept; exit 92; }
  [[ "phase=world save=$EXPECTED_SAVE paused=1 speed=1.0" != *"paused=0"* ]] || { echo SELFTEST_FAIL_paused_reject; exit 93; }
  [[ 'isolation=on frames=24 focused=0' == isolation=on*focused=0* ]] || { echo SELFTEST_FAIL_isolation_accept; exit 94; }
  [[ 'isolation=on frames=24 focused=1' != isolation=on*focused=0* ]] || { echo SELFTEST_FAIL_focus_reject; exit 95; }
  [[ 'ChatHotkey=/' == 'ChatHotkey=/' ]] || { echo SELFTEST_FAIL_config; exit 96; }
  [[ "${INPUT_COUNT:-0}" == 0 ]] || { echo SELFTEST_FAIL_dry_input; exit 97; }
  echo 'RESULT KAH-INT-001-SELFTEST PASS cases=8 remote=0 KAH=0 input=0'
  exit 0
fi

INPUT_COUNT=0
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
EVIDENCE_DIR="$EVIDENCE_ROOT/$RUN_ID"
mkdir -p "$EVIDENCE_DIR" || fail_setup evidence_directory_unavailable

# Gate 1: the exact reviewed transport preamble must resolve to instance 3;
# the helper checks pending inbox/lock by presence only and changes nothing.
[[ "$RIG" == 4080 && "$KAH_INSTANCE" == 3 && "$KENSHI_DIR" == /c/KenshiInst/3 && "$KDIR" == /c/KenshiInst/3 && "$KAH_DIR" == 'C:\KenshiInst\3\mods\AutomationHarness' ]] || fail_setup route_variables_mismatch
route_report=$(rig4080_i3_preflight 2>&1) || fail_setup "i3_route_or_inbox_gate: ${route_report//$'\n'/; }"
[[ "$route_report" == *'RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only'* ]] || fail_setup unexpected_route_proof

# Gate 2: one exact running i3 process and both pinned loaded modules. Helper output
# ties loaded path and on-disk hash to the process; do not accept an install receipt.
module_proof=$(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' -ExpectedExecutablePath "$EXPECTED_EXE" 2>&1 | tr -d '\r') || fail_setup loaded_module_probe_failed
printf '%s\n' "$module_proof" >"$EVIDENCE_DIR/module-proof.txt"
pid=$(python3 - "$EVIDENCE_DIR/module-proof.txt" "$EXPECTED_EXE" "$EXPECTED_STOBE" "$EXPECTED_HARNESS" "$STOBE_SHA" "$HARNESS_SHA" <<'PY'
import sys
lines=open(sys.argv[1],encoding='utf-8',errors='replace').read().splitlines()
want_exe,want_stobe,want_harness,want_stobe_hash,want_harness_hash=sys.argv[2:]
pid=''; exe=[]; modules={}; current=None
for line in lines:
    if line.startswith('PID='): pid=line[4:]
    elif line.startswith('PROCESS_PATH_PART='):
        exe.append(line.split(':',1)[1] if ':' in line else '')
    elif line.startswith('LOADED_MODULE='):
        current=line.split('=',1)[1]; modules[current]={'path':[],'hash':''}
    elif line.startswith('MODULE_PATH_PART=') and current:
        modules[current]['path'].append(line.split(':',1)[1] if ':' in line else '')
    elif line.startswith('ON_DISK_SHA256=') and current:
        modules[current]['hash']=line.split('=',1)[1].upper(); current=None
if not pid.isdigit() or ''.join(exe)!=want_exe: sys.exit(1)
for name,path,digest in [('Stobe.dll',want_stobe,want_stobe_hash),('AutomationHarness.dll',want_harness,want_harness_hash)]:
    row=modules.get(name)
    if not row or ''.join(row['path']).lower()!=path.lower() or row['hash']!=digest.upper(): sys.exit(2)
print(pid)
PY
) || fail_setup exact_i3_process_or_loaded_module_path_hash_mismatch
[[ "$pid" =~ ^[0-9]+$ ]] || fail_setup exact_i3_pid_missing
printf 'PROCESS_PID=%s\nPROCESS_PATH=%s\nSTOBE_SHA256=%s\nHARNESS_SHA256=%s\n' "$pid" "$EXPECTED_EXE" "$STOBE_SHA" "$HARNESS_SHA"

# Pin local candidate provenance and the actual i3 on-disk payload. These reads
# are read-only and run before any UI input.
source_manifest='/c/KenshiModding/pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/SOURCE-MANIFEST.json'
payload_manifest='/c/KenshiModding/pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/PAYLOAD-MANIFEST.json'
source_hash=$(sha256sum "$source_manifest" | awk '{print toupper($1)}') || fail_setup source_manifest_unavailable
payload_hash=$(sha256sum "$payload_manifest" | awk '{print toupper($1)}') || fail_setup payload_manifest_unavailable
[[ "$source_hash" == "$SOURCE_MANIFEST_SHA" && "$payload_hash" == "$PAYLOAD_MANIFEST_SHA" ]] || fail_setup candidate_manifest_pin_mismatch
stobe_disk_hash=$(sha256sum /c/KenshiInst/3/mods/Stobe/Stobe.dll | awk '{print toupper($1)}') || fail_setup i3_stobe_file_unavailable
harness_disk_hash=$(sha256sum /c/KenshiInst/3/mods/AutomationHarness/AutomationHarness.dll | awk '{print toupper($1)}') || fail_setup i3_harness_file_unavailable
[[ "$stobe_disk_hash" == "$STOBE_SHA" && "$harness_disk_hash" == "$HARNESS_SHA" ]] || fail_setup i3_on_disk_payload_mismatch

# Gate 3: read-only config, world and copied save evidence. No backend/session query.
ini=/c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini
[[ -f "$ini" ]] || fail_setup i3_stobe_config_missing
ini_hash=$(sha256sum "$ini" | awk '{print toupper($1)}') || fail_setup i3_stobe_config_unreadable
hotkey_lines=$(grep -iE '^[[:space:]]*ChatHotkey[[:space:]]*=' "$ini" | sed 's/[[:space:]]//g' | tr -d '\r') || fail_setup chat_hotkey_config_unreadable
[[ "$hotkey_lines" == 'ChatHotkey=/' ]] || fail_setup "ChatHotkey_not_exactly_slash: $hotkey_lines"
status_before=$(timeout 12 stobe-auto status </dev/null 2>&1 | tr -d '\r') || fail_setup kah_world_status_unavailable
[[ "$status_before" == *'phase=world'* && "$status_before" == *"save=$EXPECTED_SAVE"* && "$status_before" == *'paused=0'* ]] || fail_setup current_world_not_expected_unpaused_copied_save
save_root=$(cygpath -u "$LOCALAPPDATA") || fail_setup local_save_root_unavailable
save_file="$save_root/kenshi/save/$EXPECTED_SAVE/quick.save"
[[ -f "$save_file" ]] || fail_setup copied_save_quick_save_missing
save_hash=$(sha256sum "$save_file" | awk '{print toupper($1)}') || fail_setup copied_save_quick_save_unreadable
[[ "$save_hash" =~ ^[A-F0-9]{64}$ ]] || fail_setup copied_save_hash_malformed

# Gate 4: input isolation is required and naturally observed focused=0. Turning
# isolation on is the harness's safety gate; no focus/window commands are used.
isolation_on=$(timeout 12 stobe-auto input_isolation on </dev/null 2>&1 | tr -d '\r') || fail_setup input_isolation_enable_failed
isolation=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup input_isolation_status_unavailable
[[ "$isolation" == isolation=on* && "$isolation" == *'focused=0'* ]] || fail_setup "isolation_or_natural_focus_gate_failed: $isolation"

# Recheck all changing preconditions immediately before first input.
status_fresh=$(timeout 12 stobe-auto status </dev/null 2>&1 | tr -d '\r') || fail_setup fresh_world_status_unavailable
[[ "$status_fresh" == *'phase=world'* && "$status_fresh" == *"save=$EXPECTED_SAVE"* && "$status_fresh" == *'paused=0'* ]] || fail_setup world_save_or_pause_changed_before_input
isolation_fresh=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup fresh_input_isolation_status_unavailable
[[ "$isolation_fresh" == isolation=on* && "$isolation_fresh" == *'focused=0'* ]] || fail_setup natural_focus_or_isolation_changed_before_input

printf 'PREFLIGHT PASS rig=4080 instance=3 pid=%s save=%s quick_save_sha256=%s stobe_sha256=%s harness_sha256=%s source_manifest_sha256=%s payload_manifest_sha256=%s ini_sha256=%s ChatHotkey=/ backend_session=NOT_REQUIRED_LOCAL_UI\n' "$pid" "$EXPECTED_SAVE" "$save_hash" "$STOBE_SHA" "$HARNESS_SHA" "$source_hash" "$payload_hash" "$ini_hash"
printf 'ISOLATION_ENABLE=%s\nISOLATION_STATUS=%s\n' "$isolation_on" "$isolation"
ROW_DEADLINE=$((SECONDS+300))
within_bound() { (( SECONDS <= ROW_DEADLINE )) || fail_setup five_minute_interaction_bound_exceeded; }

# The baseline must be a closed chat before the test key; ui tree is scoped to
# Stobe_ChatWindow and never invokes the global `ui close` command.
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/00-tree-before.txt" 2>&1 || fail_evidence baseline_chat_tree_failed
cat "$EVIDENCE_DIR/00-tree-before.txt"
grep -Fq "no visible widget named or captioned 'Stobe_ChatWindow'" "$EVIDENCE_DIR/00-tree-before.txt" || fail_setup chat_not_closed_at_baseline
timeout 12 stobe-auto screenshot kah-int-001-i3-${RUN_ID}-00-before >"$EVIDENCE_DIR/00-shot-command.txt" 2>&1 || fail_evidence baseline_screenshot_failed
cat "$EVIDENCE_DIR/00-shot-command.txt"

# Screenshot command reports the current KAH render/client dimensions. Scoped
# ui tree absolute bounds must fit and the chat root must equal this client area.
render_size() {
  python3 - "$1" <<'PY'
import re, sys
s=open(sys.argv[1],encoding='utf-8',errors='replace').read()
m=re.search(r'(?<!\d)(\d{2,5})x(\d{2,5})(?!\d)',s)
if not m or int(m.group(1)) < 100 or int(m.group(2)) < 100: sys.exit(1)
print(m.group(1),m.group(2))
PY
}

# Parse only visible descendants from the scoped tree. Require unique textbox,
# unique titlebar, and exactly one close/cancel/dismiss-labeled descendant. All
# coordinates are absolute render/client pixels and must remain in that client.
open_geometry() {
  python3 - "$1" "$2" "$3" "${4:-draft}" <<'PY'
import re,sys
text=open(sys.argv[1],encoding='utf-8',errors='replace').read()
W,H=map(int,sys.argv[2:4])
mode=sys.argv[4]
if '(first 120)' in text or not re.search(r'\d+ widget\(s\) under Stobe_ChatWindow \(up 0\)',text):
    print('TREE_FAIL scoped_chat_missing_or_truncated',file=sys.stderr); sys.exit(2)
items=[]
for segment in re.split(r'\s+\|\s+',text):
    m=re.search(r'(?P<name>[^\s]+)(?: \'(?P<caption>.*?)\')? (?P<x>-?\d+),(?P<y>-?\d+) (?P<w>\d+)x(?P<h>\d+)(?P<hidden> hidden)?$',segment)
    if not m: continue
    name=m.group('name'); cap=m.group('caption') or ''
    x,y,w,h=map(int,(m.group('x'),m.group('y'),m.group('w'),m.group('h')))
    if m.group('hidden'): continue
    if w<=0 or h<=0 or x<0 or y<0 or x+w>W or y+h>H:
        print('TREE_FAIL_bounds_outside_render_client',file=sys.stderr); sys.exit(3)
    items.append((name,cap,x,y,w,h))
roots=[i for i in items if i[0]=='Stobe_ChatWindow']
if len(roots)!=1:
    print('TREE_FAIL_chat_root_not_unique',file=sys.stderr); sys.exit(4)
root=roots[0]
if root[2:6]!=(0,0,W,H):
    print('TREE_FAIL_root_render_client_mismatch',file=sys.stderr); sys.exit(5)
if mode=='open-only':
    print(f'ROOT_RECT={root[2]},{root[3]},{root[4]},{root[5]}')
    sys.exit(0)
titlebars=[i for i in items if i is not root and re.search(r'title[ _-]?bar',i[0]+' '+i[1],re.I)]
if len(titlebars)!=1:
    print('TREE_FAIL_titlebar_not_unique',file=sys.stderr); sys.exit(6)
close=[i for i in items if i is not root and re.search(r'\b(close|cancel|dismiss)\b',i[0]+' '+i[1],re.I)]
if len(close)!=1:
    print('TREE_FAIL_close_label_not_unique',file=sys.stderr); sys.exit(7)
t=titlebars[0]; c=close[0]
if not (t[2]<=c[2] and t[3]<=c[3] and c[2]+c[4]<=t[2]+t[4] and c[3]+c[5]<=t[3]+t[5]):
    print('TREE_FAIL_close_not_inside_titlebar',file=sys.stderr); sys.exit(8)
edit=[i for i in items if i is not root and re.search(r'(edit|textbox|input)',i[0],re.I)]
if len(edit)!=1:
    print('TREE_FAIL_textbox_not_unique',file=sys.stderr); sys.exit(9)
e=edit[0]
print(f'TEXTBOX_NAME={e[0]}')
for label,i in [('TEXTBOX',e),('CLOSE',c)]:
    cx=i[2]+i[4]//2; cy=i[3]+i[5]//2
    if cx<=0 or cy<=0 or cx>=W or cy>=H: print('TREE_FAIL_coordinate_outside_client',file=sys.stderr); sys.exit(10)
    print(f'{label}_CENTER={cx},{cy}')
print(f'ROOT_RECT={root[2]},{root[3]},{root[4]},{root[5]}')
PY
}

# Open and verify the first chat before any coordinate click.
within_bound
[[ "$status_fresh" == *"save=$EXPECTED_SAVE"* && "$isolation_fresh" == *'focused=0'* && "$isolation_fresh" == *'held=none'* ]] || fail_setup pre_open_gate_changed
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto key_inject / tap 120 >/dev/null || fail_setup open_key_inject_failed
sleep 1
timeout 12 stobe-auto screenshot kah-int-001-i3-${RUN_ID}-01-open >"$EVIDENCE_DIR/01-shot-command.txt" 2>&1 || fail_evidence open_screenshot_failed
cat "$EVIDENCE_DIR/01-shot-command.txt"
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/01-tree-open.txt" 2>&1 || fail_evidence open_chat_tree_failed
cat "$EVIDENCE_DIR/01-tree-open.txt"
read -r W H < <(render_size "$EVIDENCE_DIR/01-shot-command.txt") || fail_evidence open_render_size_missing
open_geometry "$EVIDENCE_DIR/01-tree-open.txt" "$W" "$H" draft >"$EVIDENCE_DIR/01-geometry.txt" 2>"$EVIDENCE_DIR/01-geometry-error.txt" || fail_setup "open_chat_geometry_ambiguous: $(cat "$EVIDENCE_DIR/01-geometry-error.txt")"
cat "$EVIDENCE_DIR/01-geometry.txt"
textbox_name=$(awk -F= '$1=="TEXTBOX_NAME"{print $2}' "$EVIDENCE_DIR/01-geometry.txt")
[[ -n "$textbox_name" ]] || fail_setup textbox_name_missing
textbox_xy=$(awk -F= '$1=="TEXTBOX_CENTER"{print $2}' "$EVIDENCE_DIR/01-geometry.txt")
[[ "$textbox_xy" =~ ^[1-9][0-9]*,[1-9][0-9]*$ ]] || fail_setup textbox_center_not_valid
textbox_x=${textbox_xy%,*}; textbox_y=${textbox_xy#*,}

# One KAH-injected coordinate click focuses the unique scoped textbox. Its
# current screenshot is retained so the caret can be judged from the evidence.
isolation=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup isolation_before_textbox_click_unavailable
within_bound
[[ "$isolation" == isolation=on* && "$isolation" == *'focused=0'* ]] || fail_setup isolation_or_focus_changed_before_textbox_click
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto mouse_inject at "$textbox_x" "$textbox_y" >/dev/null || fail_setup textbox_coordinate_move_failed
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto mouse_inject left click 80 >/dev/null || fail_setup textbox_coordinate_click_failed
sleep 1
timeout 12 stobe-auto screenshot kah-int-001-i3-${RUN_ID}-02-textbox >"$EVIDENCE_DIR/02-shot-command.txt" 2>&1 || fail_evidence textbox_screenshot_failed
cat "$EVIDENCE_DIR/02-shot-command.txt"
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/02-tree-textbox.txt" 2>&1 || fail_evidence textbox_tree_failed
cat "$EVIDENCE_DIR/02-tree-textbox.txt"

# Draft one literal slash; no Enter/send command is present in this row.
isolation=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup isolation_before_slash_draft_unavailable
within_bound
[[ "$isolation" == isolation=on* && "$isolation" == *'focused=0'* && "$isolation" == *'held=none'* ]] || fail_setup isolation_or_focus_changed_before_slash_draft
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto key_inject / tap 120 >/dev/null || fail_setup literal_slash_key_inject_failed
sleep 1
timeout 12 stobe-auto screenshot kah-int-001-i3-${RUN_ID}-03-slash-draft >"$EVIDENCE_DIR/03-shot-command.txt" 2>&1 || fail_evidence slash_draft_screenshot_failed
cat "$EVIDENCE_DIR/03-shot-command.txt"
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/03-tree-slash-draft.txt" 2>&1 || fail_evidence slash_draft_tree_failed
cat "$EVIDENCE_DIR/03-tree-slash-draft.txt"
read -r W3 H3 < <(render_size "$EVIDENCE_DIR/03-shot-command.txt") || fail_evidence draft_render_size_missing
open_geometry "$EVIDENCE_DIR/03-tree-slash-draft.txt" "$W3" "$H3" draft >"$EVIDENCE_DIR/03-geometry.txt" 2>"$EVIDENCE_DIR/03-geometry-error.txt" || fail_evidence "draft_chat_geometry_invalid: $(cat "$EVIDENCE_DIR/03-geometry-error.txt")"
# Require exactly one visible descendant whose caption is the literal slash.
python3 - "$EVIDENCE_DIR/03-tree-slash-draft.txt" "$textbox_name" <<'PY' || fail_evidence literal_single_slash_not_proven_by_ui_tree
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='replace').read(); want=sys.argv[2]
found=[]
for part in re.split(r'\s+\|\s+',s):
    m=re.search(r"([^\s]+)(?: '([^']*)')? -?\d+,-?\d+ \d+x\d+",part)
    if m and m.group(1)==want: found.append(m.group(2) or '')
if found!=['/']: sys.exit(1)
PY

# Requery immediately before the single close-control click. No global ui close,
# widget-name click, typing, or fallback is permitted.
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/03-tree-close-target.txt" 2>&1 || fail_evidence close_target_tree_failed
read -r WC HC < <(render_size "$EVIDENCE_DIR/03-shot-command.txt") || fail_evidence close_target_render_size_missing
open_geometry "$EVIDENCE_DIR/03-tree-close-target.txt" "$WC" "$HC" draft >"$EVIDENCE_DIR/03-close-geometry.txt" 2>"$EVIDENCE_DIR/03-close-geometry-error.txt" || fail_setup "unique_close_target_not_proven: $(cat "$EVIDENCE_DIR/03-close-geometry-error.txt")"
close_xy=$(awk -F= '$1=="CLOSE_CENTER"{print $2}' "$EVIDENCE_DIR/03-close-geometry.txt")
[[ "$close_xy" =~ ^[1-9][0-9]*,[1-9][0-9]*$ ]] || fail_setup close_center_not_valid
close_x=${close_xy%,*}; close_y=${close_xy#*,}
isolation=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup isolation_before_draft_discard_unavailable
within_bound
[[ "$isolation" == isolation=on* && "$isolation" == *'focused=0'* ]] || fail_setup isolation_or_focus_changed_before_draft_discard
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto mouse_inject at "$close_x" "$close_y" >/dev/null || fail_setup close_coordinate_move_failed
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto mouse_inject left click 80 >/dev/null || fail_setup close_control_click_failed
sleep 1
timeout 12 stobe-auto screenshot kah-int-001-i3-${RUN_ID}-04-draft-discarded >"$EVIDENCE_DIR/04-shot-command.txt" 2>&1 || fail_evidence draft_discard_screenshot_failed
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/04-tree-draft-discarded.txt" 2>&1 || fail_evidence draft_discard_tree_failed
cat "$EVIDENCE_DIR/04-tree-draft-discarded.txt"
grep -Fq "no visible widget named or captioned 'Stobe_ChatWindow'" "$EVIDENCE_DIR/04-tree-draft-discarded.txt" || fail_evidence draft_close_not_proven_leave_draft_unsent

# Open a separate untouched chat, then close it with the second slash. Do not
# click, type, paste, edit, or move the injected cursor inside this fresh chat.
isolation=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup isolation_before_fresh_open_unavailable
within_bound
[[ "$isolation" == isolation=on* && "$isolation" == *'focused=0'* && "$isolation" == *'held=none'* ]] || fail_setup isolation_or_focus_changed_before_fresh_open
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto key_inject / tap 120 >/dev/null || fail_setup fresh_chat_open_key_failed
sleep 1
timeout 12 stobe-auto screenshot kah-int-001-i3-${RUN_ID}-05-fresh-open >"$EVIDENCE_DIR/05-shot-command.txt" 2>&1 || fail_evidence fresh_chat_open_screenshot_failed
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/05-tree-fresh-open.txt" 2>&1 || fail_evidence fresh_chat_open_tree_failed
read -r W5 H5 < <(render_size "$EVIDENCE_DIR/05-shot-command.txt") || fail_evidence fresh_chat_render_size_missing
open_geometry "$EVIDENCE_DIR/05-tree-fresh-open.txt" "$W5" "$H5" open-only >"$EVIDENCE_DIR/05-geometry.txt" 2>"$EVIDENCE_DIR/05-geometry-error.txt" || fail_evidence "fresh_chat_open_not_proven: $(cat "$EVIDENCE_DIR/05-geometry-error.txt")"
isolation=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup isolation_before_fresh_close_unavailable
within_bound
[[ "$isolation" == isolation=on* && "$isolation" == *'focused=0'* && "$isolation" == *'held=none'* ]] || fail_setup isolation_or_focus_changed_before_fresh_close
INPUT_COUNT=$((INPUT_COUNT+1)); timeout 12 stobe-auto key_inject / tap 120 >/dev/null || fail_setup fresh_untouched_close_key_failed
sleep 1
timeout 12 stobe-auto screenshot kah-int-001-i3-${RUN_ID}-06-fresh-closed >"$EVIDENCE_DIR/06-shot-command.txt" 2>&1 || fail_evidence fresh_chat_close_screenshot_failed
timeout 12 stobe-auto ui tree Stobe_ChatWindow up 0 >"$EVIDENCE_DIR/06-tree-fresh-closed.txt" 2>&1 || fail_evidence fresh_chat_close_tree_failed
cat "$EVIDENCE_DIR/06-tree-fresh-closed.txt"
grep -Fq "no visible widget named or captioned 'Stobe_ChatWindow'" "$EVIDENCE_DIR/06-tree-fresh-closed.txt" || fail_product second_slash_did_not_close_untouched_chat
isolation=$(timeout 12 stobe-auto input_isolation status </dev/null 2>&1 | tr -d '\r') || fail_setup final_input_isolation_status_unavailable
[[ "$isolation" == isolation=on* && "$isolation" == *'focused=0'* ]] || fail_setup final_isolation_or_focus_gate_failed

printf 'RESULT %s PASS rig=4080 instance=3 pid=%s save=%s backend_session=NOT_REQUIRED_LOCAL_UI input_count=%s open=%s/01-tree-open.txt+01-shot-command.txt caret=%s/02-tree-textbox.txt+02-shot-command.txt slash_draft=%s/03-tree-slash-draft.txt+03-shot-command.txt fresh_untouched_close=%s/05-tree-fresh-open.txt+06-tree-fresh-closed.txt+shots isolation=%s\n' "$ROW" "$pid" "$EXPECTED_SAVE" "$INPUT_COUNT" "$EVIDENCE_DIR" "$EVIDENCE_DIR" "$EVIDENCE_DIR" "$EVIDENCE_DIR" "$isolation"
