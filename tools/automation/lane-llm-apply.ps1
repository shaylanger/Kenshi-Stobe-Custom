<#
lane-llm-apply.ps1 [-Rig 4080] [-Lane i3|i4|all] [-Check]
Apply (or --check) the ONE per-rig LLM config to the isolated lanes' private DBs.
  -Rig 4080 : config C:\KAH\lane-llm.json on the 4080 (base_url may contain {bridge_port}; key_file = Windows path, never printed),
              lanes from lane-defs.4080.json; runs lane-llm-apply-4080.sh in the 4080's WSL (via ssh from the 5090, directly on the 4080).
  -Rig 5090 : forwards to lane-llm-apply.sh in this PC's WSL (registry C:\KenshiTestRuns\lanes\lanes-5090.json).
Only base_url, model, api_key, max_tokens, connector_type, api_badge_id=NULL and is_default=(id=1) are written to every
core_llm_connector row (no production extras such as service_tier); HTTP_TIMEOUT is set from "http_timeout".
Switch the provider later: edit C:\KAH\lane-llm.json (+ drop key_file), run this once with -Lane all. No game restart needed.
#>
param([ValidateSet('4080', '5090')][string]$Rig = '4080', [string]$Lane = 'all', [switch]$Check)
$ErrorActionPreference = 'Stop'
$chk = if ($Check) { '--check' } else { '' }
if ($Rig -eq '5090') { wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/lane-llm-apply.sh $chk $Lane; exit $LASTEXITCODE }
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$onRig = $env:COMPUTERNAME -eq 'DESKTOP-NQQPA73'
$cmd = "bash /mnt/c/KenshiTestRuns/lane-i4/lane-llm-apply-4080.sh $chk $Lane --defs /mnt/c/KenshiTestRuns/lane-i4/lane-defs.4080.json"
if ($onRig) { wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -c $cmd }
else {
  & scp -q "$here\lane-llm-apply-4080.sh" "$here\lane-defs.4080.json" 4080:C:/KenshiTestRuns/lane-i4/
  & ssh -o BatchMode=yes 4080 "wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- $cmd"
}
exit $LASTEXITCODE
