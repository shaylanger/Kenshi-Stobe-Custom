#!/usr/bin/env bash
# Shared, bounded portrait row helpers. These rows are read-only with respect to
# actor inventory/save state. RESULT_LOG is owned by run-batch.sh.
set -uo pipefail

PORTRAIT_DLL_SHA="${PORTRAIT_STOBE_SHA256^^}"
[[ "$PORTRAIT_DLL_SHA" =~ ^[A-F0-9]{64}$ ]] || PORTRAIT_DLL_SHA=383C9158FAC4EC4E33F2F27046FBCC04B8EF5D2044A37AF134D5EDFB95EABA37

portrait_result() {
  local row="$1" status="$2" evidence="$3"
  printf 'RESULT %s %s %s\n' "$row" "$status" "$evidence"
}

portrait_setup_fail() {
  portrait_result "$1" 'FAIL setup:' "$2"
  exit 0
}

portrait_product_fail() {
  portrait_result "$1" 'FAIL' "$2"
  exit 0
}

portrait_kah() { timeout 12 stobe-auto "$@" 2>/dev/null; }

portrait_integrity_preflight() {
  local row="$1" script_path="$2" script_hash lib_hash
  [[ "${PORTRAIT_SCRIPT_SHA256:-}" =~ ^[A-Fa-f0-9]{64}$ ]] || portrait_setup_fail "$row" 'emitted list lacks pinned row-script hash'
  [[ "${PORTRAIT_LIB_SHA256:-}" =~ ^[A-Fa-f0-9]{64}$ ]] || portrait_setup_fail "$row" 'emitted list lacks pinned row-library hash'
  script_hash=$(sha256sum "$script_path" | awk '{print toupper($1)}')
  lib_hash=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print toupper($1)}')
  [[ "$script_hash" == "${PORTRAIT_SCRIPT_SHA256^^}" ]] || portrait_setup_fail "$row" "row script hash changed (expected=${PORTRAIT_SCRIPT_SHA256^^} actual=$script_hash)"
  [[ "$lib_hash" == "${PORTRAIT_LIB_SHA256^^}" ]] || portrait_setup_fail "$row" "row helper hash changed (expected=${PORTRAIT_LIB_SHA256^^} actual=$lib_hash)"
}

portrait_preflight() {
  local row="$1" expected_rig="$2" expected_instance="$3" expected_save="$4" actor="$5" speaker="$6"
  local modroot="$KDIR/RE_Kenshi/mods/Stobe" dll hash status wa ws
  if [[ "$expected_rig" == 4080 ]]; then modroot="$KDIR/mods/Stobe"; fi
  dll="$modroot/Stobe.dll"
  [[ "${RIG:-}" == "$expected_rig" ]] || portrait_setup_fail "$row" "wrong rig (expected=$expected_rig actual=${RIG:-unset})"
  [[ "${KAH_INSTANCE:-1}" == "$expected_instance" ]] || portrait_setup_fail "$row" "wrong instance (expected=$expected_instance actual=${KAH_INSTANCE:-unset})"
  [[ -f "$dll" ]] || portrait_setup_fail "$row" "installed Stobe.dll missing at $dll"
  hash=$(sha256sum "$dll" | awk '{print toupper($1)}')
  [[ "$hash" == "$PORTRAIT_DLL_SHA" ]] || portrait_setup_fail "$row" "Stobe.dll hash mismatch (expected=$PORTRAIT_DLL_SHA actual=$hash)"
  status=$(portrait_kah status | tail -1)
  [[ "$status" == *"phase=world"* && "$status" == *"save=$expected_save"* ]] || portrait_setup_fail "$row" "copied-save/world preflight failed status=${status:0:240}"
  wa=$(portrait_kah where "$actor" | tail -1)
  ws=$(portrait_kah where "$speaker" | tail -1)
  [[ "$wa" == *"#"* && "$wa" == *"$actor"* ]] || portrait_setup_fail "$row" "target actor unavailable: $actor evidence=${wa:0:180}"
  [[ "$ws" == *"#"* && "$ws" == *"$speaker"* ]] || portrait_setup_fail "$row" "speaker unavailable: $speaker evidence=${ws:0:180}"
  printf 'PREFLIGHT row=%s rig=%s instance=%s save=%s dll=%s actor=%s speaker=%s\n' \
    "$row" "$expected_rig" "$expected_instance" "$expected_save" "$hash" "$wa" "$ws"
}

portrait_equipped() {
  portrait_kah inv "$1" | grep -oE '"name":"[^"]+","count":[0-9]+,"equipped":true' | sort
}

