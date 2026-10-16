# imm26 10-f OPTION A: native save-persistent item id (NC26 candidate, NOT installed anywhere)

Shay 2026-10-16: "10-f lets do option A". Server option B (`pending-fixes/imm26-durable-item-id`, strict type fingerprint) is NOT in compose and stays as the fallback inside this patch.

## Why it works (Phase 1 verdict: viable)
Kenshi runtime handles (`hand.serial`) are reused after a reload, so `hand_<serial>` identifies nothing across loads. Profession Gear already proved a per-item id that survives save/load AND a full process restart: it hooks `Item::serialiseInInventory` and writes `state->sdata["ProfessionGearPersistentId"]` (+ `activeValues`), and hooks `Item::loadFromSerialiseInInventory` to read it back and bind it to the NEW runtime handle (`Kenshi-Profession-Gear-Progression/src/ProfessionGearPlugin.cpp:715-770, 2088-2089`, TEST_PLAN rows 314-318 all PASS, stable across normal transfers, buyItem copy handled in row 324). Only `Item` overrides `serialiseInInventory` (KenshiLib `Item.h:163`), so one hook covers Weapon/Armour/Container. PG and STOBE already both hook `Inventory::buyItem`, so double hooks coexist. Other persisted per-item fields (`quality`, `chargesLeft`, `properOwner`, `inventoryPos`) are gameplay-visible or shared: not usable.

## What this adds
Native (`native/StobeDurableItem.{h,cpp}`, applied by `nc26_edit.py <NC25 tree>`, tree used: `C:\KenshiTestRuns\imm26-nc26`):
- `Stobe::DurableItem` hooks the two Item (de)serialise functions; id format `sdi1-<16 hex>` (two `rand_s` words), stored in `sdata["StobeDurableItemId"]`; runtime map handle-string -> {id, prototype}; a handle reused by another prototype drops the binding; `Reset()` in LoadCampaign/NewCampaign/ImportCampaign (before the original, items rebind while loading); cap 8192 entries; log tags `DURABLE_ITEM: hooked|install|stamped|restored`.
- `SocialExactTransferEvidence` (main.cpp) rescans the RECEIVER's inventory for the proven Item (same address, serial, quantity, prototype) and stamps it (get-or-create), then emits `"durable_item_id":"sdi1-..."` in that transfer_evidence item row. Both the theft event and the later return event carry it; the id is restored by the engine after reload, so it is identical across loads.
- Ids are stamped lazily (only on items that exact-transfer evidence proves moved), never on every item.
Server (`apply.py`, on top of option B; `--with-b` applies B first):
- `social_event_contract.php`: `durable_item_id` must match `^sdi1-[0-9a-f]{16}$`.
- `stobeSocialRepairFingerprintKeyMap`: match returned -> original by durable id (exactly one each side, same prototype+type, returned quantity <= original), then B's fingerprint only for items not consumed by an id match and only for returned items WITHOUT an id (an id that matches nothing is a known different object). Setting `STOBE_REPAIR_DURABLE_ID_ENABLED` (default on). The unchanged rescope guard (same campaign, newer numeric epoch, session present, storage ids), the whole-stack native proof thief->owner, single-incident rule and stolen/owed quantity caps all still apply. Same-load path unchanged.

## Limits (be honest)
- Only items inside an inventory section carry the id (ground items use `serialise(GameSaveState)`: no id -> fallback B). A stack that is split or merged is a different Item (existing evidence also fails closed on that): no id -> fallback B.
- Gear (non-stackable) is the PG-proven case; STACKABLE items with the id are not yet proven in game (the sdata write is generic, but verify in the live row).
- The save contains a new sdata key on stamped items; removing the DLL leaves an unused harmless key (same as PG).
- Stamp happens at the evidence sweep after the transfer: a save/quit within seconds of the theft misses the id (fallback B).
- `verified_items[..].matched_by` still says `cross_load_fingerprint` for id matches (B label); the DURABLE_ITEM log lines and the stored `durable_item_id` in the theft/return evidence tell them apart.

## Offline proof done
- `imm26_durable_item_id_native_regression.php` (19 checks): baseline (B only) FAILS at the first cross-load id check; with apply.py 19/19 PASS; B's own test still 18/18; all `tests/imm26_*regression.php` exit as before on the scratch copy `/root/imm26/durA-work` (stobe_test under flock); `imm26_wpB_repair_regression.php` fails identically on the B-only baseline copy (`/root/imm26/dur-work`, "harm is on the ledger as a grievance") - pre-existing/data dependent, not caused by A.
- Re-apply check: apply.py twice -> second says "already applied"; without B and without `--with-b` it refuses; `--with-b` on a pristine copy of the live lib files applies both.
- Native: `nc26_edit.py` second run refuses; scratch build BUILD OK (objects=70, guards DURABLE_ITEM, travel_terminal, FOLLOW_DIAG present). DLL path and SHA256 are in the handoff / last line below.

