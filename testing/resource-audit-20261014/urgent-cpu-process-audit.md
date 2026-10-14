# Urgent 5090 CPU/process audit — 2026-10-14

Read-only CIM/Get-Process inspection; no processes were stopped or altered. Initial unprivileged CIM access was denied, then the same narrow inventory succeeded with scoped elevation.

At 2026-10-14 18:48:40Z, 9,651 MB physical RAM was free. The filtered inventory contained 40 processes: 18 ChatGPT.exe, two codex.exe, six powershell.exe, five wslhost.exe, and one each of Kenshi, llama-server, python, ssh, vmmem, wslrelay, and wslservice. Target PIDs 86884 and 57304 were absent.

Precise five-second sample: 18:48:55.755Z–18:49:00.865Z.

| PID | Process / role | Start (local CIM) | CPU delta | Private / working set | Assessment |
|---:|---|---|---:|---:|---|
| 36376 | ChatGPT.exe renderer, parent 9092 | Oct 13 21:53:15 | +5.83 CPU-s / 5.11s (~114% of one core) | 4,686 / 4,385 MB | Main suspicious process; sustained renderer work and private memory rose from 4,470 MB in an earlier snapshot. Candidate to inspect/close through the app owner if confirmed disposable. |
| 49028 | codex.exe app-server, parent 9092 | Oct 12 13:51:45 | +1.19 CPU-s / 5.11s (~23% of one core) | 11,490 / 3,184 MB | High private memory, but latest CPU activity modest; not evidence of a retry spin in this sample. |
| 26972 | kenshi_x64.exe, parent 74724 | Oct 14 10:25:53 | +7.33 CPU-s / 5.11s (~143% of one core) | 5,052 / 2,027 MB | Expected active test game; user designated it to stay. |
| 97588 | llama-server.exe, parent 119180 | Oct 14 12:09:23 | +0.00 CPU-s | 6,873 / 5,093 MB | Idle in sampled interval; user designated model to stay. |
| 29152 | PowerShell private adapter host | Oct 14 12:11:49 | +0.00 CPU-s | 69 / 77 MB | Idle. |
| 24916 | gpulog.ps1 -Rig 5090 | Oct 12 18:24:21 | +0.05 CPU-s | 122 / 150 MB | No active spin evidence. |
| 60584 | paired-runner-supervisor.ps1 -Loop -IntervalSec 45 | Oct 13 22:36:44 | +0.00 CPU-s | 131 / 118 MB | Idle at sample. |
| 90704 | live-testing-waker.ps1 -Run | Oct 13 21:08:10 | +0.00 CPU-s | 126 / 130 MB | Idle at sample. |
| 61940 | python capture_server.py | Oct 12 23:44:25 | +0.00 CPU-s | 12 / 10 MB | Idle at sample. |

Older five-second comparison had PID 49028 +4.88 CPU-s, PID 36376 +1.98, PID 26972 +7.14, and llama PID 97588 +0.00. The changing CPU rates show workload variation, not a stable runaway loop for codex.exe; PID 36376 is the strongest current app-side candidate. The build producer PID 57304 was absent, so no live CPU/progress evidence supports treating it as the cause. The paired runner supervisor existed but consumed no CPU in the final window. No evidence identifies a duplicate retry loop or warrants stopping a harness process.

Recommended safe next action for the coordinator: inspect the owning ChatGPT window/task for renderer PID 36376 and close that specific disposable renderer/window through the application if it is the unwanted session. Do not stop PID 49028 (app-server) or either designated game/model process based on this evidence alone. No stop was issued by this auditor.

## Follow-up: app ownership and bounded quiet sample (2026-10-14)

Read-only 10.018-second sample, 18:54:49.212Z–18:54:59.230Z:

| PID | Owner/role | CPU delta | Private delta | Working-set delta | End private / WS |
|---:|---|---:|---:|---:|---:|
| 36376 | ChatGPT.exe Electron renderer, parent 9092 | +3.23 CPU-s (~32% of one core) | +11.8 MB | +4.0 MB | 4,640.7 / 4,266.4 MB |
| 49028 | codex.exe app-server, parent 9092 | +0.53 CPU-s (~5% of one core) | -1.0 MB | -0.6 MB | 11,484.3 / 2,760.9 MB |
| 49192 | codex-code-mode-host.exe, child of 49028 | +0.00 CPU-s | +0.1 MB | -0.2 MB | 31.7 / 53.6 MB |
| 9092 | ChatGPT.exe main process, parent 13740 | +0.58 CPU-s | -10.7 MB | -12.1 MB | 406.4 / 371.2 MB |

The renderer PID 36376 has no window title; its parent PID 9092 is the ChatGPT main process with window title `ChatGPT`. Process ancestry supports association with that app window but does not reveal an exact Codex thread/session. PID 49028 is a Codex app-server child of the same main process; its child PID 49192 is the code-mode host. It has 22 node.exe, 12 node_repl.exe, 16 cmd.exe and 34 conhost.exe descendants within the two inspected app trees, largely in longstanding cohorts from Oct 12 and Oct 14 12:10. Recent descendants (12:54–12:55) are one command-runner and its PowerShell/pwsh children; the sampled PID 49028 CPU is low and there is no snapshot evidence of a rapid retry/spawn loop. Child command lines were not printed.

The renderer's earlier >1-core five-second burst did not persist: in this 10-second interval it averaged about 32% of one core, while its private memory grew only 11.8 MB. The app-server's private/working set were effectively flat/slightly down, despite its large 11.5 GB private allocation. These short samples cannot establish a leak. Free physical RAM at 18:48:40Z was 9.65 GB.

Safe cleanup: if the ChatGPT window is unwanted, close the relevant conversation/window through the app UI and allow the app to reap its renderer; do not force-terminate PID 36376. Keep PID 49028 running while any Codex tasks depend on its app-server; if the user wants that task stopped, use the owning task/app control so its child processes can wind down cleanly. No stop or app/service change was made. The previous suspected build producer PID 57304 remained absent in the last inventory.

HANDOFF remains coordinator-owned per workspace instructions; parent coordinator should add this receipt summary to testing/HANDOFF.md.
