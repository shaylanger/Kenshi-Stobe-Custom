#!/usr/bin/env python3
"""NC24 row 25-b (imm26-sfW): NaturalOutput follows the node's BUILDING_FUNCTIONALITY ref one hop and reads its `produces` ITEM list.
Usage: python3 nc24edit.py <tree>   (edits src/ and legacy-v1/ ActivityPolicySupport.cpp in place, CRLF-safe)
Iron Resource (42248-gamedata.base) -functionality-> Ore mine (1869, type 62) -produces-> Raw Iron (1866, ITEM). how=gamedata:functionality>produces.
Also extends the ACTIVITY_MINE_EXACT_DIAG lists= dump with the first-hop functionality records' own list names (fn=<sid>[list:n,...])."""
import sys, io
tree = sys.argv[1]
OLD1 = '''    GameData* ref=it->second[k].ptr;
    if(!ref || ref->type!=ITEM || ref->stringID.empty()) continue;
'''
NEW1 = '''    GameData* ref=it->second[k].ptr;
    if(ref && ref->type==BUILDING_FUNCTIONALITY) { // NC24 (25-b): node -> functionality -> produces -> ITEM
     auto pr=ref->objectReferences.find("produces");
     if(pr!=ref->objectReferences.end()) {
      for(size_t j=0;j<pr->second.size() && j<32;++j) {
       GameData* prod=pr->second[j].ptr;
       if(!prod || prod->type!=ITEM || prod->stringID.empty()) continue;
       if(std::find(in.dataItems.begin(),in.dataItems.end(),prod->stringID)==in.dataItems.end()) {
        in.dataItems.push_back(prod->stringID); if(list.empty()) list=it->first+">produces";
       }
      }
     }
     continue;
    }
    if(!ref || ref->type!=ITEM || ref->stringID.empty()) continue;
'''
OLD2 = '''     o<<(n?",":"")<<li->first<<":"<<li->second.size();
'''
NEW2 = '''     o<<(n?",":"")<<li->first<<":"<<li->second.size();
    { // NC24: list names of each first-hop functionality record (one round to see a data miss)
     unsigned m=0;
     for(auto li=b->getGameData()->objectReferences.begin();li!=b->getGameData()->objectReferences.end() && m<12;++li,++m)
      for(size_t k=0;k<li->second.size() && k<4;++k) {
       GameData* fr=li->second[k].ptr;
       if(!fr || fr->type!=BUILDING_FUNCTIONALITY) continue;
       o<<" fn="<<fr->stringID<<"[";
       unsigned q=0; for(auto fl=fr->objectReferences.begin();fl!=fr->objectReferences.end() && q<12;++fl,++q) o<<(q?",":"")<<fl->first<<":"<<fl->second.size();
       o<<"]";
      }
    }
'''
for rel in ("/src/ActivityPolicySupport.cpp", "/legacy-v1/ActivityPolicySupport.cpp"):
    p = tree + rel
    s = io.open(p, encoding="utf-8", newline="").read()
    nl = "\r\n" if s.count("\r\n") * 2 > s.count("\n") else "\n"
    assert '"produces"' not in s, "NC24 already applied: " + rel
    for old, new in ((OLD1, NEW1), (OLD2, NEW2)):
        o2, n2 = old.replace("\n", nl), new.replace("\n", nl)
        assert s.count(o2) == 1, "anchor count %d in %s: %r" % (s.count(o2), rel, old[:60])
        s = s.replace(o2, n2)
    io.open(p, "w", encoding="utf-8", newline="").write(s)
print("nc24edit applied")
