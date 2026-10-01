#!/usr/bin/env python3
"""KenshiFP round 8 (KenshiFP tree): bug 13 from the 2026-09-30 automated run.

An NPC with a full pack couldn't take clothes off (UNEQUIP_ITEM no carried section has
room), so a paid deal failed after she'd said "let me get it off". Now, when no carried
section has room, the item is dropped at her feet with Inventory::dropItem, and the
unequip counts as done only if the item really left the equipment section.

Usage: patch_kfp_round8.py <KenshiFP root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


patch("client/kenshifp_client.c",
      '#define KLIB_INVSECT_HASROOM_SYM "?_NV_hasRoomForItem@InventorySection@@QEAA_NPEAVGameData@@H@Z"\n',
      '#define KLIB_INVSECT_HASROOM_SYM "?_NV_hasRoomForItem@InventorySection@@QEAA_NPEAVGameData@@H@Z"\n'
      '#define KLIB_INV_DROPITEM_SYM "?_NV_dropItem@Inventory@@QEAAXPEAVItem@@@Z"\n')

patch("client/kenshifp_client.c",
      "typedef int (*stobe_invsect_hasroom_t)(void *section, void *game_data, int quantity);\n",
      "typedef int (*stobe_invsect_hasroom_t)(void *section, void *game_data, int quantity);\n"
      "typedef void (*stobe_inv_dropitem_t)(void *inventory, void *item);\n")

patch("client/kenshifp_client.c",
      "static stobe_invsect_hasroom_t g_stobe_invsect_hasroom;\n",
      "static stobe_invsect_hasroom_t g_stobe_invsect_hasroom;\n"
      "static stobe_inv_dropitem_t g_stobe_inv_dropitem;\n")

patch("client/kenshifp_client.c",
      """    if (!destination) {
        logline("[stobe] UNEQUIP_ITEM no carried section has room item=%p qty=%d source=%s",
                item, qty, source_name[0] ? source_name : "(unknown)");
        return 0;
    }
""",
      """    if (!destination) {
        /* Full pack: drop it at the character's feet rather than refuse. It only
         * counts if the item really left the equipment section. */
        if (!g_stobe_inv_dropitem) {
            HMODULE klib = GetModuleHandleA("KenshiLib.dll");
            if (klib)
                g_stobe_inv_dropitem = (stobe_inv_dropitem_t)GetProcAddress(klib, KLIB_INV_DROPITEM_SYM);
        }
        if (g_stobe_inv_dropitem) {
            g_stobe_inv_dropitem(inv, item);
            int still_equipped = g_stobe_invsect_hasitem(source, item) ? 1 : 0;
            logline("[stobe] UNEQUIP_ITEM no carried section has room; dropped at feet item=%p qty=%d source=%s result=%s",
                    item, qty, source_name[0] ? source_name : "(unknown)",
                    still_equipped ? "failed" : "dropped");
            return still_equipped ? 0 : 1;
        }
        logline("[stobe] UNEQUIP_ITEM no carried section has room item=%p qty=%d source=%s",
                item, qty, source_name[0] ? source_name : "(unknown)");
        return 0;
    }
""")

print("patch_kfp_round8: applied")