## Apply / build
- Server (scratch or later compose): `python3 pending-fixes/imm26-durableA/apply.py <tree> --with-b` (WSL; back up first; `php -l`; then the two tests above under `flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/<test>`). NOT deployed to the live tree or ss-merge.
- Native: `python3 pending-fixes/imm26-durableA/nc26_edit.py <fresh NC25 tree>` then `build-stobe.ps1 -Root <tree> -Out <dir> -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG`. Install later with `install-dll.ps1 Stobe` only on the 4080 lane for the live proof.

## LIVE PROOF RECIPE (later separate WP; 4080 isolated lane, kah-* fixture copy, private backend with B+A applied, NC26 DLL; two save/load cycles)
Setup: lane with NC26 DLL (SHA in the handoff) and a private server tree/DB carrying `apply.py --with-b`; `SOCIAL_RELATIONSHIP_MODE=enabled`; settings `STOBE_REPAIR_DURABLE_ID_ENABLED` and `STOBE_REPAIR_FINGERPRINT_ENABLED` default (on). Owner O (e.g. Cind) and thief T (squad NPC or Malzin) with O holding (a) one non-stackable gear item G (e.g. a named weapon) and (b) one stackable stack S (e.g. 5 of one food/material). Use the existing 10-e/FX-CIND scene and `rowtools/reloadrun-b.sh` pattern for save/load cycles.
1. THEFT: T takes G and S from O (existing theft setup of the 10-a..10-e rows). Expect in the Stobe log: `DURABLE_ITEM: stamped id=sdi1-XXXX handle=... proto=...` for G (and S if its whole stack moved unchanged), and in the server inbox (`social_event_inbox`) the theft event `facts.transfer_evidence.items[]` carrying `durable_item_id` = the stamped id and `item_key` `hand_<serial1>`. Record id_G, id_S, serial1.
2. SAVE kah-durA-1 immediately after the stamp lines (stamp happens in the sweep after the move; wait for the DURABLE_ITEM line before saving).
3. LOAD cycle 1 (load kah-durA-1): expect `DURABLE_ITEM: restored id=<id_G> handle=<new>` (and id_S). `iteminfo`/harness: G now has a different `hand_<serial>` (or the same: both fine), same id.
4. SAVE kah-durA-2 from the loaded state, LOAD cycle 2 (load kah-durA-2): expect `restored` again for the same ids (proves the id is re-serialised, not only read once).
5. RETURN after cycle 2: T hands G (and S) back to O with the harness/dialogue transfer used in 10-b. Expect the return event `transfer_evidence.items[]` with the SAME `durable_item_id` but a new `item_key` `hand_<serial3>`.
6. SERVER CHECK: `social_incident` repair state (`state->>'kind'='social_repair'`) shows `returned_quantities` > 0, `verified_items.hand_<serial1>` with `return_item_key` `hand_<serial3>`; an `SE` restitution_relief row exists and `material_state` complete/partial as owed. PASS = G credited by id after TWO reloads. S: PASS if credited the same way; if the stack has no `restored` line, record "stackable id not persisted" (fallback B then credits the fingerprint) - that is a finding, not a failure of G.
7. NEGATIVES (separate branches from kah-durA-1): (a) T gives O a DIFFERENT same-name item (not the stolen one): no credit, status return_unattributed; (b) kill switch: set `STOBE_REPAIR_DURABLE_ID_ENABLED=0` and `STOBE_REPAIR_FINGERPRINT_ENABLED=0`: the correct return is NOT credited; (c) older save (rollback to an earlier epoch) stays refused by the rescope guard.
8. Also check the save itself: nothing else changed; load a save made WITHOUT the NC26 DLL and one made by NC26 on the previous DLL (unknown sdata key ignored, game loads).
Evidence to keep: Stobe log DURABLE_ITEM lines, the two inbox rows (theft/return) with ids, repair state JSON, screenshots only if a step is visual.

## Build result
NC26 scratch build BUILD OK (objects=70): `C:\KenshiTestRuns\imm26-nc26-b2\out\Stobe.dll`, copy `pending-fixes/imm26-durableA/NC26/Stobe.dll` (git-ignored), SHA256 A3E63FB1453F9782933D73F55514433CA1F037F8F0F8B5BC17E159A1D3E7CAD9. Source tree `C:\KenshiTestRuns\imm26-nc26` (NC25 + nc26_edit.py). Not installed. `bash offline-tests.sh` -> `RESULT durableA-offline PASS`.
