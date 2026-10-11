#!/bin/bash
# kfp-pipeline.sh -- one command per KenshiFP build (WSL, root): scratch tree -> pending patches -> DLL -> FULL animlab gate
# with a per-patch delta -> staged DLL for both rigs. Never touches /root/KenshiFP (kfp-fixer owns it). No game.
#
# Usage (inside WSL DwemerAI4Skyrim3 as root; start long runs detached: setsid nohup bash kfp-pipeline.sh ... > log 2>&1 &):
#   kfp-pipeline.sh [--combined] [--base live|rev:<KenshiModding rev>|dir:<tree root>] [--revert <patch>]...
#                   [--patches <p1,p2,..> | --all-pending] [--exclude <p1,..>] [--jobs N] [--drop 0.05] [--stage|--no-stage]
#                   [--no-4080] [--keep] [--per-patch] [--out DIR]
# COMBINED-FIRST (Shay 2026-10-10, build cycle ~1 h -> ~10 min): the gate runs only 'base' and 'all' first. When 'all'
#   shows no SET regression vs base (no BREAK/newfail row base->all, gate FAIL only from known-base flips) it is staged
#   right away. Only when it fails are the per-patch trees (+P alone, -P set minus P) gated to name the breaking patch
#   (BREAK logic below, combined re-run without it). --per-patch (env KFP_PER_PATCH=1) always gates every tree (old mode).
# ONE BUILD LINE (Shay 2026-10-10): rigs never choose between builds. The default run (no --patches/--all-pending) is
#   --combined = base + EVERY pending-fixes/kfp-* patch; a patch that conflicts in the set or BREAKs in-set is left out
#   (named in the final line as excluded=<p>:<why>) and the run repeats without it (new run dir <run>-x<k>), so the rest
#   still ships. Gate failures that fail identically on the base (gate "flipped" keys that flip on base too, e.g. pool s1
#   while a known refit is pending) are KNOWN-BASE: reported (known-base=...), never blocking; only a gate failure the
#   patches cause (BREAK in delta.tsv, or a new flip/mutation miss on 'all') blocks. Staging (any mode) makes the build
#   THE build: C:\KenshiTestRuns\staged\KenshiFP-latest.txt (+ C:\KAH\staged on the 4080) names it, staged KenshiFP-*.dll
#   older than THE build and the one before it are deleted on both rigs (newest 2 kept), older "staged-build: KenshiFP" queue lines are replaced by one new line.
#   install-dll.ps1 KenshiFP -Staged [-Rig 4080] installs the latest pointer. --patches/--all-pending runs are trial builds:
#   they don't stage unless --stage is given. Watcher: kfp-buildwatch.sh reruns --combined when pending-fixes/kfp-* or
#   /root/KenshiFP change (90 s quiet). Each run holds C:\KenshiTestRuns\inflight\kfp-pipeline-<run> while it runs.
#   --exclude   leave these patches out (combined re-runs use it; env KFP_EXCL_NOTE carries the reasons)
#   --base      live (default) = /root/KenshiFP incl. its uncommitted working tree; rev: = components/KenshiFP snapshot at a
#               KenshiModding git rev; dir: = any tree root (client/, re_plugin/, tests/)
#   --revert    take a patch that is already IN the base back out first (to measure it as a pending patch): its diff is made
#               on the newest components/KenshiFP snapshot rev where the patch applies, then reverse-applied (patch -R) per
#               file (files of it the base doesn't have are skipped)
#   --patches   comma list in APPLY ORDER; a name resolves to a path, pending-fixes/<name>, pending-fixes/kfp-<name>.py|.patch
#   --all-pending  every pending-fixes/kfp-*.py|kfp-*.patch, name order (LC_ALL=C); patches already in the base are
#               detected (their diff reverse-applies) and skipped with status in-base; ones that conflict with the base
#               (superseded, or applied with no snapshot rev to diff against) are skipped with a warning (fatal with --patches)
#   --jobs      gate runs in parallel (default 6, env KFP_JOBS; at 3 the WSL load sat at ~5 of 32 cores, 2026-10-11)
#   --drop      take-rate drop that counts as a break in the per-patch delta (default 0.05)
#   --stage-from <run dir>  only stage that run's DLL (after a FAIL the coordinator accepted, e.g. a baseline change)
#   --stage     stage a --patches/--all-pending run (default only for --combined and --stage-from)
#   --no-stage  stop after the verdict; --no-4080: stage on the 5090 only; --keep: keep the scratch trees
#   env KFP_STAGED / KFP_QUEUE / KFP_STAGED_4080 override the staging dirs (tests)
# Stages:
#   1 base   copy the base into $RUN/base (and apply --revert)
#   2 patch  each patch alone on the base (pending | partial: some files already in the base, the rest applied from its
#            diff | in-base | conflict-base), then the full set in order; when the set
#            fails, every earlier patch is paired with the failing one so the offending combination is named
#   3 build  re_plugin/build.sh in the scratch tree (it builds relative to its own dir) -> KenshiFP.dll + sha8
#   4 gate   components/KenshiFP/animlab/gate.sh, unchanged, in a private mount namespace per tree: the tree is bind-mounted
#            on /root/KenshiFP, /root/animlab-build is an overlay, /root/animlab-{kfp-src,gate,work} empty private dirs, /tmp is private, the lab scripts
#            (animlab/ + harness tools/animlab) and fp-viewmodel.sh are a snapshot taken at the start. So runs are parallel,
#            consistent and leave nothing behind. Trees gated: base + all; only when they regress (or --per-patch): +P (alone, N>=2), -P (set minus P,
#            N>=3). The gate pools EVERY stroke with key tables (0..VM_NSTROKE-1) + corpus pool/strokes.tsv. Mutations
#            only on 'all'.
#            Delta ($RUN/delta.tsv): per patch, alone (base -> +P) and in-set (set minus P -> all): every gate verdict
#            flip and every pool take rate change >= 0.02 (s<n>.take_all / arc / blade / stroke). BREAK = PASS->FAIL, a check
#            new in the patch's tree that FAILs there (the patch ships a check it fails), or a drop >= --drop in-set (e.g. "DELTA kfp-pt30-flip in-set s1.take_all 0.95 -> 0.64 BREAK").
#   5 stage  on PASS: C:\KenshiTestRuns\staged\KenshiFP-<sha8>.dll (+ .txt manifest) + KenshiFP-latest.txt, same on the
#            4080 in C:\KAH\staged (+ C:\KAH\inst-staged.ps1), SHA256 checked on both sides, staged KenshiFP DLLs
#            older than the previous build removed (newest 2 kept); queue\5090.next / 4080.next get ONE "staged-build: KenshiFP" line (older ones replaced).
#            Install at each rig's next restart (Kenshi closed):
#              5090: install-dll.ps1 KenshiFP -Staged          4080: install-dll.ps1 KenshiFP -Staged -Rig 4080
# Output: one final line  PIPELINE PASS <sha8> patches=<..> [excluded=..] [known-base=..] gate=<summary> run=<dir>
#                     or  PIPELINE FAIL <stage> <reason> delta=<delta.tsv> run=<dir>     (exit 0 / 1)
# Lab on the 4080 CPU: not used. The pool runs the Linux adapter binary (needs Linux); the 4080 has Windows Python 3.13 +
# numpy 2.3.4 but its only WSL distro is the (stopped) LLM stack, and it has 12 logical cores vs 32 here, so a gate there
# would be slower and would mean starting that distro. Not worth it; the 5090 runs the gates in parallel instead.
set -u
# offline lab job (Shay 2026-10-10: the game never waits for analysis): the whole pipeline (build, gate, regress, frames,
# ffmpeg) runs at nice 15 / ionice idle; every child inherits it (run-comb-1535-x1 ran its gate at nice 0, load 28/32)
renice -n 15 -p $$ >/dev/null 2>&1; ionice -c 3 -p $$ >/dev/null 2>&1
# run from a private copy: editing this file while a run is in flight must not change the running script
if [ -z "${KFP_PIPELINE_COPY:-}" ]; then c=$(mktemp /tmp/kfp-pipeline.XXXXXX); cp "$0" "$c"; KFP_PIPELINE_COPY=$c exec bash "$c" "$@"; fi
IFL=""; trap 'rm -f "$KFP_PIPELINE_COPY" $IFL' EXIT
WS=/mnt/c/KenshiModding; PF=$WS/pending-fixes; LIVE=/root/KenshiFP; PR=/root/kfp-pipeline
LABK=$WS/components/KenshiFP/animlab; LABH=$WS/Kenshi-Automation-Harness/tools/animlab
STAGED=${KFP_STAGED:-/mnt/c/KenshiTestRuns/staged}; QD=${KFP_QUEUE:-/mnt/c/KenshiTestRuns/queue}; R4DIR=${KFP_STAGED_4080:-'C:\KAH\staged'}
SSH=/mnt/c/Windows/System32/OpenSSH/ssh.exe; SCP=/mnt/c/Windows/System32/OpenSSH/scp.exe
BASE=live; REVERTS=(); PLIST=""; ALLP=0; JOBS=${KFP_JOBS:-6}; DROP=0.05; STAGE=""; R4080=1; KEEP=0; RUN=""; SFROM=""; COMB=0; EXCL=""
PERP=${KFP_PER_PATCH:-0}   # 1 = always gate the per-patch trees (old mode); 0 = combined-first (per-patch only on a failure)
KA=()   # args a combined re-run keeps
while [ $# -gt 0 ]; do case "$1" in
  --base) BASE=$2; KA+=("$1" "$2"); shift;; --revert) REVERTS+=("$2"); KA+=("$1" "$2"); shift;; --patches) PLIST=$2; shift;;
  --all-pending) ALLP=1;; --combined) COMB=1;; --exclude) EXCL=$2; shift;; --stage) STAGE=1; KA+=("$1");;
  --jobs) JOBS=$2; KA+=("$1" "$2"); shift;; --drop) DROP=$2; KA+=("$1" "$2"); shift;; --no-stage) STAGE=0; KA+=("$1");;
  --no-4080) R4080=0; KA+=("$1");; --keep) KEEP=1; KA+=("$1");; --per-patch) PERP=1; KA+=("$1");;
  --out) RUN=$2; shift;; --stage-from) SFROM=$2; shift;; -h|--help) sed -n '2,64p' "$0"; exit 0;;
  *) echo "kfp-pipeline: unknown arg $1"; exit 2;; esac; shift; done
