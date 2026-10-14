param([string]$ScratchRoot = '')
$ErrorActionPreference = 'Stop'

function FullPath([string]$Path) { [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
function AssertPath([string]$Name, [string]$Actual, [string]$Expected) {
    if (-not [string]::Equals((FullPath $Actual), (FullPath $Expected), [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Name}: actual=$(FullPath $Actual) expected=$(FullPath $Expected)"
    }
}
function AssertRequiredFiles([string]$Root, [string[]]$RelativePaths) {
    $missing = @($RelativePaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf) })
    if ($missing.Count -gt 0) { throw "missing staged dependency: $($missing -join ', ')" }
}

$candidateRel = Join-Path 'pending-fixes\today-dialogue-fixes' 'coarse-region-integration'
$candidateRelPath = Join-Path $candidateRel 'fixture.php'
$processorRel = Join-Path '..\combined\processor' 'chat.php'
$adapterRel = Join-Path '..\..\live-destination-broader\server' 'travel-adapter-baseline.php'
$activityPackageRel = 'pending-fixes\npc-immersion\combined-release-destination-discovery-incomplete-hunt-20261013'
$activityRequired = @(
    'live\lib\activity\ActivityAgreementAdapter.php',
    'live\lib\activity\ActivityService.php',
    'live\lib\destination_discovery.php',
    'live\lib\destination_catalog.json',
    'merge\lib\activity\ActivityChat.php',
    'merge\lib\activity\ActivityAgreementAdapter.php',
    'merge\lib\activity\ActivityService.php',
    'merge\lib\destination_discovery.php',
    'merge\lib\destination_catalog.json',
    (Join-Path $activityPackageRel 'final-source-manifest.json'),
    'pending-fixes\activity-chat-incomplete-hunt-candidate\activity-chat-incomplete-hunt-regression.php',
    'pending-fixes\activity-chat-incomplete-hunt-candidate\ActivityAgreementAdapter.php',
    'pending-fixes\rig4080-validation\conversation-regressions\activity-regression.php',
    (Join-Path $activityPackageRel 'activity-discovery-enrichment-regression.php'),
    'pending-fixes\basic-ingame-smoke\CD2-exact-raw.json'
)
$activityScratchRequired = @($activityRequired | ForEach-Object { if ($_ -match '^(live|merge)\\') { Join-Path $activityPackageRel $_ } else { $_ } })

if ($ScratchRoot) {
    $root = FullPath $ScratchRoot
} else {
    $root = FullPath (Join-Path $PSScriptRoot '..\..')
}

$candidate = Join-Path $root $candidateRel
$expectedProcessor = Join-Path $root 'pending-fixes\today-dialogue-fixes\combined\processor\chat.php'
$expectedAdapter = Join-Path $root 'pending-fixes\live-destination-broader\server\travel-adapter-baseline.php'
AssertPath 'processor dependency from fixture directory' (Join-Path $candidate $processorRel) $expectedProcessor
AssertPath 'adapter dependency from fixture directory' (Join-Path $candidate $adapterRel) $expectedAdapter
AssertRequiredFiles $root $activityScratchRequired
if ($ScratchRoot) { AssertRequiredFiles $root $activityScratchRequired }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("kah-offline-path-selftest-" + [guid]::NewGuid().ToString('N'))
try {
    $scratchCandidate = Join-Path $tempRoot $candidateRel
    $scratchProcessor = Join-Path $tempRoot 'pending-fixes\today-dialogue-fixes\combined\processor\chat.php'
    $scratchAdapter = Join-Path $tempRoot 'pending-fixes\live-destination-broader\server\travel-adapter-baseline.php'
    foreach ($p in @($scratchCandidate, (Split-Path -Parent $scratchProcessor), (Split-Path -Parent $scratchAdapter))) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $scratchCandidate 'fixture.php') 'fixture sentinel'
    Set-Content -LiteralPath $scratchProcessor 'processor sentinel'
    Set-Content -LiteralPath $scratchAdapter 'adapter sentinel'
    AssertPath 'processor dependency from mirrored scratch fixture' (Join-Path $scratchCandidate $processorRel) $scratchProcessor
    AssertPath 'adapter dependency from mirrored scratch fixture' (Join-Path $scratchCandidate $adapterRel) $scratchAdapter
    if (-not (Test-Path -LiteralPath (Join-Path $scratchCandidate $candidateRelPath.Substring($candidateRel.Length + 1)))) { throw 'scratch fixture sentinel missing' }
    if (-not (Test-Path -LiteralPath (Join-Path $scratchCandidate $processorRel))) { throw 'scratch processor sentinel missing' }
    if (-not (Test-Path -LiteralPath (Join-Path $scratchCandidate $adapterRel))) { throw 'scratch adapter sentinel missing' }

    # Exercise the exact staging failures found on the 4080: the composed
    # ActivityChat requires its adapter sibling, the focused runner requires
    # its own adapter sibling, and broad activity regression opens the raw CD2
    # input from a repository-relative path.
    foreach ($rel in $activityScratchRequired) {
        if ($rel -eq (Join-Path $activityPackageRel 'merge\lib\activity\ActivityAgreementAdapter.php') -or
            $rel -eq 'pending-fixes\activity-chat-incomplete-hunt-candidate\ActivityAgreementAdapter.php' -or
            $rel -eq 'pending-fixes\basic-ingame-smoke\CD2-exact-raw.json') { continue }
        $target = Join-Path $tempRoot $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Set-Content -LiteralPath $target 'dependency sentinel'
    }
    $adapterTarget = Join-Path $tempRoot (Join-Path $activityPackageRel 'merge\lib\activity\ActivityAgreementAdapter.php')
    New-Item -ItemType Directory -Path (Split-Path -Parent $adapterTarget) -Force | Out-Null
    $caughtAdapterMiss = $false
    try { AssertRequiredFiles $tempRoot $activityScratchRequired } catch { $caughtAdapterMiss = $_.Exception.Message -like '*ActivityAgreementAdapter.php*' }
    if (-not $caughtAdapterMiss) { throw 'missing ActivityAgreementAdapter.php was not caught by staging preflight' }
    Set-Content -LiteralPath $adapterTarget 'adapter sentinel'
    $focusedAdapterTarget = Join-Path $tempRoot 'pending-fixes\activity-chat-incomplete-hunt-candidate\ActivityAgreementAdapter.php'
    $caughtFocusedAdapterMiss = $false
    try { AssertRequiredFiles $tempRoot $activityScratchRequired } catch { $caughtFocusedAdapterMiss = $_.Exception.Message -like '*ActivityAgreementAdapter.php*' }
    if (-not $caughtFocusedAdapterMiss) { throw 'missing focused-runner ActivityAgreementAdapter.php sibling was not caught by staging preflight' }
    Set-Content -LiteralPath $focusedAdapterTarget 'focused adapter sentinel'
    $caughtRawMiss = $false
    try { AssertRequiredFiles $tempRoot $activityScratchRequired } catch { $caughtRawMiss = $_.Exception.Message -like '*CD2-exact-raw.json*' }
    if (-not $caughtRawMiss) { throw 'missing CD2-exact-raw.json was not caught by staging preflight' }
    $rawTarget = Join-Path $tempRoot 'pending-fixes\basic-ingame-smoke\CD2-exact-raw.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $rawTarget) -Force | Out-Null
    Set-Content -LiteralPath $rawTarget '{}'
    AssertRequiredFiles $tempRoot $activityScratchRequired
    'RESULT OFFLINE-FIXTURE-PATHS PASS scratch-relative-dependencies=2 activity-staging-dependencies={0} missing-file-cases=3' -f $activityRequired.Count
}
catch {
    "RESULT OFFLINE-FIXTURE-PATHS FAIL setup $($_.Exception.Message)"
    exit 1
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
