# llm-health.ps1 (PI-15): Windows wrapper for llm-health.sh (1-token chat-LLM provider check). Prints `LLM-HEALTH OK <ms>` or `LLM-HEALTH FAIL http=<code> <body>`; exit 1 on FAIL.
param([switch]$NoCache)
$sh = Join-Path $PSScriptRoot 'llm-health.sh'
$bash = 'C:\Program Files\Git\bin\bash.exe'
$a = @($sh); if ($NoCache) { $a += '--no-cache' }
& $bash @a
exit $LASTEXITCODE
