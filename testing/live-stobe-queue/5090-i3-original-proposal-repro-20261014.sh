#!/usr/bin/env bash
# Re-run original native timeout proposal with fresh valid copied-player proximity.
set -euo pipefail
export RIG=5090 KAH_INSTANCE=3 KENSHI_DIR=/mnt/d/KenshiInst/3 KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness'
auto=(python3 /mnt/c/KenshiModding/tools/stobe-auto)
out=$(mktemp -d /tmp/5090-i3-original-proposal.XXXXXX)
"${auto[@]}" status | tee "$out/world.txt"
grep -q 'phase=world save=kah-5090c-ui-20261014.*paused=0' "$out/world.txt"
"${auto[@]}" where Harf | tee "$out/where.before.txt"
handle=$(python3 - "$out/where.before.txt" <<'PY'
import pathlib,re,sys
m=re.search(r'^Harf (#676879872/\d+)',pathlib.Path(sys.argv[1]).read_text())
assert m
print(m.group(1))
PY
)
"${auto[@]}" stobe_state "$handle" | tee "$out/state.before.txt"
"${auto[@]}" teleport Shay Harf | tee "$out/copied-player-position.txt"
"${auto[@]}" where Harf | tee "$out/where.current.txt"
python3 - "$out/where.current.txt" <<'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text()
assert re.search(r'^Harf #676879872/\d+',s)
assert float(re.search(r'dist=([\d.]+)',s).group(1)) <=80
PY
stat -c%s /mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log > "$out/native.offset.txt"
"${auto[@]}" stobe_say "$handle" 'Do you know a place worth travelling to beyond Spring, perhaps the Armoury Ruin in Greyshelf? I am asking about a possible trip, not agreeing to start one yet.' | tee "$out/proposal.send.txt"
printf 'receipt_dir=%s\n' "$out"
