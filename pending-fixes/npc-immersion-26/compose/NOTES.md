# imm26 server compose (imm26-compose2, 2026-10-15)

Composed tree: `/root/imm26/compose` (WSL DwemerAI4Skyrim3) = base + wpA + wpB + wpD + wpE + wpC1 + wpC2 + travel fix.
Single patch: `/root/imm26/compose.patch` (copy here, `patch -p1` on a fresh copy of `/root/imm26/base`, 837 KB, 41+ files).

## Method (why not imm26-compose.sh patch-by-patch)
Each `wp<X>.patch` applies to base alone and reproduces the `/root/imm26/wp<X>` tree exactly (verified, `patch --ignore-whitespace`).
Patch-on-patch failed (B/E/C2 conflicts, CRLF noise). Instead `compose_merge.py` does a file-level 3-way merge of the six wp trees
(order A B D E C1 C2) with `git merge-file --diff3` on LF-normalised text, then restores CRLF on files that are pure CRLF in base
(`processor/bored.php`, `lib/activity/ActivityChat.php`). wpD's whole-file CRLF noise on bored.php is gone: the merge result is
pure CRLF like base and only the logical D/B/C2 hunks differ. `mkcompose_patch.sh` regenerates `compose.patch` (diff -ruN base compose)
and proves it applies to a fresh copy of base with an identical result.
Rebuild: `python3 /root/imm26/compose_merge.py [ORDER]` then resolve conflicts, `bash /root/imm26/mkcompose_patch.sh`.
Then the travel fix: `python3 travel-fix/apply-travel-actor-serial.py /root/imm26/compose` (idempotent) after the merge.

## Hand-resolved conflicts (7)
1. `data/social_relationship_rules.json`: keep wpA `abandoned_in_danger` + wpB `behaviour_change_relief` (+ existing `restitution_relief`).
2. `lib/travel_companionship.php` (wpD vs wpE, around the PrepareTravel call): keep D's origin/`$isReplace` block and E's ACCEPT
   `stobeTravelTakeRegionalConsent` block (placed right after `stobeCommitmentPrepareTravel`, before the replace branch).
3. `lib/activity/ActivityChat.php` requires: keep D `npc_availability.php` + E `ActivityKinds.php`, `ActivityLifecycle.php`.
4. `debug/db_updates.php`: keep both migrations (`imm26_wpB` 202610150210 and `imm26_npc_principle` 202610150031).
5. `lib/social_additions.php` `$readers`: all four entries (B knowledge/ties/repair + C1 context).
6. `lib/npc_referrals.php` candidate loop: `$score = $imm26 ? stobeImm26ReferralScore(...) : count(...)` (C1), then B's
   `$score = $score*10 + $tieRank` and `relationship_to_you` hint, plus C1's `'kind'=>'visible'`.
7. `processor/chat.php` after-reply hook: both C1 `stobeImm26C1AfterReply` and C2 `imm26C2AfterManualTurn` blocks.

## Compose-level fixes (found by the first full run; the wp trees are NOT changed, so wp owners must carry these)
- `lib/imm26_ties.php` `stobeTieFromMap`: `function_exists('stobeRelationshipEntryFor')` guard (wpB x wpC1: C1's pure test does not load chat_helper_functions).
- `lib/imm26_plans.php` `stobeImm26ImplicitFollow`: `function_exists('getSetting')` guard around both `getSetting` calls (wpD item 23 called from wpE region test without settings.php).
- `lib/destination_discovery.php` `stobeDestinationRecordCounts` (wpE): REAL BUG. `storeEvent()` overwrites `CACHE_CITY/CACHE_REGION/CACHE_LOCATION` from the event's geo, so the diagnostics row cleared the current town for the rest of the request (broke travel_known_places 2 asserts, world_town_rumour 3). Now saves/restores the three globals.
- `tests/imm26_wpE_situated_events_regression.php`, `tests/imm26_wpC2_followups_comm_regression.php`: cleanup() also deletes recent `inputtext/inputtext_s/situated_remark_claim` rows (chat_flow_regression leaves them; the claim gate refuses within 30 s of manual input / global spacing). Failed identically on the bare wpE tree after chat_flow.
- Added `tests/imm26_travel_target_out_of_people_regression.php` (travel fix regression) to the patch.

## Checks (all on /root/imm26/compose, stobe_test DB)
- php -l: every changed/new php file clean (41+ files).
- `patch -p1` of compose.patch on a fresh copy of base: clean, result identical to compose tree (`mkcompose_patch.sh`).
- Full stobe-tests: `suites: 93 passed, 5 FAILED, 7 known pre-existing`. The 5 failures are all expected pre-existing:
  chat_json_endpoint, main_ingress_http, npc_player_view (68/2, identical to base), social_property, social_fights.
  `bio_unique` and `relationship_stance` now PASS (fixed by wpA). No new failures. Every wpA/B/C1/C2/D/E regression and the travel regression pass inside the run.
- `flock -o` note: an orphaned `php -S` test server on /root/imm26/base (parent /init) held /tmp/stobe-tests.lock and blocked the run; killed it (not Shay's). Check `fuser -v /tmp/stobe-tests.lock` if the lock waits.

## Trivial CONTRACTS items noticed (not done; next WP)
- `abandoned_in_danger` rule key is present (wpA). Server still rejects it without an `agreement_id` (CONTRACTS item list).
- `nearby[].role/squad_name/squad_id/settlement` still dropped by the `social_privacy` audience whitelist (MISMATCH 4).

## user_message fix (imm26-compose-fix-usermsg, 2026-10-15; row 04-c)
`lib/imm26_ties.php` stobeTiesConversationContext and `lib/imm26_knowledge.php` stobeKnowledgeConversationContext read `$meta['user_message']`, which chat.php never sets (it sets `player_message`); both now fall back to `player_message` (user_message kept first, as in npc_referrals.php). Regression asserts added to `tests/imm26_wpB_knowledge_regression.php`. Full stobe-tests: 93 passed, 5 FAILED (the 5 known), 7 known. compose.patch regenerated (APPLY-IDENTICAL). Delta copied to 5 lane sites (`*.bak-pre-usermsg`).
