#!/usr/bin/env python3
"""Round 9d: "Here, take this bread" gave nothing when the item is "Poppyseed Bread": the voice
hand-over only matched full item names. If no full name matches, match a distinctive word of the
name (4+ letters, not a quality/size word), but only when exactly one carried item fits.

Usage: patch_round9d.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/negotiation_voice.php"
t = p.read_text(encoding="utf-8")
old = """        // 2. "Here's your drink" / "what I owe you": the item(s) this deal says you owe."""
new = """        // 1b. A distinctive word of the name ("this bread" -> Poppyseed Bread), if exactly one fits.
        if (count($items) === 0) {
            $generic = ['basic','standard','high','quality','specialist','masterwork','shoddy','small','large','dried','brown','veggie','regulars','with','your','this','that','some'];
            $fits = [];
            foreach ($inventory as $name => $have) {
                foreach (preg_split('/[^a-z]+/', $name) ?: [] as $word) {
                    if (strlen($word) < 4 || in_array($word, $generic, true)) continue;
                    if (preg_match('/\\b' . preg_quote($word, '/') . 's?\\b/', $text)) { $fits[$name] = $have; break; }
                }
            }
            if (count($fits) === 1) {
                $name = array_key_first($fits);
                $items[] = ['name'=>$name, 'qty'=>1];
            }
        }
        // 2. "Here's your drink" / "what I owe you": the item(s) this deal says you owe."""
assert t.count(old) == 1, "anchor"
p.write_text(t.replace(old, new), encoding="utf-8")
print("patch_round9d: applied")
