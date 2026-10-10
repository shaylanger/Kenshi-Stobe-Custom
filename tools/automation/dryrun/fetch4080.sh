#!/bin/bash
# fetch4080.sh: copy the 4080's take-script files (C:\KenshiTestRuns: *.sh *.py *.txt *.list *.lab, no media) into
# /root/.cache/kah-dryrun/4080-testruns, which the 4080 dry-run sandbox layers over /c/KenshiTestRuns (the 4080 has its
# own f36/f38/... copies the 5090 lacks). Run by dryrun.sh for --rig 4080 (cached 10 min); WSL, Windows ssh.exe (4080 alias).
C=/root/.cache/kah-dryrun/4080-testruns
if [ -d "$C" ] && [ -z "${FORCE:-}" ] && [ -n "$(find "$C" -maxdepth 0 -mmin -10 2>/dev/null)" ]; then echo "fetch4080: cached"; exit 0; fi
rm -rf "$C.new"; mkdir -p "$C.new"
SSH="timeout 90 /mnt/c/Windows/System32/OpenSSH/ssh.exe -o ConnectTimeout=8 -o BatchMode=yes 4080"
# tar over "." stops early on a locked file (game.lock, a running take's .out): name the entries instead
names=$($SSH "dir /b C:\\KenshiTestRuns" 2>/dev/null | tr -d '\r' | grep -v -x -E 'corpus|logs|inflight|queue|game\.lock|.*\.(out|mp4|png|jpg|zip|dll|play)' | tr '\n' ' ')
[ -n "$names" ] && $SSH "tar -cf - -C C:/KenshiTestRuns --exclude=*.mp4 --exclude=*.png --exclude=*.jpg --exclude=*.zip --exclude=*.dll --exclude=*.mkv --exclude=*.out --exclude=*.npz --exclude=*.bin --exclude=*.ttf $names" 2>/dev/null \
  | tar -xf - -C "$C.new" --wildcards --no-anchored '*.sh' '*.py' '*.txt' '*.list' '*.lab' 2>/dev/null
n=$(find "$C.new" -type f | wc -l)
if [ "$n" -gt 0 ]; then rm -rf "$C"; mv "$C.new" "$C"; echo "fetch4080: $n files"; else rm -rf "$C.new"; echo "fetch4080: FAILED (ssh 4080?), 4080 rows see the 5090's C:\\KenshiTestRuns"; exit 1; fi
