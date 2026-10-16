# NC10 = NC9 + (1) Verdict(): homeBuilding no longer counts as ownership for animals-only roaming squads in a not-real faction
#             (roaming wild herds always carry _homeBuilding=1, i5 op6 NC9 flags);
#        (2) MineSourcePermitted: a node whose faction is not a real faction ("No Faction") is unowned.
# usage: python3 nc10edit.py <root holding src + legacy-v1>
import sys
root=sys.argv[1]
def rw(p,f):
    s=open(p,newline='').read(); crlf='\r\n' in s
    s=s.replace('\r\n','\n'); s=f(s)
    if crlf: s=s.replace('\n','\r\n')
    open(p,'w',newline='').write(s)
def once(s,old,new):
    assert s.count(old)==1,(old,s.count(old)); return s.replace(old,new)
def wild(s):
    return once(s,' if(f.baseTown || f.homeTown || f.homeBuilding || f.occupiedTown || f.slaves || f.stuff)\n',
' // NC10: homeBuilding is NOT ownership here: every roaming wild herd (natural and spawned) has it set.\n'
' // The faction clause above already proved the squad is in no real faction (Shay: wild animals pass).\n'
' if(f.baseTown || f.homeTown || f.occupiedTown || f.slaves || f.stuff)\n')
def policy(s):
    return once(s,'  if(b->getFaction() && b->getFaction()!=actor->getFaction()) {\n   reason="resource_owned_by_other_faction"',
'  // NC10: a node in "No Faction" (non-null, not a real faction) is unowned.\n'
'  if(b->getFaction() && b->getFaction()!=actor->getFaction() && !b->getFaction()->isNotARealFaction()) {\n   reason="resource_owned_by_other_faction"')
for d in ('src','legacy-v1'):
    rw(root+'/'+d+'/ActivityWildVerdict.h',wild)
    rw(root+'/'+d+'/ActivityPolicySupport.cpp',policy)
print('ok')
