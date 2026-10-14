param(
    [string]$BodyPath,
    [string]$SshConfig = 'C:\Users\Shay\.ssh\config',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$script:ReadinessStageMarker = 'KAH4080_RECEIVER_STAGE post_route_guard v1'
$script:ReadonlyRoute = "readonly RIG=4080 KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3 KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'`n"
$script:Chat007OutputSections = @(
    'HOST / INSTANCE', 'EXACT I3 PROCESS AND LOADED MODULE HASHES', 'ON-DISK MOD HASHES',
    'INSTANCE CONFIG', 'PRIVATE BACKEND HEALTH', 'PRIVATE BACKEND PROCESS',
    'READY SESSION GENERATION (SANITIZED)', 'KAH WORLD STATUS',
    'KAH GAME TIME / PAUSE STATE', 'INPUT ISOLATION / FOCUS', 'FP STATE',
    'FRESH ACTOR LIST (300)', 'CHAT007 PREFLIGHT OUTPUT COMPLETE v1'
)

function Get-Chat007StderrDiagnostic([string]$stderr) {
    $text = [string]$stderr
    $text = [regex]::Replace($text, '(?m)^KAH4080_(?:RECEIVER|BASH)_PID=\d+\r?\n?', '')
    $excerptLines = @()
    $excerptSource = [regex]::Replace($text, '(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----', '[REDACTED PRIVATE KEY]')
    $normalized = $excerptSource.Replace("`r`n", "`n").Replace("`r", "`n")
    foreach ($line in ($normalized -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 4)) {
        $safeLine = [string]$line
        # Remove complete credential-bearing headers before the general field
        # rules so cookie values and auth schemes cannot leak through.
        $safeLine = [regex]::Replace($safeLine, '(?i)\b(authorization|proxy-authorization|cookie|set-cookie)\s*:\s*.*$', '$1: [REDACTED]')
        $safeLine = [regex]::Replace($safeLine, '(?i)\bBearer\s+[^\s,;]+', 'Bearer [REDACTED]')
        $safeLine = [regex]::Replace($safeLine, '(?i)\bBasic\s+[A-Za-z0-9+/]+=*', 'Basic [REDACTED]')
        $safeLine = [regex]::Replace($safeLine, '(?i)\b(session(?:[ _-]?id)?|sessionid|sid|phpsessid|php[ _-]?session[ _-]?id)\b(\s*[=:]\s*)(?:"[^"]*"|''[^'']*''|[^\s,;&)}]+)', '$1$2[REDACTED]')
        $safeLine = [regex]::Replace($safeLine, '(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|client[_-]?secret|token|credential(?:s)?|cookie|set-cookie|private[_-]?key|signing[_-]?key|csrf(?:[_-]?token)?|xsrf(?:[_-]?token)?|signature|username)\b(\s*[=:]\s*)(?:"[^"]*"|''[^'']*''|[^\s,;&)}]+)', '$1$2[REDACTED]')
        $safeLine = [regex]::Replace($safeLine, '(?i)\b([a-z][a-z0-9+.-]*://)[^/@\s:]+(?::[^/@\s]*)?@', '$1[REDACTED]@')
        $safeLine = [regex]::Replace($safeLine, '\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b', '[REDACTED JWT]')
        $safeLine = [regex]::Replace($safeLine, '\b[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\b', '[REDACTED SESSION ID]')
        $safeLine = [regex]::Replace($safeLine, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '?')
        if ($safeLine.Length -gt 320) { $safeLine = $safeLine.Substring(0, 317) + '...' }
        $excerptLines += $safeLine
    }
    $excerpt = ($excerptLines -join ' | ')
    if ($excerpt.Length -gt 1200) { $excerpt = $excerpt.Substring(0, 1197) + '...' }
    $lower = $text.ToLowerInvariant()
    $class = 'other'
    if (-not $text.Trim()) { $class = 'empty' }
    elseif ($lower -match 'permission denied|operation not permitted|not permitted') { $class = 'permission_denied' }
    elseif ($lower -match 'password is required|authentication failure|no tty present|a terminal is required|askpass') { $class = 'authentication_required' }
    elseif ($lower -match 'no such file or directory|command not found|could not open input file') { $class = 'missing_file_or_command' }
    elseif ($lower -match 'connection refused') { $class = 'connection_refused' }
    elseif ($lower -match 'timed out|timeout') { $class = 'timeout' }
    elseif ($lower -match 'network is unreachable|host is down|could not resolve|name or service not known') { $class = 'network_error' }
    elseif ($lower -match 'php (warning|fatal error|parse error)|fatal error|parse error') { $class = 'php_error' }
    elseif ($lower -match '(^|\n)(bash|sh):') { $class = 'shell_error' }
    $lineCount = @($text -split '\r?\n' | Where-Object { $_.Trim() }).Count
    [pscustomobject]@{ Captured = [bool]$text.Trim(); Class = $class; LineCount = $lineCount; Excerpt = $excerpt }
}

function Get-ReadinessStderrSummary([string]$stderr) {
    $text = [string]$stderr
    # SSH combines client and remote stderr. This fixed remote marker confirms
    # the receiver passed the host and exact i3 preamble gates; absence is only
    # an unconfirmed stage, not proof that SSH itself failed.
    $marker = $script:ReadinessStageMarker
    $markerPattern = '(?m)^' + [regex]::Escape($marker) + '\r?$'
    $receiverStage = if ([regex]::IsMatch($text, $markerPattern)) { 'post_route_guard' } else { 'unconfirmed' }
    $diagnosticText = [regex]::Replace($text, $markerPattern, '')
    $diagnosticText = [regex]::Replace($diagnosticText, '(?m)^KAH4080_(?:RECEIVER|BASH)_PID=\d+\r?\n?', '')
    $trimmed = $diagnosticText.TrimStart([char]0xFEFF, [char]0x20, [char]0x09, [char]0x0D, [char]0x0A)
    $category = 'other_unrecognized'
    if (-not $diagnosticText.Trim()) { $category = 'empty' }
    elseif ($trimmed.StartsWith('#< CLIXML', [StringComparison]::Ordinal)) { $category = 'known_clixml_prefix' }
    elseif ($diagnosticText -match '(?is)<Obj\s+S="progress"|Preparing modules for first use') { $category = 'powershell_progress' }
    elseif ($diagnosticText -match '(?i)access is denied|permission denied') { $category = 'permission_denied' }
    $lineCount = @($diagnosticText -split '\r?\n' | Where-Object { $_.Trim() }).Count
    [pscustomobject]@{ Captured = [bool]$diagnosticText.Trim(); Category = $category; LineCount = $lineCount; ReceiverStage = $receiverStage }
}

function Get-Chat007JsonStringEnd([string]$json, [int]$start) {
    if ($start -lt 0 -or $start -ge $json.Length -or $json[$start] -cne '"') {
        throw 'Expected a JSON string token'
    }
    for ($cursor = $start + 1; $cursor -lt $json.Length; $cursor++) {
        if ($json[$cursor] -ceq '\') { $cursor++; continue }
        if ($json[$cursor] -ceq '"') { return ($cursor + 1) }
    }
    throw 'Unterminated JSON string token'
}

function Get-Chat007TopLevelJsonProperties([string]$json) {
    # ConvertFrom-Json validates JSON syntax, while the small scanner below
    # preserves top-level duplicate names (which ordinary object conversion
    # may collapse to the first or last value).
    try { $parsed = ConvertFrom-Json -InputObject $json -ErrorAction Stop }
    catch { throw 'Readiness record is not valid JSON' }
    if ($null -eq $parsed -or $parsed -isnot [pscustomobject]) {
        throw 'Readiness record must be a JSON object'
    }

    $properties = New-Object 'System.Collections.Generic.List[object]'
    $cursor = 0
    while ($cursor -lt $json.Length -and [char]::IsWhiteSpace($json[$cursor])) { $cursor++ }
    if ($cursor -ge $json.Length -or $json[$cursor] -cne '{') { throw 'Readiness record must start with a JSON object' }
    $cursor++

    while ($true) {
        while ($cursor -lt $json.Length -and [char]::IsWhiteSpace($json[$cursor])) { $cursor++ }
        if ($cursor -lt $json.Length -and $json[$cursor] -ceq '}') { $cursor++; break }
        if ($cursor -ge $json.Length -or $json[$cursor] -cne '"') { throw 'Expected a top-level JSON property name' }

        $keyStart = $cursor
        $cursor = Get-Chat007JsonStringEnd $json $cursor
        $rawKey = $json.Substring($keyStart, $cursor - $keyStart)
        try { $propertyName = ConvertFrom-Json -InputObject $rawKey -ErrorAction Stop }
        catch { throw 'Readiness record has an invalid JSON property name' }
        if ($propertyName -isnot [string]) { throw 'Readiness record property name must be a JSON string' }

        while ($cursor -lt $json.Length -and [char]::IsWhiteSpace($json[$cursor])) { $cursor++ }
        if ($cursor -ge $json.Length -or $json[$cursor] -cne ':') { throw 'Expected a colon after a JSON property name' }
        $cursor++
        while ($cursor -lt $json.Length -and [char]::IsWhiteSpace($json[$cursor])) { $cursor++ }
        if ($cursor -ge $json.Length) { throw 'Missing JSON property value' }

        $valueStart = $cursor
        if ($json[$cursor] -ceq '"') {
            $cursor = Get-Chat007JsonStringEnd $json $cursor
        }
        elseif ($json[$cursor] -ceq '{' -or $json[$cursor] -ceq '[') {
            $closers = New-Object 'System.Collections.Generic.List[char]'
            if ($json[$cursor] -ceq '{') { $closers.Add([char]'}') } else { $closers.Add([char]']') }
            $cursor++
            while ($closers.Count -gt 0 -and $cursor -lt $json.Length) {
                if ($json[$cursor] -ceq '"') { $cursor = Get-Chat007JsonStringEnd $json $cursor; continue }
                if ($json[$cursor] -ceq '{') { $closers.Add([char]'}'); $cursor++; continue }
                if ($json[$cursor] -ceq '[') { $closers.Add([char]']'); $cursor++; continue }
                if ($json[$cursor] -ceq '}' -or $json[$cursor] -ceq ']') {
                    if ($closers[$closers.Count - 1] -cne [char]$json[$cursor]) { throw 'Mismatched JSON container delimiter' }
                    $closers.RemoveAt($closers.Count - 1)
                    $cursor++
                    continue
                }
                $cursor++
            }
            if ($closers.Count -ne 0) { throw 'Unterminated JSON container value' }
        }
        else {
            while ($cursor -lt $json.Length -and $json[$cursor] -cne ',' -and $json[$cursor] -cne '}') { $cursor++ }
        }
        $rawValue = $json.Substring($valueStart, $cursor - $valueStart).Trim()
        if (-not $rawValue) { throw 'Missing JSON property value' }
        $properties.Add([pscustomobject]@{ Name = $propertyName; RawValue = $rawValue })

        while ($cursor -lt $json.Length -and [char]::IsWhiteSpace($json[$cursor])) { $cursor++ }
        if ($cursor -lt $json.Length -and $json[$cursor] -ceq ',') {
            $cursor++
            while ($cursor -lt $json.Length -and [char]::IsWhiteSpace($json[$cursor])) { $cursor++ }
            if ($cursor -ge $json.Length -or $json[$cursor] -cne '"') { throw 'Expected a property after the JSON comma' }
            continue
        }
        if ($cursor -lt $json.Length -and $json[$cursor] -ceq '}') { $cursor++; break }
        throw 'Expected a comma or closing brace after a JSON property'
    }

    while ($cursor -lt $json.Length -and [char]::IsWhiteSpace($json[$cursor])) { $cursor++ }
    if ($cursor -ne $json.Length) { throw 'Unexpected data after readiness JSON object' }
    return ,$properties.ToArray()
}

function Get-Chat007ReadinessFlags([string]$sectionBody) {
    $jsonLines = @($sectionBody -split '\r?\n' | Where-Object { $_.Trim().StartsWith('{', [StringComparison]::Ordinal) })
    if ($jsonLines.Count -ne 1) { throw 'Readiness section must contain exactly one JSON object record' }
    $properties = Get-Chat007TopLevelJsonProperties $jsonLines[0].Trim()
    $result = @{}
    foreach ($name in @('session_present', 'generation_present', 'manager_ready_matches')) {
        $matches = @($properties | Where-Object { $_.Name -ceq $name })
        $result[$name] = ($matches.Count -eq 1 -and $matches[0].RawValue -ceq 'true')
    }
    return $result
}

function Get-Chat007StreamResult([string]$stdout, [string]$stderr, [int]$childExitCode) {
    $diag = Get-Chat007StderrDiagnostic $stderr
    if ($childExitCode -ne 0) {
        return [pscustomobject]@{
            ExitCode = $childExitCode
            Failure = "RESULT KAH-CHAT-007 FAIL setup: remote read body exited with code $childExitCode; stderr_captured=$($diag.Captured.ToString().ToLowerInvariant()) stderr_class=$($diag.Class) stderr_lines=$($diag.LineCount); stderr_excerpt=[$($diag.Excerpt)]"
        }
    }
    $missing = @()
    $sectionBodies = @{}
    foreach ($section in $script:Chat007OutputSections) {
        $heading = "=== $section ==="
        $match = [regex]::Match($stdout, '(?m)^' + [regex]::Escape($heading) + '\s*$')
        if (-not $match.Success) { $missing += $section; continue }
        if ($section -ne 'CHAT007 PREFLIGHT OUTPUT COMPLETE v1') {
            $tail = $stdout.Substring($match.Index + $match.Length)
            $next = [regex]::Match($tail, '(?m)^=== .* ===\s*$')
            $sectionBody = if ($next.Success) { $tail.Substring(0, $next.Index) } else { $tail }
            $sectionBodies[$section] = $sectionBody
            if (-not $sectionBody.Trim()) { $missing += "$section result" }
        }
    }
    if ($missing.Count -eq 0) {
        $requiredEvidence = @(
            @{ Section = 'HOST / INSTANCE'; Name = 'host'; Pattern = '(?im)^DESKTOP-NQQPA73\s*$' },
            @{ Section = 'HOST / INSTANCE'; Name = 'instance marker'; Pattern = '(?im)^instance=3\s+synced=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' },
            @{ Section = 'EXACT I3 PROCESS AND LOADED MODULE HASHES'; Name = 'PID'; Pattern = '(?m)^PID=\d+$' },
            @{ Section = 'EXACT I3 PROCESS AND LOADED MODULE HASHES'; Name = 'process path'; Pattern = '(?m)^PROCESS_PATH_PART=\d+/\d+:C:\\KenshiInst\\3\\RE_Kenshi\\kenshi_x64\.exe$' },
            @{ Section = 'EXACT I3 PROCESS AND LOADED MODULE HASHES'; Name = 'Stobe loaded hash'; Pattern = '(?s)LOADED_MODULE=Stobe\.dll(?:(?!LOADED_MODULE=).)*ON_DISK_SHA256=[0-9a-fA-F]{64}' },
            @{ Section = 'EXACT I3 PROCESS AND LOADED MODULE HASHES'; Name = 'Harness loaded hash'; Pattern = '(?s)LOADED_MODULE=AutomationHarness\.dll.*?ON_DISK_SHA256=[0-9a-fA-F]{64}' },
            @{ Section = 'ON-DISK MOD HASHES'; Name = 'Stobe on-disk hash'; Pattern = '(?im)^[0-9a-f]{64}\s+\*?/c/KenshiInst/3/mods/Stobe/Stobe\.dll$' },
            @{ Section = 'ON-DISK MOD HASHES'; Name = 'Harness on-disk hash'; Pattern = '(?im)^[0-9a-f]{64}\s+\*?/c/KenshiInst/3/mods/AutomationHarness/AutomationHarness\.dll$' },
            @{ Section = 'INSTANCE CONFIG'; Name = 'private backend host'; Pattern = '(?im)^ServerHost=127\.0\.0\.1$' },
            @{ Section = 'INSTANCE CONFIG'; Name = 'private backend port'; Pattern = '(?im)^ServerPort=18084$' },
            @{ Section = 'PRIVATE BACKEND HEALTH'; Name = 'health ok'; Pattern = '"ok"\s*:\s*true' },
            @{ Section = 'PRIVATE BACKEND HEALTH'; Name = 'database ready'; Pattern = '"database"\s*:\s*true' },
            @{ Section = 'PRIVATE BACKEND HEALTH'; Name = 'schema ready'; Pattern = '"database_schema_ready"\s*:\s*true' },
            @{ Section = 'PRIVATE BACKEND PROCESS'; Name = 'private PHP listener'; Pattern = 'php\s+-S\s+127\.0\.0\.1:18084\s+-t\s+/tmp/stobe-standalone4080/site' },
            @{ Section = 'READY SESSION GENERATION (SANITIZED)'; Name = 'sanitized session presence'; Pattern = '"session_present"\s*:\s*(true|false)' },
            @{ Section = 'READY SESSION GENERATION (SANITIZED)'; Name = 'session status'; Pattern = '"status"\s*:\s*(null|"[^"]*")' },
            @{ Section = 'READY SESSION GENERATION (SANITIZED)'; Name = 'session game time'; Pattern = '"gamets"\s*:\s*(null|\d+)' },
            @{ Section = 'READY SESSION GENERATION (SANITIZED)'; Name = 'load hash'; Pattern = '"load_id_sha256"\s*:\s*"[0-9a-fA-F]{64}"' },
            @{ Section = 'READY SESSION GENERATION (SANITIZED)'; Name = 'generation presence'; Pattern = '"generation_present"\s*:\s*(true|false)' },
            @{ Section = 'READY SESSION GENERATION (SANITIZED)'; Name = 'manager readiness'; Pattern = '"manager_ready_matches"\s*:\s*(true|false)' },
            @{ Section = 'KAH WORLD STATUS'; Name = 'world/save status'; Pattern = 'phase=world\s+save=\S+.*?paused=\d+\s+speed=\S+\s+squad=\d+\s+player=\S+' },
            @{ Section = 'KAH GAME TIME / PAUSE STATE'; Name = 'game time and pause'; Pattern = 'game_hours=\S+\s+day=\d+\s+time=\d{2}:\d{2}\s+speed=\S+\s+paused=\d+' },
            @{ Section = 'INPUT ISOLATION / FOCUS'; Name = 'isolation and focus'; Pattern = 'isolation=(on|off).*focused=\d+' },
            @{ Section = 'FP STATE'; Name = 'FP state'; Pattern = 'fp_mode=\d+.*ui_open=\d+.*control=\d+.*focus=\d+' },
            @{ Section = 'FRESH ACTOR LIST (300)'; Name = 'actor roster result'; Pattern = '(?m)^\d+\s+within\s+300:.*#[0-9]+/[0-9]+' }
        )
        foreach ($rule in $requiredEvidence) {
            if ($sectionBodies[$rule.Section] -notmatch $rule.Pattern) { $missing += "evidence:$($rule.Name)" }
        }
        try {
            $readinessFlags = Get-Chat007ReadinessFlags $sectionBodies['READY SESSION GENERATION (SANITIZED)']
            foreach ($name in @('session_present', 'generation_present', 'manager_ready_matches')) {
                if (-not $readinessFlags[$name]) { $missing += "evidence:$name must be uniquely boolean true" }
            }
        }
        catch { $missing += 'evidence:valid readiness JSON record' }
        if ($stdout -notmatch 'RESULT 4080-I3-ROUTE PASS route=C:\\KenshiInst\\3 inbox=clear metadata-only') {
            $missing += 'evidence:route pass'
        }
        if ($stdout -notmatch 'speaker=\S+') { $missing += 'evidence:speaker' }
    }
    if ($missing.Count) {
        $items = ($missing | ForEach-Object { $_ -replace '[\r\n]+', ' ' }) -join ','
        return [pscustomobject]@{
            ExitCode = 2
            Failure = "RESULT KAH-CHAT-007 FAIL setup: captured read output is incomplete; missing=$items; stderr_captured=$($diag.Captured.ToString().ToLowerInvariant()) stderr_class=$($diag.Class) stderr_lines=$($diag.LineCount); stderr_excerpt=[$($diag.Excerpt)]"
        }
    }
    [pscustomobject]@{ ExitCode = 0; Failure = $null }
}

# Keep the large Bash body out of both Windows CreateProcess command lines. The
# only remote command argument is a small, fixed PowerShell receiver encoded
# with the verified PS5 UTF-16LE -EncodedCommand convention. The UTF-8 Bash
# bytes travel as Base64 on SSH stdin and are then written byte-for-byte to
# Git Bash's stdin.
$script:RemoteReceiver = @'
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
if ([Environment]::MachineName -cne 'DESKTOP-NQQPA73') { throw 'Refusing remote Bash body on an unexpected host' }
[Console]::Error.WriteLine('KAH4080_RECEIVER_PID=' + $PID)
$payload = [Console]::In.ReadToEnd()
$modeSeparator = $payload.IndexOf("`n", [StringComparison]::Ordinal)
if ($modeSeparator -lt 0) { throw 'Missing remote payload mode' }
$payloadMode = $payload.Substring(0, $modeSeparator)
if ($payloadMode -cne 'STANDARD' -and $payloadMode -cne 'READINESS') { throw 'Unrecognized remote payload mode' }
$encodedBody = $payload.Substring($modeSeparator + 1)
$bodyBytes = [Convert]::FromBase64String($encodedBody)
$body = [Text.Encoding]::UTF8.GetString($bodyBytes).TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
$routePreamble = "export RIG=4080 KAH_INSTANCE=3`nexport KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3`nexport KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'`n"
$rigEnvLine = '. /c/KenshiModding/tools/automation/rig-env.sh' + "`n"
if (-not $body.StartsWith(($routePreamble + $rigEnvLine), [StringComparison]::Ordinal)) { throw 'Isolated-i3 preamble drift' }
$remainingBody = $body.Substring(($routePreamble + $rigEnvLine).Length)
$readonlyRoute = "readonly RIG=4080 KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3 KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'`n"
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($routePreamble + $rigEnvLine + $readonlyRoute + $remainingBody)
if ($payloadMode -ceq 'READINESS') { [Console]::Error.WriteLine('KAH4080_RECEIVER_STAGE post_route_guard v1') }
$tempBody = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-' + [Guid]::NewGuid().ToString('N') + '.sh')
$bash = $null
try {
    # Stage complete body before execution to avoid a closed-stdin write race.
    [IO.File]::WriteAllBytes($tempBody, $bodyBytes)
$bash = New-Object System.Diagnostics.Process
$bash.StartInfo.FileName = 'C:\Program Files\Git\bin\bash.exe'
$bash.StartInfo.Arguments = '--noprofile --norc "' + $tempBody + '"'
$bash.StartInfo.UseShellExecute = $false
$null = $bash.Start()
[Console]::Error.WriteLine('KAH4080_BASH_PID=' + $bash.Id)
$timedOut = -not $bash.WaitForExit(110000)
if ($timedOut) {
    & taskkill.exe /PID $bash.Id /T /F 2>&1 | Out-Null
    try { $bash.Kill() } catch {}
    [Console]::Error.WriteLine('REMOTE_BASH_TIMEOUT limit_ms=110000; owned Bash tree terminated')
    exit 124
}
exit $bash.ExitCode
}
finally {
    if ($bash) { $bash.Dispose() }
    Remove-Item -LiteralPath $tempBody -Force -ErrorAction SilentlyContinue
}
'@

function Get-ReceiverEncodedCommand {
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script:RemoteReceiver))
}