portrait_open_capture() {
  local row="$1" actor="$2" speaker="$3" expected_private="$4" expected_absent="${5:-no}"
  local read log shot inv_before inv_after portrait_line expected_field observed_field mesh base_lines modroot
  modroot="$KDIR/RE_Kenshi/mods/Stobe"
  if [[ "${RIG:-}" == 4080 ]]; then modroot="$KDIR/mods/Stobe"; fi
  log="$modroot/stobe.log"
  [[ -f "$log" ]] || portrait_setup_fail "$row" "Stobe log missing at $log"
  base_lines=$(wc -l < "$log")
  inv_before=$(portrait_equipped "$actor")
  [[ -n "$inv_before" ]] || portrait_setup_fail "$row" "no equipped items to preserve for $actor"
  portrait_kah stobe_npcinfo open "$actor" "$speaker" >/dev/null || portrait_setup_fail "$row" "panel open command failed"
  sleep 2
  portrait_kah stobe_npcinfo refresh >/dev/null || portrait_setup_fail "$row" "panel refresh command failed"
  sleep 2
  read=$(portrait_kah stobe_npcinfo read | tail -1)
  [[ "$read" == *"open=1"* ]] || portrait_setup_fail "$row" "profile did not open after refresh read=${read:0:260}"
  [[ "$read" == *"portrait=1"* ]] || portrait_product_fail "$row" "panel has no image after successful open/refresh read=${read:0:260}"
  if [[ "$expected_private" == yes ]]; then
    [[ "$read" == *"tex=StobeProfilePortrait_"* ]] || portrait_product_fail "$row" "private portrait texture not installed read=${read:0:260}"
  fi
  portrait_line=$(tail -n +$((base_lines + 1)) "$log" | grep -F "PROFILE_PORTRAIT: npc=$actor " | tail -1)
  [[ "$portrait_line" == *"applied=1"* ]] || portrait_product_fail "$row" "private render did not apply for $actor log=${portrait_line:0:260}"
  if [[ "$expected_absent" == yes ]]; then
    [[ "$portrait_line" == *"hidden_before_cull=0"* && "$portrait_line" =~ expected=[^[:space:]] ]] || \
      portrait_product_fail "$row" "headgear clone was present or expected mesh evidence missing=${portrait_line:0:280}"
    expected_field=$(printf '%s\n' "$portrait_line" | sed -n 's/.* expected=\([^ ]*\) excluded_meshes=.*/\1/p')
    observed_field=$(printf '%s\n' "$portrait_line" | sed -n 's/.* observed=\(.*\) applied=.*/\1/p')
    [[ -n "$expected_field" && -n "$observed_field" ]] || portrait_product_fail "$row" "expected/observed mesh sets are missing: ${portrait_line:0:280}"
    IFS=';' read -r -a expected_meshes <<< "$expected_field"
    for mesh in "${expected_meshes[@]}"; do
      [[ -n "$mesh" ]] || continue
      [[ ";$observed_field" == *";$mesh;"* ]] && portrait_product_fail "$row" "expected equipped headgear mesh exists in private scene: $mesh"
    done
  fi
  shot="portrait-${row}-$(date +%s)"
  portrait_kah screenshot "$shot" >/dev/null || portrait_setup_fail "$row" "screenshot command failed"
  sleep 1
  [[ -s "$KDIR/mods/AutomationHarness/shots/$shot.png" ]] || portrait_setup_fail "$row" "screenshot file missing ($shot)"
  inv_after=$(portrait_equipped "$actor")
  [[ "$inv_before" == "$inv_after" ]] || portrait_product_fail "$row" "equipped inventory changed across portrait render"
  if [[ "$expected_absent" == yes ]]; then
    printf 'RESULT %s PASS evidence=actor=%s equipped_headgear=1 private_clone_absent=1 applied=1 inventory_unchanged=1 screenshot=%s visual_review=required\n' \
      "$row" "$actor" "$KDIR/mods/AutomationHarness/shots/$shot.png"
  else
    printf 'RESULT %s PASS evidence=actor=%s texture=%s applied=1 equipment_unchanged=1 screenshot=%s visual_review=required\n' \
      "$row" "$actor" "$(printf '%s' "$read" | grep -oE 'tex=[^ ]+' | head -1)" "$KDIR/mods/AutomationHarness/shots/$shot.png"
  fi
}

portrait_fault_setup_block() {
  local row="$1" rig="$2" instance="$3" save="$4" actor="$5" speaker="$6" kind="$7"
  portrait_preflight "$row" "$rig" "$instance" "$save" "$actor" "$speaker"
  # The exact pinned DLL exposes no portrait-fault injection switch. Do not
  # damage a renderer/resource or claim a fallback result without a trigger.
  if [[ "$kind" == private ]]; then
    portrait_setup_fail "$row" 'pinned 383C DLL has no safe private-render fault injector; no image/resource state changed'
  fi
  portrait_setup_fail "$row" 'pinned 383C DLL has no safe private+native renderer fault injector; initials path not triggered'
}
