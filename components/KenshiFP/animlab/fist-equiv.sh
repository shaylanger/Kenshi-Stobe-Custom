#!/bin/bash
# fist-equiv.sh <candidate dir (native.py fists --out)> [patch.py] [client dir]
# Lab-vs-game equivalence for the NA1 fists: builds kfpvm_fist.c against a COPY of the KenshiFP client (default the
# live tree /root/KenshiFP/client, read only: build.sh compiles a copy) with the fists patch (default pending-fixes/kfp-fists-na1.py), dumps the
# game's keyed fist path vm_fist_at per technique / hand on a u grid and compares it with the lab's keys.json
# (native.py keyed_at, the path the lab solved and checked). Prints one line: RESULT FIST-EQUIV PASS|FAIL <max errors>.
# Limits: p <= 0.02 dm, f/u <= 0.01 (the tables carry 3-4 decimals).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; L=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
CAND=${1:?candidate dir}; P=${2:-/mnt/c/KenshiModding/pending-fixes/kfp-fists-na1.py}; SRC=${3:-/root/KenshiFP/client}
OUT=/tmp/kfpvm_fist_$$; trap 'rm -rf $OUT $OUT.d $OUT.txt' EXIT
PA=(); [ -s "$P" ] && PA=(--patch "$P")   # no patch file = the fist code is already in the source
bash "$HERE/build.sh" --src "$SRC" "${PA[@]}" --main kfpvm_fist.c --out "$OUT" > $OUT.log 2>&1 || { echo "RESULT FIST-EQUIV FAIL build: $(tail -3 $OUT.log | tr '\n' ' ')"; rm -f $OUT.log; exit 1; }
rm -f $OUT.log
"$OUT" 200 > $OUT.txt || { echo "RESULT FIST-EQUIV FAIL run"; exit 1; }
python3 - "$CAND" $OUT.txt "$L" <<'PY'
import sys, os, json, glob
cand, dump, L = sys.argv[1:4]
sys.path.insert(0, L)
import native as NV
G = {}
for ln in open(dump):
    a, s, u, p, f, w = ln.strip().split('|')
    G.setdefault(a, {}).setdefault(int(s), []).append((float(u),) + tuple(tuple(map(float, x.split(','))) for x in (p, f, w)))
worst, bad, n, seen = [0.0, 0.0], [], 0, set()
for kj in sorted(glob.glob(os.path.join(cand, '*', 'keys.json'))):
    k = json.load(open(kj)); a = k['anim']
    if a not in G:
        bad.append('%s: no game table' % a); continue
    seen.add(a)
    for s, side in ((0, 'R'), (1, 'L')):
        gp = k['guard'][side]; kp = k['keys'][side]
        for row in G[a][s]:
            u = row[0]
            lp = NV.keyed_at(gp, kp, gp, k['ku'], u)
            ep = max(abs(row[1][j] - lp[0][j]) for j in range(3))
            ef = max(max(abs(row[2][j] - lp[1][j]), abs(row[3][j] - lp[2][j])) for j in range(3))
            worst = [max(worst[0], ep), max(worst[1], ef)]; n += 1
            if ep > 0.02 or ef > 0.01:
                bad.append('%s %s u%.2f dp %.3f df %.3f' % (a, side, u, ep, ef))
miss = sorted(set(G) - seen - {'guard'})
ok = not bad and n > 0
print('RESULT FIST-EQUIV %s techniques=%d samples=%d max_dp=%.4f dm max_df=%.4f%s%s' % (
    'PASS' if ok else 'FAIL', len(seen), n, worst[0], worst[1], (' no-lab-candidate=' + ','.join(miss)) if miss else '',
    (' bad=' + '; '.join(bad[:4])) if bad else ''))
sys.exit(0 if ok else 1)
PY
