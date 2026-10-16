#!/usr/bin/env python3
"""NC22 = NC21 + ClearGroup bandits are no longer rejected as owned_target (row IMM-14-d).
Usage: python3 nc22edit.py <tree>  (tree has src/ = NC21 sources; ActivityOwnership.h is copied into src/ by this script)."""
import sys, io, os, shutil
tree = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
shutil.copyfile(here + "/ActivityOwnership.h", tree + "/src/ActivityOwnership.h")
def load(p):
    s = io.open(p, encoding="utf-8", newline="").read(); return s, ("\r\n" if s.count("\r\n") * 2 > s.count("\n") else "\n")
def sub(s, nl, old, new):
    old = old.replace("\n", nl); new = new.replace("\n", nl)
    assert s.count(old) == 1, "anchor count %d: %r" % (s.count(old), old[:90])
    return s.replace(old, new)
p = tree + "/src/ActivityPolicySupport.cpp"; s, nl = load(p)
s = sub(s, nl, '#include "ActivityMineProduct.h"\n', '#include "ActivityMineProduct.h"\n#include "ActivityOwnership.h"\n')
s = sub(s, nl, ' if(target->getMySlaveOwner().serial) {reason="owned_target";return true;}\n',
 ' {\n'
 '  // NC22: a non-zero owner handle alone is not ownership (spawned wild bandits carry one); see ActivityOwnership.h.\n'
 '  const char* own=Ownership::Decide(target->isAnimal(),target->getMySlaveOwner().serial,(int)target->isSlave(),\n'
 '   target->isChainedMode(),target->inSomething==IN_PRISON);\n'
 '  if(*own) {reason=own;return true;}\n'
 ' }\n')
s = sub(s, nl, 'bool IsProtectedActivityTarget(Character* actor,Character* target,std::string& reason) {\n',
 'std::string OwnershipDiag(Character* target) {\n'
 ' if(!target) return "owner=na";\n'
 ' try {\n'
 '  std::ostringstream o; o<<"ownerSerial="<<target->getMySlaveOwner().serial<<" slaveState="<<(int)target->isSlave()\n'
 '   <<" chained="<<(target->isChainedMode()?1:0)<<" prison="<<(target->inSomething==IN_PRISON?1:0)<<" animal="<<(target->isAnimal()?1:0);\n'
 '  return o.str();\n'
 ' } catch(...) {return "owner=err";}\n'
 '}\n'
 'bool IsProtectedActivityTarget(Character* actor,Character* target,std::string& reason) {\n')
io.open(p, "w", encoding="utf-8", newline="").write(s)
p = tree + "/src/ActivityPolicySupport.h"; s, nl = load(p)
s = sub(s, nl, 'bool IsProtectedActivityTarget(Character*, Character*, std::string& reason);\n',
 'bool IsProtectedActivityTarget(Character*, Character*, std::string& reason);\n'
 '// NC22 diagnostic for the ACTIVITY_CLEARGROUP_MEMBER line: ownerSerial slaveState chained prison animal.\n'
 'std::string OwnershipDiag(Character*);\n')
io.open(p, "w", encoding="utf-8", newline="").write(s)
p = tree + "/src/ActivityRuntimeBindings.cpp"; s, nl = load(p)
s = sub(s, nl, '   <<" memberY="<<mp.y<<" actorY="<<ap.y;\n', '   <<" memberY="<<mp.y<<" actorY="<<ap.y<<" "<<OwnershipDiag(member);\n')
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("nc22edit OK")
