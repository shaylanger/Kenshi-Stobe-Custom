set -e
R=/mnt/c/KenshiModding; P=$R/pending-fixes/npc-immersion-26; W=/root/ncpatch
rm -rf $W; mkdir -p $W/a $W/b
cp -r $R/components/STOBE/src $W/a/src; cp $R/components/STOBE/CMakeLists.txt $R/components/STOBE/Stobe.vcxproj $W/a/
rm -f $W/a/src/*.bak*
cp -r $P/NC/src $W/b/src; cp $P/NC/CMakeLists.txt $P/NC/Stobe.vcxproj $W/b/
# legacy-v1 is a new top-level dir in the package
cp -r $P/NC/legacy-v1 $W/b/legacy-v1
cd $W
diff -ruN --binary a b > nc.patch || true
cp nc.patch $P/NC/nc.patch
grep -c '^diff' nc.patch; ls -la nc.patch
# verify: apply on pristine components copy and compare to NC
rm -rf $W/v; mkdir $W/v; cp -r a/. $W/v/; cd $W/v; patch -p1 --binary -s -i ../nc.patch
diff -rq $W/v/src $P/NC/src && diff -rq $W/v/legacy-v1 $P/NC/legacy-v1 && cmp $W/v/CMakeLists.txt $P/NC/CMakeLists.txt && cmp $W/v/Stobe.vcxproj $P/NC/Stobe.vcxproj && echo PATCH_ROUNDTRIP_OK
grep '^diff' $W/nc.patch | sed 's#diff -ruN --binary a/##;s# b/.*##' | tr '\n' ' '
