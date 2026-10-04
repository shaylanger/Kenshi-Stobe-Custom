#!/bin/bash
# m24 fixer 15: apply m24-f15-rel.py to the live tree and ss-merge (.new + mv, owner/mode kept). Aborts if a REL wrapper runs.
set -e
pgrep -f 'rel-m18.sh|rel-b55.sh' >/dev/null && { echo "ABORT: rel-m18/rel-b55 running"; exit 1; }
P=/mnt/c/KenshiModding/pending-fixes/m24-f15-rel.py
F="REL-p3-06-ko-loot-witnessed.txt rel-m18.sh rel-b55.sh"
for T in /var/www/html/StobeServer /root/stobe-work/ss-merge; do
  tmp=$(mktemp -d); mkdir -p $tmp/tests/social_relationship/ingame
  for f in $F; do cp -p $T/tests/social_relationship/ingame/$f $tmp/tests/social_relationship/ingame/; done
  python3 $P $tmp >/dev/null
  for f in $F; do
    src=$tmp/tests/social_relationship/ingame/$f; dst=$T/tests/social_relationship/ingame/$f
    case $f in *.sh) bash -n $src;; esac
    cp $src $dst.new; chown --reference=$dst $dst.new; chmod --reference=$dst $dst.new; mv $dst.new $dst
  done
  rm -rf $tmp; echo "deployed $T"
done
