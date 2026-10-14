# 5090 Stobe backend source inventory (read-only)

State: **PREPARED / NOT EXECUTED**. This packet collects narrowly allowlisted provenance metadata from the documented 5090 WSL source locations. It does not read source contents, credentials, environment dumps, saves, logs, or configuration; it does not contact a backend, database, game, or service.

## Pinned route

- Host alias: `5090`, enforced as Windows hostname `DESKTOP-JFLPK99` before WSL starts.
- Transport: `run.ps1` checks `$env:COMPUTERNAME` equals `DESKTOP-JFLPK99`, then invokes `C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1`, which runs `wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding -- bash -s` and sends this exact body on stdin.
- Documented candidate roots, from `docs/STOBE_TESTING_GUIDE.md`:
  - `/var/www/html/StobeServer` (documented live checkout)
  - `/root/stobe-work/ss-merge` (documented merge checkout)
- Explicit exclusions: shared service ports `:8083` and `:18083`; no service start/stop, HTTP, PostgreSQL, SSH to 4080, game, or save operation.

`run.ps1` enforces the host binding, based on the documented physical host identity; this is not merely a label emitted by Bash. It aborts before WSL invocation on any other hostname. The Bash body emits `FAIL` for a missing root, a symlink/canonical-path mismatch, an unexpected repo root, or unavailable metadata. Every hashed file must resolve to the exact allowlisted path under its pinned root.

## Exact command (not run during packet preparation)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\testing\live-stobe-queue\packets\5090-source-inventory-20261014\run.ps1
```

## Allowed metadata

For each exact root: canonical path and existence; Git worktree yes/no, canonical Git root, and commit; only the manifest filenames listed in `inventory.sh` and their SHA-256; presence and SHA-256 for the small required-source allowlist in `inventory.sh`. File contents and unlisted filenames are never emitted. A non-Git tree is reported as `repo=no`; this packet does not claim source trust or release suitability from presence or hashes alone.

## Local checks

`selftest.ps1` validates the host gate, packet's static allowlists, exact route/command, forbidden-operation exclusions, and shell syntax using local fixtures only. It does not call WSL, SSH, a device, or any service.
