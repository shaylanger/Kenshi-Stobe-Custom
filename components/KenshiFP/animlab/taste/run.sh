#!/bin/bash
# taste/run.sh -- score the animation lab against Shay's (and the coordinator's) accept/reject decisions (taste set), and
# print the rule -> check map. WSL: bash /mnt/c/KenshiModding/components/KenshiFP/animlab/taste/run.sh [--md out.md] [--only R1,R2]
# Unarmed spec on fist candidates: bash run.sh unarmed <candidate dir>...  (e.g. /root/animlab-work/p4/fist2)
set -u
HERE=$(cd "$(dirname "$0")" && pwd); L=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
ROOT=${ANIMLAB_CORPUS:-/mnt/c/KenshiTestRuns/corpus}
# vmcheck (PT29/PT30 every-frame checks) lives embedded in fp-viewmodel.sh: extract it for the checks file ({V})
sed -n "/^cat > \"\$OUT\/vmcheck.py\" <<'VMCHECK'/,/^VMCHECK/p" "$HERE/../../tests/ingame/fp-viewmodel.sh" | sed '1d;$d' > /tmp/kfp-vmcheck.py
case "${1:-score}" in
unarmed) shift; exec python3 "$L/spec.py" unarmed "$@" --rules "$HERE/rules.tsv";;
map) exec python3 "$L/spec.py" map "$HERE/rules.tsv" "${@:2}";;
spec) shift; cls=$1; shift; exec python3 "$L/spec.py" run "$HERE/rules.tsv" "$@" --checks "$HERE/checks.json" --class "$cls";;
*) [ "${1:-}" = score ] && shift
   exec python3 "$L/taste.py" score "$HERE/taste.tsv" --rules "$HERE/rules.tsv" --checks "$HERE/checks.json" --root "$ROOT" \
        --cache "${TASTE_CACHE:-/root/animlab-work/taste-cache}" "$@";;
esac
