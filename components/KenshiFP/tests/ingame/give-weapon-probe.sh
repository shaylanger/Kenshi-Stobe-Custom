#!/bin/bash
# give-weapon-probe.sh <out dir>   (5090 WSL or 4080 Git Bash via rig-env.sh; Kenshi in the world, harness up)
# Proves the harness `give` creates weapons (2026-10-10 fix: createItem(manufacturer, hand, weapon type, model grade); the
# old call passed the WEAPON as gd, which the game's factory always refuses). For each probe weapon (base + modded, by sid
# from the sweep catalog, plus one by name with an explicit maker/model): give 1, check the reply says "got 1/1" AND `inv`
# lists the weapon name, then unequip it (ground). A full weapon slot is freed by give itself (replaced=). One RESULT line:
# PASS = every probe weapon arrived. Proved 15/15 on harness E028A18F (giveprobe5090c, 2026-10-10).
OUT=$1; [ -n "$OUT" ] || { echo "usage: give-weapon-probe.sh <out dir>"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-harness-give}
RE=${CR:-/mnt/c}/KenshiModding/tools/automation/rig-env.sh; [ -f "$RE" ] && . "$RE"
mkdir -p "$OUT" && cd "$OUT" || { echo "RESULT WEAPONGIVE-PROBE FAIL setup: out dir"; exit 2; }
A(){ stobe-auto "$@" </dev/null 2>&1; }
SH=${SH:-Axima}
A inv $SH | grep -q name || { echo "RESULT WEAPONGIVE-PROBE FAIL setup: no $SH"; exit 2; }
A inv $SH > inv-before.txt
pass=0; fail=0; bad=""
probe(){ # label, give args...
  local lab=$1 nm=$2; shift 2; local r inv
  r=$(A give $SH "$@" | head -1)
  inv=$(A inv $SH)
  if echo "$r" | grep -q " got 1/1" && echo "$inv" | grep -qF "\"$nm\""; then pass=$((pass + 1)); st=OK
  else fail=$((fail + 1)); st=FAIL; bad="$bad [$lab]"; fi
  echo "$st give $SH $* -> $r" | tee -a probe.txt
  [ $st = OK ] && echo "   unequip: $(A unequip $SH "$nm" | head -1)" >> probe.txt
}
probe chisa "Chisa Katana" "5022626-Universal Wasteland Expansion.mod" 1
probe guardless "Guardless Katana" "923-gamedata.base" 1
probe dagger "Dagger" "55401-ArkWeaponPack.mod" 1
probe razor "Makeshift Razor" "2757863-BanditWeaponExpansion.mod" 1
probe bastard "Bastard Sword" "55395-ArkWeaponPack.mod" 1
probe kopesh "Holy Kopesh" "2758970-HN Ascended.mod" 1
probe chopper "Short Horse Chopper" "2758975-HN Ascended.mod" 1
probe bonehammer "Bone Hammer" "1535159-Hiver_Expansion.mod" 1
probe wrench "Wrench" "55424-ArkWeaponPack.mod" 1
probe cleaver "Beaked Cleaver" "1535185-ShriekingBandit_Expansion.mod" 1
probe hatchet "Ronin Hatchet" "2757887-WeaponExpansion_Ronin.mod" 1
probe paladin "Paladin's Cross" "52299-rebirth.mod" 1
probe ironclub "Iron Club" "Iron Club" 1
probe katana-maker "Katana" "Katana" 1 maker "Edgewalkers" model "Mid-Grade Salvage"
probe ranger "Ranger" "66169-Newwworld.mod" 1
A inv $SH > inv-after.txt
if [ $fail = 0 ]; then echo "RESULT WEAPONGIVE-PROBE PASS $pass/$((pass + fail)) weapons created and in $SH's inventory (log $OUT/probe.txt)"
else echo "RESULT WEAPONGIVE-PROBE FAIL $pass/$((pass + fail)) failed:$bad (log $OUT/probe.txt)"; fi
