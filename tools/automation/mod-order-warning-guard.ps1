# Pure, fail-closed classifier shared by the test-launch path and its fixtures.
function Normalize-WarningText([string]$Text) {
  if ($null -eq $Text) { return '' }
  $s = $Text.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()
  $s = [regex]::Replace($s, '[^\p{L}\p{Nd}]+', ' ')
  [regex]::Replace($s.Trim(), '\s+', ' ')
}

function Test-ModOrderWarningText([string]$Text) {
  if ($null -eq $Text) { return $false }
  # Static controls may split a line, so ignore layout whitespace only. The
  # observed words, casing, and punctuation must remain exact.
  $s = [regex]::Replace($Text.Trim(), '\s+', ' ')
  return [string]::Equals($s, 'One or more mods are missing or in incorrect order. Continue anyway?', [StringComparison]::Ordinal)
}

function Get-TestDialogDecision($Dialog, $Controls, [uint32[]]$ExpectedPids) {
  $rawTitle = [string]$Dialog.Title
  $title = Normalize-WarningText $rawTitle
  if (-not ($ExpectedPids -contains [uint32]$Dialog.Pid) -or $Dialog.Cls -cne '#32770') {
    return [pscustomobject]@{ Kind='Ignore'; Button=$null; Diagnostic='process-or-class-scope-mismatch' }
  }

  if ([string]::Equals($rawTitle, 'Mods warning', [StringComparison]::Ordinal) -or
      [string]::Equals($rawTitle, 'Kenshi CTD Fix', [StringComparison]::Ordinal)) {
    $body = (@($Controls | Where-Object { $_.Cls -ceq 'Static' } | ForEach-Object { [string]$_.Title }) -join ' ')
    $yesButtons = @($Controls | Where-Object {
      $_.Cls -ceq 'Button' -and $_.Enabled -eq $true -and
      [string]::Equals([string]$_.Title, '&Yes', [StringComparison]::Ordinal)
    })
    $noButtons = @($Controls | Where-Object {
      $_.Id -eq 7 -and $_.Cls -ceq 'Button' -and $_.Enabled -eq $true -and
      [string]::Equals([string]$_.Title, '&No', [StringComparison]::Ordinal)
    })
    if ((Test-ModOrderWarningText $body) -and $yesButtons.Count -eq 1 -and
        $yesButtons[0].Id -eq 6 -and $noButtons.Count -eq 1) {
      return [pscustomobject]@{ Kind='Warning'; Button=$yesButtons[0]; Diagnostic='' }
    }
    return [pscustomobject]@{ Kind='Unknown'; Button=$null; Diagnostic='warning-text-or-yes-no-control-mismatch' }
  }

  $validLauncherTitle = $title -ceq 'kenshi' -or
    $rawTitle -cmatch '^Kenshi [0-9]+\.[0-9]+\.[0-9]+ - x64(?: \([^()\r\n]+\))?\z'
  $launcherButtons = @($Controls | Where-Object {
    $_.Id -eq 1003 -and $_.Cls -ceq 'Button' -and $_.Enabled -eq $true -and
    (Normalize-WarningText ([string]$_.Title)) -eq 'ok'
  })
  if ($validLauncherTitle -and $launcherButtons.Count -eq 1) {
    return [pscustomobject]@{ Kind='Launcher'; Button=$launcherButtons[0]; Diagnostic='' }
  }
  [pscustomobject]@{ Kind='Unknown'; Button=$null; Diagnostic='unrecognized-kenshi-dialog' }
}

# Classify every scoped modal before acting. This lets the test launcher clear
# exact known mod warnings first, while unrelated prompts remain untouched and
# cause the launch path to fail closed afterwards.
function Get-TestDialogBatch($Entries, [uint32[]]$ExpectedPids) {
  $warnings = @()
  $remaining = @()
  foreach ($entry in $Entries) {
    $decision = Get-TestDialogDecision $entry.Dialog $entry.Controls $ExpectedPids
    $classified = [pscustomobject]@{ Dialog=$entry.Dialog; Controls=$entry.Controls; Decision=$decision }
    if ($decision.Kind -eq 'Warning') { $warnings += $classified }
    else { $remaining += $classified }
  }
  [pscustomobject]@{ Warnings=$warnings; Remaining=$remaining }
}

