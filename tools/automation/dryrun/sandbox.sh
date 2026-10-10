#!/bin/bash
# sandbox.sh <rig 5090|4080> <row out dir (real)> <name> <save> <player> <mate> <timeout s> <command>
# One dry-run row in a throw-away sandbox (WSL, root; started by dryrun.sh through `unshare --mount --pid --fork`):
#   /            overlay of the real root (writes discarded)      /tmp  fresh tmpfs
#   C: drive     overlay of /mnt/c, noexec (no Windows exe can really run), at /mnt/c (5090) or /c (4080, plus its Git
#                Bash fstab: /mnt/c = C:/, /mnt/d/Steam = C:/Program Files (x86)/Steam, no other /mnt/d)
#   Kenshi dir   fake, empty: /mnt/d/Steam/steamapps/common/Kenshi (5090) or "/c/Program Files (x86)/Steam/..." (4080)
#   shims        /dryrun/bin first on PATH; the absolute ffmpeg.exe/ffprobe.exe (FFX) and, on the 4080, quser.exe are
#                bind-mounted shims; 4080: no wslpath (Git Bash has none), cygpath shim instead
# The real game, real logs, real KenshiTestRuns files and the live server are never touched; pid namespace = pkill and
# friends only see the sandbox.
set -u
RIG=$1 ROWOUT=$2 NAME=$3 SAVE=$4 PLAYER=$5 MATE=$6 TO=$7 CMD=$8
HERE=/mnt/c/KenshiModding/tools/automation/dryrun
S=$(mktemp -d /tmp/kah-dryrun.XXXXXX)
mount -t tmpfs -o size=4g none "$S" || { echo "DRYRUN $NAME FAIL sandbox: tmpfs mount failed (root needed)"; exit 3; }
mkdir -p "$S"/{ru,rw,r,cu,cw}
R=$S/r
mount -t overlay overlay -o lowerdir=/,upperdir="$S/ru",workdir="$S/rw" "$R" || { echo "DRYRUN $NAME FAIL sandbox: root overlay"; exit 3; }
mount -t proc proc "$R/proc"; mount --rbind /dev "$R/dev"; mount --make-rslave "$R/dev"; mount -t tmpfs none "$R/tmp"
if [ "$RIG" = 4080 ]; then CM=$R/c; KD="/c/Program Files (x86)/Steam/steamapps/common/Kenshi"; else CM=$R/mnt/c; KD=/mnt/d/Steam/steamapps/common/Kenshi; fi
mkdir -p "$CM"
mount -t overlay overlay -o lowerdir=/mnt/c,upperdir="$S/cu",workdir="$S/cw",noexec "$CM" || { echo "DRYRUN $NAME FAIL sandbox: C: overlay"; exit 3; }
mkdir -p "$R$KD/mods/AutomationHarness/shots" "$R$KD/RE_Kenshi/mods/Stobe"
K4=/root/.cache/kah-dryrun/4080-testruns
if [ "$RIG" = 4080 ] && [ -d "$K4" ]; then
  # the 4080's own C:\KenshiTestRuns scripts (fetch4080.sh) over the 5090's
  mkdir -p "$S/ku" "$S/kw"
  mount -t overlay overlay -o lowerdir="$K4":/mnt/c/KenshiTestRuns,upperdir="$S/ku",workdir="$S/kw",noexec "$CM/KenshiTestRuns"
fi
: > "$R$KD/KenshiFP.log"; : > "$R$KD/mods/AutomationHarness/harness.log"; touch "$R$KD/mods/AutomationHarness/enabled.flag"
# tools
mkdir -p "$R/dryrun/bin" "$R/drstate" "$R/drout"
cp -r "$HERE/lib" "$R/dryrun/lib"; cp -r /root/.cache/kah-dryrun/canned "$R/dryrun/canned"
cp /root/.cache/kah-dryrun/spec.tsv /root/.cache/kah-dryrun/saves.txt "$R/drstate/"
mount --bind "$ROWOUT" "$R/drout"
B=$R/dryrun/bin
w() { printf '#!/bin/sh\nexec /usr/bin/python3 /dryrun/lib/%s "$@"\n' "$2" > "$B/$1"; chmod +x "$B/$1"; }
w stobe-auto kahstub.py; w python3 pyshim.py; w python pyshim.py
for t in ffmpeg ffprobe ffmpeg.exe ffprobe.exe powershell.exe quser.exe tasklist.exe cmd.exe taskkill.exe schtasks.exe wsl.exe stobe-say sleep date; do
  printf '#!/bin/sh\nexec /usr/bin/python3 /dryrun/lib/fakeexe.py --as %s "$@"\n' "$t" > "$B/$t"; chmod +x "$B/$t"