function New-RemotePayload([byte[]]$bodyBytes, [bool]$readinessMode) {
    $mode = if ($readinessMode) { 'READINESS' } else { 'STANDARD' }
    $mode + "`n" + [Convert]::ToBase64String($bodyBytes)
}

function Get-SshArguments([string]$config) {
    $receiver = Get-ReceiverEncodedCommand
    '-F "{0}" -o BatchMode=yes -o ConnectTimeout=8 4080 powershell.exe -NoProfile -NonInteractive -EncodedCommand {1}' -f $config, $receiver
}

function New-SshStartInfo([string]$config, [scriptblock]$configProbe = $null) {
    if ([string]::IsNullOrWhiteSpace($config) -or -not [IO.Path]::IsPathRooted($config)) {
        throw 'Refusing SSH invocation without an absolute trusted config path'
    }
    if ($null -eq $configProbe) {
        $configProbe = { param($path) Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop }
    }

    # Test-Path can throw AccessDenied when the config is protected. Treat that
    # as unknown and let OpenSSH itself report the failure. The command remains
    # pinned to `ssh.exe -F <explicit-config> ... 4080`; there is no fallback to
    # ambient config, another alias, or another transport.
    $configExists = $null
    try { $configExists = [bool](& $configProbe $config) } catch { $configExists = $null }
    if ($configExists -eq $false) { throw 'Trusted SSH config path does not exist' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'ssh.exe'
    $psi.Arguments = Get-SshArguments $config
    $psi.UseShellExecute = $false
    $psi
}

function Assert-IsolatedI3Body([string]$body) {
    $body = $body.TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
    $routePreamble = @'
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
'@ + "`n"
    if (-not $body.StartsWith($routePreamble, [StringComparison]::Ordinal)) {
        throw 'Refusing remote body without the exact explicit isolated-i3 route preamble'
    }
    $tail = $body.Substring($routePreamble.Length)
    $rigEnvLine = '. /c/KenshiModding/tools/automation/rig-env.sh' + "`n"
    if (-not $tail.StartsWith($rigEnvLine, [StringComparison]::Ordinal)) {
        throw 'Refusing remote body without the trusted rig-env setup immediately after the i3 preamble'
    }
    $tail = $tail.Substring($rigEnvLine.Length)
    if ($tail -match '(?i)\b(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\s*=' -or
        $tail -match '(?i)\bunset\s+(?:-v\s+)?(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\b' -or
        $tail -match '(?im)(?:^|[;&|\s])(?:command\s+)?(?:env|eval|exec|source)\b' -or
        $tail -match '(?im)(?:^|[;&|\s])\.\s+') {
        throw 'Refusing remote body that could override or unset isolated-i3 routing'
    }
}

function Invoke-RemoteBashBody([string]$path, [string]$config) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Bash body file not found: $path" }
    $bodyBytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($path))
    $body = [Text.Encoding]::UTF8.GetString($bodyBytes).TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
    $chat007Stream = [IO.Path]::GetFileName($path) -ceq 'chat007-session-reader-stream.review.sh'
    $nativeReadinessStream = [IO.Path]::GetFileName($path) -ceq 'native-minimal-readiness-4080i3.sh'
    Assert-IsolatedI3Body $body
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
    $payload = New-RemotePayload $bodyBytes $nativeReadinessStream

    $psi = New-SshStartInfo $config
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $ssh = New-Object System.Diagnostics.Process
    $ssh.StartInfo = $psi
    # Each stream is capped at 4 MiB; overflow fails closed while retaining the captured prefix.
    $captureLimitBytes = 4MB
    $stdoutFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-stdout-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $stderrFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-stderr-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $stdoutEof = $stdoutFile + '.eof'
    $stderrEof = $stderrFile + '.eof'
    $stdoutOverflow = $stdoutFile + '.overflow'
    $stderrOverflow = $stderrFile + '.overflow'
    $stdoutEvent = 'kah4080-out-' + [Guid]::NewGuid().ToString('N')
    $stderrEvent = 'kah4080-err-' + [Guid]::NewGuid().ToString('N')
    $null = Register-ProcessCaptureStream $ssh 'OutputDataReceived' $stdoutEvent $stdoutFile $stdoutEof $stdoutOverflow $captureLimitBytes
    $null = Register-ProcessCaptureStream $ssh 'ErrorDataReceived' $stderrEvent $stderrFile $stderrEof $stderrOverflow $captureLimitBytes
    $null = $ssh.Start()
    $ssh.BeginOutputReadLine()
    $ssh.BeginErrorReadLine()
    $ssh.StandardInput.Write($payload)
    $ssh.StandardInput.Close()
    $timedOut = -not $ssh.WaitForExit(120000)
    if ($timedOut) {
        & taskkill.exe /PID $ssh.Id /T /F 2>&1 | Out-Null
        try { $ssh.Kill() } catch {}
    }
    $null = $ssh.WaitForExit(5000)
    $drainDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while ((-not (Test-Path -LiteralPath $stdoutEof)) -or (-not (Test-Path -LiteralPath $stderrEof))) {
        if ([DateTime]::UtcNow -ge $drainDeadline) { break }
        Start-Sleep -Milliseconds 50
    }
    $streamsDrained = (Test-Path -LiteralPath $stdoutEof) -and (Test-Path -LiteralPath $stderrEof)
    $captureLimitExceeded = (Test-Path -LiteralPath $stdoutOverflow) -or (Test-Path -LiteralPath $stderrOverflow)
    Unregister-Event -SourceIdentifier $stdoutEvent -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $stderrEvent -ErrorAction SilentlyContinue
    $stdoutText = if (Test-Path -LiteralPath $stdoutFile) { ([IO.File]::ReadAllText($stdoutFile)).Replace("`r`n", "`n").Replace("`r", "`n") } else { '' }
    $stderrText = if (Test-Path -LiteralPath $stderrFile) { ([IO.File]::ReadAllText($stderrFile)).Replace("`r`n", "`n").Replace("`r", "`n") } else { '' }
    $receiverPid = [regex]::Match($stderrText, '(?m)^KAH4080_RECEIVER_PID=(\d+)').Groups[1].Value
    $bashPid = [regex]::Match($stderrText, '(?m)^KAH4080_BASH_PID=(\d+)').Groups[1].Value
    if ($receiverPid -or $bashPid) { [Console]::Error.WriteLine('REMOTE_PROCESS_META receiver_pid=' + $receiverPid + ' bash_pid=' + $bashPid) }
    $captureFailure = $captureLimitExceeded -or -not $streamsDrained
    $stderrUserText = [regex]::Replace($stderrText, '(?m)^KAH4080_(?:RECEIVER|BASH)_PID=\d+\r?\n?', '')
    Remove-Item -LiteralPath $stdoutFile,$stderrFile,$stdoutEof,$stderrEof,$stdoutOverflow,$stderrOverflow -Force -ErrorAction SilentlyContinue
    if ($chat007Stream) {
        [Console]::Out.Write($stdoutText)
        $streamResult = Get-Chat007StreamResult $stdoutText $stderrText $(if ($timedOut) { 124 } else { $ssh.ExitCode })
        if ($streamResult.Failure) { [Console]::Error.WriteLine($streamResult.Failure) }
        elseif ($stderrText.Trim()) {
            $diag = Get-Chat007StderrDiagnostic $stderrText
            [Console]::Error.WriteLine("CHAT007 stderr_captured=true stderr_class=$($diag.Class) stderr_lines=$($diag.LineCount)")
        }
        if ($timedOut) { [Console]::Error.WriteLine('SSH_TIMEOUT limit_ms=120000; owned process tree terminated'); exit 124 }
        if ($captureLimitExceeded) { [Console]::Error.WriteLine('SSH_CAPTURE_FAIL_CLOSED reason=per-stream-cap-exceeded limit_bytes=4194304; captured prefix preserved'); exit 125 }
        if (-not $streamsDrained) { [Console]::Error.WriteLine('SSH_CAPTURE_FAIL_CLOSED reason=stream-drain-timeout; captured prefix preserved'); exit 125 }
        exit $streamResult.ExitCode
    }
    if ($nativeReadinessStream) {
        [Console]::Out.Write($stdoutText)
        if ($stderrText.Trim()) {
            $diag = Get-ReadinessStderrSummary $stderrText
            [Console]::Error.WriteLine("READINESS_STDERR captured=$($diag.Captured.ToString().ToLowerInvariant()) category=$($diag.Category) receiver_stage=$($diag.ReceiverStage) lines=$($diag.LineCount)")
        }
        if ($timedOut) { [Console]::Error.WriteLine('SSH_TIMEOUT limit_ms=120000; owned process tree terminated'); exit 124 }
        if ($captureLimitExceeded) { [Console]::Error.WriteLine('SSH_CAPTURE_FAIL_CLOSED reason=per-stream-cap-exceeded limit_bytes=4194304; captured prefix preserved'); exit 125 }
        if (-not $streamsDrained) { [Console]::Error.WriteLine('SSH_CAPTURE_FAIL_CLOSED reason=stream-drain-timeout; captured prefix preserved'); exit 125 }
        exit $ssh.ExitCode
    }
    [Console]::Out.Write($stdoutText)
    [Console]::Error.Write($stderrUserText)
    if ($timedOut) { [Console]::Error.WriteLine('SSH_TIMEOUT limit_ms=120000; owned process tree terminated'); exit 124 }
    if ($captureLimitExceeded) { [Console]::Error.WriteLine('SSH_CAPTURE_FAIL_CLOSED reason=per-stream-cap-exceeded limit_bytes=4194304; captured prefix preserved'); exit 125 }
    if (-not $streamsDrained) { [Console]::Error.WriteLine('SSH_CAPTURE_FAIL_CLOSED reason=stream-drain-timeout; captured prefix preserved'); exit 125 }
    exit $ssh.ExitCode
}

