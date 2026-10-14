#!/usr/bin/env bash
set -euo pipefail

export KAH_INSTANCE=3

# Use the standalone route guard, whose own pinned implementation sources the
# pinned rig-env.sh. Suppress its route paths and status text; this receipt is
# deliberately limited to the fields listed below.
route_helper=/c/KenshiModding/tools/automation/rig4080/instance-route-preflight.sh
env_helper=/c/KenshiModding/tools/automation/rig-env.sh
route_hash=$(sha256sum "$route_helper" | awk '{print toupper($1)}')
env_hash=$(sha256sum "$env_helper" | awk '{print toupper($1)}')
[[ "$route_hash" == 408FD0CAC181FEE32EF5DD0D0512CBD10494962CF1E251412EB900AF80E6EF51 &&
   "$env_hash" == A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D ]] || {
  printf 'PREFLIGHT_STOP pinned_i3_route_helper_changed\n' >&2
  exit 2
}
bash "$route_helper" >/dev/null 2>&1 || {
  printf 'PREFLIGHT_STOP isolated_i3_route_gate_failed\n' >&2
  exit 2
}

process_proof=$(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command '
$ErrorActionPreference = "Stop"
$expectedExe = "C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe"
$expectedDll = "C:\KenshiInst\3\mods\Stobe\Stobe.dll"
try {
  $matches = @(Get-Process -Name "kenshi_x64" -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $expectedExe })
  if ($matches.Count -ne 1) { [Console]::Error.WriteLine("PROCESS_GATE_FAIL"); exit 21 }
  $game = $matches[0]

  # Query only the named module in this exact PID. Do not enumerate or emit
  # the process module collection.
  $tasklistPath = Join-Path $env:SystemRoot "System32\tasklist.exe"
  $moduleRows = @(& $tasklistPath /m Stobe.dll /fi "PID eq $($game.Id)" /fo csv /nh 2>$null)
  if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("STOBE_MODULE_QUERY_FAIL"); exit 22 }
  $parsedRows = @($moduleRows | ConvertFrom-Csv -Header ImageName,ProcessId,ModuleList)
  $loaded = @($parsedRows | Where-Object { $_.ProcessId -eq [string]$game.Id -and $_.ModuleList -eq "Stobe.dll" }).Count -gt 0
  if (-not $loaded) { [Console]::Error.WriteLine("STOBE_MODULE_GATE_FAIL"); exit 23 }
  if (-not (Test-Path -LiteralPath $expectedDll -PathType Leaf)) { [Console]::Error.WriteLine("STOBE_DLL_GATE_FAIL"); exit 24 }
  $dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $expectedDll).Hash.ToUpperInvariant()
  [Console]::Out.WriteLine("PID=$($game.Id)")
  [Console]::Out.WriteLine("PROCESS_PATH=$($game.Path)")
  [Console]::Out.WriteLine("STOBE_LOADED=1")
  [Console]::Out.WriteLine("STOBE_DLL_ON_DISK_SHA256=$dllHash")
  exit 0
}
catch {
  [Console]::Error.WriteLine("PROCESS_STOBE_PROOF_FAIL")
  exit 25
}
') || {
  printf 'PREFLIGHT_STOP exact_i3_process_or_Stobe_proof_failed\n' >&2
  exit 2
}
[[ "$process_proof" == *'PID='* &&
   "$process_proof" == *'PROCESS_PATH=C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'* &&
   "$process_proof" == *'STOBE_LOADED=1'* &&
   "$process_proof" == *'STOBE_DLL_ON_DISK_SHA256='* ]] || {
  printf 'PREFLIGHT_STOP process_or_Stobe_proof_fields_missing\n' >&2
  exit 2
}
printf '%s\n' "$process_proof"

# This command is used only as a read-only source for the current world/save
# identity. Its response is parsed and never echoed.
status=$(timeout 12 stobe-auto status 2>/dev/null | tr -d '\r' | tail -1) || {
  printf 'PREFLIGHT_STOP read_only_loaded_save_identity_unavailable\n' >&2
  exit 2
}
save_label=kah-stobe-travel-validation-20261013
[[ "$status" == *'phase=world'* && "$status" == *"save=$save_label"* ]] || {
  printf 'PREFLIGHT_STOP expected_copied_save_not_loaded\n' >&2
  exit 2
}
save_root=$(cygpath -u "$LOCALAPPDATA") || {
  printf 'PREFLIGHT_STOP isolated_save_root_unavailable\n' >&2
  exit 2
}
save_file="$save_root/kenshi/save/$save_label/quick.save"
[[ -f "$save_file" ]] || {
  printf 'PREFLIGHT_STOP copied_save_quick_save_missing\n' >&2
  exit 2
}
save_hash=$(sha256sum "$save_file" | awk '{print toupper($1)}')
[[ "$save_hash" =~ ^[A-F0-9]{64}$ ]] || {
  printf 'PREFLIGHT_STOP copied_save_hash_malformed\n' >&2
  exit 2
}
printf 'COPIED_SAVE_LABEL=%s\nCOPIED_SAVE_QUICK_SHA256=%s\n' "$save_label" "$save_hash"

row_hash=$(sha256sum /c/KenshiModding/tests/ingame/stobe/STOBE-PORTRAIT-ABSENT-4080.sh | awk '{print toupper($1)}')
helper_hash=$(sha256sum /c/KenshiModding/tests/ingame/stobe/portrait-row-lib.sh | awk '{print toupper($1)}')
[[ "$row_hash" == A98D0E7A0D6F821DA647C1B7523983D882FE679B66C574E808AFE49888D5AF50 ]] || {
  printf 'PREFLIGHT_STOP row_script_hash_mismatch\n' >&2
  exit 2
}
[[ "$helper_hash" == 64780F2411742D407291CD775FFAE49DB58A6CA500A2BA1070E985A4A6A88784 ]] || {
  printf 'PREFLIGHT_STOP row_helper_hash_mismatch\n' >&2
  exit 2
}
printf 'ROW_SHA256=%s\nHELPER_SHA256=%s\n' "$row_hash" "$helper_hash"