done
# sleep/date: the C build of the same virtual clock (lib/drclock.c, built by dryrun.sh): no python start per poll sleep
[ -x /root/.cache/kah-dryrun/drclock ] && { cp /root/.cache/kah-dryrun/drclock "$B/sleep"; cp /root/.cache/kah-dryrun/drclock "$B/date"; }
cp "$B/stobe-auto" "$R/usr/local/bin/stobe-auto"; cp "$B/stobe-say" "$R/usr/local/bin/stobe-say"
if [ "$RIG" = 4080 ]; then
  printf '#!/bin/sh\nexec /usr/bin/python3 /dryrun/lib/fakeexe.py --as cygpath "$@"\n' > "$B/cygpath"; chmod +x "$B/cygpath"
  rm -f "$R/usr/bin/wslpath" "$R/bin/wslpath" 2>/dev/null
  mkdir -p "$CM/KAH/bin"; for f in ctl.ps1 itrun.ps1 display-check.ps1 kcfg.ps1; do [ -e "$CM/KAH/$f" ] || echo "# dryrun placeholder" > "$CM/KAH/$f"; done
  [ -e "$CM/Windows/System32/quser.exe" ] && mount --bind "$B/quser.exe" "$CM/Windows/System32/quser.exe"
else
  printf '#!/bin/sh\nexec /usr/bin/python3 /dryrun/lib/fakeexe.py --as wslpath "$@"\n' > "$B/wslpath"; chmod +x "$B/wslpath"
fi
FD="$CM/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin"
mkdir -p "$FD"; for e in ffmpeg.exe ffprobe.exe; do [ -e "$FD/$e" ] || : > "$FD/$e"; mount --bind "$B/$e" "$FD/$e"; done
cp "$HERE/row.sh" "$R/dryrun/row.sh"
if [ "$RIG" = 4080 ]; then
  # the 4080's Git Bash /etc/fstab: C:/ on /mnt/c, C:/Program Files (x86)/Steam on /mnt/d/Steam (nothing else under /mnt/d)
  mkdir -p "$R/mnt/c" "$R/mnt/d/Steam"; mount --rbind "$CM" "$R/mnt/c"; mount --rbind "$CM/Program Files (x86)/Steam" "$R/mnt/d/Steam"
fi
BASEPATH=/dryrun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EXTRA=(); [ "$RIG" = 4080 ] && EXTRA=(RIG=4080)
chroot "$R" /usr/bin/env -i HOME=/root LANG=C.UTF-8 PATH=$BASEPATH DR_BASE_PATH=$BASEPATH DR_STATE=/drstate DR_RIG="$RIG" \
  DR_KDIR="$KD" DR_CANNED=/dryrun/canned DR_SPEC=/drstate/spec.tsv DR_SAVES=/drstate/saves.txt DR_SAVE="${SAVE#-}" \
  DR_NAME="$NAME" DR_SAVEARG="$SAVE" PLAYER="$PLAYER" MATE="$MATE" DR_TO="$TO" DR_CMD="$CMD" ${DR_FIXTURE_JSON:+DR_FIXTURE_JSON=$DR_FIXTURE_JSON} ${DR_IDLE:+DR_IDLE=$DR_IDLE} ${DR_PROF:+DR_PROF=1} \
  "${EXTRA[@]}" /bin/bash /dryrun/row.sh
rc=$?
# files the row wrote on C: (label files, outputs) for the analyzer, as paths in the rig's form
P=/mnt/c; [ "$RIG" = 4080 ] && P=/c
{ ( cd "$S/cu" && find . -type f -newer "$R/drstate/spec.tsv" | sed "s#^\.#$P#" )
  [ -d "$S/ku" ] && ( cd "$S/ku" && find . -type f | sed "s#^\.#$P/KenshiTestRuns#" ); } > "$ROWOUT/written.txt" 2>/dev/null
mkdir -p "$ROWOUT/labels"
grep -E '(\.lab|/lab[^/]*\.txt|/labels[^/]*\.txt|/s3lab[^/]*\.txt)$' "$ROWOUT/written.txt" | while IFS= read -r f; do
  cp "$R$f" "$ROWOUT/labels/$(echo "$f" | tr '/ ' '__')" 2>/dev/null
done
# small text outputs (labels, evidence, .out) for debugging a FAIL
grep -E '\.(lab|txt|out|log|csv|tsv)$' "$ROWOUT/written.txt" | head -400 | while IFS= read -r f; do
  [ "$(stat -c %s "$R$f" 2>/dev/null || echo 9999999)" -lt 400000 ] && { mkdir -p "$ROWOUT/files$(dirname "$f")"; cp "$R$f" "$ROWOUT/files$f"; }
done
cp "$R/drstate/"{calls.log,flags.log,recordings.jsonl,labels.list,prof} "$ROWOUT/" 2>/dev/null
[ -f "$R/drstate/labels.list" ] && while IFS= read -r f; do cp "$R$f" "$ROWOUT/labels/$(echo "$f" | tr '/ ' '__')" 2>/dev/null; done < "$R/drstate/labels.list"
exit $rc
