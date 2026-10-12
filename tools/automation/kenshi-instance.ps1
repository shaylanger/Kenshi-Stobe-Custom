<#
kenshi-instance.ps1: second (third, ...) Kenshi install copies so one PC can run two test games at once (multi-instance,
C:\KenshiTestRuns\multi-instance\PLAN.md). Instance 1 = the Steam install (D:\Steam\steamapps\common\Kenshi), untouched.
Instance n >= 2 = D:\KenshiInst\<n> (4080: C:\KenshiInst\<n>, instance 1 = its C:\Program Files (x86) Steam install), built from instance 1 without duplicating its ~28 GB:
  - a folder whose whole subtree holds only read-only content (no cfg/ini/txt/json/log/dll/exe/... file, nothing skipped)
    is a directory junction to instance 1's folder (most of data\ and the texture mods, incl. Vortex's file symlinks);
  - in the other folders big read-only files (>= 2 MB) are NTFS hard links, everything else (small files, anything written
    at runtime or replaced by install-dll.ps1, Vortex symlinked files) is a real copy,
so neither game writes into the other's files. NEVER delete a junctioned folder's contents through D:\KenshiInst (that
deletes instance 1's files): use `remove` (rmdir /s, which drops junctions without following them). Its saves live in its own save\ folder (settings.cfg
"User save location=0"), never in %LOCALAPPDATA%\kenshi\save that instance 1 uses, so autosaves can't collide.

  kenshi-instance.ps1 path   [-Instance n]          the game folder of instance n (1 = Steam install)
  kenshi-instance.ps1 sync   [-Instance 2] [-Saves a,b]   create/refresh the copy from instance 1 (mods, DLLs, cfgs, gfx-mods
                                                    state; files gone from instance 1 are removed) + copy those saves and every kah-* test save
  kenshi-instance.ps1 save   <name>[,name] [-Instance 2]  copy saves (+ every kah-*; names may use * ?) from %LOCALAPPDATA%\kenshi\save into the copy
  kenshi-instance.ps1 status [-Instance 2]          exists? linked/copied counts, running game pid, saves
  kenshi-instance.ps1 selftest [-Instance 2]        checks the copy: no small/mutable file is a hard link, every big
                                                    data file is, save location is local, harness runtime files absent
  kenshi-instance.ps1 remove -Instance n            delete the copy (refuses while its game runs)
