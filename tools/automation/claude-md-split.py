#!/usr/bin/env python3
"""claude-md-split.py: build docs/claude-md-archive/ from the ORIGINAL CLAUDE.md snapshot (claude-md-trim, 2026-10-15).

Reads docs/claude-md-archive/CLAUDE.md.original (line-for-line copy of the CLAUDE.md being trimmed) and writes
  - one archive page per topic (original lines moved verbatim, in original order, nothing paraphrased)
  - CLAUDE.md.proposed (short core: verbatim original lines spliced in via {{L<n>}} + condensed pointers)
  - RULE_CHECKLIST.md (every original line -> new location + enforcement flag)
Run:  python -I tools/automation/claude-md-split.py   then   python -I tools/automation/claude-md-verify.py
Does NOT touch CLAUDE.md, settings or hooks. LF endings, UTF-8 without BOM.
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ARC = os.path.join(ROOT, "docs", "claude-md-archive")
ORIG = os.path.join(ARC, "CLAUDE.md.original")

# archive page -> (title, intro, original line numbers, 1-based)
PAGES = {
    "coordinator-session.md": ("Coordinator / session rules (relay, handoff, GOAL, subagents)",
        "Read before: starting a session as coordinator, handing off, spawning agents, deciding what to test.",
        [10, 12, 13, 15, 16, 37, 38, 39]),
    "speed-and-rigs.md": ("Speed, waker, lanes, rig uptime (2026-10-08 .. 2026-10-11)",
        "Read before: touching runners/lanes/queues/wakers, rig idle questions, speed or GPU work.",
        [9, 18, 19, 21, 22, 23, 24, 25, 26, 58]),
    "animation-fp.md": ("Animation / KenshiFP viewmodel / take discipline (CLOSED, historical)",
        "Animation work is closed (see top banner of CLAUDE.md). Read only if animation/FP filming resumes.",
        [20, 30, 31]),
    "pg.md": ("Profession Gear (PG), finished",
        "Read only if PG balance work is ever reopened.",
        [32, 55]),
    "test-discipline.md": ("Test discipline: batching, RESULT lines, efficiency, clean-up",
        "Read before: running or judging a batch, writing a test wrapper, cleaning up after a run.",
        [17, 27, 28, 29, 76, 77]),
    "test-bed.md": ("Test bed: loop, saves, commands, pre-flight, safety",
        "Read before: launching the game for tests or writing scenarios.",
        [69, 70, 71, 72, 73, 74, 78, 79]),
    "stobe-server-tests.md": ("STOBE server on/off, NPC info panel, server fixes",
        "Read before: any STOBE server change or deciding whether the LLM-backed server should run.",
        [14, 33, 75]),
    "ram-and-gfx.md": ("RAM budget, WSL cap, graphics mods, windowed/DISPLAY2 launches",
        "Read before: RAM/vmmem problems, launching on the 5090, handing the PC back to Shay.",
        [34, 35, 36]),
    "where-things-are.md": ("Where things are: repos, builds, installs, logs, machines",
        "Read before: building/installing a DLL, finding logs, using server/harness/4080.",
        [45, 46, 51, 52, 53, 54, 56, 57]),
    "model-routing.md": ("Model routing and validation (2026-10-14/15)",
        "Read before: spawning a subagent or changing models.",
        [61, 62, 63, 64, 65, 66]),
}

# lines kept verbatim in the core
CORE_VERBATIM = [1, 3, 5, 6, 8, 11, 40, 41, 42, 44, 47, 48, 50, 60, 68, 81,
                 82, 83, 84, 85, 86, 87]   # lines >= the "## Large programs" heading are core too (computed in main())

# enforcement flags: line -> (kind, what)   kind in HOOK / TOOL / MEMORY / POLICY
ENF = {
    11: ("TOOL", "tools/automation/session-start.ps1 (prints marker, HANDOFF, statuses, waker status)"),
    12: ("HOOK", "context-meter hook + .claude/context-meter.project.ps1 (300k handoff steps); tools/automation/handoff-ready.ps1 (refuses stale HANDOFF); agent-status.ps1; kenshi-waker-guard.ps1 Stop blocks STOPPED-CONTEXT/FAILED statuses"),
    13: ("POLICY", "testing/HANDOFF.md is the state file"),
    14: ("TOOL", "tests/ingame/stobe/STOBE-NPCPANEL.sh"),
    17: ("TOOL", "tools/automation/event-wait.sh, event-sweep.sh, run-batch.sh (refuses without dry run), dryrun.sh"),
    18: ("TOOL", "tools/automation/lane-waker.sh, lane-watch.ps1, rig-health.sh; Stop hook also blocks on IDLE-GAME/non-OK health"),
    19: ("HOOK", ".claude/settings.json Stop + PreToolUse -> tools/automation/hooks/kenshi-waker-guard.ps1 (waker required, sleep > 120 s denied, 5090 idle reason, 4080 idle via rig4080-state.ps1)"),
    20: ("TOOL", "take preflight, tools/automation/review-pack.py, queue\\5090.next/4080.next (Stop hook blocks when missing/> 6 h)"),
    21: ("TOOL", "tools/automation/dryrun.sh, kfp-pipeline.sh, install-dll.ps1 -Staged"),
    22: ("TOOL", "tools/automation/rig-runner.ps1, kenshi-gfx.ps1, kfp-pipeline.sh, wait-event.ps1"),
    23: ("TOOL", "tools/automation/rig-watchdog.ps1 (ALERT-<rig>.txt; rig-health.sh and Stop hook block on ALERT)"),
    24: ("TOOL", "runner preempt/queue rules in tools/automation/rig-runner.ps1"),
    25: ("TOOL", "runner preempt/queue rules in tools/automation/rig-runner.ps1"),
    26: ("POLICY", "standing order; speed-scout agent"),
    28: ("TOOL", "stobe-fight-lib.sh verdict(), run-batch.sh, batch-excerpts.sh"),
    30: ("TOOL", "fp-viewmodel.sh VMQUICK (animation closed)"),
    31: ("TOOL", "components/KenshiFP/animlab/corpus.sh (animation closed)"),
    33: ("TOOL", "tools/automation/stobe-server.sh on|off; wsl-restart.ps1"),
    34: ("TOOL", "tools/automation/wsl-restart.ps1, wsl-cache-trim.sh, gfx-mods.sh"),
    35: ("TOOL", "tools/automation/kenshi-ctl.ps1 launch (windowed, DISPLAY2); gfx-mods.sh on"),
    36: ("TOOL", "tools/automation/wsl-voice.sh, gfx-mods.sh"),
    37: ("POLICY", "coordinator decision"),
    56: ("TOOL", "tools/automation/install-dll.ps1 (SHA256 check; allowlisted in .claude/settings.json)"),
    58: ("TOOL", "tools/automation/rig4080-state.ps1, rig5090-state.ps1"),
    60: ("HOOK", "model-routing section heading"),
    61: ("HOOK", ".claude/settings.json model + effortLevel"),
    62: ("HOOK", "tools/automation/hooks/agent-router.ps1 (PreToolUse Agent) + tools/automation/model-policy.json + agent-ledger-post.ps1 (PostToolUse Agent)"),
    63: ("POLICY", "no verifier/gates (router no longer gates)"),
    64: ("TOOL", "docs/MODEL_TEST.md, tools/model-test/mt.py"),
    69: ("TOOL", "kenshi-ctl.ps1 lock|release|launch|stop"),
    70: ("TOOL", "tests/ingame/stobe/fullbase-guard.sh"),
    73: ("TOOL", "tools/stobe-goal-watch.sh"),
    76: ("HOOK", "tools/automation/testruns-sweep.ps1 + Stop hook blocks on STALE > 24 h"),
    77: ("TOOL", "tools/automation/testruns-sweep.ps1"),
    82: ("POLICY", "permission system still wins; AskUserQuestion denied in .claude/settings.json"),
    89: ("HOOK", "large-programs section heading"),
    90: ("TOOL", "program ledger C:\\KenshiTestRuns\\programs\\<name>.json; session-start.ps1 prints it"),
    91: ("HOOK", "tools/automation/coord-heartbeat.ps1 (PostToolUse * hook) + coord-supervisor + Stop hook"),
    92: ("TOOL", "docs/WP_SIZING.md, codemap.sh, AGENT_PROMPTS.md standard block"),
    94: ("HOOK", ".claude/settings.json Stop + PreToolUse -> kenshi-waker-guard.ps1"),
    44: ("POLICY", "git section heading"),
    47: ("POLICY", "commit identity (repo-local user.email); check before committing"),
    48: ("POLICY", "one commit per fix, push after commit"),
}

# core lines that are condensed pointers rather than verbatim (line -> note)
CONDENSED_IN_CORE = {9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
                      33, 34, 35, 36, 37, 38, 39, 45, 46, 51, 52, 53, 54, 56, 57, 58,
                      61, 62, 63, 64, 65, 66, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79}
IN_CORE_WITH_POINTER = {30: "banner (closed)", 31: "banner (closed)", 32: "pointer only (PG finished)", 55: "pointer only (PG finished)"}

CORE = r"""{{L1}}

