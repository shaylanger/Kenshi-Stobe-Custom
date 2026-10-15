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

## Checks
See RESULTS section below (filled by the run).

## Trivial CONTRACTS items noticed (not done; next WP)
- `abandoned_in_danger` rule key is present (wpA). Server still rejects it without an `agreement_id` (CONTRACTS item list).
- `nearby[].role/squad_name/squad_id/settlement` still dropped by the `social_privacy` audience whitelist (MISMATCH 4).
