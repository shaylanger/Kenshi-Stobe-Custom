# path-guard-lib.ps1 (PI-53, Shay 2026-10-16): guard for -Out/-Path style arguments that agents pass from Git Bash.
# Git Bash strips unquoted/double-quoted backslashes (-Out C:\KenshiTestRuns\agents\x.md arrives as C:KenshiTestRunsagentsx.md), which
# used to create a stray file in the current directory (C:\KenshiModding\KenshiTestRunsagents...brief.md) and the operator started without its brief.
#   . "$PSScriptRoot\path-guard-lib.ps1"; $Out = Resolve-GuardedPath $Out 'lane-brief -Out'
# Accepts: C:\x, C:/x, \\unc\share, /c/x and /mnt/c/x (converted to C:\x). Auto-fixes the known stripped form C:KenshiTestRunsagents<rest>
# -> C:\KenshiTestRuns\agents\<rest> (and C:KenshiTestRuns<dir><rest> for agents|lanes|handoff|inbox|out) and warns on stderr.
# Anything else (relative, drive-colon without separator, empty) is refused: throws (callers exit 2) with the fix text.
function Resolve-GuardedPath([string]$Value, [string]$What = 'path') {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$What is empty" }
    $v = $Value.Trim()
    if ($v -match '^[A-Za-z]:[\\/]') { return $v }
    if ($v -match '^\\\\[^\\]') { return $v }
    if ($v -match '^/mnt/([A-Za-z])/(.*)$') { return ($Matches[1].ToUpper() + ':\' + ($Matches[2] -replace '/', '\')) }
    if ($v -match '^/([A-Za-z])/(.*)$') { return ($Matches[1].ToUpper() + ':\' + ($Matches[2] -replace '/', '\')) }
    if ($v -match '^([A-Za-z]):KenshiTestRuns(agents|lanes|handoff|inbox|out)(.+)$') {
        $fixed = $Matches[1].ToUpper() + ':\KenshiTestRuns\' + $Matches[2] + '\' + $Matches[3]
        [Console]::Error.WriteLine("path-guard: $What '$Value' had its backslashes stripped (Git Bash); using '$fixed'. Use the PowerShell tool or forward slashes (C:/KenshiTestRuns/agents/x.md) next time.")
        return $fixed
    }
    throw "$What '$Value' is not an absolute path with a drive-letter colon and separator (Git Bash strips backslashes: C:\KenshiTestRuns\agents\x.md becomes C:KenshiTestRunsagentsx.md). Use the PowerShell tool, or forward slashes: C:/KenshiTestRuns/agents/x.md"
}
