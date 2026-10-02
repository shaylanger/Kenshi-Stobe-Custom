#!/usr/bin/env python3
"""A take-off order to a squadmate outside the request's people list was dropped.

Run 11: "Malzin, take off your iron hat." while she was out of chat range: the people
list held only Shay, stobeQueueUnequipItemRequest found no serial ("actor serial was
unavailable") and she said "I couldn't actually remove that item." KenshiFP finds far
squad members itself (bug 118); only the serial was missing. Fall back to the stored
serial when the name is unambiguous (stobeResolveLiveParticipantSerial(..., true)).

Usage: patch_r23_unequip_far_squadmate.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

lib = Path(sys.argv[1]) / 'lib' / 'chat_helper_functions.php'
s = lib.read_text(encoding='utf-8')
if 'take-off for someone out of range' in s:
    print('already patched'); sys.exit(0)
old = """    if ($serial <= 0) {
        stobeLogWarn('Unequip request skipped because actor serial was unavailable', ["""
new = """    if ($serial <= 0 && function_exists('stobeResolveLiveParticipantSerial')) {
        // A take-off for someone out of range (a squadmate at the base): the stored serial.
        $serial = stobeResolveLiveParticipantSerial($safeActor, true);
    }
    if ($serial <= 0) {
        stobeLogWarn('Unequip request skipped because actor serial was unavailable', ["""
assert s.count(old) == 1, 'anchor'
s = s.replace(old, new)
lib.write_text(s, encoding='utf-8', newline='')
print('patched', lib)
