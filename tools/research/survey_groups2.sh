#!/bin/bash
# Vanilla anchors for the cap tiers.
cd /mnt/c/KenshiModding/tools/research
python3 npc_wealth.py 2>/dev/null > /tmp/all_wealth.txt
for n in "Dust Bandit " "Dust King" "Hungry Bandit" "Starving Bandit" "Bandit Leader" "Tinfist" "Tengu" "Emperor" "Lord " "Noble" "Seto" "Longen" "Cat-Lon" "Moll" "Bad Teeth" "Valamon" "Grayflayer" "Okran" "High Inquisitor" "Shopkeeper" "Bartender" "Trader /" "Weapon Smith" "Samurai /" "Mercenary" "Crab" "Hiver" "Red Sabre" "Black Dragon" "Ninja"; do
  grep -F -- "$n" /tmp/all_wealth.txt | head -4
done | sort -u
