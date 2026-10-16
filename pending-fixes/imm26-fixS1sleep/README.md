# imm26-fixS1sleep: drop asleep / KO / dead bystanders from a fight's audience (row 15-bx witness S1)

Finding: `Utils.cpp` `CollectEventPeopleFromAnchor` builds the audience as a sphere (max of ShoutRadius / proximity radius) with only an area check; no dead / KO / asleep filter, so a sleeper 62 u from a fight got the fight events and the list is frozen at emit time. Decision (coordinator default): asleep / unconscious / dead characters are dropped from the audience. The event's own actor and target are appended by `BuildEventPeopleJson` before the collector and are NOT filtered (a KO victim stays in the list). OFFLINE ONLY: no DLL built, nothing installed.

## What changes (base = NC2627 composed source `C:\KenshiTestRuns\imm26-nc2627\src`)
- new `src/StobeAsleepState.h` (header-only): `StobeCharacterAsleepOrDown(w, &task, &prone, &sleeping)` = the exact predicate moved out of `main.cpp` `SocialCollectWitnesses` (IN_BED / SLEEP_ON_FLOOR / USE_BED / PS_KO / PS_PLAYING_DEAD / StateBroadcastData isSleeping), and `StobeCharacterDownOrAsleep(w)` = isDead() || isUnconcious() || asleep (unreadable state keeps the character).
- `src/main.cpp`: `#include "StobeAsleepState.h"`; `ResolveCurrentNpcTaskSafe` loses `static` (forward decl + definition; the header declares it); the witness block in `SocialCollectWitnesses` (~5589-5611) now calls the shared helper (same behaviour, logged task/prone/sleeping unchanged). main.cpp is CRLF; the patch preserves it.
- `src/Utils.cpp`: `#include "StobeAsleepState.h"`; in `CollectEventPeopleFromAnchor`, after `IsEventAreaCompatible`, `if (StobeCharacterDownOrAsleep(other)) continue;` (before the distance check and before the person is appended, so it also does not consume the per-anchor / total caps).
- CMakeLists.txt: no change (header-only).
- Awake / standing NPCs: unchanged.

## Apply
`cd <tree root containing src/>; patch -p1 --binary < pending-fixes/imm26-fixS1sleep/imm26-fixS1sleep.patch` (or the anchor-asserting `python3 pending-fixes/imm26-fixS1sleep/make_edit.py <tree root>`: exit 2 on a missing anchor, exit 3 if already applied; the patch and the script give byte-identical results). The patch is `-text` in `.gitattributes` so git does not rewrite its line endings.

## Test
`components/STOBE/tests/cpp/fight_audience_asleep_source_tests.py <src dir>` (source assertions: filter present and before the append, helper holds the full predicate, main.cpp uses the helper and has no second copy, actor/target still appended first, ResolveCurrentNpcTaskSafe non-static).
`bash pending-fixes/imm26-fixS1sleep/offline-tests.sh [tree root]` (WSL) -> base fails, patched passes, patch == script result, mutation (filter disabled) fails, second run refuses. `RESULT fixS1sleep-offline PASS`.
Not provable offline: that it compiles against the Kenshi headers (only existing includes/members used: Character::isDead/isUnconcious/getProneState/inSomething/stateBroadcast, all already used by main.cpp) and the in-game effect.

## What the NC28 compose must do
Apply this patch AFTER all NC2627 edits (touches main.cpp lines ~65 include, ~5154 fwd decl, ~5589 witness block, ~5973 definition; Utils.cpp ~13 include and ~1240); anchors are asserted by `make_edit.py`. If another NC28 patch also edits those exact lines, re-run `offline-tests.sh` on the composed tree. Then build (a `-Guard` list needs no new tag) and live-check row 15-bx: sleeper S1 near a fight must be absent from the fight event's people list while an awake bystander is present.
