$ErrorActionPreference = 'SilentlyContinue'
$mutex = New-Object System.Threading.Mutex($false, 'Local\StobeTrainingLogWatch')
if (-not $mutex.WaitOne(0, $false)) { exit 0 }

$root = 'C:\KenshiModding\training-data\live\game-logs'
$session = Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir = Join-Path $root "watch-$session"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$files = @(
    @{ Name='stobe'; Path='D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log' },
    @{ Name='kenshifp'; Path='D:\Steam\steamapps\common\Kenshi\KenshiFP.log' },
    @{ Name='re_kenshi'; Path='D:\Steam\steamapps\common\Kenshi\RE_Kenshi_log.txt' },
    @{ Name='stobe_sdk'; Path='D:\Steam\steamapps\common\Kenshi\Stobe_SDK.log' }
)
$state = @{}

function Add-WatchMarker([string]$dest, [string]$message) {
    $line = "`r`n===== $(Get-Date -Format o) $message =====`r`n"
    [IO.File]::AppendAllText($dest, $line, [Text.Encoding]::UTF8)
}

try {
    while ($true) {
        foreach ($item in $files) {
            if (-not (Test-Path -LiteralPath $item.Path)) { continue }
            $info = Get-Item -LiteralPath $item.Path
            $dest = Join-Path $outDir ($item.Name + '.log')
            if (-not $state.ContainsKey($item.Name)) {
                $state[$item.Name] = @{ Pos = [int64]0; Created = $info.CreationTimeUtc }
                Add-WatchMarker $dest "watch_started source=$($item.Path)"
            }
            $s = $state[$item.Name]
            if ($info.Length -lt $s.Pos -or $info.CreationTimeUtc -ne $s.Created) {
                Add-WatchMarker $dest 'source_reset_or_replaced'
                $s.Pos = [int64]0
                $s.Created = $info.CreationTimeUtc
            }
            if ($info.Length -le $s.Pos) { continue }

            $input = [IO.File]::Open($item.Path, 'Open', 'Read', 'ReadWrite')
            $null = $input.Seek($s.Pos, 'Begin')
            $output = [IO.File]::Open($dest, 'Append', 'Write', 'ReadWrite')
            $buffer = New-Object byte[] 1048576
            while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $output.Write($buffer, 0, $read)
            }
            $output.Dispose()
            $input.Dispose()
            $s.Pos = [int64]$info.Length
        }
        Start-Sleep -Seconds 1
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
