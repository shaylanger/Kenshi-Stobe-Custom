#!/usr/bin/env bash
# hunt26a-scene-stub.sh <outdir>: selftest stand-in for hunt26a-scene.sh. STUB_TEXT_SEQ = ';'-separated offer sentences per call ('' = scene bad); the last repeats. Counter in $STUB_COUNT.
OUT="$1"; mkdir -p "$OUT"; n=$(cat "$STUB_COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$STUB_COUNT"
IFS=';' read -r -a seq <<<"$STUB_TEXT_SEQ"; t="${seq[$((n-1))]:-${seq[$((${#seq[@]}-1))]}}"
[ "$t" = BAD ] && { echo "SCENE-BAD cind sees no goat" > "$OUT/log.txt"; exit 3; }
echo "SCENE-OK" > "$OUT/log.txt"
printf 'SAY1 12:00:00\nOFFER_SEEN=1 12:00:05\n[2026] ACTION_EXEC: SAY [Malzin]: %s (PC)\nSAY2 12:00:08\n' "$t" > "$OUT/offer.txt"