[ -z "$PLIST" ] && [ $ALLP = 0 ] && [ -z "$SFROM" ] && COMB=1   # default = the one combined build line
[ $COMB = 1 ] && { [ -n "$PLIST" ] && { echo "kfp-pipeline: --combined takes every pending patch (use --exclude, not --patches)"; exit 2; }; ALLP=1; }
STAGE=${STAGE:-$COMB}; EXNOTE=${KFP_EXCL_NOTE:-}
[ "$(id -u)" = 0 ] || { echo "PIPELINE FAIL setup run as root in WSL (needs unshare/mount)"; exit 1; }
[ -n "$SFROM" ] && { RUN=$SFROM; KEEP=1; }
RUN=${RUN:-$PR/run-$(date +%m%d-%H%M%S)}; mkdir -p "$RUN"/{diffs,logs,snap}; D=$RUN/delta.tsv
IFL=/mnt/c/KenshiTestRuns/inflight/kfp-pipeline-$(basename "$RUN"); [ -n "${KFP_STAGED:-}" ] && IFL=""   # tests: no marker
[ -n "$IFL" ] && { mkdir -p "$(dirname "$IFL")"; echo "$RUN" > "$IFL"; }
echo $$ > "$RUN/pipeline.pid"   # wait-event.ps1 -Producer kfp-pipeline-<run>: PRODUCER GONE when this run dies without staging
say() { echo "$*" | tee -a "$RUN/pipeline.log"; }
die() { say "PIPELINE FAIL $1 $2${EXNOTE:+ excluded=$EXNOTE} delta=$D run=$RUN"; cleanup; exit 1; }
# rerun_without <names> <why>: combined mode leaves these patches out and repeats the run (the rest still ships)
rerun_without() { local ex=${EXCL:+$EXCL,}$1 k=1 n; for n in ${1//,/ }; do EXNOTE="${EXNOTE:+$EXNOTE;}$n:$2"; done
  while [ -e "${RUN%-x*}-x$k" ]; do k=$((k+1)); done
  say "COMBINED leaving out $1 ($2); rerun -> ${RUN%-x*}-x$k"; cleanup; rm -f $IFL
  KFP_EXCL_NOTE=$EXNOTE exec bash "$KFP_PIPELINE_COPY" --combined "${KA[@]}" --exclude "$ex" --out "${RUN%-x*}-x$k"; }
cleanup() { [ $KEEP = 1 ] && return; rm -rf "$RUN"/tree-* "$RUN"/ns-* "$RUN"/snap "$RUN"/base "$RUN"/pre-*
  ls -dt "$PR"/run-* 2>/dev/null | tail -n +6 | xargs -r rm -rf; }   # keep the newest 5 runs (small: logs, gate outputs)
# stage_dll <dll> <patches> <gate note>: copy to $STAGED (+ manifest) and the 4080 (SHA checked), queue lines; sets ST
stage_dll() { local dll=$1 pn=$2 note=$3 sha h sd ql rh; sha=$(sha256sum "$dll" | cut -d' ' -f1); h=$(echo "${sha:0:8}" | tr a-f A-F)
  mkdir -p "$STAGED"; sd=$STAGED/KenshiFP-$h.dll; cp "$dll" "$sd"
  [ "$(sha256sum "$sd" | cut -d' ' -f1)" = "$sha" ] || die stage "5090 copy sha mismatch"
  printf 'KenshiFP %s sha256 %s\nstaged %s by kfp-pipeline (%s)\nbase %s reverted=%s\npatches %s\ngate %s\nrun %s\n' "$h" "$sha" "$(date '+%F %T')" "$note" \
    "$BASE" "$(for r in "${REVERTS[@]}"; do printf '%s,' "$(pname "$r")"; done)" "$pn" "$(head -1 "$RUN/gate-all/RESULT.txt" 2>/dev/null)" "$RUN" > "${sd%.dll}.txt"
  { printf 'KenshiFP %s sha256 %s\npatches %s\n' "$h" "$sha" "$pn"; printf 'excluded %s\nknown-base %s\n' "${EXNOTE:-none}" "${KB:-none}"
    printf 'staged %s by kfp-pipeline (%s)\nrun %s\n' "$(date '+%F %T')" "$note" "$RUN"; } > "$STAGED/KenshiFP-latest.txt.new"
  mv -f "$STAGED/KenshiFP-latest.txt.new" "$STAGED/KenshiFP-latest.txt"   # line 1 = THE build every rig installs
  # superseded: keep THE build + the one before it (lists still naming the previous build can install it), drop older ones
  ls -t "$STAGED"/KenshiFP-*.dll 2>/dev/null | grep -vxF "$sd" | tail -n +2 | while read -r o; do rm -f "$o" "${o%.dll}.txt"; done
  ST=5090; ql="staged-build: KenshiFP $h ($(date '+%F %H:%M') kfp-pipeline, patches=$pn, $note)"
  for q in "$QD/5090.next" "$QD/4080.next"; do [ -f "$q" ] && sed -i '/^staged-build: KenshiFP /d' "$q"; done
  echo "$ql -> before the next batch (Kenshi closed): install-dll.ps1 KenshiFP -Staged" >> "$QD/5090.next"
  if [ $R4080 = 1 ]; then
    if timeout 60 "$SSH" -n 4080 "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force $R4DIR | Out-Null\"" > /dev/null \
       && timeout 300 "$SCP" -q < /dev/null "$(wslpath -w "$sd")" "$(wslpath -w "${sd%.dll}.txt")" "$(wslpath -w "$STAGED/KenshiFP-latest.txt")" "4080:${R4DIR//\\//}/" \
       && timeout 60 "$SCP" -q < /dev/null "$(wslpath -w "$WS/tools/automation/rig4080/inst-staged.ps1")" 4080:C:/KAH/; then
      rh=$(timeout 60 "$SSH" -n 4080 "powershell -NoProfile -Command \"(Get-FileHash $R4DIR\KenshiFP-$h.dll).Hash\"" | tr -d '\r\n' | tr A-F a-f)
      if [ "$rh" = "$sha" ]; then ST="5090,4080"
        timeout 60 "$SSH" -n 4080 "powershell -NoProfile -Command \"Get-ChildItem $R4DIR\\KenshiFP-*.dll | Where-Object { \$_.Name -notlike 'KenshiFP-$h.*' } | Sort-Object LastWriteTime -Descending | Select-Object -Skip 1 | ForEach-Object { Remove-Item -Force -ErrorAction SilentlyContinue \$_.FullName, (\$_.FullName -replace '[.]dll\$','.txt') }\"" > /dev/null || say "STAGE 4080 could not remove superseded builds"
        echo "$ql -> before the next batch (Kenshi closed): install-dll.ps1 KenshiFP -Staged -Rig 4080 (or on the 4080: C:\KAH\inst-staged.ps1)" >> "$QD/4080.next"
      else say "STAGE 4080 sha mismatch (${rh:-none}): not staged there"; fi
    else say "STAGE 4080 unreachable: not staged there"; fi
  fi
  say "STAGE $ST $sd"; }
pname() { local b; b=$(basename "$1"); echo "${b%.*}"; }
resolve() { local n=$1 c; for c in "$n" "$PF/$n" "$PF/kfp-$n.py" "$PF/kfp-$n.patch" "$PF/$n.py" "$PF/$n.patch"; do
    [ -f "$c" ] && { readlink -f "$c"; return 0; }; done; return 1; }
# apply_one <patch> <tree>: .py = python3 <script> <tree root>; .patch/.diff = git apply -p1 (fallback patch -p1)
apply_one() { case "$1" in
  *.py) python3 "$1" "$2" ;;
  *) (cd "$2" && { git apply -p1 --whitespace=nowarn "$1" 2>/dev/null || patch -s -p1 --no-backup-if-mismatch < "$1"; }) ;; esac; }
