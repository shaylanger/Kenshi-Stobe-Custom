# testruns-sweep-selftest.ps1 (PI-62): selftest for `testruns-sweep.ps1 -Auto`, temp root only (no live state, no WSL, no ssh).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\testruns-sweep-selftest.ps1
# Output: one "SELFTEST testruns-sweep <case> PASS|FAIL" line per case, final "SELFTEST-SUMMARY n pass / m fail"; exit 1 on any FAIL.
$ErrorActionPreference = 'Stop'
$sweep = Join-Path $PSScriptRoot 'testruns-sweep.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("sweepst-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; "SELFTEST testruns-sweep $name PASS" } else { $script:fail++; "SELFTEST testruns-sweep $name FAIL $detail" }
}
function Mk-Root([string]$name) {
    $r = Join-Path $tmp $name
    foreach ($d in 'agents', 'inflight', 'queue', 'corpus', 'logs') { New-Item -ItemType Directory -Force -Path (Join-Path $r $d) | Out-Null }
    $r
}
function Mk([string]$root, [string]$name, [double]$ageH, [switch]$Dir, [string]$content = 'x') {
    $p = Join-Path $root $name
    if ($Dir) { New-Item -ItemType Directory -Force -Path $p | Out-Null; $f = Join-Path $p 'f.txt'; Set-Content -LiteralPath $f -Value $content; $items = @($p, $f) }
    else { Set-Content -LiteralPath $p -Value $content; $items = @($p) }
    $t = (Get-Date).AddHours(-$ageH)
    foreach ($i in $items) { (Get-Item -LiteralPath $i -Force).LastWriteTime = $t }
    $p
}
function Run-Sweep([string]$root, [string[]]$more = @()) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sweep, 'check', '-Auto', '-NoRemote', '-Local', '-Root', $root, '-WorkspaceRepo', $script:repo) + $more
    $o = & powershell @a 2>&1
    $script:lastExit = $LASTEXITCODE
    ($o | Out-String)
}
try {
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    # a workspace repo with a remote: pushed, then (later) one unpushed commit
    $bare = Join-Path $tmp 'remote.git'; $script:repo = Join-Path $tmp 'ws'
    & git init -q --bare $bare 2>&1 | Out-Null
    & git init -q -b main $script:repo 2>&1 | Out-Null
    & git -C $script:repo config user.email t@t; & git -C $script:repo config user.name t
    Set-Content -LiteralPath (Join-Path $script:repo 'a.txt') -Value 1
    & git -C $script:repo add -A; & git -C $script:repo commit -q -m c1
    & git -C $script:repo remote add origin $bare; & git -C $script:repo push -q -u origin main 2>&1 | Out-Null

    # ---------- case 1: allow-list deletes, protections hold ----------
    $r = Mk-Root 'r1'
    $selfTxt = Mk $r 'selftest-run7.txt' 30
    $pd = Mk $r 'pd' 30 -Dir
    $brief = Mk $r 'agents$2.brief.md' 30
    $nc10 = Mk $r 'imm26-nc10' 30 -Dir
    $nc10b = Mk $r 'imm26-nc10-b' 30 -Dir
    $nc31 = Mk $r 'imm26-nc31' 30 -Dir       # newest-2 = 31 -> N <= 31 deletable
    $nc32 = Mk $r 'imm26-nc32' 30 -Dir       # too new to delete -> auto-keep
    $nc33 = Mk $r 'imm26-nc33' 30 -Dir       # newest
    $ncRun = Mk $r 'imm26-nc12' 30 -Dir      # named by a RUNNING status -> protected
    $ncFresh = Mk $r 'imm26-nc11' 2 -Dir     # fresh -> untouched
    $selfFresh = Mk $r 'selftest-run8.txt' 2 # fresh -> untouched
    $unknown = Mk $r 'mystery-dir' 40 -Dir   # unknown name -> stays STALE
    $unknownF = Mk $r 'notes.txt' 40
    $selfOther = Mk $r 'selftest-all-3.txt' 40  # not in allow-list -> stays
    $pdLike = Mk $r 'pd-keep' 40 -Dir        # only exact 'pd'
    $inflMarked = Mk $r 'selftest-run99.txt' 40  # named by an inflight marker -> protected
    $corp = Mk $r 'corpus\old.txt' 100       # corpus content untouched
    Set-Content -LiteralPath (Join-Path $r 'inflight\selftest-run99.txt') -Value 'marker'
    Set-Content -LiteralPath (Join-Path $r 'agents\wp1.status') -Value "wp1 | RUNNING | 2026-10-16 20:00`ntask: x`nlatest: y`noutputs: imm26-nc12 tree`nnext: z"
    $out = Run-Sweep $r
    Check 'del-selftest-run' (-not (Test-Path -LiteralPath $selfTxt))
    Check 'del-pd' (-not (Test-Path -LiteralPath $pd))
    Check 'del-stray-brief' (-not (Test-Path -LiteralPath $brief))
    Check 'del-old-nc' ((-not (Test-Path -LiteralPath $nc10)) -and (-not (Test-Path -LiteralPath $nc10b)) -and (-not (Test-Path -LiteralPath $nc31)))
    Check 'keep-recent-nc-on-disk' ((Test-Path -LiteralPath $nc32) -and (Test-Path -LiteralPath $nc33))
    $keepTxt = if (Test-Path (Join-Path $r 'sweep-keep.tsv')) { Get-Content -Raw (Join-Path $r 'sweep-keep.tsv') } else { '' }
    Check 'autokeep-recent-nc-recorded' (($keepTxt -match 'imm26-nc32') -and ($keepTxt -match 'imm26-nc33') -and ($keepTxt -match 'AUTO\(PI-62\)'))
    Check 'running-status-protects-nc' (Test-Path -LiteralPath $ncRun)
    Check 'fresh-protected' ((Test-Path -LiteralPath $ncFresh) -and (Test-Path -LiteralPath $selfFresh))
    Check 'unknown-name-stays-stale' ((Test-Path -LiteralPath $unknown) -and (Test-Path -LiteralPath $unknownF) -and ($out -match 'mystery-dir') -and ($out -match 'notes\.txt'))
    Check 'selftest-all-not-allowlisted' ((Test-Path -LiteralPath $selfOther) -and (Test-Path -LiteralPath $pdLike))
    Check 'inflight-named-protected' (Test-Path -LiteralPath $inflMarked)
    Check 'corpus-untouched' ((Test-Path -LiteralPath $corp) -and (Test-Path -LiteralPath (Join-Path $r 'inflight\selftest-run99.txt')) -and (Test-Path -LiteralPath (Join-Path $r 'agents\wp1.status')))
    $log = if (Test-Path (Join-Path $r 'sweep-auto.log')) { Get-Content -Raw (Join-Path $r 'sweep-auto.log') } else { '' }
    Check 'deletions-logged' (($log -match 'DELETE.*selftest-run7\.txt') -and ($log -match 'DELETE.*\\pd\t') -and ($log -match 'DELETE.*imm26-nc10\t') -and ($log -notmatch 'DELETE.*mystery'))
    Check 'check-still-exit1-for-leftovers' ($script:lastExit -eq 1) "exit=$script:lastExit"

    # ---------- case 2: second run does not re-keep, and does not delete kept ----------
    $before = (Get-Content (Join-Path $r 'sweep-keep.tsv')).Count
    [void](Run-Sweep $r)
    Check 'idempotent-keep' ((Get-Content (Join-Path $r 'sweep-keep.tsv')).Count -eq $before)

    # ---------- case 3: expired auto-keep is not renewed ----------
    $r3 = Mk-Root 'r3'
    $rep = Mk $r3 'b3-report.txt' 30
    $old = (Get-Date).AddDays(-8).ToString('yyyy-MM-dd HH:mm')
    Set-Content -LiteralPath (Join-Path $r3 'sweep-keep.tsv') -Value "$old`t$rep`tAUTO(PI-62): finished agent report file"
    $out3 = Run-Sweep $r3
    Check 'expired-autokeep-surfaces-stale' (($out3 -match 'b3-report\.txt') -and ($script:lastExit -eq 1)) "exit=$script:lastExit"
    Check 'expired-autokeep-not-deleted' (Test-Path -LiteralPath $rep)

    # ---------- case 4: auto-keep removes the block (no other leftovers) ----------
    $r4 = Mk-Root 'r4'
    [void](Mk $r4 'pi11-stage' 30 -Dir); [void](Mk $r4 'b3-report.txt' 30)
    $out4 = Run-Sweep $r4
    Check 'autokeep-clears-block' ($script:lastExit -eq 0 -and $out4 -match 'old24=0') "exit=$script:lastExit out=$out4"
    Check 'autokeep-keeps-files' ((Test-Path (Join-Path $r4 'pi11-stage')) -and (Test-Path (Join-Path $r4 'b3-report.txt')))

    # ---------- case 5: 4080 launch-log dump via cache, auto-kept; unknown 4080 item stays ----------
    $r5 = Mk-Root 'r5'
    Set-Content -LiteralPath (Join-Path $r5 'sweep-4080.cache') -Value @('C:\KenshiTestRuns\logs\20261016-094137-before-launch|40.0|9.2', 'C:\KAH\weird-thing|40.0|1.0')
    $out5 = Run-Sweep $r5
    Check '4080-launch-dump-autokept' (((Get-Content -Raw (Join-Path $r5 'sweep-keep.tsv')) -match '4080:C:\\KenshiTestRuns\\logs\\20261016-094137-before-launch') -and ($out5 -notmatch 'before-launch'))
    Check '4080-unknown-stays-stale' ($out5 -match 'weird-thing')
    Check '4080-never-deleted-remote' (-not (Test-Path (Join-Path $r5 'sweep-auto.log')) -or ((Get-Content -Raw (Join-Path $r5 'sweep-auto.log')) -notmatch 'DELETE'))

    # ---------- case 6: unpushed commit blocks NC delete and auto-keep ----------
    Set-Content -LiteralPath (Join-Path $script:repo 'b.txt') -Value 2
    & git -C $script:repo add -A; & git -C $script:repo commit -q -m c2
    $r6 = Mk-Root 'r6'
    $a = Mk $r6 'imm26-nc1' 30 -Dir; [void](Mk $r6 'imm26-nc33' 30 -Dir); $b = Mk $r6 'pi5-stage' 30 -Dir; $c = Mk $r6 'selftest-run1.txt' 30
    $out6 = Run-Sweep $r6
    Check 'unpushed-blocks-nc-delete' (Test-Path -LiteralPath $a)
    Check 'unpushed-blocks-autokeep' ((-not (Test-Path (Join-Path $r6 'sweep-keep.tsv'))) -and ($out6 -match 'pi5-stage'))
    Check 'unpushed-does-not-block-selftest-delete' (-not (Test-Path -LiteralPath $c))

    # ---------- case 7: dry run changes nothing ----------
    $r7 = Mk-Root 'r7'
    $d7 = Mk $r7 'selftest-run1.txt' 30
    [void](Run-Sweep $r7 @('-DryRun'))
    Check 'dryrun-no-delete' (Test-Path -LiteralPath $d7)

    # ---------- case 8: without -Auto nothing is touched (hook behaviour unchanged) ----------
    $r8 = Mk-Root 'r8'
    $d8 = Mk $r8 'selftest-run1.txt' 30
    $o8 = & powershell -NoProfile -ExecutionPolicy Bypass -File $sweep check -NoRemote -Local -Root $r8 -WorkspaceRepo $script:repo 2>&1 | Out-String
    Check 'no-auto-no-change' ((Test-Path -LiteralPath $d8) -and ($LASTEXITCODE -eq 1) -and ($o8 -match 'selftest-run1'))

    # ---------- case 9: nothing named like corpus/fixtures can be deleted even if it matches a pattern ----------
    $r9 = Mk-Root 'r9'
    $fx = Mk $r9 'KenshiTestFixtures' 100 -Dir
    $o9 = Run-Sweep $r9
    Check 'fixtures-protected' (Test-Path -LiteralPath $fx)
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST-SUMMARY $pass pass / $fail fail"
exit ([int]($fail -gt 0))
