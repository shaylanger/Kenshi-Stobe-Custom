# imm26-sfTrav: deterministic travel PROPOSE (kind Travel for the sfO seam)

Sibling of imm26-sfO (`inject-propose.sh`, Hunt / ClearGroup). Separate seam, marker and anchor, so sfO and its queued scripts are untouched.

## What it does
`inject-travel.sh <lane> <npc|any> [destination] [--kind same_route|detour|guide] [--leader npc|player] [--row ID] [--ttl SEC] [--keep-text]` writes a one-shot marker
`<lane>/test-inject-travel.json`. On the armed NPC's next travel-consent chat turn, `processor/chat.php` (one guarded call, right before the ordinary `stobeTravelCapture`)
calls `stobeTravelTestInjectApply()` (`lib/imm26_travel_test_inject.php`). It feeds a synthetic `travel_decision=PROPOSE` (kind, leader, destination from the marker) through the
UNCHANGED `stobeTravelCapture()`: same policy refusal, availability gate, destination grounding, plan hash, `stobeCommitmentPrepareTravel`, `stobeTravelWrite` as an LLM PROPOSE.
Nothing is hand-inserted. The visible text becomes `I can lead us to <dest>. Shall we go?` only when the product stored the offer (`--keep-text` keeps the model's words;
a product refusal keeps its own refusal text). The ordinary capture then sees `{"travel_decision":"NONE"}` (no double record). The player's own "Yes" must still be ACCEPTed by the
model with an exact quote through the normal path (the offline test proves the Yes reaches ACCEPTED on the same agreement id).

Gate (all three or the file does nothing): site root `/tmp/stobe-*/site`; DB socket inside the lane root; marker valid, unexpired, names this NPC (or `any`), unused.
Inert when: another NPC speaks, marker expired, destination does not ground for the NPC (marker kept), trip already ACCEPTED (marker kept), kind is a meeting kind.

Limits (honest): the seam sits inside the `$travelConsentTurn` block, so it cannot help an NPC the server holds in the player faction (`npcIsInPlayerFaction`: no travel prompt at all).
That is the 19-e root cause per `imm26-inv20a` (stale `stobe-auto faction Cind Nameless`), which needs the recipe fix (reset Cind's server faction), not this seam. An empty destination only
grounds when the NPC has local candidates or known places; the rows pass `Squin` (a known visited zone). 20-d's later "safe start" refusal (`lib/commitment_native_bridge.php:105-108`) is a
separate native-receipt issue; this only makes the PROPOSE reliable.

## Files
- `pending-fixes/imm26-sfTrav/`: `imm26_travel_test_inject.php` (seam), `apply.py` (anchor-asserted, idempotent, CRLF-safe installer for a server tree), `imm26_sfTrav_inject_travel.php` (offline test, modes lane / notlane / armed)
- `rowtools/inject-travel.sh` (arm / `--status` / `--disarm`), `inject-travel-deploy.sh <lane>|all` (`--check`), `inject-travel-selftest.sh` (36 checks, WSL)
- `rowtools/tripdefs_sftrav.sh` (redefines `tr_trip_setup` in-process: arm before s1, re-arm before the s1b fallback, disarm once s1 is PROPOSED; `SFT_INJECT=0` = old behaviour)
- NEW runners (no queued script edited): `reload-run-sftrav.sh 20-d <lane>` (= reload-run-sfj.sh + tripdefs_sftrav.sh, same checker, same options incl. `--alt`), `unblockrun_sftrav.sh 08-d <lane>` (= unblockrun_sfs.sh + tripdefs_sftrav.sh)
- `rowtools/inject-travel-runners-selftest.sh` (13 checks, WSL, fake transport)

## Swap list (operator / coordinator, nothing here touches a lane by itself)
1. After EVERY `lane-deploy.sh <lane>` (it replaces the tree and removes both seams): `bash rowtools/inject-travel-deploy.sh <lane>` (and `inject-propose-deploy.sh <lane>` for Hunt rows). Check: `bash rowtools/inject-travel-deploy.sh --check <lane>`; `bash rowtools/inject-travel.sh <lane> --status` shows `SEAM deployed`. Backup: `<lane>/bak-pre-sfTrav/chat.php`; opcache picks it up within ~1 min.
2. 20-d: `bash rowtools/reload-run-sftrav.sh 20-d 4080-i4 [--alt "the Stumble Inn"] [--allow-retry "<why>"]` instead of `reload-run-sfj.sh 20-d`.
3. 08-d: `bash rowtools/unblockrun_sftrav.sh 08-d 4080-i4 [--allow-retry "<why>"]` instead of `unblockrun_sfs.sh 08-d`.
4. Any other row that opens with `tr_trip_setup` can source `tripdefs_sftrav.sh` last in a new runner. 19-e needs the faction reset first (see limits).
5. Evidence per row: `$EV/inject_arm.txt` (ARMED / DISARMED lines), lane `<lane>/test-inject-travel.fired-*.json` (result proposed|refused, agreement id, final text), lane `stobe.log` "STOBE_TEST_TRAVEL_INJECT fired".

## Checks run (offline, 2026-10-16)
`bash rowtools/inject-travel-selftest.sh` -> `SELFTEST-RESULT PASS 36 checks` (unpatched tree fails first; apply/idempotent/php -l; wired once right before `stobeTravelCapture($imm26TravelRaw` after the plan-notice filter;
25 lane checks; notlane inert; existing `imm26_20a_deferred_confirm`, `batch4_travel`, `trip_resume` regressions still pass on the patched tree; script/marker/refusals; deploy body replay).
`rowtools/inject-travel-runners-selftest.sh` -> `SELFTEST SFTRAV ALL PASS 13/13`. `bash -n` on all new scripts, `php -l` on both PHP files.
