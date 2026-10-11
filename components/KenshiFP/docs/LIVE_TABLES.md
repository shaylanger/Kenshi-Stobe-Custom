# KenshiFP live animation tables (fp_tables)

Tune viewmodel poses, sword strokes, fist keys, grips and fade/near-clip/timing values in the running game, with no
rebuild (Shay 2026-10-10). Source: `client/kfp_tables.inc` (pending patch `pending-fixes/kfp-live-tables.py` until it is
in the base). With no file the compiled values are used, so shipped behaviour is unchanged.

## File
`<KenshiFP dll folder>\fp_tables.txt` (RE_Kenshi `mods\KenshiFP\`). The DLL reads it when it appears, re-reads it when
its write time changes (about 2 Hz), and goes back to the compiled values when it is deleted. Each (re)load first resets
every registered table to the compiled values, so one file = one whole variant.

```
# comment
pose.m_ready.py = -1.4               # one value: <table>.<row>.<col>
swk_alt.s2_k3 = 2.1 0.4 4.9 -0.3 0.8 0.5 -0.6 0 0.8   # a whole row (9 values: px py pz fx fy fz ux uy uz)
swk_u = 0 0.28 0.38 0.47 0.58 0.78 1    # a whole table from element 0
tau = 0.1                             # scalars are named after their fp_vm set key (range checks apply)
vm.fn_gx = 1.2                        # any fp_vm set key, also ones not registered (e.g. new patch keys)
```
Tables (`fp_tables list` for all with sizes): `pose` (m_/r_ ready aim reload block), `swk` (stroke 0 keys k1..k5),
`swk_alt` (strokes 1..3: s1_k1..s3_k5), `swk_u`, `swk_ul`, `low` (m r), `groll`, `plsl`, `rest`, `sup`, `pole`,
`kick_p`, `fist_guard`, `fist_<tech>` + `fist_<tech>_u`, and ~90 scalars (`zf0 zf1 nearclip sw_dur tau e1* elb* wrl* rl*`
...). Keys: flat index, row name/index, or `row.col`. Start from `fp_tables dump <file>` (current) or
`fp_tables dump <file> defaults` (compiled); a `diff` dump lists only the rows that differ.

## Commands (harness)
`fp_tables state | list | reload [file] | load <file> | set <table> <key> <v..> | set vm <key> <v> | get <table> [key] |
dump <file> [diff|defaults] | reset`. Every reply ends with `tables hash=<8 hex> default=0|1 changed=<n> file=...`:
log the hash with every take. `fp_vm rec dump` writes `# tables <hash at rec on> now=<hash>` plus a `# set -1` line for
every value that differed from the compiled one at `rec on`, so the lab replays the filmed variant from the recording
alone. vm_set key `t.<table>.<key>` sets one table value (`fp_vm set t.pose.m_ready.py -1.4`, KenshiFP.ini
`vm_t.pose.m_ready.py=-1.4`, lab `--set t.pose.m_ready.py=-1.4`).

## Lab (same format, same code)
- `animlab/kfpvm_replay` / `kfpvm_drive` `--tables <file>`: the variant applied after the recording's own sets.
- `animlab/kfpvm_tables check <file> [dump]` / `defaults <out>` / `cmd <fp_tables args>`: the game's parser, registry
  and hash offline (build: `animlab/build.sh --sync --patch /mnt/c/KenshiModding/pending-fixes/kfp-live-tables.py
  --main kfpvm_tables.c --out /root/animlab-build/kfpvm_tables`; drop `--patch` once kfp-live-tables is in
  /root/KenshiFP; rebuild after any patch that adds a table). Without it `fptables.py check` says `no adapter` and the
  sweep reports `lab-dump=n/a` (always so on the 4080: Windows python, no adapter).
- `Kenshi-Automation-Harness/tools/animlab/fptables.py make|show|check|expand`: write variant files, expand a sweep list.

## Pose sweep (render pass)
`tests/ingame/fp-pose-sweep.sh <list> [player mate hostile outdir]` (env `SWEEP_WEAPON=sword|crossbow`, `SWEEP_ZOOMS`):
one launch, per variant `fp_tables load`, the VMQUICK segment at zoom 0 and 25, tiles labelled `[<variant> #<hash>]`,
recordings per variant, `RESULT POSESWEEP-<variant>` + `<out>/sweep-index.tsv` for the auto-review agent. List lines:
`<name> [<base file>|-] [<lhs>=<v,..>]...`. Run it through a queue list (`queue\any\`, `# needs: KenshiFP latest`,
no `RIG=` in the row so either rig takes it; the variants file must exist on both rigs under `C:\KenshiTestRuns\tables\`).
Example list: `C:\KenshiTestRuns\queue\done\22-lt-sweep-smoke.list` (variants `C:\KenshiTestRuns\tables\sweep-smoke.txt`:
`base` + `rdy-low`), about 6 min on the 5090.
Row `POSESWEEP-TABLES` proves the mechanism: set changes the hash, get reads it back, dump -> reset -> load restores the
set hash, reset returns the compiled hash, the lab adapter hashes the game dump the same, and every changed variant
moved the viewmodel-local arm/weapon vectors (rec group 1, not world position) by >= 0.05 vs `base`
(`<out>/tables-check/pose-diff.txt`). First real run 2026-10-11 (5090, staged DCCED30B): all 3 rows PASS, compiled
4f49590b, set/dump-reload 8d3c1400, lab adapter hash of the game dump 8d3c1400 (match), rdy-low max local move 5.5.

## Adding a table
A patch that adds a table/scalar adds one line to `g_kt[]` in `kfp_tables.inc` (`KT_POSES`, `KT_VEC`, `KT_VEC1`,
`KT_ROW`, `KT_SCAL("<fp_vm key>", var)`). Until then its fp_vm keys work in files as `vm.<key>`.
