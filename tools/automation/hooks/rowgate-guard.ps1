# rowgate-guard.ps1 (PreToolUse, matcher Agent): ROW REWORK GATE (imm26 credit-review cut #1; docs/ROW_REWORK_GATE.md).
# Runs next to agent-router.ps1 (same matcher group). It NEVER rewrites the input (no updatedInput), so it cannot clash with the router: it only denies
# (exit 2 + reason on stderr) or lets the call through (exit 0, no output) and records the attempt in C:\KenshiTestRuns\rowgate\<row>.json.
# Internal error: the call is allowed and logged (fail open, like the router). Only acts when cwd is under C:\KenshiModding.
$raw = [Console]::In.ReadToEnd()
$py = Join-Path (Split-Path -Parent $PSScriptRoot) 'rowgate.py'
$pyexe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyexe) { $pyexe = 'C:\Users\Shay\AppData\Local\Programs\Python\Python312\python.exe' }
if (-not (Test-Path $pyexe) -or -not (Test-Path $py)) { [Console]::Error.WriteLine('rowgate-guard: python or rowgate.py missing, call allowed'); exit 0 }
$raw | & $pyexe -I $py guard
exit $LASTEXITCODE
