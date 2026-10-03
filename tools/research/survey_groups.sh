#!/bin/bash
# Print the wealth survey for each NPC group used to design the deal-offer cap tiers.
cd /mnt/c/KenshiModding/tools/research
for q in "bandit" "barman bartender" "trader shopkeeper" "samurai noble lord" "shek" "slaver slave trader" "tech hunter" "esata tinfist bugmaster longen cat-lon moll narko"; do
  echo "#### $q"
  python3 npc_wealth.py $q 2>/dev/null | head -14
done