function Invoke-TransportSelfTest {
    $bodyPrefix = @'
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
'@
    $bodyPrefix = $bodyPrefix.Replace("`r`n", "`n").Replace("`r", "`n")
    $bodyPrefix += "`n"
    $accepted = $false
    try {
        Assert-IsolatedI3Body ($bodyPrefix + "# exact isolated-i3 prefix fixture`n")
        $accepted = $true
    } catch { }
    if (-not $accepted) { throw 'Exact isolated-i3 preamble followed by trusted rig-env setup was rejected' }

    $strictRouteRejects = @(
        @{ Name = 'missing preamble'; Body = ". /c/KenshiModding/tools/automation/rig-env.sh`n" },
        @{ Name = 'altered host instance'; Body = $bodyPrefix.Replace('KAH_INSTANCE=3', 'KAH_INSTANCE=2') },
        @{ Name = 'altered rig-env setup'; Body = $bodyPrefix.Replace('. /c/KenshiModding/tools/automation/rig-env.sh', '. /tmp/rig-env.sh') },
        @{ Name = 'duplicate route assignment'; Body = $bodyPrefix + "export KAH_INSTANCE=3`n" },
        @{ Name = 'later route override'; Body = $bodyPrefix + "KAH_INSTANCE=1 stobe-auto status`n" }
    )
    foreach ($case in $strictRouteRejects) {
        $rejected = $false
        try { Assert-IsolatedI3Body $case.Body } catch { $rejected = $true }
        if (-not $rejected) { throw "Isolated-i3 route regression accepted $($case.Name)" }
    }
    $arguments = Get-SshArguments 'C:\Users\Shay\.ssh\config'
    $commandLineLength = ('ssh.exe ' + $arguments).Length
    $receiverLength = (Get-ReceiverEncodedCommand).Length
    if ($script:RemoteReceiver -notmatch 'DESKTOP-NQQPA73' -or $commandLineLength -ge 8192 -or $receiverLength -ge 8192) {
        throw "Fixed transport command unexpectedly large: cmd=$commandLineLength receiver=$receiverLength"
    }
    $chat007BodyPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'pending-fixes\rig4080-validation\chat007-session-reader-stream.review.sh'
    $chat007Body = Get-Content -LiteralPath $chat007BodyPath -Raw
    if ($chat007Body -notmatch '(?m)^# CHAT007_READONLY_PREFLIGHT_STREAM_CONTRACT v1$' -or
        $chat007Body -notmatch '(?m)^printf ''\\n=== CHAT007 PREFLIGHT OUTPUT COMPLETE v1 ===\\n''$') {
        throw 'CHAT-007 stream contract or terminal completion marker is missing from the approved body'
    }
    $receiverReadonlyAssignment = '$readonlyRoute = "readonly RIG=4080 KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3 KAH_DIR=''C:\KenshiInst\3\mods\AutomationHarness''`n"'
    if (-not $script:RemoteReceiver.Contains($receiverReadonlyAssignment) -or
        -not $script:RemoteReceiver.Contains('+ $readonlyRoute + $remainingBody')) {
        throw 'Remote receiver does not define and compose its own explicit-i3 readonly route line'
    }
    if (-not $script:RemoteReceiver.Contains('[IO.File]::WriteAllBytes($tempBody, $bodyBytes)') -or
        $script:RemoteReceiver -match 'StandardInput\.BaseStream\.Write\(\$bodyBytes') {
        throw 'Remote receiver must stage the complete Bash body before execution; streaming it into bash -s can break on early exit'
    }

    # A protected config may make Test-Path throw AccessDenied. In that case
    # the wrapper must still delegate to OpenSSH with the explicit config and
    # the one hard-pinned host alias; OpenSSH's error must remain terminal.
    $trustedConfig = 'C:\Users\Shay\.ssh\config'
    $accessDeniedProbe = { param($path) throw [UnauthorizedAccessException]::new('synthetic access denied') }
    $delegated = New-SshStartInfo $trustedConfig $accessDeniedProbe
    if ($delegated.FileName -cne 'ssh.exe' -or
        $delegated.Arguments -notmatch '^-F "C:\\Users\\Shay\\\.ssh\\config" -o BatchMode=yes -o ConnectTimeout=8 4080 powershell\.exe ' -or
        $delegated.Arguments -match '(?<!\S)(?:5090|localhost|127\.0\.0\.1)(?:\s|$)' -or
        $delegated.Arguments -notmatch ' 4080 powershell\.exe ') {
        throw "AccessDenied config probe did not preserve the fixed SSH delegation: file=$($delegated.FileName) args=$($delegated.Arguments)"
    }
    $missingConfigRejected = $false
    try { $null = New-SshStartInfo $trustedConfig { param($path) $false } } catch { $missingConfigRejected = $true }
    if (-not $missingConfigRejected) { throw 'Missing trusted SSH config was not rejected before delegation' }
    $emptyConfigRejected = $false
    try { $null = New-SshStartInfo '' { param($path) throw 'probe must not run' } } catch { $emptyConfigRejected = $true }
    if (-not $emptyConfigRejected) { throw 'Empty SSH config path was not rejected' }
    $invokeSource = Get-Content -LiteralPath $PSCommandPath -Raw
    if ($invokeSource -notmatch '(?s)\$ssh\.WaitForExit\(120000\).*?exit \$ssh\.ExitCode' -or
        $invokeSource -match '(?s)catch\s*\{[^}]*ssh[^}]*\}\s*(?:#.*)?\r?\n\s*(?:\$null\s*=\s*\$ssh\.Start\(\)|\$ssh\.Start\(\))') {
        throw 'SSH errors must remain terminal; wrapper must propagate the exact ssh.exe exit code without retry/fallback'
    }

    if ($script:RemoteReceiver -notmatch '\$bash\.WaitForExit\(110000\)' -or
        $invokeSource -notmatch '\$ssh\.WaitForExit\(120000\)' -or
        $invokeSource -notmatch '(?s)BeginOutputReadLine\(\).*?BeginErrorReadLine\(\)') {
        throw 'Transport must use bounded waits and event-driven stream capture'
    }
    if (-not $script:RemoteReceiver.Contains('KAH4080_RECEIVER_PID=') -or -not $script:RemoteReceiver.Contains('KAH4080_BASH_PID=')) { throw 'Receiver and owned Bash PID metadata are required' }
    if ($invokeSource -notmatch '\$captureLimitBytes = 4MB' -or
        $invokeSource -notmatch 'KahOrderedCapture]::Attach' -or
        $invokeSource -notmatch 'streamsDrained' -or
        $invokeSource -notmatch 'SSH_CAPTURE_FAIL_CLOSED') {
        throw 'Local SSH capture must enforce a byte cap and fail closed when streams do not drain'
    }
    $hangBody = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-timeout-' + [Guid]::NewGuid().ToString('N') + '.sh')
    $hangOut = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-timeout-' + [Guid]::NewGuid().ToString('N') + '.out')
    $hangErr = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-timeout-' + [Guid]::NewGuid().ToString('N') + '.err')
    $hangOutEof = $hangOut + '.eof'
    $hangErrEof = $hangErr + '.eof'
    $hangOutOverflow = $hangOut + '.overflow'
    $hangErrOverflow = $hangErr + '.overflow'
    $outEvent = 'kah4080-test-out-' + [Guid]::NewGuid().ToString('N')
    $errEvent = 'kah4080-test-err-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($hangBody, "for i in {1..250}; do printf 'batch-line-%03d`n' `$i; done; printf 'backlog-last-marker`n'; printf 'stderr-drain-marker`n' >&2; (sleep 2) & wait`n", (New-Object Text.UTF8Encoding($false)))
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = 'C:\Program Files\Git\bin\bash.exe'
        $proc.StartInfo.Arguments = '--noprofile --norc "' + $hangBody + '"'
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $null = Register-ProcessCaptureStream $proc 'OutputDataReceived' $outEvent $hangOut $hangOutEof $hangOutOverflow 1048576
        $null = Register-ProcessCaptureStream $proc 'ErrorDataReceived' $errEvent $hangErr $hangErrEof $hangErrOverflow 1048576
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $null = $proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        Start-Sleep -Milliseconds 100
        $waitExpired = -not $proc.WaitForExit(750)
        if ($waitExpired) { try { $proc.Kill() } catch {} }
        $null = $proc.WaitForExit(2000)
        $drainDeadline = [DateTime]::UtcNow.AddSeconds(5)
        while ((-not (Test-Path -LiteralPath $hangOutEof)) -or (-not (Test-Path -LiteralPath $hangErrEof))) {
            if ([DateTime]::UtcNow -ge $drainDeadline) { break }
            Start-Sleep -Milliseconds 50
        }
        $captured = if (Test-Path -LiteralPath $hangOut) { [IO.File]::ReadAllText($hangOut) } else { '' }
        $capturedErr = if (Test-Path -LiteralPath $hangErr) { [IO.File]::ReadAllText($hangErr) } else { '' }
        $clock.Stop()
        $lines = @($captured -split '\r?\n' | Where-Object { $_ })
        if (-not $waitExpired -or -not (Test-Path -LiteralPath $hangOutEof) -or -not (Test-Path -LiteralPath $hangErrEof) -or
            $lines.Count -ne 251 -or $lines[-1] -ne 'backlog-last-marker' -or (($lines[0..249] -join ',') -ne ((0..249 | ForEach-Object { 'batch-line-{0:D3}' -f ($_ + 1) }) -join ',')) -or $capturedErr -notmatch 'stderr-drain-marker' -or
            (Test-Path -LiteralPath $hangOutOverflow) -or (Test-Path -LiteralPath $hangErrOverflow) -or $clock.Elapsed.TotalSeconds -ge 7) {
            throw ('Synthetic inherited-pipe timeout/backlog regression failed: waitExpired=' + $waitExpired + ' lines=' + $lines.Count + ' last=' + $lines[-1] + ' stdoutEOF=' + (Test-Path $hangOutEof) + ' stderrEOF=' + (Test-Path $hangErrEof) + ' stderrMarker=' + ($capturedErr -match 'stderr-drain-marker') + ' elapsed=' + $clock.Elapsed.TotalSeconds)
        }
        try { $proc.StandardOutput.Close() } catch {}
        try { $proc.StandardError.Close() } catch {}
        $proc.Dispose()
    }
    finally {
        Unregister-Event -SourceIdentifier $outEvent -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errEvent -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $hangBody,$hangOut,$hangErr,$hangOutEof,$hangErrEof,$hangOutOverflow,$hangErrOverflow -Force -ErrorAction SilentlyContinue
    }
    $capBody = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-cap-' + [Guid]::NewGuid().ToString('N') + '.sh')
    $capOut = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-cap-' + [Guid]::NewGuid().ToString('N') + '.out')
    $capEof = $capOut + '.eof'
    $capOverflow = $capOut + '.overflow'
    $capEvent = 'kah4080-test-cap-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($capBody, "for i in {1..50}; do printf 'bounded-cap-line-%03d`n' `$i; done`n", (New-Object Text.UTF8Encoding($false)))
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = 'C:\Program Files\Git\bin\bash.exe'
        $proc.StartInfo.Arguments = '--noprofile --norc "' + $capBody + '"'
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $null = Register-ProcessCaptureStream $proc 'OutputDataReceived' $capEvent $capOut $capEof $capOverflow 1024
        $null = Register-ProcessCaptureStream $proc 'ErrorDataReceived' ($capEvent + '-err') ($capOut + '.err') ($capEof + '.err') ($capOverflow + '.err') 1024
        $null = $proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        if (-not $proc.WaitForExit(5000)) { throw 'Synthetic output-cap writer did not exit' }
        $drainDeadline = [DateTime]::UtcNow.AddSeconds(3)
        while ((-not (Test-Path -LiteralPath $capEof)) -or (-not (Test-Path -LiteralPath ($capEof + '.err')))) {
            if ([DateTime]::UtcNow -ge $drainDeadline) { break }
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $capOverflow) -or (Get-Item -LiteralPath $capOut).Length -gt 1024 -or
            -not (Test-Path -LiteralPath $capEof) -or -not (Test-Path -LiteralPath ($capEof + '.err'))) {
            throw 'Synthetic output cap failed to preserve a bounded prefix and mark overflow/drain state'
        }
        try { $proc.StandardOutput.Close() } catch {}
        try { $proc.StandardError.Close() } catch {}
        $proc.Dispose()
    }
    finally {
        Unregister-Event -SourceIdentifier $capEvent -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier ($capEvent + '-err') -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $capBody,$capOut,($capOut + '.err'),$capEof,($capEof + '.err'),$capOverflow,($capOverflow + '.err') -Force -ErrorAction SilentlyContinue
    }
    # Exercise the exact Bash syntax locally. The legacy `readonly -x` form
    # fails on Bash; the corrected form must retain exports and select i3.
    $bashPath = 'C:\Program Files\Git\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bashPath -PathType Leaf)) { throw "Git Bash not found for synthetic compatibility test: $bashPath" }
    function Invoke-SyntheticBash([string]$scriptText) {
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = $bashPath
        $proc.StartInfo.Arguments = '--noprofile --norc -s'
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardInput = $true
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $null = $proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $proc.StandardInput.Write($scriptText)
        $proc.StandardInput.Close()
        $proc.WaitForExit()
        [pscustomobject]@{ ExitCode = $proc.ExitCode; Stdout = $outTask.Result; Stderr = $errTask.Result }
    }
    function Invoke-SyntheticBashFile([string]$scriptText) {
        $temp = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'kah4080-selftest-' + [Guid]::NewGuid().ToString('N') + '.sh')
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($scriptText)
            [IO.File]::WriteAllBytes($temp, $bytes)
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo.FileName = $bashPath
            $proc.StartInfo.Arguments = '--noprofile --norc "' + $temp + '"'
            $proc.StartInfo.UseShellExecute = $false
            $proc.StartInfo.RedirectStandardOutput = $true
            $proc.StartInfo.RedirectStandardError = $true
            $null = $proc.Start()
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            $proc.WaitForExit()
            [pscustomobject]@{ ExitCode = $proc.ExitCode; Stdout = $outTask.Result; Stderr = $errTask.Result; BytesWritten = $bytes.Length }
        }
        finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    function Invoke-SyntheticClosedPipeWrite {
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $proc.StartInfo.Arguments = '-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 100; exit 23"'
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardInput = $true
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $null = $proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $writeFailed = $false
        try {
            $payload = New-Object byte[] (2 * 1024 * 1024)
            $proc.StandardInput.BaseStream.Write($payload, 0, $payload.Length)
            $proc.StandardInput.BaseStream.Flush()
        }
        catch [IO.IOException] { $writeFailed = $true }
        finally {
            try { $proc.StandardInput.Close() } catch {}
        }
        $proc.WaitForExit()
        [pscustomobject]@{ ExitCode = $proc.ExitCode; WriteFailed = $writeFailed; Stderr = $errTask.Result }
    }
    $legacyReadonly = Invoke-SyntheticBash "readonly -x RIG=4080`n"
    if ($legacyReadonly.ExitCode -eq 0 -or $legacyReadonly.Stderr -notmatch 'readonly: -x: invalid option') {
        throw "Legacy Bash syntax failure was not reproduced: exit=$($legacyReadonly.ExitCode) stderr=$($legacyReadonly.Stderr.Trim())"
    }
    $statusScript = @'
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
'@
    $statusScript = $statusScript.Replace("`r`n", "`n") + $script:ReadonlyRoute + @'
