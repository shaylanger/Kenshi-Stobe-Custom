#!/bin/bash
# lane-deploy.sh - put EVERY built imm26 server fix (compose tree) on one lane's PRIVATE backend in one step.
#
#   lane-deploy.sh <lane-root> [--dry] [-v] [--migrate] [--src DIR] [--patch FILE] [--base DIR]
#   lane-deploy.sh --pack <outdir-with-"bundle"-in-name> [--src DIR] [--patch FILE] [--base DIR]
#
# Run inside WSL (DwemerAI4Skyrim3). <lane-root> = /tmp/stobe-<lane> that has site/ (imm26 compose-installed).
# Operators run it BETWEEN ROWS (no row running); PHP opcache serves a changed file after ~1 min; nothing is restarted.
#
# Source: --src DIR, default = the directory this script sits in if it holds BUNDLE_FILES.txt (a packed bundle, used on
# the 4080), else the compose tree /root/imm26/compose. File set = files touched by compose.patch
# (/root/imm26/compose.patch, else the repo copy) UNION files that differ base->compose (when /root/imm26/base exists),
# minus config/DB/lane-local files (EXCL below). Only files that differ from the lane are copied.
# Steps: lint all new/changed php from the source first (abort = lane untouched) -> backup the files about to change to
# <root>/bak-pre-bundle-<ts>/ (+ ROLLBACK.sh) -> copy each via <file>.new.bundle + mv -> cmp + php -l verify ->
# write <root>/BUNDLE_DEPLOYED (ts, bundle id, sha256 + status per file). Idempotent: a second run changes nothing.
# Refuses: root not under /tmp/stobe-* (after readlink -f), site symlinked outside /tmp/stobe-*, anything under
# /var/www, site without lib/imm26_plans.php, site == source. Never touches the live tree /var/www/html/StobeServer,
# conf/, config*, env files, keys, logs, DB, voices/portraits. --migrate additionally runs tools/bootstrap-database.php
# with <root>/env.sh when a schema file changed (otherwise a MIGRATE-NEEDED flag is printed).
# Output: ONE summary line (add -v for the per-file list). Exit 0 ok / 2 refuse / 3 bad source / 5 lint / 6 verify.
set -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${BUNDLE_SRC:-}; BASE=${BASE:-/root/imm26/base}; PATCH=${COMPOSE_PATCH:-}
DRY=0; VERB=0; MIGRATE=0; PACK=""; ROOT=""
die() { echo "lane-deploy: $2" >&2; exit "$1"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry) DRY=1;; -v) VERB=1;; --migrate) MIGRATE=1;;
    --src) SRC=$2; shift;; --patch) PATCH=$2; shift;; --base) BASE=$2; shift;; --pack) PACK=$2; shift;;
    -h|--help) sed -n '2,24p' "$0"; exit 0;;
    -*) die 2 "unknown option $1";;
    *) [ -z "$ROOT" ] || die 2 "two roots given"; ROOT=$1;;
  esac; shift