# snapshot <rev> -> tree root of components/KenshiFP at that KenshiModding rev (cached in the run)
snapshot() { local d=$RUN/pre-$1; [ -d "$d" ] || { mkdir -p "$d"; git -C "$WS" archive "$1" components/KenshiFP | tar -x -C "$d" --strip-components=2; }; echo "$d"; }
# mkdiff <patch>: unified diff of the patch, made on the newest snapshot rev where it applies whole (scripts aren't reversible)
mkdiff() { local p=$1 n out r pre t; n=$(pname "$p"); out=$RUN/diffs/$n.diff; [ -s "$out" ] && { echo "$out"; return 0; }
  case "$p" in *.py) ;; *) cp "$p" "$out"; echo "$out"; return 0;; esac
  for r in HEAD $(git -C "$WS" log --format=%h -n 40 HEAD -- components/KenshiFP | sed 's/$/~1/'); do
    pre=$(snapshot "$r"); t=$RUN/pre-try; rm -rf "$t"; cp -a "$pre" "$t"
    if apply_one "$p" "$t" > /dev/null 2>&1; then (cd "$RUN" && diff -ruN --exclude='*.pyc' "pre-$r" pre-try | sed "s#^--- pre-$r/#--- a/#; s#^+++ pre-try/#+++ b/#") > "$out"
      rm -rf "$t"; [ -s "$out" ] && { echo "$out"; return 0; }; fi
  done; rm -rf "$RUN/pre-try"; return 1; }
