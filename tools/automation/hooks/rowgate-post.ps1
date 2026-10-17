# rowgate-post.ps1 (PostToolUse, matcher Agent): marks a FOREGROUND agent's row attempt done and records the agentId (docs/ROW_REWORK_GATE.md).
# Background agents ("Async agent launched") stay running until their agents\<name>.status says DONE/FAILED/STOPPED (or 45 min without a status). Never blocks.
$raw = [Console]::In.ReadToEnd()
$py = Join-Path (Split-Path -Parent $PSScriptRoot) 'rowgate.py'
$pyexe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyexe) { $pyexe = 'C:\Users\Shay\AppData\Local\Programs\Python\Python312\python.exe' }
if ((Test-Path $pyexe) -and (Test-Path $py)) { $raw | & $pyexe -I $py post }
exit 0
