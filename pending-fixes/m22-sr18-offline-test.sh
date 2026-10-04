#!/usr/bin/env bash
# offline check of REL-SR18-SR19-fullbase.sh(.new): fake stobe-auto + stubbed inspector; prints RESULT lines and the
# inserted scenario lines. usage: bash m22-sr18-offline-test.sh <wrapper> [fail-teleport]
set -u
W="$1"; T=/tmp/sr18t; rm -rf $T; mkdir -p $T/bin $T/out
cat > $T/bin/stobe-auto <<'EOF'
#!/bin/bash
f="$2"; cp "$f" /tmp/sr18t/last-$(basename "$f")
case "$f" in
  *setup.txt) echo "PASS  1 @wait-world"; echo "== 10 passed, 0 failed";;
  *) n=CNAME; grep -q KNAME "$f" && n=KNAME
     echo "PASS  27 @set $n where x => $n=Rel Test"
     if [ -n "${FAILTP:-}" ]; then echo "FAIL  30 @until 20 teleport \${C} Avarek dist 4 ~ moved=1 => moved=0"; fi
     echo "== 40 passed, 0 failed";;
esac
EOF
chmod +x $T/bin/stobe-auto
R="$(dirname "$W")/run-as.sh"; [ -f "$R.new" ] && R="$R.new"; cp "$R" $T/run-as.sh
sed -e 's/^insp(){.*/insp(){ case "$*" in *expect-effect*) return 0;; esac; return 0; }/' -e 's/^  sleep 20$/  :/' "$W" > $T/w.sh
FAILTP="${2:-}" PATH=$T/bin:$PATH OUT=$T/out RESULT_LOG=$T/out/r.txt bash $T/w.sh all
for f in $T/last-*; do echo "--- $(basename $f)"; grep -n "^where \|^@until 20 teleport\|^buildings\|^health\|^wake" "$f"; done
