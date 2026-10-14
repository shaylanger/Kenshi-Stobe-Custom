#!/usr/bin/env bash
# Executable KAH-INT-003 portrait/target-refresh row for isolated 4080 instance 3.
# KAH-only UI operations; never focuses the game, changes equipment, or writes the save.
set -uo pipefail
source "$(dirname "$0")/portrait-row-lib.sh"

ROW=KAH-INT-003
EXPECTED_DLL=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C
EXPECTED_HARNESS=974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D
EXPECTED_SAVE=kah-stobe-4080-standalone-active
ACTOR_A="${PORTRAIT_ACTOR_A:-Solka [Samurai Police Aina]}"
ACTOR_B="${PORTRAIT_ACTOR_B:-Apothecary Matsuyo}"
SPEAKER="${PLAYER:-Bark}"
LOG=/c/KenshiInst/3/mods/Stobe/stobe.log

bad_setup() { portrait_setup_fail "$ROW" "$1"; }
bad_evidence() { portrait_product_fail "$ROW" "$1"; }
kah() { portrait_kah "$@"; }
field() { printf '%s\n' "$1" | grep -oE "(^| )$2=[^ ]+" | tail -1 | sed "s/^.*$2=//"; }
serial_of() { printf '%s\n' "$1" | grep -oE '#[0-9]+/[0-9]+' | head -1 | sed -E 's/^#([0-9]+)\/.*/\1/'; }
native_handle() { printf '%s\n' "$1" | grep -oE '#[0-9]+/[0-9]+' | head -1 | tr -d '#'; }
generation_of() { field "$1" gen; }

[[ "${RIG:-}" == 4080 && "${KAH_INSTANCE:-}" == 3 ]] || bad_setup "wrong route rig=${RIG:-unset} instance=${KAH_INSTANCE:-unset}"
portrait_integrity_preflight "$ROW" "$0"
command -v rig4080_i3_preflight >/dev/null 2>&1 || bad_setup 'isolated i3 route helper missing'
rig4080_i3_preflight >/dev/null || bad_setup 'isolated i3 route/inbox preflight failed'
[[ "$(hostname | tr '[:lower:]' '[:upper:]')" == DESKTOP-NQQPA73 ]] || bad_setup 'unexpected 4080 host'

