#!/bin/bash
# lane-deploy-selftest.sh - offline selftest of lane-deploy.sh on a temp copy tree (run in WSL; touches only /tmp/stobe-bundletest-$$*)
D=$(cd "$(dirname "$0")" && pwd); LD=$D/lane-deploy.sh
T=/tmp/stobe-bundletest-$$; fail=0; n=0
chk() { n=$((n+1)); if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
cleanup() { rm -rf "$T" "$T"-*; }
trap cleanup EXIT; cleanup
mkdir -p $T-src/base/lib $T-src/base/tests $T-src/base/conf $T-src/comp/lib $T-src/comp/tests $T-src/comp/conf
# base
echo '<?php // a v1' > $T-src/base/lib/a.php; echo '<?php // b v1' > $T-src/base/lib/b.php; echo '<?php // t v1' > $T-src/base/tests/t.php
echo 'conf=base' > $T-src/base/conf/conf.php
# compose: a changed (in patch), b changed (NOT in patch: found by base diff), new c (in patch), new tests/t2 (base diff), conf changed (excluded), lane-local fixture
echo '<?php // a v2' > $T-src/comp/lib/a.php; echo '<?php // b v2' > $T-src/comp/lib/b.php; echo '<?php // t v1' > $T-src/comp/tests/t.php
echo '<?php // c new' > $T-src/comp/lib/c.php; echo '<?php // t2 new' > $T-src/comp/tests/t2.php
echo 'conf=COMPOSE' > $T-src/comp/conf/conf.php; echo '<?php // fixture compose' > $T-src/comp/lib/test_provider_reply_fixture.php
cat > $T-src/p.patch <<'EOF'
diff -ruN a/lib/a.php b/lib/a.php
--- a/lib/a.php	2026-01-01
+++ b/lib/a.php	2026-01-02
@@ -1 +1 @@
-x
+y
diff -ruN a/lib/c.php b/lib/c.php
--- a/lib/c.php	1970-01-01
+++ b/lib/c.php	2026-01-02
diff -ruN a/conf/conf.php b/conf/conf.php
--- a/conf/conf.php	2026-01-01
+++ b/conf/conf.php	2026-01-02
EOF
mk_lane() { # root
  rm -rf "$1"; mkdir -p "$1/site"; cp -a $T-src/base/. "$1/site/"; echo '<?php // imm26' > "$1/site/lib/imm26_plans.php"
  echo '<?php // lane-local fixture' > "$1/site/lib/test_provider_reply_fixture.php"; echo 'conf=lane' > "$1/site/conf/conf.php"; echo 'env' > "$1/env.sh"
}
SRC=$T-src/comp; BASE=$T-src/base; PAT=$T-src/p.patch
LANE=$T-laneA; mk_lane $LANE
# refusals
o=$(bash $LD /tmp/notstobe --src $SRC --patch $PAT --base $BASE 2>&1); rc=$?; chk "refuse root outside /tmp/stobe-*" '[ $rc = 2 ] && echo "$o" | grep -q refuse'
bash $LD /var/www/html/StobeServer --src $SRC --patch $PAT --base $BASE >/dev/null 2>&1; rc=$?; chk "refuse live tree path (rc=2)" '[ $rc = 2 ]'
mkdir -p $T-bad/site/lib; bash $LD $T-bad --src $SRC --patch $PAT --base $BASE >/dev/null 2>&1; rc=$?; chk "refuse non-imm26 site (rc=2)" '[ $rc = 2 ]'
mkdir -p $T-link; ln -s /var/www $T-link/site; bash $LD $T-link --src $SRC --patch $PAT --base $BASE >/dev/null 2>&1; rc=$?; chk "refuse site symlinked outside /tmp/stobe-* (rc=2)" '[ $rc = 2 ]'
bash $LD $LANE --src $LANE/site --patch $PAT --base $BASE >/dev/null 2>&1; rc=$?; chk "refuse site == source (rc=2)" '[ $rc = 2 ]'
# dry
before=$(cd $LANE && find . -type f | sort | xargs sha256sum | sha256sum)
o=$(bash $LD $LANE --dry --src $SRC --patch $PAT --base $BASE 2>&1); echo "   $o"
after=$(cd $LANE && find . -type f | sort | xargs sha256sum | sha256sum)
chk "dry writes nothing" '[ "$before" = "$after" ]'
chk "dry reports 2 changed + 2 new" 'echo "$o" | grep -q "would-change=2 would-add=2"'
chk "dry is one line" '[ "$(echo "$o" | wc -l)" = 1 ]'
# lint failure leaves lane untouched
echo '<?php this is not php {' > $SRC/lib/bad.php
o=$(bash $LD $LANE --src $SRC --patch $PAT --base $BASE 2>&1); rc=$?
chk "lint failure aborts rc=5" '[ $rc = 5 ]'
after=$(cd $LANE && find . -type f | sort | xargs sha256sum | sha256sum); chk "lint failure: lane untouched, no backup dir" '[ "$before" = "$after" ] && ! ls -d $LANE/bak-pre-bundle-* >/dev/null 2>&1'
rm -f $SRC/lib/bad.php
# real deploy
o=$(bash $LD $LANE -v --src $SRC --patch $PAT --base $BASE 2>&1); rc=$?; echo "$o" | sed 's/^/   /'
chk "deploy rc=0" '[ $rc = 0 ]'
chk "a.b.t2.c deployed (cmp)" 'cmp -s $SRC/lib/a.php $LANE/site/lib/a.php && cmp -s $SRC/lib/b.php $LANE/site/lib/b.php && cmp -s $SRC/lib/c.php $LANE/site/lib/c.php && cmp -s $SRC/tests/t2.php $LANE/site/tests/t2.php'
chk "conf NOT touched" 'grep -q "conf=lane" $LANE/site/conf/conf.php'
chk "lane-local fixture NOT touched" 'grep -q "lane-local" $LANE/site/lib/test_provider_reply_fixture.php'
chk "lane-only file (imm26_plans.php) untouched" 'grep -q imm26 $LANE/site/lib/imm26_plans.php'
bak=$(ls -d $LANE/bak-pre-bundle-* | head -1)
chk "backup holds old a.php and b.php" 'grep -q "a v1" $bak/lib/a.php && grep -q "b v1" $bak/lib/b.php'
chk "NEWFILES lists c.php and t2.php" 'grep -q "lib/c.php" $bak/NEWFILES.txt && grep -q "tests/t2.php" $bak/NEWFILES.txt'
chk "BUNDLE_DEPLOYED has sha256 + status" 'grep -q "lib/a.php  CHANGED" $LANE/BUNDLE_DEPLOYED && grep -Eq "^[0-9a-f]{64}  lib/c.php  NEW" $LANE/BUNDLE_DEPLOYED'
chk "no .new.bundle leftovers" '! find $LANE/site -name "*.new.bundle" | grep -q .'
# idempotent
sum1=$(sha256sum $LANE/BUNDLE_DEPLOYED | cut -d' ' -f1)
o=$(bash $LD $LANE --src $SRC --patch $PAT --base $BASE 2>&1); rc=$?
chk "second run: already up to date, rc=0" '[ $rc = 0 ] && echo "$o" | grep -q "already up to date"'
chk "second run: no new backup dir, BUNDLE_DEPLOYED unchanged" '[ "$(ls -d $LANE/bak-pre-bundle-* | wc -l)" = 1 ] && [ "$sum1" = "$(sha256sum $LANE/BUNDLE_DEPLOYED | cut -d" " -f1)" ]'
# rollback
bash $bak/ROLLBACK.sh >/dev/null 2>&1
chk "ROLLBACK.sh restores a.php/b.php and removes new files" 'grep -q "a v1" $LANE/site/lib/a.php && grep -q "b v1" $LANE/site/lib/b.php && [ ! -e $LANE/site/lib/c.php ] && [ ! -e $LANE/site/tests/t2.php ]'
# pack -> bundle -> deploy on a second lane (the 4080 path), script run from inside the bundle
PK=$T-pk/bundle
o=$(bash $LD --pack $PK --src $SRC --patch $PAT --base $BASE 2>&1); echo "   $o"
chk "pack: 4 files, conf/fixture excluded" 'echo "$o" | grep -q "files=4" && [ ! -e $PK/files/conf ] && [ -f $PK/files/tests/t2.php ] && [ -f $PK/lane-deploy.sh ]'
LANE2=$T-laneB; mk_lane $LANE2
o=$(bash $PK/lane-deploy.sh $LANE2 2>&1); rc=$?; echo "   $o"
chk "bundle deploy from bundle dir rc=0, 3 changed/new + 1 changed (a,b changed; c,t2 new)" '[ $rc = 0 ] && echo "$o" | grep -q "changed=2 new=2"'
chk "bundle deploy cmp equal to compose" 'cmp -s $SRC/lib/a.php $LANE2/site/lib/a.php && cmp -s $SRC/tests/t2.php $LANE2/site/tests/t2.php && grep -q "conf=lane" $LANE2/site/conf/conf.php'
o=$(bash $PK/lane-deploy.sh $LANE2 2>&1); chk "bundle second run idempotent" 'echo "$o" | grep -q "already up to date"'
# migrate flag
mkdir -p $SRC/data $LANE/site/data; echo 'select 1;' > $SRC/data/schema.sql; echo 'select 0;' > $LANE/site/data/schema.sql
o=$(bash $LD $LANE --dry --src $SRC --patch $PAT --base $BASE 2>&1); chk "schema change flagged MIGRATE-NEEDED (dry)" 'echo "$o" | grep -q MIGRATE-NEEDED'
echo "lane-deploy-selftest: $((n-fail))/$n passed, $fail failed"
[ $fail = 0 ]