sync refuses while that instance's game runs (a running game holds its DLLs). Instance 1's game may run during a sync
(files are only read there). Disk: ~1.8 GB of copies per instance (D: has the hard-linked rest for free).
#>
param(
  [Parameter(Position = 0)][ValidateSet('path', 'sync', 'save', 'status', 'selftest', 'remove')][string]$Command = 'status',
  [Parameter(Position = 1)][string]$Name = '',
  [int]$Instance = 2,
  [string[]]$Saves = @()
)
$ErrorActionPreference = 'Stop'
# instance 1 = the rig's Steam install: D:\Steam\... on the 5090, C:\Program Files (x86)\Steam\... on the 4080 (no D: there;
# lane 4080b, multi-instance-4080 2026-10-11); copies on the same volume (hard links): D:\KenshiInst | C:\KenshiInst
$Src = @('D:\Steam\steamapps\common\Kenshi', 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi') | Where-Object { Test-Path "$_\kenshi_x64.exe" } | Select-Object -First 1
if (-not $Src) { throw 'no Kenshi install (D:\Steam\... or C:\Program Files (x86)\Steam\...)' }
$Root = if ($Src -like 'D:\*') { 'D:\KenshiInst' } else { 'C:\KenshiInst' }
$UserSaves = "$env:LOCALAPPDATA\kenshi\save"
$LinkMin = 2MB
# never hard-linked (written at runtime, or replaced by install-dll.ps1 while the other game holds it open)
$MutableExt = @('.cfg', '.ini', '.txt', '.json', '.log', '.sc', '.zip', '.dll', '.exe', '.asi', '.tsv', '.flag', '.bolt', '.csv', '.def', '.bat', '.hkt', '.xml')
# not mirrored at all: runtime state of instance 1 (saves, logs, harness inbox/outbox, recordings, crash dumps)
$SkipDirs = @('save', 'logs', '_screens', 'mods\AutomationHarness\shots')
$SkipFiles = @('inbox.txt*', 'outbox.txt', 'harness.log', 'autoload.txt', 'input_isolation.flag', 'vmrec-*', 'crashDump*.zip',
               '*.log', 'instance.txt', 'settings.gfx.play', 'gfx.applied', 'kenshi.cfg.play')

Add-Type @'
using System; using System.IO; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class KInstLinks {
  [StructLayout(LayoutKind.Sequential)] struct BHFI { public uint a, c1, c2, la1, la2, lw1, lw2, vsn, sh, sl, n, ih, il; }
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetFileInformationByHandle(SafeFileHandle h, out BHFI i);
  public static int Count(string p) {
    using (var fs = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
      BHFI i; return GetFileInformationByHandle(fs.SafeFileHandle, out i) ? (int)i.n : -1; } }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CreateHardLinkW(string l, string t, IntPtr z);
  public static void Link(string l, string t) { if (!CreateHardLinkW(l, t, IntPtr.Zero)) throw new IOException("CreateHardLink " + l + ": error " + Marshal.GetLastWin32Error()); }
}
'@

function InstDir([int]$n) { if ($n -le 1) { $Src } else { Join-Path $Root "$n" } }
$Dst = InstDir $Instance

function Procs([string]$dir) {
  $r = ([IO.Path]::GetFullPath($dir)).TrimEnd('\') + '\'
  @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($r, [StringComparison]::OrdinalIgnoreCase) })
}
function Skipped([string]$rel) {
  foreach ($d in $SkipDirs) { if ($rel -eq $d -or $rel -like "$d\*") { return $true } }
  $leaf = Split-Path $rel -Leaf
  foreach ($f in $SkipFiles) { if ($leaf -like $f) { return $true } }
  $false
}
function IsReparse($i) { [bool]($i.Attributes -band [IO.FileAttributes]::ReparsePoint) }
function Mutable([IO.FileInfo]$f) { $MutableExt -contains $f.Extension.ToLower() }
function IsLink([IO.FileInfo]$f) { -not (IsReparse $f) -and $f.Length -ge $LinkMin -and -not (Mutable $f) }
# folders of instance 1 that must be real folders in the copy (a mutable or skipped file/folder somewhere below)
# speed-scout r9: .NET enumeration + inline Skipped/Mutable (same rules; was Get-ChildItem -Recurse + Split-Path per entry,
# 6.4 s over 27k entries on the 5090, now 0.3 s, identical 191 dirs); keys lower-case; an ancestor already in = all above it are
function ImpureDirs {
  $imp = @{ '' = 1 }; $n = $Src.Length + 1
  $mut = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach ($e in $MutableExt) { [void]$mut.Add($e) }
  $pats = @($SkipFiles | ForEach-Object { New-Object System.Management.Automation.WildcardPattern ($_, [System.Management.Automation.WildcardOptions]::IgnoreCase) })
  $dirs = @($SkipDirs | ForEach-Object { $_.ToLower() })
  foreach ($f in ([IO.DirectoryInfo]$Src).EnumerateFileSystemInfos('*', [IO.SearchOption]::AllDirectories)) {
    $rl = $f.FullName.Substring($n).ToLower(); $bad = $false
    foreach ($d in $dirs) { if ($rl -eq $d -or $rl.StartsWith("$d\")) { $bad = $true; break } }
    if (-not $bad -and -not ($f.Attributes -band [IO.FileAttributes]::Directory) -and $mut.Contains($f.Extension)) { $bad = $true }
    if (-not $bad) { foreach ($p in $pats) { if ($p.IsMatch($f.Name)) { $bad = $true; break } } }
    if ($bad) { $i = $rl.LastIndexOf('\'); while ($i -gt 0) { $rl = $rl.Substring(0, $i); if ($imp.ContainsKey($rl)) { break }; $imp[$rl] = 1; $i = $rl.LastIndexOf('\') } }
  }
  $imp
}
function Del-Dir([string]$path) {   # a junction: drop the link only; a real folder: rmdir /s (never follows junctions)
  $i = Get-Item -LiteralPath $path -Force
  if (IsReparse $i) { [IO.Directory]::Delete($path, $false) } else { cmd /c rmdir /s /q "`"$path`"" 2>&1 | Out-Null }
}
function JunctionTarget([string]$path) {
  $i = Get-Item -LiteralPath $path -Force
  if (IsReparse $i) { "$($i.Target)" } else { $null }
}
function Copy-Saves([string[]]$names) {
  # a name with * or ? = every matching save folder (kah-* = every test save); unique, in order
  $list = @($names | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object {
    if ($_ -match '[*?]') { @(Get-ChildItem $UserSaves -Directory -Filter $_ -ErrorAction SilentlyContinue | ForEach-Object Name) } else { $_ } } | Select-Object -Unique)
  foreach ($s in $list) {
    $from = Join-Path $UserSaves $s
    if (-not (Test-Path $from)) { throw "no save '$s' in $UserSaves" }
    $null = & robocopy $from (Join-Path $Dst "save\$s") /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "robocopy of save $s failed ($LASTEXITCODE)" }
    "save $s -> $Dst\save\$s"
  }
}
function Set-Setting([string]$file, [string]$key, [string]$val) {
  $lines = @(Get-Content $file); $hit = $false
  $out = foreach ($l in $lines) { if ($l -like "$key=*") { $hit = $true; "$key=$val" } else { $l } }
  if (-not $hit) { $out = @($out) + "$key=$val" }
  Set-Content -Path $file -Value $out -Encoding Ascii
}
$script:st = @{ junction = 0; link = 0; copy = 0; same = 0; purged = 0; busy = @(); dead = 0 }
function Sync-Dir([string]$rel, [hashtable]$imp) {
  $s = if ($rel) { Join-Path $Src $rel } else { $Src }; $d = if ($rel) { Join-Path $Dst $rel } else { $Dst }
  [void][IO.Directory]::CreateDirectory($d)
  $want = @{}
  foreach ($c in Get-ChildItem -LiteralPath $s -Force) {
    $r = if ($rel) { "$rel\$($c.Name)" } else { $c.Name }
    if (Skipped $r) { continue }
    $want[$c.Name.ToLower()] = 1
    $to = Join-Path $d $c.Name
    if ($c.PSIsContainer) {
      $has = Test-Path -LiteralPath $to
      if (-not $imp.ContainsKey($r.ToLower())) {
        if ($has -and (JunctionTarget $to) -eq $c.FullName) { $script:st.same++; continue }
        if ($has) { Del-Dir $to }
        cmd /c mklink /J "`"$to`"" "`"$($c.FullName)`"" 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $to)) { throw "mklink /J $to failed" }
        $script:st.junction++
      } else {
        if ($has -and (JunctionTarget $to)) { Del-Dir $to }
        Sync-Dir $r $imp
      }
      continue
    }
    $from = $c
    if (IsReparse $c) {   # Vortex file symlink: copy what it points to (no symlink privilege here)
      if (-not $c.Target -or -not (Test-Path -LiteralPath "$($c.Target)")) { $script:st.dead++; $want.Remove($c.Name.ToLower()); continue }
      $from = Get-Item -LiteralPath "$($c.Target)" -Force
    }
    $t = [IO.FileInfo]$to
    if ($t.Exists -and $t.Length -eq $from.Length -and $t.LastWriteTimeUtc -eq $from.LastWriteTimeUtc) { $script:st.same++; continue }
    try {
      if ($t.Exists) { [IO.File]::Delete($to) }   # a hard link: drops the name only
      if (IsLink $c) { [KInstLinks]::Link($to, $c.FullName); $script:st.link++ }
      else { [IO.File]::Copy($from.FullName, $to, $true); $script:st.copy++ }
    } catch { $script:st.busy += $r }   # held open by game 1 (or the copy's game): next sync
  }
  # purge what instance 1 no longer has (gfx-mods.sh / anim-mods.sh renames, removed mods); skipped runtime files stay
  foreach ($c in Get-ChildItem -LiteralPath $d -Force) {
    $r = if ($rel) { "$rel\$($c.Name)" } else { $c.Name }
    if ($want.ContainsKey($c.Name.ToLower()) -or (Skipped $r) -or $r -eq 'instance.txt') { continue }
    if ($c.PSIsContainer) { Del-Dir $c.FullName } else { try { [IO.File]::Delete($c.FullName) } catch { $script:st.busy += $r; continue } }
    $script:st.purged++
  }
}

switch ($Command) {
  'path' { $Dst; exit 0 }
  'save' {
    if ($Instance -le 1) { throw 'instance 1 uses the user save folder already' }
    Copy-Saves (@($Name) + $Saves + 'kah-*'); exit 0   # + every kah-* test save (see sync)
  }
  'remove' {
    if ($Instance -le 1) { throw 'refusing to remove instance 1 (the Steam install)' }
    if ((Procs $Dst).Count) { throw "instance $Instance game is running" }
    if (Test-Path $Dst) { Del-Dir $Dst }   # rmdir /s: drops junctions + hard link names, instance 1's files stay
    "removed $Dst"; exit 0
  }
  'status' {
    if (-not (Test-Path "$Dst\kenshi_x64.exe")) { "instance $Instance : not created ($Dst)"; exit 1 }
    $p = Procs $Dst
    $sv = if (Test-Path "$Dst\save") { (@(Get-ChildItem "$Dst\save" -Directory | ForEach-Object Name)) -join ',' } else { '' }
    $stamp = if (Test-Path "$Dst\instance.txt") { (Get-Content "$Dst\instance.txt" -Raw).Trim() } else { 'no instance.txt' }
    "instance $Instance : $Dst | $stamp | game: $(if ($p.Count) { 'pid ' + (($p | ForEach-Object ProcessId) -join ',') } else { 'not running' }) | saves: $sv"
    exit 0
  }
  'selftest' {
    $bad = @(); $n = @{ j = 0; l = 0; c = 0 }
    $stack = New-Object System.Collections.Stack; $stack.Push('')
    while ($stack.Count) {
      $rel = $stack.Pop(); $d = if ($rel) { Join-Path $Dst $rel } else { $Dst }
      foreach ($c in Get-ChildItem -LiteralPath $d -Force) {
        $r = if ($rel) { "$rel\$($c.Name)" } else { $c.Name }
        if ($r -eq 'save' -or $r -like 'save\*' -or (Skipped $r) -or $r -eq 'instance.txt') { continue }
        $srcp = Join-Path $Src $r
        if ($c.PSIsContainer) {
          if (IsReparse $c) { $n.j++; if ("$($c.Target)" -ne $srcp) { $bad += "junction $r -> $($c.Target)" } }
          else { $stack.Push($r) }
          continue
        }
        $sf = Get-Item -LiteralPath $srcp -Force -ErrorAction SilentlyContinue
        if (-not $sf) { $bad += "not in instance 1: $r"; continue }
        $links = [KInstLinks]::Count($c.FullName)
        if (IsLink $sf) { if ($links -ge 2) { $n.l++ } else { $bad += "not linked: $r" } }
        else { $n.c++; if ($links -ge 2) { $bad += "copy expected, is a hard link: $r" } }
      }
    }
    $set = Get-Content "$Dst\settings.cfg" | Where-Object { $_ -like 'User save location=*' }
    if ($set -ne 'User save location=0') { $bad += "settings.cfg: '$set' (want User save location=0)" }
    if ($bad.Count) { "SELFTEST FAIL ($($bad.Count)): " + (($bad | Select-Object -First 8) -join ' | '); exit 1 }
    "SELFTEST PASS: $($n.j) junctions, $($n.l) hard links, $($n.c) copies, save location local"; exit 0
  }
  'sync' {
    if ($Instance -le 1) { throw 'instance 1 is the Steam install itself' }
    if ((Procs $Dst).Count) { throw "instance $Instance game is running: stop it first (KAH_INSTANCE=$Instance kenshi-ctl.ps1 stop)" }
    $t0 = Get-Date
    $imp = ImpureDirs
    Sync-Dir '' $imp
    Set-Setting "$Dst\settings.cfg" 'User save location' '0'
    New-Item -ItemType Directory -Force "$Dst\save" | Out-Null
    # Shay's graphics as kenshi-gfx.ps1 saved them for instance 1 (settings.cfg itself may be in test "low" values now)
    if (-not (Test-Path "$Dst\settings.gfx.play") -and (Test-Path 'C:\KenshiTestRuns\settings.gfx.play')) {
      Copy-Item 'C:\KenshiTestRuns\settings.gfx.play' "$Dst\settings.gfx.play" }
    Set-Content "$Dst\instance.txt" "instance=$Instance synced=$(Get-Date -Format s) from=$Src" -Encoding Ascii
    $st = $script:st
    "sync instance $Instance -> $Dst : $($st.junction) junctions, $($st.link) hard links, $($st.copy) copies, $($st.same) unchanged, $($st.purged) removed, $($st.dead) dead links skipped, $($st.busy.Count) busy$(if ($st.busy.Count) { ' (' + (($st.busy | Select-Object -First 3) -join ',') + ')' }) ($([int]((Get-Date) - $t0).TotalSeconds) s)"
    # every kah-* test save too, not only the asked ones (Shay 2026-10-11: every lane has every test save, all lanes can use
    # all saves at once; run-batch load_target switches the launch save to a row's pf_load target, e.g. kah-fpstudio).
    # 5090b (rig-lane2.ps1 7b2373a) and 4080b both get it through this one place; robocopy /MIR = unchanged saves cost ~0 s.
    Copy-Saves (@($Saves) + 'kah-*')
    exit 0
  }
}
