#!/usr/bin/env python3
"""m31c: REL-p7-04 (batch Q) - Daphnilis started the lock pick (Stobe 'liberation task ... task=201 subject=Izumi'
4 s after the order) but Izumi's chains never came off in 210 s; no combat on either. The old progress gate accepted
the task line, so nothing re-issued the order. Now: wait for the chains themselves; after 45 s order again, after
another 45 s teleport + order again; `crime <slave>` (who still targets her) and `where <freer>` are recorded on
each miss. Same assertions (chains off, freed fact names the freer).
Usage: python3 m31c-p704-retry.py <server tree root>   (live tree only: ss-merge has no p7-04 file)
"""
import sys, os

root = sys.argv[1]
p = os.path.join(root, 'tests/social_relationship/ingame/REL-p7-04-enslaved-real-liberator.txt')
s = open(p, encoding='utf-8').read()
L = r'D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log'
C = r'EVENT_SCAN: slave state serial=\d+ name=__SLAVE__ chained=1->0'

old_start = '# m31 (batch P: the order was never carried out'
old_end = '@log-wait 180 %s ~ %s\n' % (L, C)
a = s.find(old_start)
b = s.find(old_end)
assert a >= 0 and b > a, 'anchors not found (already applied?)'
assert s.count(old_end) == 1
b += len(old_end)
old = s[a:b]
assert 'chance ${FREE} lockpick ${SLAVE}' in old and 'order ${FREE} PICK_LOCK_ON_SHACKLES target ${SLAVE}' in old

def guard(action, wait=None):
    head = '@any @log-wait %d %s ~ %s' % (wait, L, C) if wait else '@any @log %s ~ %s' % (L, C)
    return '%s || %s\n' % (head, action)

ORDER = 'order ${FREE} PICK_LOCK_ON_SHACKLES target ${SLAVE}'
new = (
    '# m31 (batch P: the order was never carried out, the slave state never moved): setup check first.\n'
    '# m31c (batch Q: the pick task started 4 s after the order, the chains never came off in 210 s): wait for the\n'
    '#   chains themselves; 45 s without them -> record who works the lock (crime/where) and order again; another\n'
    '#   45 s -> teleport the freer back and order again. Every retry is skipped once the chains are off.\n'
    'chance ${FREE} lockpick ${SLAVE} ~ lockpick_chance=(0\\.0*[1-9]|[1-9])\n'
    + ORDER + '\n'
    'speed 2\n'
    + guard('crime ${SLAVE} radius 50', 45)
    + guard('where ${FREE}')
    + guard(ORDER)
    + guard('crime ${SLAVE} radius 50', 45)
    + guard('speed 0')
    + guard('teleport ${FREE} ${SLAVE} dist 3')
    + guard(ORDER)
    + guard('speed 2')
    + '@log-wait 120 %s ~ %s\n' % (L, C)
)
s = s[:a] + new + s[b:]
st = os.stat(p)
open(p + '.new', 'w', encoding='utf-8').write(s)
os.chmod(p + '.new', st.st_mode & 0o7777)
try:
    os.chown(p + '.new', st.st_uid, st.st_gid)  # keep the web user's ownership (run as root)
except PermissionError:
    pass
os.replace(p + '.new', p)  # never rewrite a file a running batch may read in place
print('patched', p)
