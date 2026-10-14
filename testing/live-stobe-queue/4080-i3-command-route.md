# 4080 instance-3 direct KAH command route

Use this route only from the trusted 4080 PowerShell 5 session. The body runs in Git Bash and proves that `KAH_INSTANCE`, `KENSHI_DIR`, and `KAH_DIR` select the isolated `C:\KenshiInst\3` install and harness. `rig4080_i3_preflight` checks only whether `inbox.txt` or `inbox.txt.lock` exists; it never opens, clears, waits on, or consumes either file. A pending inbox or lock stops the body before the command.

For multiword arguments, encode the complete Bash body as UTF-8 Base64. PowerShell passes only a simple Base64 pipeline through `bash -lc`, avoiding PowerShell 5's native argument truncation:

```powershell
$bash = 'C:\Program Files\Git\bin\bash.exe'
$body = @'
export RIG=4080 KAH_INSTANCE=3
. /c/KenshiModding/tools/automation/rig-env.sh
rig4080_i3_preflight || exit $?
stobe-auto stobe_say "<fresh verified target>" "<exact multiword utterance>"
'@
$payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
$command = "printf '%s' $payload | base64 -d | bash -s"
& $bash -lc $command
```

Before using a real row, replace both placeholders with the exact target and utterance from its approved packet, then retain the decoded body or payload in its receipt. The preflight's pass proves routing and an empty inbox at that instant; it does not replace the row's current world, session, build, target, or evidence gates. If it reports `STOP inbox pending or locked`, stop and preserve the inbox and lock unchanged. Do not retry through instance 1.

The installed `C:\KAH\bin\stobe-auto` shim also fails closed when an isolated install is intended: the explicit instance number, game root, and harness path must agree, and a pending inbox/lock is rejected before Python is started. Omitted or stale `KAH_DIR` cannot fall back to shared instance 1.

## Large 4080 Bash bodies over SSH

When a PowerShell-to-SSH-to-Git-Bash row body is too large for a Windows native command line, store the approved UTF-8 Bash body in a file and invoke `tools/automation/remote-bash-stdin-4080.ps1 -BodyPath <file>`. This wrapper requires the exact `RIG=4080`, `KAH_INSTANCE=3`, `KENSHI_DIR=/c/KenshiInst/3`, and instance-3 `KAH_DIR` preamble followed immediately by the trusted `rig-env.sh` setup. It rejects later route-variable assignments/unsets and `env`, `eval`, `exec`, or additional source commands; after `rig-env.sh`, it marks the route variables readonly before the row body runs. It pins the SSH config and checks the remote hostname before starting Git Bash. A short fixed PowerShell 5 `-EncodedCommand` receiver is sent to SSH, while the body's normalized UTF-8 bytes are Base64-encoded on SSH stdin. The receiver validates and fully writes the decoded body to a uniquely named temporary `.sh` file before starting Git Bash on that file, then removes it in `finally`. This avoids streaming into `bash -s`, where a fail-fast early exit can close stdin while PowerShell is still writing a large body and raise a broken-pipe/CLIXML error. The complete row body never enters a CreateProcess argument. The `stobe-auto` shim retains its own fail-closed instance/path checks.

Offline transport check (no SSH or rig access):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/automation/remote-bash-stdin-4080.ps1 -SelfTest
```

Run the offline contract check from Git Bash with:

```bash
bash tools/automation/rig4080/instance-route-selftest.sh
```

It uses a temporary harness and fake `cygpath`/Python commands. It does not contact the 4080 or invoke the real KAH client.
