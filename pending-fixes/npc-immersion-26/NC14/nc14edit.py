# NC14 = NC13 + call site for ProposalTrace::SightDiag (NC13 defined it but never called it). Diagnostic only.
# Usage: python3 nc14edit.py <NC13-tree-root>   (root contains src/); edits src/ActivityRuntimeBindings.cpp only.
import sys,io
root=sys.argv[1]
def edit(path,old,new,count=1):
    p=root+'/'+path
    s=io.open(p,'r',encoding='utf-8',newline='').read()
    if '\r\n' in s:
        old=old.replace('\n','\r\n'); new=new.replace('\n','\r\n')
    assert s.count(old)==count,(path,old[:60],s.count(old))
    s=s.replace(old,new)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
P='src/ActivityRuntimeBindings.cpp'
# 1. members for the two characters (valid for the whole ProposalFacts scope; destructor runs inside it)
edit(P,' unsigned huntEmitted,animals; bool scanned; double hour; std::vector<std::string> animalLines; // NC13 ACTIVITY_SIGHT_DIAG\n',
 ' unsigned huntEmitted,animals; bool scanned; double hour; std::vector<std::string> animalLines; // NC13 ACTIVITY_SIGHT_DIAG\n'
 ' Character* diagActor; Character* diagRequester; // NC14: set once both resolve; used by the destructor call to SightDiag\n')
edit(P,'huntEmitted(0),animals(0),scanned(false),hour(-1.0) {}','huntEmitted(0),animals(0),scanned(false),hour(-1.0),diagActor(NULL),diagRequester(NULL) {}')
# 2. call site: destructor, BEFORE the "if(emitted) return" (so a Mine-only result still reports); SightDiag self-gates on huntEmitted/scanned and rate limits 1/5s/actor
edit(P,' ~ProposalTrace() {\n  try {\n   if(emitted) return;\n',' ~ProposalTrace() {\n  try { SightDiag(diagActor,diagRequester); } catch(...) { } // NC14 call site\n  try {\n   if(emitted) return;\n')
# 3. record the resolved characters
edit(P,' if(!actor || !requester) return "{\\"candidates\\":[]}";\n',' if(!actor || !requester) return "{\\"candidates\\":[]}";\n trace.diagActor=actor; trace.diagRequester=requester;\n')
