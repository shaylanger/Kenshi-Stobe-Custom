# fix26f4: 26-f offer/accept while Cind is in combat (sfO seam availability bypass)

Evidence: op17 4080-i4 (rows/26-f, stobeserver.log 22:27:20 req_6ad2a4c421999): the fix26f2 seam fired (ClearGroup intent built from the turn's own native candidate, 4 agreed targets) but
`ActivityChat.php:104` threw "Activity availability rejected": `npc_availability.php:34` reason `in_combat` (Cind is fighting the bandits). `ActivityChat.php:106` checks the same gate again at ACCEPT, so fixing only the
PROPOSE turn would have failed at the Yes.

Decision: option (B), clearly scoped. Option (A) (recipe keeps the bandits non-hostile) cannot be made deterministic offline: the recipe sets the bandits' relation to -100 on purpose (a ClearGroup target must be hostile),
the Holy Sentinel peace step has nothing to flip on the i4h save, and the Yes turn would still need the bandits peaceful until after the accept. Not attempted.

What changed (test seam only, lane gate `/tmp/stobe-*/site` + private DB socket; the production files `npc_availability.php`, `ActivityChat.php` and apply.py's single guarded call are untouched):
- `pending-fixes/imm26-sfO/ActivityTestInject.php` (patched by `pending-fixes/imm26-fix26f4/patch.py`, anchor-asserted): marker key `bypass_availability: true` (only written by `inject-propose.sh --bypass-availability`).
  On fire, the PROPOSE turn's `$turn['availability']` is opened (logged `STOBE_TEST_ACTIVITY_INJECT availability bypassed` with the product gate's reasons) and a phase-2 marker (`phase: accept`, same actor,
  `bypass_window` default 600 s) is written. While the record is `proposed` the Yes turn gets availability opened too; when the model answers NONE (it is told to decline while in combat) AND the native side delivered REAL
  consent evidence (`request.consent`), the model's choice is replaced by ACCEPT. `adapter->accept()` still validates the evidence; consent is never created. The marker is consumed when the record is no longer `proposed`, on expiry, or by `--disarm-all`.
- `inject-propose.sh`: `--bypass-availability`, `--bypass-window SEC` (60..1800), `--disarm` (now keeps a phase-2 marker), `--disarm-all`.
- `reloaddefs_sfe.sh.candidate`: arms with `--bypass-availability` (opt out `RW_INJECT_BYPASS=0`), `rs_inject_end` (status + `--disarm-all`, evidence `inject_end.txt`) on every exit path via the `rd_26f` wrapper.
- Honesty: a 26-f PASS proves accept (real consent) -> native scope check -> save+load -> resume while the NPC is in combat; it does NOT prove that the product lets a fighting NPC take a job. Evidence of what the gate said: server log "availability bypassed ... was_reasons [in_combat]".

Deploy (outside this ticket): `bash rowtools/inject-propose-deploy.sh 4080-i4` (copies the new ActivityTestInject.php; apply.py is idempotent), then swap the candidate:
`cd rowtools && cp reloaddefs_sfe.sh.candidate reloaddefs_sfe.sh` only when no operator on 4080-i4 runs reloaddefs_sfe.sh. One call unchanged: `bash rowtools/reload-run-sfe.sh 26-f 4080-i4 --save kah-imm26-4080-i4h`.

Tests (offline): `bash rowtools/inject-propose-selftest.sh` (php J1..J11 incl. unarmed/old-armed/expired/gate-closed still rejected in combat; script C11..C14), `bash rowtools/fix26f-selftest.sh`, `bash rowtools/reload-sfe-selftest.sh` on a staged copy with the candidate swapped in.

Design question for Shay (not decided here): should an NPC already fighting a group be able to take a ClearGroup job against that same group? Today WP-D item 21 says no (any in_combat NPC declines new commitments, "Not now, I'm in the middle of a fight").
Arguments for an exception: clearing the group she is fighting is the same fight, and a player may well say "clear them out" mid-fight. Against: the refusal is deliberate and tested (21 rows), and a job would start with no safe moment to save/hand over. Left as is.