{{L3}}

{{L5}}
{{L6}}

Short core. All other rules moved verbatim to `docs/claude-md-archive/` (index at the bottom; rule-by-rule map in `RULE_CHECKLIST.md` there): read the named page before the matching task.

## Current program
- **NPC immersion 26 (imm26):** read `testing/NPC_IMMERSION_26_HANDOFF.md` (+ `NPC_IMMERSION_26_TESTS.md`) and `testing/HANDOFF.md` "Right now". 4080 only, all server/DLL changes OK, 5090 untouched until Shay says.

{{L8}}
{{L11}}
- **State:** `testing/HANDOFF.md` is the live state file; update "Right now" the moment an agent/batch starts or finishes or a build installs. Context-limit handoff: follow the context-meter hook steps exactly (`handoff-ready.ps1`). Every subagent keeps `C:\KenshiTestRuns\agents\<name>.status` current via `tools/automation/agent-status.ps1 <name> RUNNING|DONE|FAILED|STOPPED-CONTEXT "<task>" "<step>" "<outputs>" "<next>"`.
- **Shay:** messages for him go by SendMessage to his relay session; never block on a question (AskUserQuestion is denied): ask in the final text and keep working. Contact him only for real decisions, asked together once; ONE final summary.
- **GOAL:** the coordinator builds, tests, validates and fixes everything itself; build any missing handler/command/driver, never report "blocked / needs setup"; loop test -> fix -> build -> install -> retest.
- **Speed:** fix every snag at its root the same hour (tooling fix + selftest + commit), use both rigs and GPUs, split new tasks into parallel agents at spawn, agents never override Shay's orders, record every tooling change where the next agent reads it.
- **Batches and wakers:** many tests per launch as a detached `run-batch.sh` job (dry run first); `touch C:\KenshiTestRuns\inflight\<name>` while anything is in flight and keep `bash tools/automation/event-wait.sh [--batch <out>]` running in the background; HEALTH STALL / LANE STUCK = fix the root that minute; queues never run dry; no rig idle > 2 min while work exists (`kenshi-ctl.ps1 idle|idle4080 "<reason>"`).
- **Token use:** grep/tail/line ranges, never whole large files or logs; one `RESULT <row> PASS|FAIL <evidence>` line per test row, open only a FAIL's `excerpt=` file.

