#!/bin/bash
# regenerate /root/imm26/compose.patch (base -> compose, -p1) and prove it applies cleanly to a fresh copy of base
set -e; cd /root/imm26; rm -rf /tmp/cp && mkdir /tmp/cp && ln -s /root/imm26/base /tmp/cp/a && ln -s /root/imm26/compose /tmp/cp/b
(cd /tmp/cp && diff -ruN -x log -x __pycache__ -x soundcache -x '*.orig' -x '*.rej' a b > /root/imm26/compose.patch) || [ $? = 1 ]
rm -rf /tmp/cpchk; mkdir /tmp/cpchk; rsync -a --exclude log --exclude __pycache__ --exclude soundcache base/ /tmp/cpchk/
cd /tmp/cpchk && patch -p1 --dry-run < /root/imm26/compose.patch | tail -3; echo "dry-run rc=${PIPESTATUS[0]}"
patch -p1 -s < /root/imm26/compose.patch && diff -rq /tmp/cpchk /root/imm26/compose -x log -x __pycache__ -x soundcache -x '*.orig' && echo "APPLY-IDENTICAL"
ls -l /root/imm26/compose.patch