printf 'RESULT 4080-I3-ROUTE PASS\nKAH_INSTANCE=%s\nKENSHI_DIR=%s\nKDIR=%s\nKAH_DIR=%s\n' "$KAH_INSTANCE" "$KENSHI_DIR" "$KDIR" "$KAH_DIR"
'@
    $status = Invoke-SyntheticBash $statusScript
    if ($status.ExitCode -ne 0 -or $status.Stdout -notmatch '(?m)^RESULT 4080-I3-ROUTE PASS$' -or
        $status.Stdout -notmatch '(?m)^KAH_INSTANCE=3$' -or
        $status.Stdout -notmatch '(?m)^KENSHI_DIR=/c/KenshiInst/3$' -or
        $status.Stdout -notmatch '(?m)^KDIR=/c/KenshiInst/3$' -or
        $status.Stdout -notmatch '(?m)^KAH_DIR=C:\\KenshiInst\\3\\mods\\AutomationHarness$') {
        throw "Corrected explicit-i3 status fixture failed: exit=$($status.ExitCode) stdout=$($status.Stdout.Trim()) stderr=$($status.Stderr.Trim())"
    }

    # An early exit plus a large unread tail used to close bash's stdin while
    # the PowerShell receiver was writing. File staging completes first, so the
    # child may exit early without interrupting transport of the script body.
    $earlyExitScript = "exit 23`n# unread tail begins`n" + ('x' * 250000) + "`n# unread tail ends`n"
    $earlyExit = Invoke-SyntheticBashFile $earlyExitScript
    if ($earlyExit.ExitCode -ne 23 -or $earlyExit.BytesWritten -ne [Text.Encoding]::UTF8.GetByteCount($earlyExitScript) -or
        $earlyExit.Stderr -match 'pipe has been ended|broken pipe') {
        throw "Early-exit large-body fixture failed: exit=$($earlyExit.ExitCode) bytes=$($earlyExit.BytesWritten) stderr=$($earlyExit.Stderr.Trim())"
    }
    $closedPipe = Invoke-SyntheticClosedPipeWrite
    if (-not $closedPipe.WriteFailed -or $closedPipe.ExitCode -ne 23) {
        throw "Synthetic closed-pipe control failed to reproduce the prior transport error: child_exit=$($closedPipe.ExitCode) write_failed=$($closedPipe.WriteFailed) stderr=$($closedPipe.Stderr.Trim())"
    }

    $sectionLines = foreach ($section in $script:Chat007OutputSections) { "=== $section ===" }
    $hashA = 'a' * 64
    $hashB = 'b' * 64
    $completeReadinessJson = '{"session_present":true,"status":"ready","gamets":123,"load_id_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation_present":true,"manager_ready_matches":true}'
    $completeTranscript = @(
        'RESULT 4080-I3-ROUTE PASS route=C:\KenshiInst\3 inbox=clear metadata-only',
        $sectionLines[0], 'DESKTOP-NQQPA73', 'instance=3 synced=2026-10-13T12:00:52',
        $sectionLines[1], 'PID=3452', 'PROCESS_PATH_PART=1/1:C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe',
        'LOADED_MODULE=Stobe.dll', "ON_DISK_SHA256=$hashA", 'LOADED_MODULE=AutomationHarness.dll', "ON_DISK_SHA256=$hashB",
        $sectionLines[2], "$hashA /c/KenshiInst/3/mods/Stobe/Stobe.dll", "$hashB /c/KenshiInst/3/mods/AutomationHarness/AutomationHarness.dll",
        $sectionLines[3], 'ServerHost=127.0.0.1', 'ServerPort=18084',
        $sectionLines[4], '{"ok":true,"database":true,"database_schema_ready":true}',
        $sectionLines[5], 'php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site',
        $sectionLines[6], $completeReadinessJson,
        $sectionLines[7], 'phase=world save=synthetic last_saved=synthetic paused=0 speed=1 squad=1 player=Shay speaker=Shay',
        $sectionLines[8], 'game_hours=123.0000 day=7 time=03:00 speed=1.0 paused=0',
        $sectionLines[9], 'isolation=on focused=0',
        $sectionLines[10], 'fp_mode=0 cursor_hidden=0 ui_open=0 ui_why=none control=0 focus=0 speaker=Shay',
        $sectionLines[11], '1 within 300: Shay #100/1 at 0m',
        $sectionLines[12]
    ) -join "`n"
    $complete = Get-Chat007StreamResult $completeTranscript '' 0
    if ($complete.ExitCode -ne 0 -or $complete.Failure) { throw "Complete CHAT-007 transcript was rejected: $($complete.Failure)" }

    $readinessFlags = @('session_present', 'generation_present', 'manager_ready_matches')
    foreach ($field in $readinessFlags) {
        $falseJson = $completeReadinessJson.Replace('"' + $field + '":true', '"' + $field + '":false')
        $falseResult = Get-Chat007StreamResult ($completeTranscript.Replace($completeReadinessJson, $falseJson)) '' 0
        if ($falseResult.ExitCode -ne 2 -or $falseResult.Failure -notmatch [regex]::Escape("evidence:$field must be uniquely boolean true")) {
            throw "CHAT-007 accepted false readiness field ${field}: $($falseResult.Failure)"
        }

        $missingJson = $completeReadinessJson.Replace('"' + $field + '":true,', '')
        if ($missingJson -ceq $completeReadinessJson) { $missingJson = $completeReadinessJson.Replace(',' + '"' + $field + '":true', '') }
        $missingResult = Get-Chat007StreamResult ($completeTranscript.Replace($completeReadinessJson, $missingJson)) '' 0
        if ($missingResult.ExitCode -ne 2 -or $missingResult.Failure -notmatch [regex]::Escape("evidence:$field must be uniquely boolean true")) {
            throw "CHAT-007 accepted missing readiness field ${field}: $($missingResult.Failure)"
        }

        foreach ($malformedValue in @('null', '"true"', '1', '[]', '{}', 'tru')) {
            $malformedJson = $completeReadinessJson.Replace('"' + $field + '":true', '"' + $field + '":' + $malformedValue)
            $malformedResult = Get-Chat007StreamResult ($completeTranscript.Replace($completeReadinessJson, $malformedJson)) '' 0
            if ($malformedResult.ExitCode -ne 2) {
                throw "CHAT-007 accepted malformed readiness value $malformedValue for $field"
            }
        }

        foreach ($duplicateValue in @('true', 'false')) {
            $duplicateJson = $completeReadinessJson.Replace('}', ',"' + $field + '":' + $duplicateValue + '}')
            $duplicateResult = Get-Chat007StreamResult ($completeTranscript.Replace($completeReadinessJson, $duplicateJson)) '' 0
            if ($duplicateResult.ExitCode -ne 2 -or $duplicateResult.Failure -notmatch [regex]::Escape("evidence:$field must be uniquely boolean true")) {
                throw "CHAT-007 accepted duplicate/conflicting readiness field ${field}=${duplicateValue}: $($duplicateResult.Failure)"
            }
        }
    }

    $truncatedTranscript = ($completeTranscript -split "(?m)^=== PRIVATE BACKEND PROCESS ===$")[0] + "=== PRIVATE BACKEND PROCESS ===`nphp -S 127.0.0.1:18084`n"
    $truncated = Get-Chat007StreamResult $truncatedTranscript '' 0
    if ($truncated.ExitCode -ne 2 -or $truncated.Failure -notmatch 'FAIL setup: captured read output is incomplete') {
        throw "Truncated CHAT-007 transcript did not fail setup: exit=$($truncated.ExitCode) failure=$($truncated.Failure)"
    }

    $missingTranscript = $completeTranscript.Replace('=== KAH WORLD STATUS ===', '=== MISSING WORLD STATUS ===')
    $missingMarker = Get-Chat007StreamResult $missingTranscript '' 0
    if ($missingMarker.ExitCode -ne 2 -or $missingMarker.Failure -notmatch 'KAH WORLD STATUS') {
        throw "Missing CHAT-007 section marker did not fail setup: exit=$($missingMarker.ExitCode) failure=$($missingMarker.Failure)"
    }

    $fillerTranscript = $completeTranscript.Replace('phase=world', 'world summary')
    $filler = Get-Chat007StreamResult $fillerTranscript '' 0
    if ($filler.ExitCode -ne 2 -or $filler.Failure -notmatch 'world/save status') {
        throw "Non-empty filler did not fail the world-status evidence gate: exit=$($filler.ExitCode) failure=$($filler.Failure)"
    }

    $badHashTranscript = $completeTranscript.Replace("ON_DISK_SHA256=$hashA", 'ON_DISK_SHA256=not-a-hash')
    $badHash = Get-Chat007StreamResult $badHashTranscript '' 0
    if ($badHash.ExitCode -ne 2 -or $badHash.Failure -notmatch 'Stobe loaded hash') {
        throw "Malformed module hash did not fail setup: exit=$($badHash.ExitCode) failure=$($badHash.Failure)"
    }

    $secretStderr = 'permission denied token=CHAT007_SECRET_SENTINEL'
    $nonzero = Get-Chat007StreamResult 'partial output' $secretStderr 73
    if ($nonzero.ExitCode -ne 73 -or $nonzero.Failure -notmatch 'exited with code 73' -or
        $nonzero.Failure -notmatch 'stderr_class=permission_denied' -or
        $nonzero.Failure -notmatch 'permission denied token=\[REDACTED\]' -or
        $nonzero.Failure -match 'CHAT007_SECRET_SENTINEL') {
        throw "Nonzero CHAT-007 child exit was not propagated with sanitized stderr: exit=$($nonzero.ExitCode) failure=$($nonzero.Failure)"
    }

    $otherStderr = "remote read setup failed before session data was available`ntransport returned no section output"
    $otherFailure = Get-Chat007StreamResult 'partial output' $otherStderr 0
    if ($otherFailure.ExitCode -ne 2 -or $otherFailure.Failure -notmatch 'stderr_class=other stderr_lines=2' -or
        $otherFailure.Failure -notmatch 'remote read setup failed before session data was available' -or
        $otherFailure.Failure -notmatch 'transport returned no section output') {
        throw "Two-line CHAT-007 other-stderr failure lost its bounded diagnostic excerpt: $($otherFailure.Failure)"
    }

    $pidStderr = "KAH4080_RECEIVER_PID=123`nKAH4080_BASH_PID=456`npermission denied"
    $pidDiag = Get-Chat007StderrDiagnostic $pidStderr
    $pidReadiness = Get-ReadinessStderrSummary "$script:ReadinessStageMarker`nKAH4080_RECEIVER_PID=123`nKAH4080_BASH_PID=456`npermission denied"
    if ($pidDiag.Class -ne 'permission_denied' -or $pidDiag.LineCount -ne 1 -or
        $pidReadiness.Category -ne 'permission_denied' -or $pidReadiness.LineCount -ne 1 -or
        $pidReadiness.ReceiverStage -ne 'post_route_guard') {
        throw 'Transport PID metadata changed existing stderr classifications'
    }
    $secretDiagnostic = @(
        'remote transport setup failed session_id=SESSION_ID_SECRET_SENTINEL'
        'Authorization: Bearer BEARER_TOKEN_SECRET_SENTINEL'
        'password=PASSWORD_SECRET_SENTINEL cookie=COOKIE_SECRET_SENTINEL credential=CREDENTIAL_SECRET_SENTINEL client_secret=CLIENT_SECRET_SENTINEL api_key=API_KEY_SECRET_SENTINEL ordinary-diagnostic Cookie: COOKIE_HEADER_SECRET_SENTINEL'
        '-----BEGIN PRIVATE KEY-----'
        'PRIVATE_KEY_SECRET_SENTINEL'
        '-----END PRIVATE KEY-----'
    ) -join "`n"
    $secretFailure = Get-Chat007StreamResult 'partial output' $secretDiagnostic 0
    foreach ($secret in @('SESSION_ID_SECRET_SENTINEL', 'BEARER_TOKEN_SECRET_SENTINEL', 'PASSWORD_SECRET_SENTINEL', 'COOKIE_SECRET_SENTINEL', 'COOKIE_HEADER_SECRET_SENTINEL', 'CREDENTIAL_SECRET_SENTINEL', 'CLIENT_SECRET_SENTINEL', 'API_KEY_SECRET_SENTINEL', 'PRIVATE_KEY_SECRET_SENTINEL', 'Authorization: Bearer')) {
        if ($secretFailure.Failure.Contains($secret)) { throw "CHAT-007 stderr excerpt leaked a synthetic secret marker: $secret" }
    }
    if ($secretFailure.Failure -notmatch 'remote transport setup failed' -or
        $secretFailure.Failure -notmatch 'ordinary-diagnostic' -or
        $secretFailure.Failure.Length -gt 1800) {
        throw "CHAT-007 stderr excerpt did not retain bounded ordinary diagnostic text: $($secretFailure.Failure)"
    }
    $longStderr = (1..6 | ForEach-Object { 'ordinary diagnostic ' + ('x' * 500) }) -join "`n"
    $boundedDiag = Get-Chat007StderrDiagnostic $longStderr
    if ($boundedDiag.Excerpt.Length -gt 1200 -or @($boundedDiag.Excerpt -split ' \| ').Count -gt 4) {
        throw "CHAT-007 stderr excerpt exceeded its line/character bound: chars=$($boundedDiag.Excerpt.Length) excerpt=<$($boundedDiag.Excerpt)>"
    }

    $clixmlReadiness = Get-ReadinessStderrSummary "#< CLIXML`r`n<Objs S=`"progress`"><AV>Preparing modules for first use; token=CLIXML_SECRET_SENTINEL</AV></Objs>"
    if ($clixmlReadiness.Category -ne 'known_clixml_prefix' -or $clixmlReadiness.LineCount -ne 2 -or
        $clixmlReadiness.ReceiverStage -ne 'unconfirmed' -or
        $clixmlReadiness.PSObject.Properties.Name -contains 'Excerpt' -or
        ($clixmlReadiness | Out-String) -match 'CLIXML_SECRET_SENTINEL') {
        throw 'Readiness wrapper did not reduce CLIXML stderr to fixed metadata'
    }
    $ordinaryReadiness = Get-ReadinessStderrSummary "permission denied`nprivate-path-and-token=READINESS_SECRET_SENTINEL"
    if ($ordinaryReadiness.Category -ne 'permission_denied' -or $ordinaryReadiness.LineCount -ne 2 -or
        $ordinaryReadiness.ReceiverStage -ne 'unconfirmed' -or
        $ordinaryReadiness.PSObject.Properties.Name -contains 'Excerpt' -or
        ($ordinaryReadiness | Out-String) -match 'READINESS_SECRET_SENTINEL') {
        throw 'Readiness wrapper did not suppress arbitrary stderr details'
    }

    $receiverMarker = 'KAH4080_RECEIVER_STAGE post_route_guard v1'
    $enteredReadiness = Get-ReadinessStderrSummary "$receiverMarker`r`naccess is denied token=READINESS_STAGE_SECRET"
    if ($enteredReadiness.Category -ne 'permission_denied' -or $enteredReadiness.LineCount -ne 1 -or
        $enteredReadiness.ReceiverStage -ne 'post_route_guard' -or
        $enteredReadiness.PSObject.Properties.Name -contains 'Excerpt' -or
        ($enteredReadiness | Out-String) -match 'READINESS_STAGE_SECRET|KAH4080_RECEIVER_STAGE') {
        throw 'Readiness wrapper did not report the fixed receiver stage while suppressing raw stderr'
    }
    $markerOnlyReadiness = Get-ReadinessStderrSummary $receiverMarker
    if ($markerOnlyReadiness.Captured -or $markerOnlyReadiness.Category -ne 'empty' -or
        $markerOnlyReadiness.LineCount -ne 0 -or $markerOnlyReadiness.ReceiverStage -ne 'post_route_guard') {
        throw 'Readiness stage marker was not excluded from diagnostic content/counts'
    }
    $lookalikeReadiness = Get-ReadinessStderrSummary "prefix $receiverMarker`npermission denied"
    if ($lookalikeReadiness.ReceiverStage -ne 'unconfirmed' -or $lookalikeReadiness.Category -ne 'permission_denied') {
        throw 'Readiness stage marker was accepted when it was not an exact standalone line'
    }

    $payloadTestBytes = [Text.Encoding]::UTF8.GetBytes($bodyPrefix)
    foreach ($modeCase in @(@{ Mode = 'STANDARD'; Readiness = $false }, @{ Mode = 'READINESS'; Readiness = $true })) {
        $modePayload = New-RemotePayload $payloadTestBytes $modeCase.Readiness
        $separator = $modePayload.IndexOf("`n", [StringComparison]::Ordinal)
        if ($separator -lt 0 -or $modePayload.Substring(0, $separator) -cne $modeCase.Mode) {
            throw "Remote payload used the wrong mode envelope for $($modeCase.Mode)"
        }
        $decoded = [Convert]::FromBase64String($modePayload.Substring($separator + 1))
        if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$payloadTestBytes, [byte[]]$decoded)) {
            throw "Remote payload mode envelope changed UTF-8 body bytes for $($modeCase.Mode)"
        }
    }
    $unknownMode = 'UNKNOWN'
    $modeGuardText = 'if ($payloadMode -cne ''STANDARD'' -and $payloadMode -cne ''READINESS'')'
    if ($unknownMode -ceq 'STANDARD' -or $unknownMode -ceq 'READINESS' -or
        -not $script:RemoteReceiver.Contains($modeGuardText)) {
        throw 'Remote receiver did not reject unknown payload modes'
    }
    try { [void][scriptblock]::Create($script:RemoteReceiver) }
    catch { throw "Remote receiver PowerShell syntax is invalid: $($_.Exception.Message)" }
    $expectedReceiverPreamble = '$ProgressPreference = ''SilentlyContinue''' + "`n" + '$ErrorActionPreference = ''Stop'''
    if (-not $script:RemoteReceiver.StartsWith($expectedReceiverPreamble, [StringComparison]::Ordinal)) {
        throw 'Remote receiver must suppress first-use progress before executing its transport logic'
    }
    $receiverRouteCheck = $script:RemoteReceiver.IndexOf('if (-not $body.StartsWith', [StringComparison]::Ordinal)
    $receiverMarkerIndex = $script:RemoteReceiver.IndexOf("if (`$payloadMode -ceq 'READINESS') { [Console]::Error.WriteLine('$receiverMarker') }", [StringComparison]::Ordinal)
    $receiverTempBody = $script:RemoteReceiver.IndexOf('$tempBody = ', [StringComparison]::Ordinal)
    if ($receiverRouteCheck -lt 0 -or $receiverMarkerIndex -le $receiverRouteCheck -or
        $receiverTempBody -le $receiverMarkerIndex) {
        throw 'Readiness-only receiver marker is not after the i3 route guard and before remote body execution'
    }

    $cases = @(
        @{ Name = 'near Windows limit'; Size = 30000 },
        @{ Name = 'past Windows limit'; Size = 50000 },
        @{ Name = 'large body'; Size = 250000 }
    )
    foreach ($case in $cases) {
        $paddingLength = $case.Size - [Text.Encoding]::UTF8.GetByteCount($bodyPrefix)
        $body = $bodyPrefix + "`n# synthetic padding begins`n" + ('x' * ($paddingLength - 30)) + "`n# synthetic end`n"
        Assert-IsolatedI3Body $body
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $payload = [Convert]::ToBase64String($bytes)
        $roundTrip = [Convert]::FromBase64String($payload)
        if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]]$roundTrip)) {
            throw "UTF-8 transport round-trip failed for $($case.Name)"
        }
        if ($payload.Length -le 32767 -and $case.Size -gt 32767) {
            throw "Fixture failed to cross the CreateProcess argument limit: $($case.Name)"
        }
    }
    # Reproduce the failure class without SSH: the old wrapper nested the
    # complete UTF-8/Base64 Bash body inside a PowerShell -EncodedCommand
    # argument. CreateProcess rejects that oversized native command line.
    $failingBody = $bodyPrefix + "`n#" + ('x' * 30000)
    $nestedBashPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($failingBody))
    $unsafePs = '$bashPayload = ''' + $nestedBashPayload + '''; $null = $bashPayload'
    $unsafePsEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($unsafePs))
    $unsafe = New-Object System.Diagnostics.ProcessStartInfo
    $unsafe.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $unsafe.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + $unsafePsEncoded
    $unsafe.UseShellExecute = $false
    $unsafeRejected = $false
    try {
        $oversized = [Diagnostics.Process]::Start($unsafe)
        if ($oversized) { $oversized.WaitForExit(); throw 'Oversized legacy command unexpectedly started' }
    } catch [ComponentModel.Win32Exception] {
        $unsafeRejected = $true
    }
    if (-not $unsafeRejected) { throw 'Synthetic legacy PS/SSH wrapper did not reproduce the CreateProcess command-line rejection' }
    $badBody = "export RIG=4080 KAH_INSTANCE=1`nexport KENSHI_DIR=/c/KenshiInst/1`nexport KAH_DIR=/c/KenshiInst/1/mods/AutomationHarness`n"
    $rejected = $false
    try { Assert-IsolatedI3Body $badBody } catch { $rejected = $true }
    if (-not $rejected) { throw 'Non-i3 body was not rejected' }
    $overrideCases = @("`nexport KAH_INSTANCE=1", "`nunset KAH_DIR", "`nKDIR=/c/KenshiInst/1 stobe-auto status", "`nenv -u KAH_DIR stobe-auto status", "`neval 'KAH_INSTANCE=1'", "`n. /tmp/route-override.sh")
    foreach ($override in $overrideCases) {
        $rejected = $false
        try { Assert-IsolatedI3Body ($bodyPrefix + $override) } catch { $rejected = $true }
        if (-not $rejected) { throw "i3 override fixture was accepted: $override" }
    }
    "RESULT 4080-REMOTE-BASH-STDIN PASS cases=$($cases.Count) max_body=250000 legacy_createprocess=blocked legacy_readonly=reproduced early_exit_large_body=PASS closed_pipe_control=PASS i3_status=PASS chat007_stream=complete+truncated+missing-marker+filler+bad-hash+exit73_sanitized+other_stderr_excerpt+secret_redaction readiness_stage=post_route_guard+unconfirmed+marker_redaction mode_envelope=standard+readiness+unknown_rejected route_guard=12_rejects+exact_accept fail-closed bounded_capture=4mb+eof_drain+backlog+overflow_rejected invoke_start_separator=PASS ordered_capture=250+linefeed_normalization=PASS command_chars=$commandLineLength receiver_chars=$receiverLength"
}

if ($SelfTest) { Invoke-TransportSelfTest; exit 0 }
if (-not $BodyPath) { throw 'Usage: remote-bash-stdin-4080.ps1 -BodyPath <UTF-8 Bash file> [-SshConfig <trusted config>]' }
Invoke-RemoteBashBody $BodyPath $SshConfig