if ($MyInvocation.InvocationName -ne '.') {
  $script:cases = 0
  function Assert-Guard([bool]$Ok, [string]$Name) { if (-not $Ok) { throw "FAIL $Name" }; $script:cases++ }
  $testPid = [uint32]4321
  $warning = [pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='Mods warning' }
  $oldWarningTitle = [pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='Kenshi CTD Fix' }
  $yesButton = [pscustomobject]@{ Id=6; Cls='Button'; Title='&Yes'; Enabled=$true }
  $noButton = [pscustomobject]@{ Id=7; Cls='Button'; Title='&No'; Enabled=$true }
  $warningControls = @(
    [pscustomobject]@{ Id=101; Cls='Static'; Title='One or more mods are missing or in incorrect order. Continue anyway?'; Enabled=$true },
    $yesButton,
    $noButton
  )
  $d = Get-TestDialogDecision $warning $warningControls @($testPid)
  Assert-Guard ($d.Kind -eq 'Warning' -and $d.Button.Id -eq 6) 'observed Mods warning accepts its unique enabled Yes button'
  Assert-Guard ((Get-TestDialogDecision $oldWarningTitle $warningControls @($testPid)).Kind -eq 'Warning') 'existing Kenshi CTD Fix title remains recognized with exact observed content'
  $layoutSplit = @([pscustomobject]@{ Id=10; Cls='Static'; Title="One or more mods are missing or in incorrect order.`r`nContinue anyway?" }, $yesButton, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $layoutSplit @($testPid)).Kind -eq 'Warning') 'line-break layout variation preserves the exact observed warning text'
  $wordingVariation = @([pscustomobject]@{ Id=10; Cls='Static'; Title="ONE OR MORE MODS ARE MISSING OR IN INCORRECT ORDER!`r`nContinue anyway." }, $yesButton, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $wordingVariation @($testPid)).Kind -eq 'Unknown') 'case and punctuation variation of the observed warning is refused'
  $titleCaseVariation = [pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='mods warning' }
  Assert-Guard ((Get-TestDialogDecision $titleCaseVariation $warningControls @($testPid)).Kind -eq 'Unknown') 'warning title must match one of the exact observed titles'
  $missingOnly = @([pscustomobject]@{ Id=101; Cls='Static'; Title='One or more mods are missing. Continue anyway?' }, $yesButton, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $missingOnly @($testPid)).Kind -eq 'Unknown') 'missing-mod-only warning is not accepted'
  $orderOnly = @([pscustomobject]@{ Id=101; Cls='Static'; Title='Some mods are in incorrect order. Continue anyway?' }, $yesButton, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $orderOnly @($testPid)).Kind -eq 'Unknown') 'incorrect-order-only warning is not accepted'
  $unobservedWording = @([pscustomobject]@{ Id=101; Cls='Static'; Title='Some mods are in the wrong order or missing. Continue anyway?' }, $yesButton, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $unobservedWording @($testPid)).Kind -eq 'Unknown') 'unobserved wording is not auto-accepted'
  $otherTitle = [pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='Steam' }
  Assert-Guard ((Get-TestDialogDecision $otherTitle $warningControls @($testPid)).Kind -eq 'Unknown') 'unrelated title is not accepted'
  $otherText = @([pscustomobject]@{ Id=101; Cls='Static'; Title='The game cannot write a crash dump.' }, $yesButton, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $otherText @($testPid)).Kind -eq 'Unknown') 'unrelated dialog text is not accepted'
  $crash = [pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='RE_Kenshi crash handler' }
  $crashControls = @(
    [pscustomobject]@{ Id=100; Cls='Static'; Title='The game crashed. Force SAVE?' },
    $yesButton,
    $noButton
  )
  Assert-Guard ((Get-TestDialogDecision $crash $crashControls @($testPid)).Kind -eq 'Unknown') 'force-SAVE crash handler prompt is refused'
  Assert-Guard ((Get-TestDialogDecision $warning $warningControls @([uint32]9876)).Kind -eq 'Ignore') 'different process is untouched'
  $disabled = @($warningControls[0], [pscustomobject]@{ Id=6; Cls='Button'; Title='&Yes'; Enabled=$false }, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $disabled @($testPid)).Kind -eq 'Unknown') 'disabled affirmative rejected'
  $ambiguous = @($warningControls[0], $yesButton, [pscustomobject]@{ Id=8; Cls='Button'; Title='&Yes'; Enabled=$true }, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $ambiguous @($testPid)).Kind -eq 'Unknown') 'ambiguous affirmative rejected'
  $wrongButtonId = @($warningControls[0], [pscustomobject]@{ Id=5; Cls='Button'; Title='&Yes'; Enabled=$true }, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $wrongButtonId @($testPid)).Kind -eq 'Unknown') 'Yes with an unexpected control ID is refused'
  $missingNo = @($warningControls[0], $yesButton)
  Assert-Guard ((Get-TestDialogDecision $warning $missingNo @($testPid)).Kind -eq 'Unknown') 'missing No control is refused'
  $changedYesCaption = @($warningControls[0], [pscustomobject]@{ Id=6; Cls='Button'; Title='YES!'; Enabled=$true }, $noButton)
  Assert-Guard ((Get-TestDialogDecision $warning $changedYesCaption @($testPid)).Kind -eq 'Unknown') 'altered affirmative caption is refused'
  $changedNoCaption = @($warningControls[0], $yesButton, [pscustomobject]@{ Id=7; Cls='Button'; Title='&NO?'; Enabled=$true })
  Assert-Guard ((Get-TestDialogDecision $warning $changedNoCaption @($testPid)).Kind -eq 'Unknown') 'altered negative caption is refused'
  $batchEntries = @(
    [pscustomobject]@{ Dialog=$crash; Controls=$crashControls },
    [pscustomobject]@{ Dialog=$warning; Controls=$warningControls },
    [pscustomobject]@{ Dialog=([pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='Mods warning' }); Controls=$warningControls }
  )
  $batch = Get-TestDialogBatch $batchEntries @($testPid)
  Assert-Guard ($batch.Warnings.Count -eq 2 -and $batch.Warnings[0].Decision.Button.Id -eq 6 -and $batch.Warnings[1].Decision.Button.Id -eq 6 -and $batch.Remaining.Count -eq 1 -and $batch.Remaining[0].Decision.Kind -eq 'Unknown') 'two duplicate warnings are ordered before the refused crash modal'
  $launcher = [pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='Kenshi 1.0.65 - x64 (Newland)' }
  $launcherButton = [pscustomobject]@{ Id=1003; Cls='Button'; Title='&OK'; Enabled=$true }
  Assert-Guard ((Get-TestDialogDecision $launcher @($launcherButton) @($testPid)).Kind -eq 'Launcher') 'versioned normal launcher remains recognized'
  $unknownKenshi = [pscustomobject]@{ Pid=$testPid; Cls='#32770'; Title='Kenshi crash recovery' }
  Assert-Guard ((Get-TestDialogDecision $unknownKenshi @($launcherButton) @($testPid)).Kind -eq 'Unknown') 'unrelated Kenshi dialog is refused'
  $launcherPath = Join-Path $PSScriptRoot '..\..\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1'
  $launcherSource = Get-Content -LiteralPath $launcherPath -Raw
  $functionStart = $launcherSource.IndexOf('function Get-Launcher {', [StringComparison]::Ordinal)
  $functionEnd = $launcherSource.IndexOf('function Get-GameWindow {', $functionStart, [StringComparison]::Ordinal)
  Assert-Guard ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'test launcher guard function is present'
  $launcherGuard = $launcherSource.Substring($functionStart, $functionEnd - $functionStart)
  Assert-Guard ($launcherGuard.Contains("[KenshiWin32]::TopWindows(`$scopedPids) | Where-Object { `$_.Cls -eq '#32770' }")) 'AutoAccept scan includes Mods warning and crash-handler modal titles'
  $warningLoop = $launcherGuard.IndexOf('foreach ($entry in $batch.Warnings)', [StringComparison]::Ordinal)
  $remainingLoop = $launcherGuard.IndexOf('foreach ($entry in $batch.Remaining)', [StringComparison]::Ordinal)
  Assert-Guard ($warningLoop -ge 0 -and $remainingLoop -gt $warningLoop) 'all exact warnings are handled before unrelated modals refuse launch'
  $pathRecheck = $launcherGuard.IndexOf('Get-KenshiProcs | Where-Object', $warningLoop, [StringComparison]::Ordinal)
  $postMessage = $launcherGuard.IndexOf('[KenshiWin32]::PostMessage($fresh[0].Handle, [KenshiWin32]::WM_COMMAND', [StringComparison]::Ordinal)
  Assert-Guard ($pathRecheck -gt $warningLoop -and $postMessage -gt $pathRecheck -and $launcherGuard.Contains('-ine $expectedExecutablePath')) 'fresh process executable path is revalidated before posting the button click'
  Assert-Guard ($launcherGuard.Contains('[KenshiWin32]::PostMessage($fresh[0].Handle, [KenshiWin32]::WM_COMMAND') -and
    $launcherGuard.Contains('[IntPtr]([uint32]$freshDecision.Button.Id), $freshDecision.Button.Handle)') -and -not $launcherGuard.Contains('[KenshiWin32]::BM_CLICK') -and
    $launcherGuard -notmatch 'SetForegroundWindow|ForceForeground|PressDialogButton|keybd_event|mouse_event|SendInput') 'warning action posts exact parent WM_COMMAND without focus or physical input'
  'RESULT MOD_ORDER_WARNING_GUARD PASS cases={0}' -f $script:cases
}
