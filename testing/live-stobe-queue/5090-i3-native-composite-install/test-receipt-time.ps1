[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'ReceiptTime.psm1') -Force
$pass = 0
function Assert-Instant([string]$Json, [string]$ExpectedUtc) {
  $actual = ConvertFrom-PinnedReceiptUtc -Json $Json
  if ($actual -isnot [DateTimeOffset]) { throw "Expected DateTimeOffset, got $($actual.GetType().FullName)" }
  if ($actual.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'") -ne $ExpectedUtc) {
    throw "Wrong instant: got $actual expected $ExpectedUtc"
  }
  $script:pass++
}
function Assert-Reject([string]$Json) {
  $rejected = $false
  try { [void](ConvertFrom-PinnedReceiptUtc -Json $Json) } catch { $rejected = $true }
  if (-not $rejected) { throw "Expected invalid receipt timestamp to reject: $Json" }
  $script:pass++
}
Assert-Instant '{"issued_utc":"2026-10-14T18:48:07Z"}' '2026-10-14T18:48:07.0000000Z'
Assert-Instant '{"issued_utc" : "2026-10-14T13:48:07-05:00"}' '2026-10-14T18:48:07.0000000Z'
Assert-Instant '{"issued_utc":"2026-10-14T18:48:07.1234567+00:00"}' '2026-10-14T18:48:07.1234567Z'
Assert-Reject '{}'
Assert-Reject '{"issued_utc":"2026-10-14T18:48:07"}'
Assert-Reject '{"issued_utc":"2026-10-14T18:48:07Z","issued_utc":"2026-10-14T18:48:08Z"}'
Assert-Reject '{"issued_utc":"2026-02-30T18:48:07Z"}'
"PASS: $pass receipt timestamp cases under PowerShell $($PSVersionTable.PSVersion)"
