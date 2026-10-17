# Model comparison tests: how to run more

Built 2026-10-15 (Shay). Compares model and effort level on a task: same prompt to every cell, blind grading by two judges, cost and time from the transcripts. First result: `docs/model-test/2026-10-15-investigation-suite/` (36 runs: Haiku, Sonnet, Opus x low, medium, high, xhigh x 3 prompts; summary in `FINDINGS2.md`, every number in `FULL_TABLE.md`, raw rows in `runs.tsv`). That result drove the tier changes in `docs/MODEL_ROUTING.md`.

Tool: `tools/model-test/mt.py` (run it in WSL: `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- python3 /mnt/c/KenshiModding/tools/model-test/mt.py <cmd> ...`). It was self-tested against the first suite: `report` reproduces its tables exactly. The runs themselves are Agent calls made by the coordinator session; there is no script that starts agents.

## Rules that kept the first test valid
- Never use Fable. Never message a running run ("arm"); a run gets only its prompt file, which the router also prefixes with one `Routing:` line.
- Subagents cannot write files, so every run returns its report as its final message. `mt.py rec` pulls it out of the transcript afterwards.
- One run per cell, run in the same fixed order, foreground (`run_in_background: false`), so the coordinator is not woken by notifications and the order is the same for every cell.
- The task must not change the world: the investigation template is read-only (no edits, no restarts, SELECT only). If you test code-changing tasks, give every run its own copy or reset the state between runs (`state-check.sh`, below).
- Do not tell a run which model it is, and keep grader prompts identical for every report.

## 1. Create a suite
```
mt.py init /mnt/c/KenshiTestRuns/invest/<name>
```
This writes `suite.json`, `prompt1.txt`, `rubric.md`, `task.tmpl` into the folder. Edit them:
- `suite.json`: `models` (haiku|sonnet|opus), `efforts` (low|medium|high|xhigh), `prompts` (the prompt files, one per task), `judges` (model and effort; the first suite used Sonnet high and Opus high), `rubric`, `template`, and `extra_reports` for old reports to grade alongside the new ones (name -> path with `{n}` for the prompt number; the first suite used its two earlier cascade reports).
- `prompt<N>.txt`: the request, verbatim. Reuse the first suite's prompts only on the state they were written for (see "Reusing the first prompts").
- `rubric.md`: the five criteria are generic; write down, per prompt, what "answers every part of the request" means before any run.
- `task.tmpl`: the wrapper around the request; `{TICKET}` and `{PROMPT}` are filled in. The default is the read-only investigator wrapper. For another kind of task change the instructions and the required report sections, but keep the "return the report as your final message" rule.

Then `mt.py gen <dir>` writes `runs/<model>-<effort>-p<n>/prompt.md` for every cell and `order.txt`, and prints the Agent call to make.

## 2. Run the cells (coordinator session)
For each run in `order.txt`, one at a time, foreground:
- Agent `description`: `[case:bench] [ticket:BENCH-<run>] [model:<m>] [effort:<e>] <run>`
- Agent `prompt`: `Read <dir>\runs\<run>\prompt.md and follow it exactly.`
The `bench` case in `tools/automation/hooks/agent-router.ps1` takes model and effort from those tags; the ledger (`C:\KenshiTestRuns\ledger\agent-runs.tsv`) records the real model and effort. Then:
```
mt.py rec <dir> <run> <agentId> [q5h_before qweek_before q5h_after qweek_after]
```
`<agentId>` is in the Agent result. Optional quota numbers are whole percents from the usage view (read before the first run of a cell and after it; they are too coarse to use per run, so cost comes from the transcript). `rec` saves `runs/<run>/report.md`, then appends one row to `runs.tsv`: wall seconds, tool calls, tokens, token cost at the official prices (`tools/automation/prices.json`, keep it current), report size, citation count and `violation_flags` (runs that issued a mutating command or wrote a file; look at each flag, most are reads or /tmp scratch). `--dry` prints without saving.

Haiku and Sonnet runs at low effort finish in about a minute; Opus xhigh and Sonnet xhigh take 9 to 14 minutes. All 36 first-suite runs took 190 minutes and $32.67 of tokens.

