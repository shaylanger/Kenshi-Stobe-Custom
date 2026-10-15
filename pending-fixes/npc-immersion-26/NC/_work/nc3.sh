cd /mnt/c/KenshiModding/pending-fixes/npc-immersion-26/NC
patch -p1 --binary -f -i _work/n2.patch >/dev/null 2>&1
rm -f CMakeLists.txt.rej CMakeLists.txt.orig Stobe.vcxproj.rej Stobe.vcxproj.orig; find . -name '*.orig' -o -name '*.rej' | head
ls src/N2* src/NativeAttention* src/ParticipationEvidence.h
