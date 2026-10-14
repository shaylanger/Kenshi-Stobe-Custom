export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
rig4080_i3_preflight || exit $?
stobe-auto stobe_say "Apothecary Matsuyo" "I mean the trip itself: would you want to travel with me to Heft, yes or no? It is completely fine to say no."
