# NPC profile age validation rows

Two immutable operator instruction emitters for both rig queues. They print their gates and exact `RESULT` templates; they do not run tests, touch rigs/services, seed records, or write queue files.

| Row | Scope | Current state / dependency |
|---|---|---|
| `npc-age-001-inmemory-persistence-render.sh` | Exact-pinned offline lazy persistence, JSON reload, CAS and biography-render fixture; PHP lint on live/merge sources | Blocked until exact hashes and an isolated no-network PHP CLI environment are verified. Uses only the fixture's disposable in-memory adapter; no real database. |
| `npc-age-002-live-biography-refresh.sh` | Authored age 137, generated humanoid 20–80, Skeleton unknown/established chronology, both web profile and in-game biography after refresh; no age-derived “older” label | Blocked pending exact deployed manifest receipt, isolated disposable fixture/snapshot path, and documented refresh/read-only observation procedure. Component hashes alone do not establish deployment. |

Hashes and behavioral scope are pinned from `pending-fixes/npc-profile-age/RELEASE-STATUS.md`. A prior 4080 pure behavior fixture and static persistence/render review are historical evidence only; neither is reused as a current row PASS. Do not execute row 002 against real NPCs or a real database. New revisions must use new row IDs and preserve these files unchanged.
