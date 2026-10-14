$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$body = Get-Content -LiteralPath (Join-Path $dir 'excerpt.sh') -Raw
$readme = Get-Content -LiteralPath (Join-Path $dir 'README.md') -Raw
$runner = Get-Content -LiteralPath (Join-Path $dir 'run.ps1') -Raw
$transportText = Get-Content -LiteralPath (Join-Path $dir 'invoke-wsl-captured.ps1') -Raw
$expectedTransportHash = 'ED417184EAC849DEFCDCB9F49F969B037A6159B67431051E53FCF450E70667DF'
$transportPath = 'C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1'
$transportSnapshot = Join-Path $dir 'invoke-wsl-captured.ps1'
$transportExists = Test-Path -LiteralPath $transportPath -PathType Leaf
$transportHash = if ($transportExists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $transportPath).Hash } else { '' }
$transportSnapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $transportSnapshot).Hash
$bodyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dir 'excerpt.sh')).Hash
$manifestPath = Join-Path $dir 'packet.manifest.tsv'
$expectedPacketFiles = @('README.md', 'run.ps1', 'excerpt.sh', 'selftest.ps1', 'sanitizer.fixture.txt', 'invoke-wsl-captured.ps1', 'transport-helper.tests.ps1')
$expectedExternalPaths = @('C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1', 'C:\KenshiModding\tools\automation\invoke-wsl-captured-ps51.tests.ps1')
$manifestOk = $false
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
  $manifestLines = @(Get-Content -LiteralPath $manifestPath)
  $manifestOk = $manifestLines.Count -ge 2 -and $manifestLines[0] -ceq ('kind' + [char]9 + 'path' + [char]9 + 'sha256')
  $seenPacket = @{}
  $seenExternal = @{}
  if ($manifestOk) {
    foreach ($manifestLine in $manifestLines | Select-Object -Skip 1) {
      $fields = $manifestLine -split ([char]9), 3
      if ($fields.Count -ne 3 -or $fields[2] -notmatch '^[0-9A-F]{64}$') { $manifestOk = $false; break }
      if ($fields[0] -ceq 'file' -and $fields[1] -cin $expectedPacketFiles -and -not $seenPacket.ContainsKey($fields[1])) {
        $resolvedArtifact = Join-Path $dir $fields[1]
        $seenPacket[$fields[1]] = $true
      } elseif ($fields[0] -ceq 'external' -and $fields[1] -cin $expectedExternalPaths -and -not $seenExternal.ContainsKey($fields[1])) {
        $resolvedArtifact = $fields[1]
        $seenExternal[$fields[1]] = $true
      } else { $manifestOk = $false; break }
      if (-not (Test-Path -LiteralPath $resolvedArtifact -PathType Leaf) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedArtifact).Hash -cne $fields[2]) {
        $manifestOk = $false; break
      }
    }
  }
  if ($seenPacket.Count -ne $expectedPacketFiles.Count -or $seenExternal.Count -ne $expectedExternalPaths.Count) { $manifestOk = $false }
}
$tokens = $null; $errors = $null
$runnerAst = [System.Management.Automation.Language.Parser]::ParseInput($runner, [ref]$tokens, [ref]$errors)
$checks = @(
  @{ Name='exact host and WSL route'; Ok=$runner.Contains('$expectedHost = ''DESKTOP-JFLPK99''') -and $runner.Contains('$expectedDistro = ''DwemerAI4Skyrim3''') -and $runner.Contains('$expectedWorkingDirectory = ''/mnt/c/KenshiModding''') -and $runner.Contains('-Distro $expectedDistro') -and $runner.Contains('-WorkingDirectory $expectedWorkingDirectory') },
  @{ Name='exact documented argv and staged receiver'; Ok=$readme.Contains('wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding -- bash -c') -and $readme.Contains('tmp=$(mktemp) || exit $?') -and $readme.Contains('cat >"$tmp" || exit $?') -and $readme.Contains('bash -s <"$tmp"') -and $transportText.Contains('Get-WslBashReceiver') -and $transportText.Contains('Get-WslBashArguments') },
  @{ Name='transport snapshot exactly matches pinned shared helper'; Ok=$transportExists -and $transportHash -ceq $expectedTransportHash -and $transportSnapshotHash -ceq $expectedTransportHash },
  @{ Name='manifest pins every exact local and external artifact'; Ok=$manifestOk },
  @{ Name='exact original six paths and three query tokens'; Ok=@('interaction.php','lib/playthrough_preferences.php','lib/playthrough_runtime.php','lib/travel_companionship.php','lib/chat_helper_functions.php','lib/activity/ActivityService.php' | Where-Object { -not $body.Contains($_) }).Count -eq 0 -and @('/var/lib/stobe','stobe_negotiation_','sys_get_temp_dir' | Where-Object { -not $body.Contains($_) }).Count -eq 0 },
  @{ Name='reviewed body hash is pinned'; Ok=$runner.Contains("'$bodyHash'") },
  @{ Name='reviewed transport hash is pinned before invocation'; Ok=$runner.Contains("`$expectedTransportSha256 = '$expectedTransportHash'") -and $runner.IndexOf('Assert-TransportPin -Path $transport') -lt $runner.IndexOf('& $transport') -and $runner.Contains('if ($actual -cne $ExpectedHash)') },
  @{ Name='transport pin function is present'; Ok=$null -ne $runnerAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-TransportPin' }, $true) },
  @{ Name='fixture modes cannot be inherited by launcher'; Ok=$runner.Contains('Test-Path -LiteralPath "Env:$name"') -and $runner.Contains('STOBE_PACKET_FIXTURE') -and $runner.Contains('STOBE_PACKET_FIXTURE_PATH') -and $runner.Contains('STOBE_PACKET_GIT_FIXTURE') -and $runner.Contains('STOBE_PACKET_GIT_FIXTURE_ROOT') -and $runner.Contains('STOBE_PACKET_GIT_FIXTURE_COMMIT') -and $runner.Contains('STOBE_PACKET_GIT_FIXTURE_PATH') },
  @{ Name='exact documented roots and commits'; Ok=$body.Contains('/var/www/html/StobeServer 4722ddd96d838e84ddb9a49da0ee893f45bcaab7') -and $body.Contains('/root/stobe-work/ss-merge 7aff5ba605a956d33accc8080f712dfba4015246') },
  @{ Name='fixed six-file allowlist'; Ok=$body.Contains('files=(interaction.php lib/playthrough_preferences.php lib/playthrough_runtime.php lib/travel_companionship.php lib/chat_helper_functions.php lib/activity/ActivityService.php)') },
  @{ Name='protected and out-of-scope files excluded'; Ok=($body -split "`n" | Where-Object { $_ -match '^  local files=' }) -notmatch 'playthrough_switching|negotiation_engine' -and $readme.Contains('remains excluded') -and $readme.Contains('outside the currently authorized list') },
  @{ Name='only exact match tokens printed'; Ok=$body.Contains('while IFS= read -r source_line') -and $body.Contains('no source line or adjacent context') -and $body.Contains('MATCH_FILE=%s TOKEN=%s') -and $body -notmatch 'grep|sed -n|cat --' },
  @{ Name='source exact commit and clean tracked path gates'; Ok=$body.Contains('[[ "$commit" != "$expected_commit" ]]') -and $body.Contains('ls-tree --full-tree "$commit" -- "$rel"') -and $body.Contains('FAIL=path_absent_from_pinned_tree') -and $body.Contains('GIT_NO_LAZY_FETCH=1') -and $body.Contains('cat-file -e "$blob"') -and $body.Contains('FAIL=blob_object_unavailable_at_pinned_commit') -and $body.Contains('diff --quiet "$commit" -- "$rel"') -and $body.Contains('realpath -e -- "$path"') },
  @{ Name='no forbidden runtime/data operations'; Ok=$body -notmatch 'curl|wget|psql|pg_isready|8083|18083|ssh|systemctl|service |INSERT|UPDATE|DELETE|/etc/|credentials|save' },
  @{ Name='incomplete throttle evidence explicit'; Ok=$body.Contains('THROTTLE_FILE=lib/negotiation_engine.php STATUS=NOT_IN_ALLOWLIST_NOT_INSPECTED') },
  @{ Name='fixed match cap and documented total output bound'; Ok=$body.Contains('readonly MAX_MATCH_ROWS=100') -and $body.Contains('FAIL=match_output_limit LIMIT=%s') -and $readme.Contains('136 output lines') -and $readme.Contains('137 total lines') },
  @{ Name='PowerShell syntax'; Ok=$errors.Count -eq 0 }
)
$failed = @($checks | Where-Object { -not $_.Ok })
if ($failed.Count) { $failed | ForEach-Object { "FAIL $($_.Name)" }; throw "packet checks failed=$($failed.Count)" }
$pinFunction = $runnerAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-TransportPin' }, $true)
Invoke-Expression $pinFunction.Extent.Text
$invocations = 0
Assert-TransportPin -Path $transportPath -ExpectedHash $expectedTransportHash
$invocations++ # fake transport invocation after accepted gate; no transport is called
if ($invocations -ne 1) { throw 'exact transport hash did not reach fake invocation' }
$invocations = 0
$mismatchRejected = $false
try {
  Assert-TransportPin -Path $transportPath -ExpectedHash ('0' * 64)
  $invocations++ # this must remain unreachable for a mismatched hash
} catch { $mismatchRejected = $_.Exception.Message -like 'PACKET_GATE_FAIL transport hash mismatch*' }
if (-not $mismatchRejected -or $invocations -ne 0) { throw "transport mismatch gate failed closed=$mismatchRejected fake_invocations=$invocations" }
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw "Git Bash missing for local syntax check: $bash" }
& $bash -n (Join-Path $dir 'excerpt.sh')
if ($LASTEXITCODE -ne 0) { throw "bash -n failed exit=$LASTEXITCODE" }
$git = (Get-Command git -ErrorAction Stop).Source
$gitFixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("stobe-source-excerpt-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $gitFixtureRoot | Out-Null
try {
  & $git -C $gitFixtureRoot init --quiet
  if ($LASTEXITCODE -ne 0) { throw "local Git fixture init failed exit=$LASTEXITCODE" }
  & $git -C $gitFixtureRoot config user.name 'Packet Selftest'
  if ($LASTEXITCODE -ne 0) { throw "local Git fixture user config failed exit=$LASTEXITCODE" }
  & $git -C $gitFixtureRoot config user.email 'packet-selftest@example.invalid'
  if ($LASTEXITCODE -ne 0) { throw "local Git fixture email config failed exit=$LASTEXITCODE" }
  Set-Content -LiteralPath (Join-Path $gitFixtureRoot 'interaction.php') -Value 'synthetic_source_must_not_be_printed' -NoNewline
  & $git -C $gitFixtureRoot add -- interaction.php
  if ($LASTEXITCODE -ne 0) { throw "local Git fixture add failed exit=$LASTEXITCODE" }
  & $git -C $gitFixtureRoot commit --quiet -m 'synthetic packet fixture'
  if ($LASTEXITCODE -ne 0) { throw "local Git fixture commit failed exit=$LASTEXITCODE" }
  $fixtureCommit = (& $git -C $gitFixtureRoot rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $fixtureCommit -notmatch '^[0-9a-f]{40,64}$') { throw 'local Git fixture commit id invalid' }
  $fixtureCommand = 'export STOBE_PACKET_GIT_FIXTURE=1 STOBE_PACKET_GIT_FIXTURE_ROOT="$1" STOBE_PACKET_GIT_FIXTURE_COMMIT="$2" STOBE_PACKET_GIT_FIXTURE_PATH="$3"; source "$4/excerpt.sh"'
  $cygpath = 'C:\Program Files\Git\usr\bin\cygpath.exe'
  if (-not (Test-Path -LiteralPath $cygpath -PathType Leaf)) { throw "cygpath missing for local fixture path conversion: $cygpath" }
  $gitFixtureRootUnix = (& $cygpath -u $gitFixtureRoot).Trim()
  $dirUnix = (& $cygpath -u $dir).Trim()
  $presentOutput = @(& $bash -c $fixtureCommand -- $gitFixtureRootUnix $fixtureCommit 'interaction.php' $dirUnix)
  $presentExit = $LASTEXITCODE
  $fixtureBlob = (& $git -C $gitFixtureRoot rev-parse "${fixtureCommit}:interaction.php").Trim()
  if ($presentExit -ne 0 -or ($presentOutput -join "`n") -cne "BLOB=$fixtureBlob FILE=interaction.php") { throw "present-path fixture mismatch exit=$presentExit output=$($presentOutput -join '|')" }
  $looseBlobPath = Join-Path (Join-Path $gitFixtureRoot '.git\objects') (Join-Path $fixtureBlob.Substring(0,2) $fixtureBlob.Substring(2))
  if (-not (Test-Path -LiteralPath $looseBlobPath -PathType Leaf)) { throw 'local Git fixture blob was not stored as the expected loose object' }
  Remove-Item -LiteralPath $looseBlobPath -Force
  $unavailableBlobOutput = @(& $bash -c $fixtureCommand -- $gitFixtureRootUnix $fixtureCommit 'interaction.php' $dirUnix)
  $unavailableBlobExit = $LASTEXITCODE
  if ($unavailableBlobExit -eq 0 -or ($unavailableBlobOutput -join "`n") -cne 'FAIL=blob_object_unavailable_at_pinned_commit FILE=interaction.php') { throw "unavailable-blob fixture mismatch exit=$unavailableBlobExit output=$($unavailableBlobOutput -join '|')" }
  $missingOutput = @(& $bash -c $fixtureCommand -- $gitFixtureRootUnix $fixtureCommit 'lib/travel_companionship.php' $dirUnix)
  $missingExit = $LASTEXITCODE
  if ($missingExit -eq 0 -or ($missingOutput -join "`n") -cne 'FAIL=path_absent_from_pinned_tree FILE=lib/travel_companionship.php') { throw "missing-tree-entry fixture mismatch exit=$missingExit output=$($missingOutput -join '|')" }
  $invalidOutput = @(& $bash -c $fixtureCommand -- $gitFixtureRootUnix ('f' * 40) 'interaction.php' $dirUnix)
  $invalidExit = $LASTEXITCODE
  if ($invalidExit -eq 0 -or ($invalidOutput -join "`n") -cne 'FAIL=git_tree_lookup FILE=interaction.php') { throw "git-tree-error fixture mismatch exit=$invalidExit output=$($invalidOutput -join '|')" }
  if (($presentOutput + $unavailableBlobOutput + $missingOutput + $invalidOutput) -join "`n" -match 'synthetic_source_must_not_be_printed') { throw 'pinned-tree metadata fixture printed synthetic source contents' }
  'RESULT 5090-SOURCE-EXCERPT-TREE-SELFTEST PASS cases=4 synthetic_git=local_only source_content_printed=no'
} finally {
  $resolvedFixture = (Resolve-Path -LiteralPath $gitFixtureRoot).Path
  $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  if (-not $resolvedFixture.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or [System.IO.Path]::GetFileName($resolvedFixture) -notlike 'stobe-source-excerpt-*') { throw "refusing unsafe temp cleanup path=$resolvedFixture" }
  Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
Push-Location $dir
try {
  $fixtureOutput = @(& $bash -c 'export STOBE_PACKET_FIXTURE=1 STOBE_PACKET_FIXTURE_PATH=./sanitizer.fixture.txt; source ./excerpt.sh')
  $fixtureExit = $LASTEXITCODE
} finally { Pop-Location }
if ($fixtureExit -ne 0) { throw "sanitizer fixture process failed exit=$fixtureExit" }
$expected = @('MATCH_FILE=fixture TOKEN=1:/var/lib/stobe','MATCH_FILE=fixture TOKEN=2:stobe_negotiation_','MATCH_FILE=fixture TOKEN=3:sys_get_temp_dir')
if (($fixtureOutput -join "`n") -cne ($expected -join "`n")) { throw "sanitizer fixture mismatch: $($fixtureOutput -join '|')" }
if (($fixtureOutput -join "`n") -match 'SYNTHETIC_SECRET|must-not-appear|do-not-print-neighbor|unrelated=') { throw 'sanitizer fixture leaked surrounding content' }
$limitFixture = Join-Path ([System.IO.Path]::GetTempPath()) ("stobe-source-excerpt-limit-" + [guid]::NewGuid().ToString('N') + '.txt')
try {
  Set-Content -LiteralPath $limitFixture -Value (@(1..101 | ForEach-Object { '/var/lib/stobe' }))
  $limitFixtureUnix = (& $cygpath -u $limitFixture).Trim()
  $limitOutput = @(& $bash -c 'export STOBE_PACKET_FIXTURE=1 STOBE_PACKET_FIXTURE_PATH="$1"; source "$2/excerpt.sh"' -- $limitFixtureUnix $dirUnix)
  $limitExit = $LASTEXITCODE
  $matchRows = @($limitOutput | Where-Object { $_ -match '^MATCH_FILE=fixture TOKEN=[0-9]+:/var/lib/stobe$' })
  $limitFailures = @($limitOutput | Where-Object { $_ -ceq 'FAIL=match_output_limit LIMIT=100' })
  if ($limitExit -eq 0 -or $matchRows.Count -ne 100 -or $limitFailures.Count -ne 1 -or $limitOutput.Count -gt 137) {
    throw "match-cap fixture failed exit=$limitExit matches=$($matchRows.Count) fail_rows=$($limitFailures.Count) lines=$($limitOutput.Count)"
  }
  'RESULT 5090-SOURCE-EXCERPT-LIMIT-SELFTEST PASS synthetic_rows=101 emitted_matches=100 overflow=fail_closed output_lines=' + $limitOutput.Count
} finally {
  if (Test-Path -LiteralPath $limitFixture -PathType Leaf) { Remove-Item -LiteralPath $limitFixture -Force }
}
"RESULT 5090-SOURCE-EXCERPT-SELFTEST PASS cases=$($checks.Count) tree_fixture=4 sanitizer_fixture=3 limit_fixture=101 shell_syntax=pass transport_gate=accept+mismatch_reject fake_invocations=0 route_contact=no"
