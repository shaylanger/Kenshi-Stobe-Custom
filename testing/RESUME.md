# How to pick up the work

Read `CLAUDE.md`, then `testing/HANDOFF.md` ("Current state": what is running, builds, mod ownership, status, next work,
run recipes). There are no separate handoff files. Roles/loop/scenario format: `testing/README.md`; open rows:
`MASTER_TEST_PLAN.md`; newest run log `archive/test-run-*-m<n>.md`.

Before doing anything: `powershell -File tools/automation/kenshi-ctl.ps1 status` (is Kenshi running / who holds the lock)
and `ssh 4080 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\ctl.ps1 status'`.

The old 2026-10-02/03 progress log that lived here: `git log -p testing/RESUME.md`.
