# 4080 process and memory audit

Read-only snapshot through the approved SSH alias `4080` and configured SSH file. No processes were started or stopped by the audit, and no command lines or credentials were collected.

- Snapshot: 2026-10-14 11:15:47–11:16:25 America/Winnipeg.
- Physical RAM: 32,671 MiB total; 20,317 MiB free (62.2% free).
- Commit: 39,257 MiB committed of 45,796 MiB limit (6,539 MiB headroom). This is commit accounting, not physical RAM use.
- GPU memory (11:16): RTX 4080, 16,376 MiB total, 12,250 MiB used, 3,801 MiB free.

Largest private-byte consumers at 11:15:47 (working set shown separately):

| Process | PID | Private MiB | Working set MiB | Start |
|---|---:|---:|---:|---|
| kenshi_x64 (instance 3, known) | 3452 | 11,013 | 760 | Oct 13 15:18 |
| kenshi_x64 (instance 2, ownership unproven) | 13872 | 9,903 | 474 | Oct 12 22:44 |
| llama-server | 2260 | 9,437 | 1,080 | Oct 14 10:15 |
| vmmem | 15124 | 2,754 | 2,747 | Oct 12 22:39 |
| steamwebhelper | 4680 | 455 | 429 | Oct 12 22:14 |
| MsMpEng | 12668 | 321 | 353 | Oct 13 22:26 |

Process counts: 2 Kenshi, 7 PowerShell, 7 sshd, 6 cmd, 3 wslhost, 2 wsl, 7 steamwebhelper. The 4080 SSH helper sessions created during this read-only audit were short-lived; the process list also showed older helper groups dating to Oct 12 and Oct 14 morning. IDs/start times were observed, but parent/session ownership was not established, so none can be called stale or safe to clean up from this evidence alone.

Cleanup recommendations: first ask the owner of PID 13872 whether that second game instance is still needed; its large private allocation makes it the clearest candidate for owner-confirmed closure. Keep known instance-3 PID 3452 and model PID 2260 untouched. Check which workloads own vmmem and the older PowerShell/cmd/sshd groups before reclaiming anything. Current RAM has ample free capacity, while VRAM has about 3.8 GiB free; the model and game processes hold most of the private commit.
