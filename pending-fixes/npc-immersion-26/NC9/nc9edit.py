# NC9 = NC8 + (1) ACTIVITY_WILD_REFUSED logs the six ownership flags individually,
# (2) Mine proposal tests a path to an approach point on a ring around the node when the centre path is 0.
# usage: python3 nc9edit.py <root holding src + legacy-v1>   (ActivityApproachRing.h is added separately by the patch)
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
    s=once(s,'namespace Stobe { namespace ActivityWild {','#include <string>\nnamespace Stobe { namespace ActivityWild {')
    s=once(s,'// Returns "" when proven wild',
'''// Individual ownership flags for the refusal log (NC9): which one marks a squad as owned.
inline std::string Flags(const WildFacts& f) {
 std::string o="baseTown="; o+=f.baseTown?"1":"0";
 o+=" homeTown="; o+=f.homeTown?"1":"0";
 o+=" homeBuilding="; o+=f.homeBuilding?"1":"0";
 o+=" occupiedTown="; o+=f.occupiedTown?"1":"0";
 o+=" slaves="; o+=f.slaves?"1":"0";
 o+=" stuff="; o+=f.stuff?"1":"0";
 return o;
}
// Returns "" when proven wild''')
    return s
def policy(s):
    s=once(s,' f.stuff=owned.stuff.size() ? true:false;\n',
' f.stuff=owned.stuff.size() ? true:false;\n'
' {\n'
'  std::ostringstream fl; fl<<ActivityWild::Flags(f)<<" squadType="<<(int)squad->getSquadType()'
'<<" slaveCount="<<owned.slaves.size()<<" stuffCount="<<owned.stuff.size()<<" ";\n'
'  flags=fl.str();\n }\n')
    s=once(s,'std::string WildRefusal(Character* target,std::string& note) {\n ActivityWild::WildFacts f;\n note.clear();',
              'std::string WildRefusal(Character* target,std::string& note) {\n ActivityWild::WildFacts f;\n std::string flags;\n note.clear();')
    # note gets flags prefix after construction
    s=once(s,' return ActivityWild::Verdict(f);\n}\nbool ProvenWild(',' note=flags+note;\n return ActivityWild::Verdict(f);\n}\nbool ProvenWild(')
    return s
HELPER='''namespace {
// NC9: Mine nodes are buildings whose centre sits inside their own footprint, so pathExists(avatar,centre)
// is 0 even for reachable nodes. Test a path to an approach point on a ring around the node instead
// (ring samples nearest the actor first, each projected to the navmesh). Rate limited per node.
bool MineApproachPath(NavMesh* nav,HavokCharacter* avatar,const Ogre::Vector3& node,const Ogre::Vector3& actorPos,unsigned serial) {
 static std::map<unsigned,DWORD> failedAt,loggedAt;
 const DWORD now=GetTickCount();
 std::map<unsigned,DWORD>::iterator f=failedAt.find(serial);
 if(f!=failedAt.end() && now-f->second<3000) return false;
 if(failedAt.size()>256) failedAt.clear();
 if(loggedAt.size()>256) loggedAt.clear();
 if(!nav || !avatar || !_finite(node.x) || !_finite(node.z)) return false;
 const float base=std::atan2(actorPos.z-node.z,actorPos.x-node.x);
 unsigned tried=0,projected=0;
 for(unsigned i=0;i<(unsigned)ActivityApproach::kCount;++i) {
  float x,z; ActivityApproach::Sample(node.x,node.z,_finite(base)?base:0.0f,i,x,z);
  float y=UtilityT::getTerrainHeight(x,z); if(!_finite(y)) y=node.y;
  const Ogre::Vector3 want(x,y,z); Ogre::Vector3 out; ++tried;
  if(nav->getClosestPoint(want,20.0f,1.0f,false,out)!=1) continue;
  if(!_finite(out.x)||!_finite(out.y)||!_finite(out.z)) continue;
  const float dx=out.x-want.x,dz=out.z-want.z; if(dx*dx+dz*dz>20.0f*20.0f) continue;
  ++projected;
  if(nav->pathExists(avatar,out)==1) {
   std::map<unsigned,DWORD>::iterator l=loggedAt.find(serial);
   if(l==loggedAt.end() || now-l->second>5000) {
    loggedAt[serial]=now;
    try { std::ostringstream s; s<<"ACTIVITY_MINE_APPROACH node="<<serial<<" sample="<<i<<" tried="<<tried<<" projected="<<projected
     <<" approach="<<out.x<<","<<out.y<<","<<out.z; Log(s.str()); } catch(...) {}
   }
   return true;
  }
 }
 failedAt[serial]=now;
 try { std::ostringstream s; s<<"ACTIVITY_MINE_APPROACH node="<<serial<<" none tried="<<tried<<" projected="<<projected; Log(s.str()); } catch(...) {}
 return false;
}
}
'''
def bind(s,src):
    s=once(s,'#include <kenshi/NavMesh.h>\n','#include <kenshi/NavMesh.h>\n#include <kenshi/util/UtilityT.h>\n#include "ActivityApproachRing.h"\n#include <cmath>\n#include <map>\n')
    if '#include <windows.h>' not in s: s=once(s,'#include <float.h>\n','#include <float.h>\n#include <windows.h>\n')
    anchor='std::string ConcreteRuntimeBindings::ProposalFacts('
    s=once(s,anchor,HELPER+anchor)
    old='    const int rawPath=world_->navmesh->pathExists(avatar,p);\n'
    new=('    int rawPath=world_->navmesh->pathExists(avatar,p);\n'
         '    if(rawPath!=1 && std::string(kind)=="Mine" && MineApproachPath(world_->navmesh,avatar,p,actor->getPosition(),object->getHandle().serial)) rawPath=1;\n')
    return once(s,old,new)
for d in ('src','legacy-v1'):
    rw(f'{root}/{d}/ActivityWildVerdict.h',wild)
    rw(f'{root}/{d}/ActivityPolicySupport.cpp',policy)
    rw(f'{root}/{d}/ActivityRuntimeBindings.cpp',lambda s:bind(s,d))
print('ok')