# chunks <diff> <dir>: split a unified diff per file; fstate <chunk> <tree>: applied | pending | conflict (per-file state,
# so a patch whose parts were already committed separately is still handled: applied files skipped, the rest applied)
chunks() { rm -rf "$2"; mkdir -p "$2"; awk -v o="$2" '/^diff /{n++} n>0 {print > sprintf("%s/%03d.diff",o,n)}' "$1"; }
fstate() { if (cd "$2" && patch -R -p1 --dry-run -s -f < "$1" > /dev/null 2>&1); then echo applied
  elif (cd "$2" && patch -p1 --dry-run -s -f < "$1" > /dev/null 2>&1); then echo pending; else echo conflict; fi; }
cfile() { awk '/^\+\+\+ b\//{sub(/^\+\+\+ b\//,""); sub(/\t.*/,""); print; exit}' "$1"; }
declare -A APPLY
if [ -n "$SFROM" ]; then   # stage an earlier run's DLL (e.g. a gate FAIL the coordinator accepted as a baseline change)
  DL_=$(ls "$RUN"/KenshiFP-*.dll 2>/dev/null | head -1); [ -f "$DL_" ] || die stage "no DLL in $RUN"
  echo "kfp-pipeline --stage-from $(date '+%F %T')" >> "$RUN/pipeline.log"; ST=unstaged
  stage_dll "$DL_" "$(awk -F'	' 'NR>1 && $2 ~ /^(pending|partial)/ {printf "%s,", $1}' "$RUN/patches.tsv" 2>/dev/null | sed 's/,$//')" "staged from run by hand: $(head -1 "$RUN/gate-all/RESULT.txt" 2>/dev/null | awk '{print "gate", $3}')"
  echo "PIPELINE STAGED $(basename "$DL_" .dll | cut -c10-) staged=$ST run=$RUN"; exit 0; fi
# --- 1 base ---------------------------------------------------------------------------------------------------------
B=$RUN/base
case "$BASE" in
  live) rsync -a --exclude .git --exclude '*.o' "$LIVE/" "$B/" ;;
  rev:*) cp -a "$(snapshot "${BASE#rev:}")" "$B" ;;
  dir:*) rsync -a --exclude .git "${BASE#dir:}/" "$B/" ;;
  *) die base "unknown --base $BASE" ;; esac
[ -f "$B/client/kfp_viewmodel.inc" ] && [ -f "$B/re_plugin/build.sh" ] || die base "no KenshiFP tree at $BASE"
for rv in "${REVERTS[@]}"; do p=$(resolve "$rv") || die base "revert patch not found: $rv"
  df=$(mkdiff "$p") || die base "revert $(pname "$p"): no snapshot rev where it applies"
  cd_=$RUN/chunks-r; chunks "$df" "$cd_"; rv_=""; sk_=""
  for c in "$cd_"/*.diff; do case $(fstate "$c" "$B") in
    applied) (cd "$B" && patch -R -s -f -p1 --no-backup-if-mismatch < "$c") >> "$RUN/logs/revert-$(pname "$p").txt" 2>&1; rv_="$rv_ $(cfile "$c")";;
    pending) sk_="$sk_ $(cfile "$c")";;
    *) die base "revert $(pname "$p"): $(cfile "$c") neither applied nor pending in the base";; esac; done
  rm -rf "$cd_"; [ -n "$rv_" ] || die base "revert $(pname "$p"): nothing of it is in the base"
  say "BASE reverted $(pname "$p") (files:$rv_${sk_:+; not in base, skipped:$sk_})"; done
say "BASE $BASE ok ($(cd "$B/client" && cat *.c *.inc *.h 2>/dev/null | sha256sum | cut -c1-12))"
# lab snapshot for every gate of this run
cp -a "$LABK" "$RUN/snap/kfp"; cp -a "$LABH" "$RUN/snap/harness"; rm -rf "$RUN"/snap/*/__pycache__
# --- 2 patch --------------------------------------------------------------------------------------------------------
P=()
if [ $ALLP = 1 ]; then while read -r f; do case ",$EXCL," in *",$(pname "$f"),"*|*",$(pname "$f" | sed 's/^kfp-//'),"*) continue;; esac; P+=("$f")
  done < <(ls "$PF"/kfp-*.py "$PF"/kfp-*.patch 2>/dev/null | LC_ALL=C sort)
  [ -n "$EXCL" ] && say "PATCH excluded: $EXCL"
