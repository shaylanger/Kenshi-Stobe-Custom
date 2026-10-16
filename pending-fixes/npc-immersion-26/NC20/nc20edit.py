#!/usr/bin/env python3
"""NC20 = NC18 + per-member ClearGroup diagnostic (row 14-d). Usage: python3 nc20edit.py <tree>  (tree has src/)."""
import sys, io
tree = sys.argv[1]
p = tree + "/src/ActivityRuntimeBindings.cpp"
s = io.open(p, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"
def sub(old, new):
    global s
    old = old.replace("\n", nl); new = new.replace("\n", nl)
    assert s.count(old) == 1, "anchor count %d: %r" % (s.count(old), old[:80])
    s = s.replace(old, new)

HELPER = r'''namespace {
// NC20 (row 14-d): the ClearGroup fixed set was empty for 5 visible hostile bandits and nothing logged which
// per-member flag rejected them. One rate-limited line (5 s per member) per platoon-mate, logged whenever the
// platoon's fixed set is smaller than the platoon-mates seen. Read-only: the extra closest-point probe below is
// diagnostic and never feeds the decision.
void NC20ClearGroupMemberDiag(NavMesh* nav,HavokCharacter* avatar,Character* actor,Character* member,const ClearGroupMemberEvidence& row,
 const std::string& protReason,int rawPath,bool pathEvaluated,bool selected,size_t setSize,size_t seen) {
 try {
  static std::map<unsigned,DWORD> last; const DWORD now=GetTickCount();
  std::map<unsigned,DWORD>::iterator it=last.find(row.serial);
  if(it!=last.end() && now-it->second<5000) return;
  if(last.size()>256) last.clear();
  last[row.serial]=now;
  const Ogre::Vector3 mp=member->getPosition(), ap=actor->getPosition();
  std::ostringstream s;
  s<<"ACTIVITY_CLEARGROUP_MEMBER actor="<<actor->getHandle().serial<<" serial="<<row.serial<<" name="<<member->getName().substr(0,32)
   <<" set="<<setSize<<"/"<<seen<<" selected="<<(selected?1:0)
   <<" visible="<<(row.visible?1:0)<<" hostile="<<(row.hostile?1:0)<<" protected="<<(row.protectedTarget?1:0)
   <<" protReason="<<protReason.substr(0,40)<<" active="<<(row.active?1:0)
   <<" dead="<<(member->isDead()?1:0)<<" ko="<<(member->isUnconcious()?1:0)<<" finite="<<(row.finitePosition?1:0)
   <<" pathExists="<<(pathEvaluated?rawPath:99)<<(pathEvaluated?"":"(not_evaluated)")
   <<" memberY="<<mp.y<<" actorY="<<ap.y;
  if(row.finitePosition && _finite(ap.x) && _finite(ap.z)) {
   const float dx=mp.x-ap.x,dz=mp.z-ap.z,dy=mp.y-ap.y;
   s<<" dist2d="<<std::sqrt(dx*dx+dz*dz)<<" dist3d="<<std::sqrt(dx*dx+dy*dy+dz*dz);
  }
  s<<" actorOnNavmesh="<<((avatar&&avatar->isOnNavmesh())?1:0);
  try { s<<" memberOnNavmesh="<<((member->getMovement()&&member->getMovement()->havokCharacter&&member->getMovement()->havokCharacter->isOnNavmesh())?1:0); } catch(...) {}
  if(nav && avatar && row.finitePosition && !(pathEvaluated && rawPath==1)) {
   Ogre::Vector3 out; const int cp=nav->getClosestPoint(mp,20.0f,1.0f,false,out);
   s<<" closest="<<cp;
   if(cp==1 && _finite(out.x)&&_finite(out.y)&&_finite(out.z)) s<<" closestDy="<<(out.y-mp.y)<<" pathToClosest="<<nav->pathExists(avatar,out);
  }
  Log(s.str());
 } catch(...) {}
}
}
'''
sub("std::string ConcreteRuntimeBindings::ProposalFacts(unsigned actorSerial,unsigned requesterSerial) {\n",
    HELPER + "std::string ConcreteRuntimeBindings::ProposalFacts(unsigned actorSerial,unsigned requesterSerial) {\n")

sub("""       std::vector<ClearGroupMemberEvidence> evidence;
       for(unsigned j=0;j<objects.size();++j) {""",
"""       std::vector<ClearGroupMemberEvidence> evidence;
       std::vector<Character*> nc20Members; std::vector<std::string> nc20Reasons; std::vector<int> nc20Path; std::vector<char> nc20Evaluated;
       for(unsigned j=0;j<objects.size();++j) {""")
sub("""        if(row.serial && row.visible && row.hostile && !row.protectedTarget && row.active && row.finitePosition)
         row.pathConfirmed=world_->navmesh->pathExists(avatar,memberPosition)==1;
        evidence.push_back(row);
       }
       clearGroupTargets[platoon]=SelectClearGroupTargets(evidence);
""",
"""        int nc20Raw=0; bool nc20Eval=false;
        if(row.serial && row.visible && row.hostile && !row.protectedTarget && row.active && row.finitePosition) {
         nc20Raw=world_->navmesh->pathExists(avatar,memberPosition); nc20Eval=true;
         row.pathConfirmed=nc20Raw==1;
        }
        evidence.push_back(row); nc20Members.push_back(member); nc20Reasons.push_back(memberReason); nc20Path.push_back(nc20Raw); nc20Evaluated.push_back(nc20Eval?1:0);
       }
       clearGroupTargets[platoon]=SelectClearGroupTargets(evidence);
       if(clearGroupTargets[platoon].size()<evidence.size()) {
        for(size_t e=0;e<evidence.size();++e) {
         const bool picked=std::find(clearGroupTargets[platoon].begin(),clearGroupTargets[platoon].end(),evidence[e].serial)!=clearGroupTargets[platoon].end();
         NC20ClearGroupMemberDiag(world_->navmesh,avatar,actor,nc20Members[e],evidence[e],nc20Reasons[e],nc20Path[e],nc20Evaluated[e]!=0,picked,clearGroupTargets[platoon].size(),evidence.size());
        }
       }
""")
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("NC20 edit applied")
