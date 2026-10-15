set -e
P=/mnt/c/KenshiModding/pending-fixes/npc-immersion-26
cd $P/NC/src
patch -p1 --binary -i $P/NC/_work/comp-delta.patch | tail -3
cd $P/NC
cp $P/N2c/n2.patch _work/n2.patch
patch -p1 --binary --dry-run -i _work/n2.patch
