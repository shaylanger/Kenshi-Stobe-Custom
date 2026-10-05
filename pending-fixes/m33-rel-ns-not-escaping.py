#!/usr/bin/env python3
"""m33 S7: rel-enslaved pick_ns skips slaves whose latest slave_state is ESCAPING_SLAVE (2).
p7-05 picked Babarg, who turned ESCAPING_SLAVE after p7-04's knockouts and ran 565 m away mid-lockpick.
Usage: m33-rel-ns-not-escaping.py <server tree root>"""
import sys

p = sys.argv[1] + "/tests/social_relationship/ingame/rel-enslaved.sh"
s = open(p).read()
anchor = '''    grep -v -E "^($A|$B)	" | awk'''
assert s.count(anchor) == 1, "anchor"
# names whose latest slave state line ends in ESCAPING_SLAVE (2) or EX_SLAVE (3)
esc = '''  # m33 S7: a slave that turned ESCAPING_SLAVE (2) after p7-04's knockouts ran 565 m away mid-lockpick: skip
  # slaves whose latest slave state is 2 (escaping) or 3 (ex-slave)
  tail -n +"$base" "$L" | grep -a "EVENT_SCAN: slave state serial=" | sed -n -E 's/.* name=(.*) chained=.* slave_state=[0-9]+->([0-9]+).*/\\1	\\2/p' |
    awk -F'	' '{st[$1]=$2} END{for(n in st) if(st[n]>=2) print n; print "@@none@@"}' > "$O/ns-escaping.txt"
'''
fn = "pick_ns(){\n  NS=\"\"; : > \"$O/ns-candidates.txt\"\n"
assert s.count(fn) == 1, "fn"
s = s.replace(fn, fn + esc)
s = s.replace(anchor, '''    grep -v -E "^($A|$B)	" | awk -F'	' 'NR==FNR{e[$0]=1;next} !($1 in e)' "$O/ns-escaping.txt" - | awk''')
open(p, "w").write(s)
print("patched", p)
