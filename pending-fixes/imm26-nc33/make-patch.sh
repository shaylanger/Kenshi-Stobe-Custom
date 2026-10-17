#!/usr/bin/env bash
# regenerate fix26apoll-poll-keep.patch from the NC32 and NC33 trees (WSL)
cd /mnt/c/KenshiTestRuns
for f in ActivityNativeExecutor.cpp ActivityRuntimeBindings.cpp; do
  diff -u imm26-nc32/src/$f imm26-nc33/src/$f | sed "1s#.*#--- a/src/$f#;2s#.*#+++ b/src/$f#"
done > /mnt/c/KenshiModding/pending-fixes/imm26-nc33/fix26apoll-poll-keep.patch
