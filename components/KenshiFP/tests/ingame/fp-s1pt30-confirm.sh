#!/bin/bash
# fp-s1pt30-confirm.sh <out dir> <name> [strokes] [reps]   (WSL/4080 bash; stobe-auto on PATH; Kenshi running)
# sword-fix2 2026-10-11: S1 (sword edge never faces the camera: clamp on in the E1 lead, edgectol -0.08, stroke-1 refit 5) +
# PT30 (follow-through roll, e1ib 0.68) confirm. Guard first: the installed KenshiFP must carry kfp-s1-edge-swing (its
# fp_tables scalar `eclsw`), else one `RESULT E6-<name> FAIL setup:` line and no take; then fp-e6-strokes.sh (sword only,
# crossbow crash guard) films the strokes.
HERE=$(cd "$(dirname "$0")" && pwd); N=${2:-s1pt30}
r=$(stobe-auto fp_tables get eclsw </dev/null 2>&1)
case "$r" in *nknown*|*rror*|*ERR*|'') echo "RESULT E6-$N FAIL setup: installed KenshiFP lacks kfp-s1-edge-swing (fp_tables get eclsw: ${r:0:80})"; exit 1;; esac
echo "note: eclsw present: ${r:0:80}"
exec bash "$HERE/fp-e6-strokes.sh" "$@"