done
if [ -z "$SRC" ]; then if [ -f "$HERE/BUNDLE_FILES.txt" ]; then SRC=$HERE; else SRC=/root/imm26/compose; fi; fi
[ -d "$SRC" ] || die 3 "source $SRC not found"
SRC=$(readlink -f "$SRC")
if [ -f "$SRC/BUNDLE_FILES.txt" ]; then FROOT=$SRC/files; BUNDLE=1; else FROOT=$SRC; BUNDLE=0; fi
case "$SRC" in /var/www/*) die 2 "source under /var/www refused";; esac

# never copied, whatever the patch says
EXCL='^(conf|log|logs|soundcache|\.git)/|^data/(portraits|voices)/|(^|/)(config[^/]*|\.env[^/]*|env\.sh)$|\.(bak[^/]*|orig|rej|log|pid|key|pem|sql\.gz|tgz|tar|gz)$|\.new\.|^lib/test_provider_reply_fixture[^/]*$'

enum_files() {
  if [ "$BUNDLE" = 1 ]; then cat "$SRC/BUNDLE_FILES.txt"; return; fi
  local p=$PATCH
  if [ -z "$p" ]; then
    for c in /root/imm26/compose.patch /mnt/c/KenshiModding/pending-fixes/npc-immersion-26/compose/compose.patch; do [ -f "$c" ] && { p=$c; break; }; done
  fi
  [ -n "$p" ] && [ -f "$p" ] && grep -E '^\+\+\+ b/' "$p" | sed 's#^+++ b/##; s#[[:space:]].*##'
  if [ -d "$BASE" ]; then
    local t; t=$(mktemp -d /tmp/lanedeploy-diff.XXXXXX)
    ln -s "$BASE" "$t/a"; ln -s "$SRC" "$t/b"
    (cd "$t" && diff -rqN a b -x log -x __pycache__ -x soundcache -x '*.orig' -x '*.rej' -x portraits -x voices -x '*.bak*' 2>/dev/null) \
      | sed -n 's#^Files a/\(.*\) and b/.* differ$#\1#p'
    rm -rf "$t"
  elif [ -z "$p" ]; then die 3 "no compose.patch and no base tree to enumerate files"; fi
}

# filtered list: valid relative path, not excluded, exists in the source; counts skipped
FILES=(); SKIPPED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in /*|*..*) SKIPPED=$((SKIPPED+1)); continue;; esac
  if printf '%s' "$f" | grep -Eq "$EXCL" || [ ! -f "$FROOT/$f" ]; then SKIPPED=$((SKIPPED+1)); continue; fi
  FILES+=("$f")
done < <(enum_files | sort -u)
[ "${#FILES[@]}" -gt 0 ] || die 3 "empty file set"
bundle_id=$(cd "$FROOT" && sha256sum "${FILES[@]}" | sha256sum | cut -c1-12)

lint_list() { local f bad=0; for f in "$@"; do case "$f" in *.php) php -l "$FROOT/$f" >/dev/null 2>&1 || { echo "LINT FAIL $f" >&2; bad=1; };; esac; done; return $bad; }

# ---------------- pack mode ----------------
if [ -n "$PACK" ]; then
  [ "$BUNDLE" = 0 ] || die 3 "--pack needs a compose tree as source"
  case "$(basename "$PACK")" in *bundle*) ;; *) die 2 "pack dir name must contain 'bundle'";; esac
  lint_list "${FILES[@]}" || die 5 "lint failed in compose; nothing packed"
  rm -rf "$PACK"; mkdir -p "$PACK/files"
  for f in "${FILES[@]}"; do mkdir -p "$PACK/files/$(dirname "$f")"; cp -p "$FROOT/$f" "$PACK/files/$f"; done
  printf '%s\n' "${FILES[@]}" > "$PACK/BUNDLE_FILES.txt"
  (cd "$PACK/files" && sha256sum "${FILES[@]}") > "$PACK/sha256.txt"
  echo "$bundle_id" > "$PACK/BUNDLE_ID"
  cp -p "$0" "$PACK/lane-deploy.sh"
  echo "lane-deploy PACK bundle=$bundle_id files=${#FILES[@]} skipped=$SKIPPED out=$PACK"
  exit 0
fi

# ---------------- deploy mode ----------------
[ -n "$ROOT" ] || die 2 "usage: lane-deploy.sh <lane-root> [--dry] [-v] [--migrate]"
case "$ROOT" in /tmp/stobe-*) ;; *) die 2 "refuse root $ROOT (must be /tmp/stobe-*)";; esac
REAL=$(readlink -f "$ROOT") || die 2 "bad root"
case "$REAL" in /tmp/stobe-*) ;; *) die 2 "refuse root $ROOT -> $REAL";; esac
SITE=$REAL/site
[ -d "$SITE" ] || die 2 "no site/ in $ROOT"
RSITE=$(readlink -f "$SITE")
case "$RSITE" in /tmp/stobe-*) ;; *) die 2 "refuse: site resolves to $RSITE";; esac
case "$RSITE" in /var/www*|*StobeServer) die 2 "refuse live tree $RSITE";; esac
[ "$RSITE" != "$SRC" ] && [ "$RSITE" != "$FROOT" ] || die 2 "site is the source tree"
[ -f "$SITE/lib/imm26_plans.php" ] || die 2 "$ROOT is not an imm26 compose-installed lane (no lib/imm26_plans.php); use install-lane-site.sh"

CHANGED=(); NEW=(); SAME=0
for f in "${FILES[@]}"; do
  if [ -f "$SITE/$f" ]; then cmp -s "$FROOT/$f" "$SITE/$f" && SAME=$((SAME+1)) || CHANGED+=("$f"); else NEW+=("$f"); fi
done
TODO=("${CHANGED[@]}" "${NEW[@]}")
MIGFLAG=""
for f in "${TODO[@]}"; do case "$f" in data/schema.sql|data/imm26_*schema*.sql|debug/db_updates.php) MIGFLAG=" MIGRATE-NEEDED";; esac; done
list_files() { [ "$VERB" = 1 ] || return 0; local f; for f in "${CHANGED[@]}"; do echo "  CHANGED $f"; done; for f in "${NEW[@]}"; do echo "  NEW     $f"; done; }

if [ "${#TODO[@]}" -gt 0 ]; then
  lint_list "${TODO[@]}" || die 5 "lint failed on source file(s); lane $ROOT untouched"
fi

if [ "$DRY" = 1 ]; then
  list_files
  echo "lane-deploy DRY $ROOT bundle=$bundle_id files=${#FILES[@]} would-change=${#CHANGED[@]} would-add=${#NEW[@]} same=$SAME skipped=$SKIPPED lint=ok$MIGFLAG (nothing written)"
  exit 0
fi

if [ "${#TODO[@]}" -eq 0 ]; then
  echo "lane-deploy $ROOT bundle=$bundle_id files=${#FILES[@]} changed=0 new=0 same=$SAME skipped=$SKIPPED: already up to date (no backup, no write)"
  exit 0
fi

exec 9>"$REAL/.bundle.lock"; flock -n 9 || die 2 "another lane-deploy is running on $ROOT"
TS=$(date +%Y%m%d-%H%M%S); BAK=$REAL/bak-pre-bundle-$TS; mkdir -p "$BAK" || die 2 "cannot create $BAK"
for f in "${CHANGED[@]}"; do mkdir -p "$BAK/$(dirname "$f")"; cp -p "$SITE/$f" "$BAK/$f"; done
: > "$BAK/NEWFILES.txt"; for f in "${NEW[@]}"; do echo "$f" >> "$BAK/NEWFILES.txt"; done
cat > "$BAK/ROLLBACK.sh" <<EOF
#!/bin/bash
# restores the files this bundle deploy changed in $SITE and removes the ones it added
set -e
cd "$BAK"
while IFS= read -r f; do [ -n "\$f" ] && rm -f "$SITE/\$f"; done < NEWFILES.txt
find . -type f ! -name NEWFILES.txt ! -name ROLLBACK.sh | sed 's#^\./##' | while IFS= read -r f; do cp -p "\$f" "$SITE/\$f"; done
echo "rolled back bundle deploy $TS in $SITE"
EOF
chmod +x "$BAK/ROLLBACK.sh"

for f in "${TODO[@]}"; do
  mkdir -p "$SITE/$(dirname "$f")"
  cp "$FROOT/$f" "$SITE/$f.new.bundle" || die 6 "copy failed $f (backup at $BAK)"
  if [ -f "$SITE/$f" ]; then chown --reference="$SITE/$f" "$SITE/$f.new.bundle" 2>/dev/null || true; chmod --reference="$SITE/$f" "$SITE/$f.new.bundle" 2>/dev/null || true
  else chown --reference="$(dirname "$SITE/$f")" "$SITE/$f.new.bundle" 2>/dev/null || true; fi
  mv -f "$SITE/$f.new.bundle" "$SITE/$f" || die 6 "mv failed $f (backup at $BAK)"
done

BADCMP=0; BADLINT=0
for f in "${FILES[@]}"; do
  cmp -s "$FROOT/$f" "$SITE/$f" || { BADCMP=$((BADCMP+1)); echo "MISMATCH $f" >&2; }
done
for f in "${TODO[@]}"; do case "$f" in *.php) php -l "$SITE/$f" >/dev/null 2>&1 || { BADLINT=$((BADLINT+1)); echo "LINT FAIL (deployed) $f" >&2; };; esac; done

{
  echo "bundle-deployed ts=$TS host=$(hostname) bundle=$bundle_id src=$SRC files=${#FILES[@]} changed=${#CHANGED[@]} new=${#NEW[@]} same=$SAME skipped=$SKIPPED backup=$BAK"
  for f in "${FILES[@]}"; do
    st=SAME; for c in "${CHANGED[@]}"; do [ "$c" = "$f" ] && st=CHANGED; done; for c in "${NEW[@]}"; do [ "$c" = "$f" ] && st=NEW; done
    echo "$(sha256sum "$SITE/$f" | cut -d' ' -f1)  $f  $st"
  done
} > "$REAL/BUNDLE_DEPLOYED"
list_files

MIG=""
if [ -n "$MIGFLAG" ] && [ "$MIGRATE" = 1 ]; then
  if ( set -a; . "$REAL/env.sh"; set +a; cd "$SITE" && php tools/bootstrap-database.php > "$REAL/bundle-migrate.log" 2>&1 ); then MIG=" migrate=ok"; else MIG=" migrate=FAIL(see $REAL/bundle-migrate.log)"; fi
  MIGFLAG=""
fi
RC=0; [ "$BADCMP" = 0 ] && [ "$BADLINT" = 0 ] || RC=6
echo "lane-deploy $ROOT bundle=$bundle_id files=${#FILES[@]} changed=${#CHANGED[@]} new=${#NEW[@]} same=$SAME skipped=$SKIPPED cmp-mismatch=$BADCMP lint-fail=$BADLINT backup=$BAK BUNDLE_DEPLOYED written$MIGFLAG$MIG"
exit $RC
