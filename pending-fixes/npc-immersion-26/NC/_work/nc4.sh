set -e
R=/mnt/c/KenshiModding; P=$R/pending-fixes/npc-immersion-26; W=/root/ncwork2
rm -rf $W; mkdir -p $W/a $W/b; cd $W
cp $P/N1/_compose-baseline-src/PlaythroughSession.cpp a/; cp $R/components/STOBE/src/PlaythroughSession.cpp b/
diff -ruN --binary a b > pt.patch || true
cp pt.patch $P/NC/_work/comp-delta2-playthrough.patch
cd $P/NC/src && patch -p1 --binary -i $W/pt.patch
cmp PlaythroughSession.cpp $R/components/STOBE/src/PlaythroughSession.cpp && echo IDENTICAL_TO_COMPONENTS