## 3. Grade blind
```
mt.py blind <dir>
```
Per prompt it shuffles every report (plus `extra_reports`) into `blind/P<n>/R01.md ...` with ticket and run names scrubbed, stores the secret key in `keys/P<n>.json` (never show it to a grader), and writes a grader prompt per judge and prompt in `grades/G-<judge>-p<n>.md`. For each judge and prompt run one Agent, foreground:
- `description`: `[case:bench] [ticket:BENCH-grade-<model>-<effort>-p<n>] [model:<m>] [effort:<e>] grade p<n>`
- `prompt`: `Read <dir>\grades\G-<model>-<effort>-p<n>.md and follow it exactly.`
Save each final message: `mt.py extract <agentId> <dir>/grades/<model>-<effort>-p<n>.txt`. A grader returns one line per report: `Rxx | root=N evid=N fix=N comp=N hon=N | total=NN | false=K | note`, a ranking and the key false claims. The two judges in the first suite agreed at r = 0.92 and neither favoured its own model family. Add a third judge if a result is close.

## 4. Read the result
```
mt.py report <dir>              # every config and prompt
mt.py report <dir> --min 20     # drop configs below 20 on any prompt
```
It prints a markdown table per config: quality for each prompt and the mean (out of 25, mean of the judges), cost, seconds and false claims per prompt, cost per task and minutes per task, then the judge agreement and total spend. Paste it into `FINDINGS.md` in the suite folder together with the caveats: one run per cell and a handful of prompts means each mean is about +/-3 points, and a single prompt can swing up to 10. Quality here is judged on evidence and fix specificity, not by applying the fix in the game.

## 5. Keep the result
Copy the suite folder's findings, `runs.tsv`, prompts, rubric, `grades/*.txt`, `keys/` and `runs/*/report.md` into `docs/model-test/<date>-<name>/` (as done for the first suite), because `C:\KenshiTestRuns` is swept for old items. Say in the commit or in `MODEL_ROUTING.md` which tier changes follow from it.

## Comparing more models or prompts later
- More prompts: add `prompt4.txt` and list it in `suite.json`; re-run `gen`; only the new cells need runs. For a fair comparison with the old suite, keep the same rubric, judges, wrapper and template.
- More models or efforts: add them to `models`/`efforts`; there is a Haiku 5.5, Sonnet 5.5 and Opus 5.5 today, and the bench tags accept `haiku|sonnet|opus` and `low|medium|high|xhigh`. Add a new model alias to the allowed list in `agent-router.ps1` (the `bench` branch) and to `tools/automation/prices.json` first.
- A fresh suite is usually cheaper than extending the old one: put the old reports in `extra_reports` so the judges rank them together with the new ones.
- Include a few earlier reports every time as an anchor, so scores stay comparable across suites.

## Reusing the first prompts
The three prompts are tied to bugs that are now fixed (Tengu's bio and refusal text, Mouse's travel loop, the slow first reply). Running them again on today's code would be a different test, because the evidence they asked about is gone. To re-run them on the original state: restore the server tree from `refs/snapshots/fresh-20261014` in `/var/www/html/StobeServer`, re-insert the five bare `Tengu` rows and the 85663 traits from the dumps in `C:\KenshiTestRuns\invest\fixes\backup\FIX-server\`, keep the validated `Stobe.dll` (sha256 `E64C6593...1A9A`), and keep the logs from that session. Easier: write new prompts against current open issues.

## Frozen world (2026-10-14)
Instead of rebuilding the 14 Oct state in the live system, there is a frozen copy of what prompts 2 and 3 ran against: `C:\KenshiTestRuns\invest\frozen-2026-10-14` (WSL `/mnt/c/KenshiTestRuns/invest/frozen-2026-10-14`), read-only, never edited. New models can be tested on it and compared with the 36 reports of the first suite without touching the live game folder, server tree, database or logs.

