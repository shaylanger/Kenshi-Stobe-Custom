# status-count-check (pilot 2, 2026-10-16)

`status-count-check.py` compares the numeric claims in an agent's status file (`2 PASS`, `13 rows`, `1 escalated` ...) with the agent's ledger and prints `MISMATCH` lines (exit 1). Read-only. Windows python or WSL python3. Selftest: `python3 -I tools/automation/status-count-check.py --selftest` (true + false case; the false case is the real pilot-1 claim "2 PASS ... 1 escalated" against 1 PASS / 13 ESCALATE lines).

    python3 -I tools/automation/status-count-check.py <agent> [--pilot-dir D | --csv F] [--no-asof]     one agent
    python3 -I tools/automation/status-count-check.py --scan --quiet --hours 3                           every recent status file with a ledger

Ledger = pilot `verdicts.csv` (agent found through `events.log agent=`), else the agent's TESTS marks in git (`imm26 <agent>: <row> <STATUS>`). Definitions are in the script header.

## Waker wiring (candidate, NOT swapped in: event-wait.sh is running)
`event-wait.sh.candidate` = the current `event-wait.sh` + one block (every `EW_COUNT_EVERY`=300 s it runs `--scan --quiet`; a NEW mismatch wakes once with `EVENT STATUS-COUNT MISMATCH ...`; `EW_COUNTCHECK=0` switches it off). Selftests on the candidate: `bash tools/automation/event-wait-statuscount-selftest.sh` (4/4), `event-wait-digest-selftest.sh` (42/42), `event-wait-batch-selftest.sh` (26/26).

Swap (only in the gap between two waker runs, i.e. right after a wake and before restarting it; never while one runs):

    cd /c/KenshiModding/tools/automation && cmp -s event-wait.sh event-wait.sh.candidate || { cp event-wait.sh event-wait.sh.bak-pre-statuscount && cp event-wait.sh.candidate event-wait.sh && bash -n event-wait.sh && echo SWAPPED; }

If `event-wait.sh` changed since the candidate was made (diff shows more than the STATUS COUNTS block), re-apply only that block (anchor `# OPERATOR WARN (handover overlap)`).