## Rigs, STOBE server, RAM
- **5090 (this PC):** Kenshi + WSL (`DwemerAI4Skyrim3`); launches windowed on DISPLAY2 via `kenshi-ctl.ps1 launch`, background, never the Samsung display, never focus the game. Shay gaming = zero 5090 use. Before Shay plays: `bash C:/KenshiModding/tools/automation/gfx-mods.sh on`.
- **4080** (`ssh 4080`, `C:\KAH\ctl.ps1`, lock owner `rig4080`, `handoff/4080-test-rig.md`): second harness/KenshiFP rig, no Stobe; run 4080 and 5090 parts as parallel jobs; never compare performance across machines.
- **STOBE server:** `bash tools/automation/stobe-server.sh off` for all non-STOBE work (LLM credits), `on` only for a STOBE batch, `off` after; remind Shay in the final summary to turn it on and run `gfx-mods.sh on`. RAM/WSL cap/graphics-mod details: `ram-and-gfx.md`.

{{L44}}
- Server repo `shaylanger/StobeServer` is committed in the live tree `/var/www/html/StobeServer` (`git push origin HEAD:stobe`, no branch switching); native repo `shaylanger/Kenshi-Stobe-Custom` = this folder (`main`).
{{L47}}
{{L48}}

{{L50}}
- **Server:** WSL `DwemerAI4Skyrim3`, live tree + merge copy `/root/stobe-work/ss-merge`: patch BOTH; back up -> stage -> `php -l` -> test -> deploy both -> commit/push; offline `stobe-tests` must pass before the next game batch.
- **Builds/installs:** `tools/automation/build-stobe.ps1`, `kfp-pipeline.sh`, harness `build.bat`; install with `tools/automation/install-dll.ps1 Stobe|KenshiFP|Harness|ProfessionGear` (Kenshi closed). Logs, repos, PG: `where-things-are.md`.

