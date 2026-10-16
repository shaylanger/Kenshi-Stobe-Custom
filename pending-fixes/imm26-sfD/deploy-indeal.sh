#!/bin/bash
# usage (inside the WSL that owns the lane, as root; social_property.php must sit next to this script):  FORCE=1 optional  bash deploy.sh <lane-root>...   e.g. /tmp/stobe-standalone4080-i4
# Deploys the staged lib/social_property.php (imm26-sfD inDeal fix) to private lane sites ONLY (never the live server tree). Aborts a lane whose file differs from the
# compose version the fix was staged on (sha 528b4f885f85896b88f0899a2919cead33cbc09a923083592d89c291151b095e) unless FORCE=1; backs the old file up to <root>/bak-pre-sfD; php -l before the move; verifies the sha afterwards.
SRC="$(cd "$(dirname "$0")" && pwd)/social_property.php"; NEWSHA=c3c681241730f241a476c1a31a66593dcc0c192faa0a7b12ffe4007e4101c269; OLDSHA=528b4f885f85896b88f0899a2919cead33cbc09a923083592d89c291151b095e
[ "$(sha256sum "$SRC" | cut -d' ' -f1)" = "$NEWSHA" ] || { echo "compose file is not the staged sfD version (compose changed since); re-stage first"; exit 2; }
for root in "$@"; do
  site=$root/site; f=lib/social_property.php; bak=$root/bak-pre-sfD
  [ -f $site/$f ] || { echo "no $site/$f"; continue; }
  cur=$(sha256sum $site/$f | cut -d' ' -f1)
  [ "$cur" = "$NEWSHA" ] && { echo "$root: already deployed"; continue; }
  if [ "$cur" != "$OLDSHA" ] && [ "$FORCE" != 1 ]; then echo "LANE DIFFERS from old compose: $root $f (sha $cur); abort (FORCE=1 to override)"; continue; fi
  mkdir -p $bak/lib; cp -p $site/$f $bak/$f
  cp "$SRC" $site/$f.new.sfd && php -l $site/$f.new.sfd >/dev/null && mv $site/$f.new.sfd $site/$f
  echo "$root: $([ "$(sha256sum $site/$f | cut -d' ' -f1)" = "$NEWSHA" ] && echo deployed || echo MISMATCH), lint $(php -l $site/$f >/dev/null 2>&1 && echo ok || echo FAIL); PHP opcache serves it after ~1 min"
done