else IFS=, read -ra L_ <<< "$PLIST"; for n in "${L_[@]}"; do [ -n "$n" ] || continue; p=$(resolve "$n") || die patch "not found: $n"; P+=("$p"); done; fi
S=(); bad=""; skip=""
printf 'patch\tstatus\tdetail\n' > "$RUN/patches.tsv"
for p in "${P[@]}"; do n=$(pname "$p"); t=$RUN/tree-alone; rm -rf "$t"; cp -a "$B" "$t"
  # per-file state of its diff first: a script whose anchor survives its own edit "applies" again on a tree that has it
  na=0; np=0; nc=0; rest=$RUN/diffs/$n.rest.diff; : > "$rest"; hd=0
  if df=$(mkdiff "$p" 2>/dev/null); then hd=1; cd_=$RUN/chunks-$n; chunks "$df" "$cd_"
    for c in "$cd_"/*.diff; do case $(fstate "$c" "$B") in applied) na=$((na+1));; pending) np=$((np+1)); cat "$c" >> "$rest";; *) nc=$((nc+1));; esac; done
    rm -rf "$cd_"; fi
  if [ $hd = 1 ] && [ $nc = 0 ] && [ $np = 0 ]; then st=in-base
  elif apply_one "$p" "$t" > "$RUN/logs/alone-$n.txt" 2>&1; then
    if diff -rq "$B" "$t" > /dev/null 2>&1; then st="in-base(no-op)"; else st=pending; S+=("$p"); fi
  elif [ $hd = 1 ] && [ $nc = 0 ]; then st="partial($na file(s) already in base, $np applied from its diff)"; APPLY[$n]=$rest; S+=("$p")
  elif [ $ALLP = 1 ]; then st="skipped:conflict-base$([ $hd = 0 ] && echo ',no-snapshot-rev-applies(applied-or-superseded?)')"; skip="$skip $n"
  else st=conflict-base; bad="$bad $n"; fi
  why=$(grep -m1 -E 'AssertionError|anchor|error|rejects|FAILED' "$RUN/logs/alone-$n.txt" 2>/dev/null | sed 's/^ *//' | cut -c1-140)
  case "$st" in pending|partial*|in-base*) why="";; esac; printf '%s\t%s\t%s\n' "$n" "$st" "$why" >> "$RUN/patches.tsv"; say "PATCH $n $st${why:+ ($why)}"
done; rm -rf "$RUN/tree-alone"
[ -n "$bad" ] && die patch "conflict with the base:${bad} (anchor errors in $RUN/patches.tsv)"
# apply_set <tree> <patch...>: in order; prints the first failing patch name
apply_set() { local t=$1 p; shift; rm -rf "$t"; cp -a "$B" "$t"; for p in "$@"; do
    apply_one "${APPLY[$(pname "$p")]:-$p}" "$t" > "$RUN/logs/set-$(basename "$t")-$(pname "$p").txt" 2>&1 || { pname "$p"; return 1; }; done; }
