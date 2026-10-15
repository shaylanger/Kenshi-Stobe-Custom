# STOBE server on/off, NPC info panel, server fixes

Read before: any STOBE server change or deciding whether the LLM-backed server should run.
Moved verbatim from CLAUDE.md (original line numbers in the comment before each block). Nothing here is paraphrased.

<!-- original CLAUDE.md line 14 -->
- **NPC info panel (2026-10-05, done):** Stobe `\` hotkey / chat "Info" button shows what the speaking char knows about the chat target (no LLM call); built into Stobe since DAF1390F, all rows verified in game. Details: `docs/NPC_INFO_PANEL.md`; test `tests/ingame/stobe/STOBE-NPCPANEL.sh`.
<!-- original CLAUDE.md line 33 -->
- **STOBE server off for non-STOBE work (Shay, 2026-10-10: OpenRouter/DeepInfra credits were being used by FP animation/combat tests):** the Stobe mod in the running game sends NPC events to the server, which calls the LLM. KenshiFP/harness/animlab batches run with `tools/automation/stobe-server.sh off` (WSL root; stops apache2 + the background processor, WSL keeps running); turn it `on` only for a STOBE batch and `off` again after. FP tests only read stobe.log optionally (raid lines). Off since 2026-10-10 15:40; the 4080 has no Stobe (checked). **Restore checklist for the final summary to Shay (he asked to be reminded):** remind him to turn STOBE back on (`stobe-server.sh on`, or it comes back by itself at the next WSL start via /etc/start_env) and to run `gfx-mods.sh on` before playing.
<!-- original CLAUDE.md line 75 -->
- Server fixes: stage in a copy, add a regression check (`tests/negotiation_engine_regression.php` etc.), confirm it fails without the fix, deploy both trees, `stobe-rotate-logs`, commit/push; then `stobe-tests` (offline) must pass before the next game batch, so a server bug never costs a game run.
