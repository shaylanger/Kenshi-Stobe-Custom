# Memory baseline vs current (2026-10-04)

Shay's question: "how are we using so much memory? I am 99% sure this was not the case when we started."
Answer: the Kenshi side has barely changed since our first commits; nearly all of the memory is used by things we didn't change (Kenshi + RE_Kenshi + mods, the WSL speech/LLM stack, open Claude/Chrome sessions).

## Method
- Same machine (5090), back to back, same WSL config (`.wslconfig` memory=10GB, swap 4GB, autoMemoryReclaim gradual, applied by `tools/automation/wsl-restart.ps1` before both runs).
- `tools/automation/mem-ab.sh` (ONLY=all): launch on `auto-home`, then 5 more loads; after each load +90 s settle, `memprobe.ps1` gives Kenshi private/working set/handles/threads. In parallel, `tools/automation/sysmem-sampler.ps1` logs vmmem, system free RAM and commit every 30 s.
- **Baseline** = first-commit DLLs: Stobe + KenshiFP from workspace b0a09a3 (2026-09-30), PG e161da1 (2026-10-02), built in `C:\KenshiTestRuns\membase\dlls`. **Current** = installed Stobe 26373D02, KenshiFP 6E0A031E, PG D7A60E49. The harness was current (4002D570) in both runs.
- Data: `C:\KenshiTestRuns\membase\run-base\`, `run-cur\` (mem.csv, sysmem.csv, SUMMARY.txt).

## Not like-for-like
- **Server not rolled back.** Detaching the live tree at d0ca5ea was blocked by the permission checker. Both runs used the current server (930d058). The server code only affects WSL memory, not Kenshi's process.
- **PG baseline started with an empty affix DB.** The old DLL would have rewritten the current 27 MB v2 `profession_gear_affixes.tsv` in v1 format, so it was moved aside for that run. That is also how PG started on day one.

## Results: Kenshi process (MB private)
| | load0 | load5 | per load | threads load0->5 | File handles load0->5 |
|---|---|---|---|---|---|
| Baseline (first commits) | 12393 | 13065 | +134 | 238 -> 298 | 1578 -> 5391 |
| Current | 12564 | 13155 | +118 | 229 -> 227 | 1585 -> 5458 |
| Difference | **+171** | **+90** | -16 | baseline thread leak (Stobe, fixed c02f95f) is gone | same |

- About 13,900 semaphores in both runs (constant, not ours).
- Allocations of 16 MB or more total about 7.5 GB in both runs; m22 tied these to Dust D3D12/DLSS and the HD texture mods.
- The per-load growth and the leak of about 770 file handles per load are the same with our first-commit DLLs. m22 showed they stay with only the harness loaded: RE_Kenshi FindFirstFile handles and the game/data mods.

## Results: system
| | vmmem working set (min/max) | system free RAM (min) | commit used (max) of 91.9 GB |
|---|---|---|---|
| Baseline | 6.9-7.3 GB | 3.7 GB | 68.6 GB |
| Current | 6.9-8.0 GB | 3.4 GB | 70.8 GB |

- 31 GB physical RAM. With Kenshi closed: free 3.4 GB, commit 58 GB. vmmem was at the 10 GB cap (14 GB private) right after a full DB dump (page cache), and the gradual reclaim brought it down to about 7 GB.
- Inside WSL (RAM): the parakeet speech-to-text server (`python server.py`) about 3.2 GB, uvicorn 0.3 GB, audiocpp 0.3 GB, postgres about 0.3 GB (shared_buffers 128 MB). The rest is page cache.
- Postgres DB `stobe` is **15 GB on disk**: 82 `stobe_profile_save_*` schemas of about 200 MB each, one per save/fixture copy. This uses disk and page cache, not RAM: a full read such as pg_dump fills the WSL cache up to the cap.
- Windows side outside Kenshi/WSL: 6+ Claude Code sessions at about 0.6-0.8 GB each (about 5 GB), Chrome, steamwebhelper, explorer 2.3 GB private.

## Conclusion
- No noticeable growth from our code: Kenshi +0.17 GB at load 0 and less growth per load than at the start. Not a bug (no MASTER bug row). The one real leak at the start (Stobe thread handles) is already fixed.
- What fills the 31 GB: Kenshi about 12.5-13 GB (game + RE_Kenshi + Dust/texture mods; +120-130 MB and about 770 file handles per reload, so long sessions with many reloads keep growing), WSL about 7-10 GB (parakeet STT 3.2 GB + page cache up to the cap), about 5 GB of Claude sessions, plus browsers. Before the 10 GB cap (applied today) WSL could grow unbounded with page cache (DB reads, logs).
- Optional ideas for Shay (decisions, not done):
  - stop parakeet STT while not testing voice input (saves 3.2 GB);
  - drop `stobe_profile_save_*` schemas of deleted kah-* copies (15 GB disk, less page cache);
  - restart Kenshi instead of reloading many times in long batches;
  - fewer parallel Claude sessions.

## Graphics mods A/B (2026-10-04, save auto-home, 4 loads each, `mem-ab.sh` ONLY="all gfxOff gfxOffHD", out `C:\KenshiTestRuns\memab-gfx`)
| Variant | load0 private | load3 private | per load | file handles | allocs >16 MB |
|---|---|---|---|---|---|
| all (Dust + ReShade + HD textures on) | 12547 MB | 13307 MB | +253 MB | 1585 -> 3935 | 268 / 7448 MB |
| gfxOff (Dust + effect DLLs + ReShade off) | 11940 MB | 12383 MB | +147 MB | 1581 -> 3850 | 263 / 7159 MB |
| gfxOffHD (also HD detail textures off) | 9334 MB | 9928 MB | +198 MB | 1462 -> 3471 | 171 / 4729 MB |

- Dust/ReShade off saves about 0.6-0.9 GB; HD detail textures off saves another 2.6 GB (mostly large texture allocations: 4.7 vs 7.2 GB in >16 MB blocks).
- Decision: automated runs use `gfx-mods.sh off --hdtex` (about 3.2-3.4 GB less than everything on). Shay restores everything with `gfx-mods.sh on` before playing.
