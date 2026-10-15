set -e
R=/mnt/c/KenshiModding
P=$R/pending-fixes/npc-immersion-26
BASE=$P/N1/_compose-baseline-src
COMP=$R/components/STOBE/src
W=/root/ncwork
rm -rf $W; mkdir -p $W/a $W/b; cd $W
for f in ChatBox.cpp Functions.cpp Globals.cpp Globals.h Utils.cpp main.cpp StobeHarnessBridge.cpp; do cp $BASE/$f a/$f; cp $COMP/$f b/$f; done
cp $COMP/BodyguardContractProbe.cpp $COMP/BodyguardContractProbe.h b/
diff -ruN --binary a b > comp-delta.patch || true
cp comp-delta.patch $P/NC/_work/comp-delta.patch
grep '^diff' comp-delta.patch
cd $P/NC/src
patch -p1 --binary --dry-run -i $W/comp-delta.patch