# Pin the exact process/module paths and current on-disk bytes before KAH access.
module_proof=$(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' -ExpectedExecutablePath 'C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe' 2>&1) || bad_setup 'exact i3 process/module proof unavailable'
printf '%s\n' "$module_proof" | grep -q "ON_DISK_SHA256=$EXPECTED_DLL" || bad_setup 'i3 Stobe module-path hash mismatch'
printf '%s\n' "$module_proof" | grep -q "ON_DISK_SHA256=$EXPECTED_HARNESS" || bad_setup 'i3 Harness module-path hash mismatch'
module_path_for() {
  local module_name=$1
  printf '%s\n' "$module_proof" | awk -v target="LOADED_MODULE=$module_name" '
    $0 == target { found=1; next }
    found && /^MODULE_PATH_PART=/ {
      sub(/^MODULE_PATH_PART=[0-9]+\/[0-9]+:/, "")
      path = path $0
      next
    }
    found { exit }
    END { print path }
  '
}
stobe_module_path=$(module_path_for Stobe.dll | tr '[:upper:]' '[:lower:]')
harness_module_path=$(module_path_for AutomationHarness.dll | tr '[:upper:]' '[:lower:]')
[[ "$stobe_module_path" == 'c:\kenshiinst\3\mods\stobe\stobe.dll' ]] || bad_setup "Stobe module is not loaded from i3: $stobe_module_path"
[[ "$harness_module_path" == 'c:\kenshiinst\3\mods\automationharness\automationharness.dll' ]] || bad_setup "Harness module is not loaded from i3: $harness_module_path"
stobe_hash=$(sha256sum /c/KenshiInst/3/mods/Stobe/Stobe.dll | awk '{print toupper($1)}')
harness_hash=$(sha256sum /c/KenshiInst/3/mods/AutomationHarness/AutomationHarness.dll | awk '{print toupper($1)}')
[[ "$stobe_hash" == "$EXPECTED_DLL" && "$harness_hash" == "$EXPECTED_HARNESS" ]] || bad_setup "installed DLL mismatch stobe=$stobe_hash harness=$harness_hash"
grep -qi '^ServerHost=127\.0\.0\.1' /c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini || bad_setup 'i3 Stobe host is not private loopback'
grep -qi '^ServerPort=18084' /c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini || bad_setup 'i3 Stobe port is not 18084'

health=$(curl.exe -fsS --max-time 5 http://127.0.0.1:18084/health.php 2>/dev/null) || bad_setup 'private 4080 backend health unavailable'
[[ "$health" == *'"ok":true'* && "$health" == *'"database_schema_ready":true'* ]] || bad_setup 'private 4080 backend/schema not ready'

# Read only the allowlisted session fields; any WSL/reader failure is a setup failure.
session=$(MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 /mnt/c/KenshiModding/pending-fixes/rig4080-validation/chat007-session-read-once.py 2>/dev/null) || bad_setup 'fresh sanitized session-generation read failed'
[[ "$session" == *'"session_present":true'* && "$session" == *'"status":"ready"'* && "$session" == *'"generation_present":true'* && "$session" == *'"manager_ready_matches":true'* ]] || bad_setup 'session is not ready on a matching generation'
[[ "$session" =~ \"gamets\":[0-9]+ && "$session" =~ \"load_id_sha256\":\"[0-9a-f]{64}\" ]] || bad_setup 'sanitized session fields incomplete'

status=$(kah status | tail -1) || bad_setup 'KAH status unavailable'
[[ "$status" == *'phase=world'* && "$status" == *'paused=0'* && "$status" == *'last_saved='"$EXPECTED_SAVE"* ]] || bad_setup "world is not the expected copied test save or is paused: ${status:0:240}"
iso=$(kah input_isolation status | tail -1) || bad_setup 'input-isolation read unavailable'
fp=$(kah fp_state | tail -1) || bad_setup 'FP/focus-state read unavailable'
[[ "$iso" == *'isolation=on'* && "$iso" == *'focused=0'* && "$fp" == *'focus=0'* ]] || bad_setup "natural isolation/focus gate failed isolation=${iso:0:160} fp=${fp:0:160}"
speaker_reply=$(kah stobe_ping | tail -1) || bad_setup 'Stobe readiness ping failed'
[[ "$speaker_reply" == *'nearest='* && "$speaker_reply" != *'nearest=none'* ]] || bad_setup "no current Stobe speaker: ${speaker_reply:0:180}"

# Check targets are unique, alive, equipped and have distinct native handles.
speaker_where=$(kah where "$SPEAKER" | tail -1) || bad_setup "speaker where failed: $SPEAKER"
[[ "$speaker_where" == *'#'* ]] || bad_setup "speaker handle unavailable: $SPEAKER"
where_a=$(kah where "$ACTOR_A" | tail -1) || bad_setup "actor A where failed: $ACTOR_A"
where_b=$(kah where "$ACTOR_B" | tail -1) || bad_setup "actor B where failed: $ACTOR_B"
state_a=$(kah stobe_state "$ACTOR_A" | tail -1) || bad_setup "actor A state failed: $ACTOR_A"
state_b=$(kah stobe_state "$ACTOR_B" | tail -1) || bad_setup "actor B state failed: $ACTOR_B"
handle_a=$(serial_of "$where_a"); handle_b=$(serial_of "$where_b")
native_a=$(native_handle "$where_a"); native_b=$(native_handle "$where_b")
[[ -n "$handle_a" && -n "$handle_b" && -n "$native_a" && -n "$native_b" && "$native_a" != "$native_b" ]] || bad_setup 'two distinct actor handles were not confirmed'
roster=$(kah chars 500) || bad_setup 'fresh actor roster unavailable'
char_a=$(printf '%s\n' "$roster" | grep -F "$ACTOR_A #$native_a" | head -1)
char_b=$(printf '%s\n' "$roster" | grep -F "$ACTOR_B #$native_b" | head -1)
race_a=$(field "$char_a" race); race_b=$(field "$char_b" race)
[[ -n "$char_a" && "$race_a" == Greenlander && "$char_a" != *' KO '* && "$char_a" != *' DEAD '* ]] || bad_setup "actor A is not the expected living humanoid (race=${race_a:-unknown}): $ACTOR_A"
[[ -n "$char_b" && "$race_b" == Greenlander && "$char_b" != *' KO '* && "$char_b" != *' DEAD '* ]] || bad_setup "actor B is not the expected living humanoid (race=${race_b:-unknown}): $ACTOR_B"
for pair in "A:$state_a" "B:$state_b"; do
  [[ "$pair" == *'dead=false'* && "$pair" == *'unconscious=false'* ]] || bad_setup "actor not living/conscious: ${pair:0:220}"
done
items_a=$(portrait_equipped "$ACTOR_A")
items_b=$(portrait_equipped "$ACTOR_B")
[[ -n "$items_a" && -n "$items_b" ]] || bad_setup 'one of the two actors has no equipped inventory to preserve'
printf 'INVENTORY %s before_A=%s\nINVENTORY %s before_B=%s\n' "$ROW" "$items_a" "$ROW" "$items_b"
headgear_a=0; headgear_b=0
[[ "$items_a" =~ [Hh]elm|[Hh]at|[Hh]ood|[Mm]ask|[Bb]andana ]] && headgear_a=1
[[ "$items_b" =~ [Hh]elm|[Hh]at|[Hh]ood|[Mm]ask|[Bb]andana ]] && headgear_b=1
(( headgear_a || headgear_b )) || bad_setup 'neither actor is wearing headgear; headgear-removal assertion unavailable'

[[ -f "$LOG" ]] || bad_setup 'Stobe runtime log missing'
base_lines=$(wc -l < "$LOG")

READ_TARGET_RESULT=''
read_target() {
  local expected="$1" prior="$2" actor="$3" result='' gen='' key=''
  for _ in $(seq 1 10); do
    result=$(kah stobe_npcinfo read | tail -1) || bad_setup "profile read failed for $actor"
    key=$(field "$result" key); gen=$(generation_of "$result")
    if [[ "$result" == *'open=1'* && "$result" == *'loaded=1'* && "$result" == *'portrait=1'* && "$result" == *'tex=StobeProfilePortrait_'* && "$key" == "$expected|$SPEAKER" && "$gen" =~ ^[0-9]+ ]] && (( gen > prior )); then
      READ_TARGET_RESULT="$result"; return 0
    fi
    sleep 1
  done
  bad_evidence "target did not refresh coherently within 10s actor=$actor expected_serial=$expected last_read=${result:0:250}"
}

check_portrait_log() {
  local actor="$1" require_absent="$2" lines="$3" event expected observed mesh
  event=''
  for _ in $(seq 1 5); do
    event=$(tail -n +$((lines + 1)) "$LOG" | grep -F "PROFILE_PORTRAIT: npc=$actor " | tail -1)
    [[ -n "$event" ]] && break
    sleep 1
  done
  [[ "$event" == *'applied=1'* ]] || bad_evidence "PROFILE_PORTRAIT applied=1 missing for $actor"
  if [[ "$require_absent" == 1 ]]; then
    [[ "$event" == *'hidden_before_cull=1'* && "$event" =~ expected=[^[:space:]] ]] || bad_evidence "equipped headgear exclusion evidence missing for $actor"
    expected=$(printf '%s\n' "$event" | sed -n 's/.* expected=\([^ ]*\) excluded_meshes=.*/\1/p')
    observed=$(printf '%s\n' "$event" | sed -n 's/.* observed=\(.*\) applied=.*/\1/p')
    [[ -n "$expected" && -n "$observed" ]] || bad_evidence "expected/observed headgear mesh evidence missing for $actor"
    IFS=';' read -r -a meshes <<< "$expected"
    for mesh in "${meshes[@]}"; do
      [[ -n "$mesh" ]] || continue
      [[ ";$observed" == *";$mesh;"* ]] && bad_evidence "equipped headgear mesh remained in portrait scene actor=$actor mesh=$mesh"
    done
  fi
}

capture() {
  local tag="$1" actor="$2" expected="$3" prior="$4" gear="$5" log_before="$6" read shot equipped
  read_target "$expected" "$prior" "$actor"
  read="$READ_TARGET_RESULT"
  check_portrait_log "$actor" "$gear" "$log_before"
  shot="kah-int003-4080-${tag}-$(date +%s)"
  kah screenshot "$shot" >/dev/null || bad_setup "screenshot command failed for $tag"
  sleep 1
  [[ -s "$KDIR/mods/AutomationHarness/shots/$shot.png" ]] || bad_setup "screenshot missing for $tag"
  equipped=$(portrait_equipped "$actor")
  case "$tag" in
    A|A-return) [[ "$equipped" == "$items_a" ]] || bad_evidence 'actor A inventory/equipment changed' ;;
    B) [[ "$equipped" == "$items_b" ]] || bad_evidence 'actor B inventory/equipment changed' ;;
  esac
  CAPTURE_RECORD=$(printf '%s\t%s\t%s\t%s\n' "$tag" "$(generation_of "$read")" "$(printf '%s\n' "$read" | grep -oE 'tex=[^ ]+' | head -1)" "$KDIR/mods/AutomationHarness/shots/$shot.png")
}

line_a=$(wc -l < "$LOG")
kah stobe_npcinfo open "$ACTOR_A" "$SPEAKER" >/dev/null || bad_setup 'NPC Info open failed for A'
sleep 2
kah stobe_npcinfo refresh >/dev/null || bad_setup 'NPC Info refresh failed for A'
capture A "$ACTOR_A" "$handle_a" 0 "$headgear_a" "$line_a"
a_record=$CAPTURE_RECORD
gen_a=$(printf '%s\n' "$a_record" | cut -f2)

line_b=$(wc -l < "$LOG")
kah select "$ACTOR_B" >/dev/null || bad_setup 'KAH selection of actor B failed'
capture B "$ACTOR_B" "$handle_b" "$gen_a" "$headgear_b" "$line_b"
b_record=$CAPTURE_RECORD
gen_b=$(printf '%s\n' "$b_record" | cut -f2)

line_a_return=$(wc -l < "$LOG")
kah select "$ACTOR_A" >/dev/null || bad_setup 'KAH selection returning to actor A failed'
capture A-return "$ACTOR_A" "$handle_a" "$gen_b" "$headgear_a" "$line_a_return"
a_return_record=$CAPTURE_RECORD
gen_a_return=$(printf '%s\n' "$a_return_record" | cut -f2)

iso_after=$(kah input_isolation status | tail -1) || bad_setup 'final isolation read failed'
fp_after=$(kah fp_state | tail -1) || bad_setup 'final focus read failed'
[[ "$iso_after" == *'isolation=on'* && "$iso_after" == *'focused=0'* && "$fp_after" == *'focus=0'* ]] || bad_setup 'isolation/focus changed during the row'

for record in "$a_record" "$b_record" "$a_return_record"; do
  tag=$(printf '%s\n' "$record" | cut -f1)
  image=$(printf '%s\n' "$record" | cut -f4)
  image_hash=$(sha256sum "$image" | awk '{print toupper($1)}')
  printf 'ARTIFACT %s tag=%s screenshot=%s sha256=%s\n' "$ROW" "$tag" "$image" "$image_hash"
done
printf 'ACTOR %s A=%s#%s race=%s gear=%s\nACTOR %s B=%s#%s race=%s gear=%s\n' \
  "$ROW" "$ACTOR_A" "$native_a" "$race_a" "$items_a" \
  "$ROW" "$ACTOR_B" "$native_b" "$race_b" "$items_b"

printf 'RESULT %s PASS rig=4080 instance=3 loaded_stobe=%s harness=%s targets=%s#%s,%s#%s generations=%s/%s/%s textures=%s/%s/%s headgear_actors=%s screenshot_set=3 inventory_unchanged=1 visual_review=required overall=provisional\n' \
  "$ROW" "$EXPECTED_DLL" "$EXPECTED_HARNESS" \
  "$ACTOR_A" "$native_a" "$ACTOR_B" "$native_b" "$gen_a" "$gen_b" "$gen_a_return" \
  "$(printf '%s\n' "$a_record" | cut -f3)" "$(printf '%s\n' "$b_record" | cut -f3)" "$(printf '%s\n' "$a_return_record" | cut -f3)" \
  "${ACTOR_A}:${headgear_a},${ACTOR_B}:${headgear_b}"
