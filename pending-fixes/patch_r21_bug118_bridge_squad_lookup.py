#!/usr/bin/env python3
"""Bug 118: bridged actions (EQUIP_ITEM, UNEQUIP_ITEM, ...) fail for a squad
member more than 750 units from the first squad member.

Run 9 (tests 15/16): Malzin was at the stone mine, 764 away, working a goal;
"put on the straw hat" -> "Straw hat, then." but KenshiFP logged
"ACTION_BRIDGE actor not found serial=..." (it only searched a 750 sphere
around Shay) and nothing happened. Look in the player's squad list first,
then fall back to the sphere.

Usage: patch_r21_bug118_bridge_squad_lookup.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'kenshifp_client.c'
text = path.read_text(encoding='utf-8')
old = """static void *stobe_find_character_by_serial(void *gw, uint32_t serial)
{
    if (!gw || !serial) return NULL;
"""
new = """static void *stobe_find_character_by_serial(void *gw, uint32_t serial)
{
    if (!gw || !serial) return NULL;
    /* Bug 118: squad members can be far from the first squad member (working a
     * goal at the mine); look them up in the squad list before the sphere. */
    if (readable((void *)((uintptr_t)gw + GW_PLAYER), 8)) {
        void *player = *(void **)((uintptr_t)gw + GW_PLAYER);
        if (readable((void *)((uintptr_t)player + PI_PLAYERCHARS + LEK_STUFF), 8)) {
            uint32_t count = *(uint32_t *)((uintptr_t)player + PI_PLAYERCHARS + LEK_COUNT);
            void **stuff = *(void ***)((uintptr_t)player + PI_PLAYERCHARS + LEK_STUFF);
            if (stuff && count <= 4096 && readable(stuff, count * sizeof(void *))) {
                for (uint32_t i = 0; i < count; i++) {
                    void *c = stuff[i];
                    if (!char_valid(c) || !readable((void *)((uintptr_t)c + CHAR_HANDLE + HAND_IDS), 20))
                        continue;
                    if (((uint32_t *)((uintptr_t)c + CHAR_HANDLE + HAND_IDS))[4] == serial)
                        return c;
                }
            }
        }
    }
"""
if 'Bug 118' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
