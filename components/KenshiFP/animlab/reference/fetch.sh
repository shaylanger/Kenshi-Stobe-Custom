#!/usr/bin/env bash
# fetch.sh <data dir>   (WSL) download the reference clips of sources.tsv: each source into its own NEW, EMPTY dir
# (<data>/cmu, <data>/bandai; refuses if one exists). Untrusted data: parsed by compare.py / mocapref.py with python3 -I,
# never executed. Licenses: see sources.tsv header (CMU free for all uses; Bandai Namco Research CC BY-NC 4.0).
set -eu
D=${1:?data dir}; HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$D"; mkdir "$D/cmu" "$D/bandai"
B=https://raw.githubusercontent.com/BandaiNamcoResearchInc/Bandai-Namco-Research-Motiondataset/master/dataset/Bandai-Namco-Research-Motiondataset-1
grep -v '^#' "$HERE/sources.tsv" | cut -f2 | sort -u | while read -r c; do
  case "$c" in
    cmu/*) f=${c#cmu/}; s=${f%%_*}
           [ -f "$D/cmu/$s.asf" ] || curl -sfL -o "$D/cmu/$s.asf" "http://mocap.cs.cmu.edu/subjects/$s/$s.asf"
           curl -sfL -o "$D/$c" "http://mocap.cs.cmu.edu/subjects/$s/$f" ;;
    bandai/*) f=${c#bandai/}; curl -sfL -o "$D/$c" "$B/data/dataset-1_$f" ;;
  esac
done
curl -sfL -o "$D/bandai/LICENSE" "$B/LICENSE"
echo "fetched into $D: $(ls "$D/cmu" | wc -l) cmu files, $(ls "$D/bandai" | wc -l) bandai files"