{{L60}}
- Coordinator = Sonnet high; each subagent's model/effort comes from `tools/automation/model-policy.json` via the Agent router hook; start each Agent description with `[case:<name>]`; bug or odd behaviour -> `[case:investigate]` first; failed attempt -> retry up to 3x, then `debug`, then `escalate`. Details: `model-routing.md`.

{{L68}}
- Loop: `kenshi-ctl.ps1 launch -Save <save>` -> `stobe-auto wait-world` -> pre-flight -> batch -> check real game state -> `kenshi-ctl.ps1 stop` -> fix -> build -> install -> relaunch. Test only on `kah-*` copies of `C:\KenshiTestFixtures\` (`FIXTURES.md`), never Shay's saves; `fullbase-guard.sh` after every Full-Base load.
- A pass = real game state changed, never just words; never weaken an assertion; no unchanged retries. Clean up after EVERY batch (`testruns-sweep.ps1`; the Stop hook blocks on > 24 h); never delete `corpus\`, `inflight\`, `game.lock`, fixtures.
- Git Bash mangles `/mnt/...`: use `wsl.exe ... bash -s <<'EOF'` or `MSYS_NO_PATHCONV=1`; WSL python3, not Windows python3. Details: `test-bed.md`, `test-discipline.md`.

{{L81}}
{{L82}}
{{L83}}
{{L84}}
{{L85}}
{{L86}}
{{L87}}
{{L40}}
{{L41}}
{{L42}}

<!-- LARGE-PROGRAMS-SLOT-BEGIN: this block may be replaced later by docs/WP_SIZING.md section 8 "PROPOSED CLAUDE.MD TEXT" (written by another agent). Keep the heading and the waker guard bullet below. -->
{{LPBODY}}
<!-- LARGE-PROGRAMS-SLOT-END -->
{{TAIL}}

## Archive index (read the page for the task; each page holds the original text verbatim)
- `docs/claude-md-archive/coordinator-session.md`: relay session, session continuity, GOAL, test index, subagent policy, naming, no manual validation.
- `docs/claude-md-archive/speed-and-rigs.md`: speed rules, lane waker, stay-reachable/idle rules, speed plans, rig uptime, GPU use, machines.
- `docs/claude-md-archive/test-discipline.md`: batching + event wait, token-light tests, test efficiency, clean-up rules.
- `docs/claude-md-archive/test-bed.md`: test loop, saves/fixtures, commands, pre-flight, safety, crash dumps, Git Bash gotchas.
- `docs/claude-md-archive/stobe-server-tests.md`: STOBE server on/off (credits), NPC info panel, server-fix rule.
- `docs/claude-md-archive/ram-and-gfx.md`: RAM budget, WSL cap, voice services, graphics mods, windowed DISPLAY2 launches.
- `docs/claude-md-archive/where-things-are.md`: repos, builds, installs, logs, machines.
- `docs/claude-md-archive/model-routing.md`: coordinator model, subagent tiers, no cascade, retry ladder.
- `docs/claude-md-archive/animation-fp.md`: animation/KenshiFP take discipline, viewmodel builds, animlab (CLOSED; only if animation resumes).
- `docs/claude-md-archive/pg.md`: Profession Gear validation gate and repo (finished).
- `docs/claude-md-archive/RULE_CHECKLIST.md`: every original rule with its new location and enforcement flag.
"""


def main():
    with open(ORIG, encoding="utf-8", newline="") as f:
        text = f.read()
    if "\r" in text:
        sys.exit("original has CR characters; refusing")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    L = lambda n: lines[n - 1]

    lp = next(i for i, ln in enumerate(lines, 1) if ln.startswith("## Large programs"))
    wk = next(i for i, ln in enumerate(lines, 1) if ln.startswith("- **Waker guard"))
    tail_nums = [i for i in range(lp, len(lines) + 1) if lines[i - 1].strip() and (i >= wk or lines[i - 1].startswith("- **Agent handoff guards"))]
    body_nums = [i for i in range(lp, len(lines) + 1) if lines[i - 1].strip() and i not in tail_nums]
    CORE_VERBATIM.extend(body_nums + tail_nums)
    assigned = {}
    for page, (_, _, nums) in PAGES.items():
        for n in nums:
            assert n not in assigned, n
            assigned[n] = page
    for n in CORE_VERBATIM:
        assert n not in assigned, n
        assigned[n] = "CORE"
    for n, ln in enumerate(lines, 1):
        if ln.strip() and n not in assigned:
            # lines moved only as pointers: find them in the page lists below
            pass
    # lines 30,31,32,55 etc are in PAGES; check coverage
    missing = [n for n, ln in enumerate(lines, 1) if ln.strip() and n not in assigned]
    if missing:
        sys.exit("unassigned lines: %s" % missing)

    for page, (title, intro, nums) in PAGES.items():
        out = ["# " + title, "", intro,
               "Moved verbatim from CLAUDE.md (original line numbers in the comment before each block). Nothing here is paraphrased.", ""]
        prev = None
        for n in sorted(nums):
            if prev is None or n != prev + 1:
                out.append("<!-- original CLAUDE.md line %d -->" % n)
            out.append(L(n))
            prev = n
        with open(os.path.join(ARC, page), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(out) + "\n")

    nl = chr(10)
    core = CORE.replace("{{LPBODY}}", nl.join(L(i) for i in body_nums)).replace("{{TAIL}}", nl.join(L(i) for i in tail_nums))
    import re
    core = re.sub(r"\{\{L(\d+)\}\}", lambda m: L(int(m.group(1))), core)
    with open(os.path.join(ARC, "CLAUDE.md.proposed"), "w", encoding="utf-8", newline="\n") as f:
        f.write(core)

    # checklist
    rows = ["# CLAUDE.md before/after rule checklist (claude-md-trim, 2026-10-15)", "",
            "Original = `docs/claude-md-archive/CLAUDE.md.original` (%d lines, %d bytes; snapshot of CLAUDE.md taken 2026-10-15)." % (len(lines), len(text.encode("utf-8"))),
            "Every non-empty original line is listed. Location: CORE-VERBATIM = identical line in `CLAUDE.md.proposed`; "
            "CORE-CONDENSED = short rewrite in the core AND the original line verbatim in the named archive page; "
            "ARCHIVE = original line verbatim in the named archive page only (core has at most an index pointer).",
            "Enforced: HOOK = a Claude Code hook in `.claude/settings.json`/context-meter; TOOL = a script/tool that implements or checks the rule; "
            "POLICY = rule text only (plus memory). The verify script confirms the named tool files exist.", "",
            "| Line | Rule (start of line) | Location | Enforced by |", "|---|---|---|---|"]
    for n, ln in enumerate(lines, 1):
        if not ln.strip():
            continue
        s = ln.strip().replace("|", "/")
        s = s[:70] + ("..." if len(s) > 70 else "")
        page = assigned[n]
        if page == "CORE":
            loc = "CORE-VERBATIM"
        elif n in CONDENSED_IN_CORE:
            loc = "CORE-CONDENSED + archive `%s`" % page
        else:
            loc = "ARCHIVE `%s`" % page
            if n in IN_CORE_WITH_POINTER:
                loc += " (core: " + IN_CORE_WITH_POINTER[n] + ")"
        kind = ENF.get(n)
        enf = "%s: %s" % kind if kind else "POLICY"
        rows.append("| %d | %s | %s | %s |" % (n, s.replace("`", "'"), loc, enf.replace("|", "/")))
    with open(os.path.join(ARC, "RULE_CHECKLIST.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rows) + "\n")
    print("wrote %d pages + CLAUDE.md.proposed (%d bytes) + RULE_CHECKLIST.md" % (len(PAGES), len(core.encode("utf-8"))))


if __name__ == "__main__":
    main()