N=${#S[@]}; T_ALL=$RUN/tree-all
if ! f=$(apply_set "$T_ALL" "${S[@]}"); then
  i=0; for p in "${S[@]}"; do [ "$(pname "$p")" = "$f" ] && break; i=$((i+1)); done; pairs=""
  for q in "${S[@]:0:$i}"; do apply_set "$RUN/tree-pair" "$q" "${S[$i]}" > /dev/null || pairs="$pairs $(pname "$q")+$f"; done
  rm -rf "$RUN/tree-pair"
  [ $COMB = 1 ] && rerun_without "$f" "set-conflict${pairs:+(${pairs# })}"
  die patch "set fails at $f: ${pairs:+conflicting pair(s):$pairs}${pairs:-no single pair fails, conflicts with the combination of the earlier patches}"
fi
say "PATCH set ok: ${N} pending ($(for p in "${S[@]}"; do printf '%s ' "$(pname "$p")"; done))"
# --- 3 build --------------------------------------------------------------------------------------------------------
(cd "$T_ALL/re_plugin" && bash build.sh) > "$RUN/logs/build.txt" 2>&1 || die build "re_plugin/build.sh failed: $(grep -m1 -i error "$RUN/logs/build.txt" | cut -c1-160) (log $RUN/logs/build.txt)"
DLL=$T_ALL/re_plugin/KenshiFP.dll; SHA=$(sha256sum "$DLL" | cut -d' ' -f1); H=$(echo "${SHA:0:8}" | tr a-f A-F)
cp "$DLL" "$RUN/KenshiFP-$H.dll"; say "BUILD KenshiFP $H"
mkdir -p "$PR/src" && tar czf "$PR/src/KenshiFP-$H.client.tar.gz" -C "$T_ALL" client && say "SRC $PR/src/KenshiFP-$H.client.tar.gz"   # exact source of this DLL: animlab agree-pose.sh replays its recordings with it (lab-calibrate)
# --- 4 gate ---------------------------------------------------------------------------------------------------------
declare -A TREE CTX
TREE[all]=$T_ALL
if [ $N -ge 1 ]; then TREE[base]=$B; fi
for p in "${S[@]}"; do n=$(pname "$p")   # CTX[P] = the tree P's in-set compare starts from
  if [ $N = 1 ]; then CTX[$n]=base; elif [ $N = 2 ]; then for q in "${S[@]}"; do [ "$q" = "$p" ] || CTX[$n]=+$(pname "$q"); done; else CTX[$n]=-$n; fi; done
gate_ns() {  # <label> <tree>
  local l=$1 t=$2 ns=$RUN/ns-$1 o=$RUN/gate-$1 mut=--no-mutate; [ "$1" = all ] && mut=""
  mkdir -p "$ns/tmp"; chmod 1777 "$ns/tmp"
  T=$t NS=$ns O=$o MUT=$mut SNAP=$RUN/snap WS=$WS unshare -m --propagation private bash -c '
    set -e; mount --bind "$T" /root/KenshiFP
    mkdir -p /root/animlab-build "$NS/up" "$NS/wk"   # prebuilt adapters regress.sh uses: overlay (writes stay private)
    mount -t overlay overlay -o lowerdir=/root/animlab-build,upperdir=$NS/up,workdir=$NS/wk /root/animlab-build
    rm -rf /root/animlab-build/kfpvm_cur /root/animlab-build/kfpvm_drive_cur   # a failed adapter build must not pool a stale binary
    for d in animlab-kfp-src animlab-gate animlab-work; do mkdir -p /root/$d "$NS/$d"; mount --bind "$NS/$d" /root/$d; done   # filled by the gate itself
    mount --bind "$NS/tmp" /tmp
    mount --bind "$SNAP/kfp" "$WS/components/KenshiFP/animlab"; mount --bind "$SNAP/harness" "$WS/Kenshi-Automation-Harness/tools/animlab"
    [ -f "$T/tests/ingame/fp-viewmodel.sh" ] && mount --bind "$T/tests/ingame/fp-viewmodel.sh" "$WS/components/KenshiFP/tests/ingame/fp-viewmodel.sh"
    set +e; bash "$WS/components/KenshiFP/animlab/gate.sh" --out "$O" $MUT' > "$RUN/logs/gate-$l.txt" 2>&1
  echo $? > "$RUN/logs/gate-$l.rc"; rm -rf "$ns"
}
# metrics <label> -> key \t value  (gate verdict keys + pool take rates per stroke)
# >>> decide-fns (kfp-pipeline-selftest.sh sources this block)
# metrics: keys normalized (a trailing ':' dropped: 'agree: ' with empty text keyed 'agree:' and counted as a new FAIL
# for every patch, 2026-10-11 run-watch-1011-1606); a REGRESS FAIL whose text is empty or starts with INFRA (the check
# produced no result: crash/kill/missing output) gets verdict INFRA = infrastructure, never a patch BREAK.
metrics() { local o=$RUN/gate-$1; [ -f "$o/verdicts.tsv" ] && awk -F'\t' -v rf="$o/regress.txt" 'BEGIN {
      while ((getline l < rf) > 0) { if (l !~ /^REGRESS FAIL /) continue; t=substr(l,14); sub(/[ \t\r]+$/,"",t); r="x"
        i=index(t,": "); if (i) { k=substr(t,1,i-1); r=substr(t,i+2) } else if (t ~ /:$/) { k=substr(t,1,length(t)-1); r="" } else continue
        gsub(/^[ \t]+|[ \t]+$/,"",r); gsub(/[0-9]+(\.[0-9]+)?/,"#",k); if (r=="" || r ~ /^INFRA/) inf[k]=1 } }
    { k=$1; sub(/:$/,"",k); v=$2; if (v=="FAIL" && (k in inf)) v="INFRA"; print k "\t" v }' "$o/verdicts.tsv"
  [ -f "$o/pool.txt" ] && awk '$1=="pool" && $2=="stroke" {s=$3; for (i=5;i<=NF;i++) { f=$i
      if (f ~ /^take_all=/) { split(f,a,"="); print "s" s ".take_all\t" a[2] }
      else if (f ~ /^[a-z]+:take=/) { split(f,a,":"); split(a[2],b,"="); split(b[2],c,"/"); print "s" s "." a[1] "\t" c[1] } } }' "$o/pool.txt"; }
# run_gates <label...>: gate these trees ($JOBS at a time), metrics + one line each; a tree whose lab adapter doesn't
# build from its source makes every pool/delta invalid: fail right there (no per-patch round on top of it)
labels=()   # every label gated in this run
run_gates() { local l e g; say "GATE $# trees ($*), $JOBS at a time"
  for l in "$@"; do while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done; gate_ns "$l" "${TREE[$l]}" & done; wait
  for l in "$@"; do labels+=("$l"); metrics "$l" > "$RUN/metrics-$l.tsv"; g=$(cat "$RUN/gate-$l/RESULT.txt" 2>/dev/null | head -1)
    say "GATE $l rc=$(cat "$RUN/logs/gate-$l.rc") ${g:-no RESULT (log $RUN/logs/gate-$l.txt)}" | cut -c1-400; done
  for l in "$@"; do e=$(grep -A3 -E '^REGRESS FAIL build-(current|drive-current)' "$RUN/gate-$l/regress.txt" 2>/dev/null | grep -m1 -E 'error|FAIL' | cut -c1-200)
    [ -z "$e" ] || die lab-build "tree $l: the lab adapter does not build from this source, pools/deltas invalid: $e"; done; }
