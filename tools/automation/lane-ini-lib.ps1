<#
lane-ini-lib.ps1 (dot-source): helpers that keep a lane's RE_Kenshi\mods\Stobe\StobeCustom.ini valid for the native reader (PowerShell 5 safe).
Why: Shay's live StobeCustom.ini is a UTF-8 file WITH BOM and TWO [Settings] blocks (EnableBoredEventConversations=1 in the first, =0 in the second).
The BOM hides the first header from the Windows ini reader, so the second block won and the lane logged EnableBoredEvents=false (imm26 rows 08-b/09-a/09-d).
Lane inis must have: no BOM, exactly one [Settings] block, EnableBoredEventConversations=1, ServerHost/ServerPort = the lane's own.
  Test-LaneIni  -Path <ini> [-Port <n>]          -> list of problems (empty = ok)
  Format-LaneIni -Text <string> -Port <n>        -> normalised text (BOM-free is applied by the writer, Write-LaneIni)
  Write-LaneIni -Path <ini> -Port <n>            -> rewrites the file in place (UTF-8 no BOM); returns $true if it changed
Merge rule: later [Settings] blocks are folded into the first; for a key present in both the FIRST wins (what the reader does without the BOM,
and what the passing lanes ran); keys only in a later block are appended to the first block; EnableBoredEventConversations is forced to 1.
#>
function Test-LaneIni {
  param([Parameter(Mandatory)][string]$Path, [int]$Port = 0)
  $p = @()
  if (-not (Test-Path -LiteralPath $Path)) { return @("missing $Path") }
  $b = [IO.File]::ReadAllBytes($Path)
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $p += 'UTF-8 BOM present' }
  $txt = [Text.Encoding]::UTF8.GetString($b).TrimStart([char]0xFEFF)
  $n = ([regex]::Matches($txt, '(?mi)^\s*\[Settings\]\s*$')).Count
  if ($n -ne 1) { $p += "[Settings] blocks=$n (need 1)" }
  $m = [regex]::Matches($txt, '(?mi)^\s*EnableBoredEventConversations\s*=\s*(\d+)')
  if ($m.Count -ne 1 -or $m[0].Groups[1].Value -eq '0') { $p += "EnableBoredEventConversations=" + (($m | ForEach-Object { $_.Groups[1].Value }) -join ',') + " (need a single 1)" }
  if ($Port -gt 0) {
    $ports = @([regex]::Matches($txt, '(?mi)^\s*ServerPort\s*=\s*(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($ports.Count -ne 1 -or $ports[0] -ne "$Port") { $p += "ServerPort=$($ports -join ',') (need $Port)" }
  }
  return $p
}
function Format-LaneIni {
  param([Parameter(Mandatory)][string]$Text, [int]$Port = 0)
  $Text = $Text.TrimStart([char]0xFEFF)
  $nl = if ($Text -match "`r`n") { "`r`n" } else { "`n" }
  $lines = $Text -split "\r?\n"
  $out = New-Object Collections.Generic.List[string]
  $seen = @{}; $pending = New-Object Collections.Generic.List[string]
  $inLater = $false; $nSettings = 0
  # pass 1: find the first [Settings] block's keys
  $cur = ''
  foreach ($l in $lines) {
    if ($l -match '^\s*\[(.+?)\]\s*$') { $cur = $Matches[1]; if ($cur -ieq 'Settings') { $nSettings++ } ; continue }
    if ($cur -ieq 'Settings' -and $nSettings -eq 1 -and $l -match '^\s*([^=;#\s][^=]*?)\s*=') { $seen[$Matches[1].ToLowerInvariant()] = $true }
  }
  # pass 2: rebuild, dropping later [Settings] headers and their duplicate keys
  $cur = ''; $nSettings = 0; $insertAt = -1
  foreach ($l in $lines) {
    if ($l -match '^\s*\[(.+?)\]\s*$') {
      $cur = $Matches[1]
      if ($cur -ieq 'Settings') { $nSettings++; $inLater = ($nSettings -gt 1); if ($inLater) { continue } }
      else { $inLater = $false }
      $out.Add($l); continue
    }
    if ($inLater) {
      if ($l -match '^\s*([^=;#\s][^=]*?)\s*=') { $k = $Matches[1].ToLowerInvariant(); if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $pending.Add($l) } }
      continue   # comments/blank lines of the dropped block are dropped with it
    }
    $out.Add($l)
  }
  # append keys that only the later blocks had to the end of the first [Settings] block
  if ($pending.Count) {
    $idx = -1; $cur = ''
    for ($i = 0; $i -lt $out.Count; $i++) {
      if ($out[$i] -match '^\s*\[(.+?)\]\s*$') { if ($cur -ieq 'Settings' -and $idx -lt 0) { $idx = $i }; $cur = $Matches[1] }
    }
    if ($idx -lt 0) { $idx = $out.Count }
    while ($idx -gt 0 -and $out[$idx - 1].Trim() -eq '') { $idx-- }
    $out.InsertRange($idx, $pending)
  }
  $t = ($out -join $nl)
  $t = [regex]::Replace($t, '(?mi)^(\s*EnableBoredEventConversations\s*=).*$', '${1}1')
  if ($Port -gt 0) {
    $t = [regex]::Replace($t, '(?mi)^(\s*ServerPort\s*=).*$', "`${1}$Port")
    $t = [regex]::Replace($t, '(?mi)^(\s*ServerHost\s*=).*$', '${1}127.0.0.1')
  }
  if ($t -notmatch '(?mi)^\s*EnableBoredEventConversations\s*=') { $t = [regex]::Replace($t, '(?mi)^(\s*\[Settings\][^\r\n]*)', "`${1}$nl" + 'EnableBoredEventConversations=1', 1) }
  return $t
}
function Write-LaneIni {
  param([Parameter(Mandatory)][string]$Path, [int]$Port = 0)
  $raw = [IO.File]::ReadAllText($Path)
  $new = Format-LaneIni -Text $raw -Port $Port
  $old = [IO.File]::ReadAllBytes($Path)
  $nb = (New-Object Text.UTF8Encoding $false).GetBytes($new)
  if ([Convert]::ToBase64String($old) -eq [Convert]::ToBase64String($nb)) { return $false }
  [IO.File]::WriteAllBytes($Path, $nb); return $true
}
