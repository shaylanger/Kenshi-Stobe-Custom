#!/usr/bin/env python3
"""Plan item 40: `stobe-auto give` reported more items than actually arrived.

Run 12: "Malzin got 4/4 Dried Meat" but the game (and her prompt) showed 3; "got 2/3
Bread". Her answers matched the game every time, so the "inventory lag" of run 11 came
from the helper's count (addItem returned true for items that did not stay).
Now `give` reports the real change in Inventory::countItems() and logs both numbers.

Usage: patch_dll_r24_give_real_count.py <STOBE-src root>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'src' / 'TestAutomation.cpp'
s = f.read_text(encoding='utf-8')
if 'countBefore' in s:
    print('already patched'); sys.exit(0)

def sub(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n}x: {old[:60]!r}'
    s = s.replace(old, new)

sub("""    int added = 0;
    for (int i = 0; i < count; ++i) {
      Item *item = world->theFactory->createItem(data, hand(), nullptr, nullptr, -1, nullptr);
      if (!Valid(item) || !inv->addItem(item, 1, false, true))
        break;
      ++added;
    }
    Log("TEST_AUTO: give " + c->getName() + " item=" + data->name + " added=" + Int(added));
    ok = added > 0;
    return c->getName() + " got " + Int(added) + "/" + Int(count) + " " + data->name;""",
"""    int added = 0;
    int countBefore = inv->countItems(data);
    for (int i = 0; i < count; ++i) {
      Item *item = world->theFactory->createItem(data, hand(), nullptr, nullptr, -1, nullptr);
      if (!Valid(item) || !inv->addItem(item, 1, false, true))
        break;
      ++added;
    }
    // addItem can report success for items that don't stay: report what really arrived.
    int real = inv->countItems(data) - countBefore;
    Log("TEST_AUTO: give " + c->getName() + " item=" + data->name + " added=" + Int(added) +
        " real=" + Int(real) + " now=" + Int(countBefore + real));
    ok = real > 0;
    return c->getName() + " got " + Int(real) + "/" + Int(count) + " " + data->name +
           " (now " + Int(countBefore + real) + ")";""")

f.write_text(s, encoding='utf-8')
print('patched', f)