# compare <patch> <kind> <before label> <after label> -> delta rows
compare() { awk -F'\t' -v p="$1" -v k="$2" -v dr="$DROP" 'NR==FNR {a[$1]=$2; next} {b[$1]=$2}
  END { for (x in a) { if (!(x in b)) { if (a[x]=="PASS") print p "\t" k "\t" x "\t" a[x] "\t-\t-\tGONE"; continue }
          if (a[x] ~ /^[0-9.]+$/ && b[x] ~ /^[0-9.]+$/) { d=b[x]-a[x]; if (d>=0.02 || d<=-0.02) {
              f=(d<=-dr ? (k=="alone" ? "drop" : "BREAK") : (d<0 ? "drop" : "gain")); printf "%s\t%s\t%s\t%s\t%s\t%+.2f\t%s\n", p, k, x, a[x], b[x], d, f } }
          else if (a[x]!=b[x]) print p "\t" k "\t" x "\t" a[x] "\t" b[x] "\t-\t" (a[x]=="INFRA" || b[x]=="INFRA" ? "infra" : a[x]=="PASS" && b[x]=="FAIL" ? (k=="alone" ? "flip" : "BREAK") : (a[x]=="FAIL" && b[x]=="PASS" ? "fix" : "changed")) }
        for (x in b) if (!(x in a)) print p "\t" k "\t" x "\t-\t" b[x] "\t-\t" (b[x]=="INFRA" ? "infra" : b[x] ~ /^FAIL/ && x != "" ? (k=="in-set" ? "BREAK" : "newfail") : "new") }' "$RUN/metrics-$3.tsv" "$RUN/metrics-$4.tsv" | sort -t$'\t' -k3,3; }
# kb_eval: a gate-all FAIL whose only cause is baseline flips the base gate shows identically = KNOWN-BASE (sets KB,
# non-blocking); anything else sets GB (the blocking reason; nores = no RESULT). The delta blocks every flip a patch causes.
kb_eval() { local gl why fa fb newf; KB=""; GB=""; [ "$(cat "$RUN/logs/gate-all.rc" 2>/dev/null)" = 0 ] && return 0
  gl=$(head -1 "$RUN/gate-all/RESULT.txt" 2>/dev/null); [ -n "$gl" ] || { GB=nores; return 0; }
  why=$(echo "$gl" | grep -o 'why=[^ ]*' | cut -d= -f2); fa=$(echo "$gl" | grep -o 'flipped=[^ ]*' | cut -d= -f2-)
  if [ $N -ge 1 ]; then fb=$(head -1 "$RUN/gate-base/RESULT.txt" 2>/dev/null | grep -o 'flipped=[^ ]*' | cut -d= -f2-); else fb=$fa; fi
  newf=$(comm -23 <(echo "$fa" | tr ';' '\n' | grep -E '^(PASS->|GONE:)' | sort -u) <(echo "$fb" | tr ';' '\n' | sort -u) | paste -sd';')
  # a FAIL key on 'all' that is not FAIL on base (or no base) = caused by the patches; mutation-missed only runs on 'all'
  nfk=""; [ $N -ge 1 ] && nfk=$( [ -f "$RUN/metrics-base.tsv" ] && awk -F'\t' 'NR==FNR {b[$1]=$2; next} $2=="FAIL" && b[$1]!="FAIL" {print $1}' \
      "$RUN/metrics-base.tsv" "$RUN/metrics-all.tsv" | paste -sd';' || echo "no-base")
  if [ -z "$newf" ] && [ -z "$nfk" ] && ! echo ",$why," | grep -qE ',(mutation-missed|corpus-file-missing),'; then
    KB=$( { echo "$fa" | tr ';' '\n' | grep -E '^(PASS->|GONE:)'; awk -F'\t' '$2=="FAIL" {print "FAIL:" $1}' "$RUN/metrics-all.tsv"; } | tr ' ' '_' | paste -sd';')
  else GB="why=$why${newf:+ new-flips=$newf}${nfk:+ new-fail=$nfk}"; fi; }
# guard_cut <comma list>: excluding more than half the set needs a clear per-patch breaker (the patch alone flips/drops/
# newfails vs base in $D); prints the list to leave out, or the refusal text + rc 1 (2026-10-11 a bogus key made all 14
# patches BREAK and the run built base + 1 patch, dropping the TDR guards)
guard_cut() { local cu=$1 nc cl n; nc=$(echo "$cu" | tr ',' '\n' | grep -c .)
  [ $((nc * 2)) -le $N ] && { echo "$cu"; return 0; }
  cl=$(for n in ${cu//,/ }; do awk -F'\t' -v n="$n" '$1==n && $2=="alone" && $7 ~ /^(flip|drop|newfail)$/ {print n; exit}' "$D"; done | paste -sd,)
  [ -n "$cl" ] && { echo "$cl"; return 0; }
  echo "would exclude $nc/$N patches ($cu) with no per-patch breaker (none flips/drops alone vs base); not staged"; return 1; }
# clean_minus <label>: tree <label> (a set minus one patch) shows no regression vs base: no BREAK/newfail, no FAIL key
# that is not FAIL on base, no INFRA
clean_minus() { [ -f "$RUN/metrics-$1.tsv" ] || return 1
  [ -z "$(compare SET set base "$1" | awk -F'\t' '$7=="BREAK" || $7=="newfail"')" ] || return 1
  [ -z "$(awk -F'\t' 'NR==FNR {b[$1]=$2; next} $2=="FAIL" && b[$1]!="FAIL"' "$RUN/metrics-base.tsv" "$RUN/metrics-$1.tsv")" ] || return 1
  ! grep -q $'\tINFRA$' "$RUN/metrics-$1.tsv"; }
# <<< decide-fns
# round 1 (combined-first): base + all only. Round 2: the per-patch trees, only when round 1 shows a regression vs base
# (or --per-patch), so the breaking patch can be named and left out.
first=(all); [ $N -ge 1 ] && first+=(base); run_gates "${first[@]}"
# INFRA (a check with no result) on a round-1 tree: re-gate those trees once (one gate, ~5 min) instead of 28 per-patch
# trees; still INFRA = die infra (nothing staged, nothing excluded): a lab infrastructure bug, never a patch verdict
infra_trees() { local l t=(); for l in "$@"; do grep -q $'\tINFRA$' "$RUN/metrics-$l.tsv" 2>/dev/null && t+=("$l"); done; echo "${t[@]}"; }
it=$(infra_trees "${first[@]}")
if [ -n "$it" ]; then say "INFRA no-result check(s) on tree(s) $it: $(cat $(for l in $it; do echo "$RUN/metrics-$l.tsv"; done) | awk -F'\t' '$2=="INFRA" {print $1}' | sort -u | paste -sd,); re-gating once"
  for l in $it; do rm -rf "$RUN/gate-$l.infra1"; mv "$RUN/gate-$l" "$RUN/gate-$l.infra1"; done; run_gates $it
  it=$(infra_trees $it); [ -z "$it" ] || die infra "check(s) gave no result twice on tree(s) $it (see $RUN/gate-*/regress.txt)"; fi
PPG=0; ff=""
if [ $N -ge 2 ]; then
  if [ $PERP = 1 ]; then ff="--per-patch"
  else sr=$(compare SET set base all | awk -F'\t' '$7=="BREAK" || $7=="newfail" {printf "%s %s->%s %s; ", $3, $4, $5, $7}')
    [ -n "$sr" ] && ff="set: ${sr%; }"; kb_eval; case "$GB" in ""|nores) ;; *) ff="${ff:+$ff; }gate: $GB";; esac; fi
  # RECENCY fast path (coordinator 2026-10-11: the 5090 sat idle ~50 min on a 30-tree round for one patch): gate the
  # set-minus-one trees newest-changed patch first, $JOBS at a time; the first clean one = that patch is the breaker,
  # rerun without it right away (the rest ships). No single clean minus-one tree = the full per-patch round below.
  # KFP_RECENCY=0 turns it off.
  if [ -n "$ff" ] && [ $COMB = 1 ] && [ $PERP = 0 ] && [ $N -ge 3 ] && [ "${KFP_RECENCY:-1}" = 1 ]; then
    say "RECENCY minus-one trees, newest patch first, $JOBS at a time (${ff})" | cut -c1-600
    mapfile -t ord < <(for p in "${S[@]}"; do echo "$(stat -c %Y "$p") $p"; done | sort -rn | cut -d' ' -f2-)
    i=0; while [ $i -lt ${#ord[@]} ]; do bl=()
      for p in "${ord[@]:$i:$JOBS}"; do n=$(pname "$p"); r=(); for q in "${S[@]}"; do [ "$q" = "$p" ] || r+=("$q"); done
        apply_set "$RUN/tree--$n" "${r[@]}" > /dev/null; TREE[-$n]=$RUN/tree--$n; bl+=("-$n"); done
      run_gates "${bl[@]}"
      for l in "${bl[@]}"; do clean_minus "$l" && { say "RECENCY set minus ${l#-} is clean vs base: ${l#-} is the breaker"
          rerun_without "${l#-}" "BREAK(recency: set without it clean vs base; ${ff:0:160})"; }; done
      i=$((i + JOBS)); done
    say "RECENCY no single minus-one tree is clean: full per-patch round"; fi
  if [ -n "$ff" ]; then say "COMBINED-FIRST per-patch round (${ff})" | cut -c1-600; pl=()
    for p in "${S[@]}"; do n=$(pname "$p"); apply_set "$RUN/tree-+$n" "$p" > /dev/null; TREE[+$n]=$RUN/tree-+$n; pl+=("+$n"); done
    if [ $N -ge 3 ]; then for p in "${S[@]}"; do n=$(pname "$p"); r=(); for q in "${S[@]}"; do [ "$q" = "$p" ] || r+=("$q"); done
      apply_set "$RUN/tree--$n" "${r[@]}" > /dev/null; TREE[-$n]=$RUN/tree--$n; pl+=("-$n"); done; fi
    pg=(); for l in "${pl[@]}"; do [ -f "$RUN/metrics-$l.tsv" ] || pg+=("$l"); done   # recency trees already gated
    [ ${#pg[@]} = 0 ] || run_gates "${pg[@]}"; PPG=1
  else say "COMBINED-FIRST all-pending clean vs base: per-patch round skipped"; fi
fi
printf 'patch\tcompare\tkey\tbefore\tafter\tdelta\tflag\n' > "$D"
if [ $N -ge 1 ]; then compare SET set base all >> "$D"
  for p in "${S[@]}"; do n=$(pname "$p"); [ $PPG = 1 ] && compare "$n" alone base "+$n" >> "$D"
    if [ $N = 1 ] || [ $PPG = 1 ]; then compare "$n" in-set "${CTX[$n]}" all >> "$D"; fi; done; fi
awk -F'\t' 'NR>1 && $2!="set" && $7 ~ /BREAK|drop|flip|GONE|newfail/ {print "DELTA " $1 " " $2 " " $3 " " $4 " -> " $5 " " $7}' "$D" | head -40 | tee -a "$RUN/pipeline.log"
# --- verdict --------------------------------------------------------------------------------------------------------
GL=$(cat "$RUN/gate-all/RESULT.txt" 2>/dev/null | head -1)
[ -n "$GL" ] || die gate "no gate result for the full set (log $RUN/logs/gate-all.txt)"
GS="$(echo "$GL" | awk '{print $3}') $(echo "$GL" | grep -o 'pool=[^ ]*\( s[0-9]*:[A-Z]*\)*' | tr ' ' ',') $(echo "$GL" | grep -o 'flipped=[^ ]*')"
br=$(awk -F'\t' 'NR>1 && $7=="BREAK" {printf "%s %s %s->%s; ", $1, $3, $4, $5}' "$D")
if [ -n "$br" ] && [ $COMB = 1 ]; then cu=$(awk -F'\t' 'NR>1 && $7=="BREAK" && $1!="SET" {print $1}' "$D" | sort -u | paste -sd,)
  if [ -n "$cu" ]; then g=$(guard_cut "$cu") || die guard "$g"; [ "$g" = "$cu" ] || say "GUARD in-set BREAK on $cu; leaving out only the clear per-patch breakers: $g"; cu=$g; fi
  [ -n "$cu" ] && rerun_without "$cu" "BREAK"; fi
[ -z "$br" ] || die delta "${br%; } (gate: $GS)"
kb_eval; [ -z "$GB" ] || die gate "$GB ($GS)"
[ -n "$KB" ] && say "GATE known-base failures (fail identically on base, non-blocking): $KB"
PN=$(for p in "${S[@]}"; do printf '%s,' "$(pname "$p")"; done); PN=${PN%,}; PN=${PN:-none}
# --- 5 stage --------------------------------------------------------------------------------------------------------
ST=unstaged; [ $STAGE = 1 ] && stage_dll "$DLL" "$PN" "gate PASS$([ $COMB = 1 ] && echo ' combined')${KB:+ known-base}"
cleanup
say "PIPELINE PASS $H patches=$PN${skip:+ skipped=${skip# }}${EXNOTE:+ excluded=$EXNOTE}${KB:+ known-base=$KB} gate=${GS// /,} staged=$ST run=$RUN"
exit 0