What FROZEN contains (full detail and the not-exact list in its `README.txt`, the database part in `README-data.txt`):
- `server\` the server code of the git ref `refs/snapshots/fresh-20261014` (tree `25c343ea83984be3dcb4eb3418ca90655a3167f9`, 1113 files, 397 MB; exact, every blob hash equals the ref).
- `native\src` the Stobe.dll C++ source as of 14 Oct, rebuilt from /root/STOBE-src minus the nine files the fixers added plus the seven FIX-native backup copies; `native\out\Stobe.dll` the validated DLL (sha256 `E64C6593...1A9A`); `native\build\` `build_portable.bat` and `build-stobe.ps1` (cd62be8).
- `gamefiles\` the small files of the game's `mods\Stobe` folder (ini, status, request, goal files); five of them are marked "later than the test" in the README (the ini and four flag/request files changed after 14 Oct 20:26).
- `logs\` the server log `stobeserver.log` plus context_sent_to_llm, output_from_llm, chat_llm_full_capture, audit_request, output_to_plugin and relationship_worker logs, all cut at the test start (2026-10-15 02:26 UTC) and the PostgreSQL database `stobe_frozen` (a copy of the tables the reports used, with the Tengu bio rows and core_npc_master 85663 restored to their 14 Oct values); both built by the data agent.
- `MANIFEST-code.txt`, `MANIFEST-data.txt`, `verify.sh` (last line `FROZEN OK` or `FROZEN DIFF <items>`): `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiTestRuns/invest/frozen-2026-10-14/verify.sh`. Run it before and after a test batch.

Use it:
- Take the ready suite folder `C:\KenshiTestRuns\invest\suite3-frozen` (or copy it). Its `suite.json` has `"frozen": "C:\\KenshiTestRuns\\invest\\frozen-2026-10-14"` and `"template": "task-frozen.tmpl"`, `prompts` `prompt2.txt` and `prompt3.txt` (exact copies of `docs/model-test/2026-10-15-investigation-suite/prompt2.txt` and `prompt3.txt`) with `"prompt_numbers": [2, 3]` so the runs keep the ids `<model>-<effort>-p2` and `-p3` of the first suite. Fill `models` and `efforts` with the cells to run, then `mt.py gen`, run the cells, `mt.py rec`, `mt.py blind`, grade, `mt.py report` as in the sections above.
- `gen` fills `{FROZEN}` (Windows path) and `{FROZEN_WSL}` (WSL path) in the template. `task-frozen.tmpl` keeps every rule of `task.tmpl` but tells the run that the world is a frozen copy: it reads the server code, native source, game files and log under FROZEN, queries only the database `stobe_frozen` (SELECT only), and must not read `/var/www/html/StobeServer`, `/root/stobe-work`, `/root/STOBE-src`, `C:\StobeBuild`, `D:\Steam\steamapps\common\Kenshi`, the live database `stobe` or `pending-fixes`; if the frozen copy lacks something it says so in the report.
- `rec` on a suite with a `frozen` key also flags (in the printed flags and in `violation_flags` of `runs.tsv`, prefix `LIVE`) every Bash, PowerShell, Read, Glob or Grep call that touches one of those live paths or `-d stobe` (database `stobe`, not `stobe_frozen`). Look at each flag; a run with LIVE flags saw the present system, not the 14 Oct one, and its score is not comparable.
- `blind` and `report` take `--prompts 2,3` to use only those prompt numbers (`report` then prints only those prompts, their mean, and the totals of only those runs). `suite.json` may carry `prompt_numbers` when a suite uses only some prompts of an older one.

Prompt 1 (slow first reply) is dropped: its evidence was in the game-side `stobe.log` of 14 Oct, which is gone (the file now is from 15 Oct), so it cannot be reproduced. Only prompts 2 (Tengu thought she was Emperor Tengu and "I haven't agreed to that job") and 3 (Mouse's travel loop) are fully testable.

What is not exact: the C++ source was rebuilt from backups and not recompiled (evidence: every source file is older than the DLL build 14 Oct 19:37, and the DLL has none of the markers added later); five game files are later than the test; the database and log depend on the cut-off 2026-10-15 02:26 UTC and on the data agent's list of tables (see `README-data.txt` for the tables without timestamps and the queries compared with the reports). Never claim an exact reproduction in a write-up; say "frozen copy".

Comparison rule: use the same rubric (`rubric.md` copied into the suite), the same two judges (Sonnet high and Opus high), and grade the new reports together with the 14 Oct reports as anchors: `extra_reports` in `suite3-frozen/suite.json` lists all 12 old model x effort reports plus the two cascade reports (`old-<model>-<effort>`, `old-suite1-A`, `old-suite1-B`) for P2 and P3, so every grader ranks old and new anonymously in one list. Report with `mt.py report <dir> --prompts 2,3`. The old and new reports are not the same world to the last byte (see above), so a difference of a few points is noise; one run per cell means each mean is about +/-3 points.

## State check (only when a run could change state)
`MT_DIR=<dir> bash tools/model-test/state-check.sh <out> --write-baseline` records the server tree, live PHP, `Stobe.dll`, ini, campaign and session fingerprints in `<dir>/baseline.env`; run it without the flag before and after each run (last line `STATE OK` or `STATE DIFF <items>`). The first suite used it to prove the read-only runs left the state untouched. It is specific to this machine's Stobe server and DLL.

## Not covered
- The first suite never tested a task that applies a code change, a mechanical lookup, or max effort, so the generator, reader and coordinator rows in `MODEL_ROUTING.md` are judgement calls.
- The old cascade arm (Haiku investigates, a verifier checks) cannot be re-run: the verifier agent and the router gates were removed on 2026-10-15; its result is in `docs/model-test/2026-10-15-investigation-suite/FINDINGS.md`.
