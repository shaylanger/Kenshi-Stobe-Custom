# NC16 = NC15 + Activity travel calls use the lifecycle's own world id (row IMM-26-a).
# Usage: python3 nc16edit.py <NC15-tree-root>   (root contains src/). Edits src/ActivityRuntimeBindings.cpp and src/ActivityHandBack.cpp only.
# Root cause: a.worldId (Activity epoch, plain 32-hex) was passed as expectedWorld to NativeTravelLifecycle::Start/InspectRequest/
# ReleaseOwned; Prepare only accepts the lifecycle's own "travel-<32hex>" id -> travel_identity_or_ownership_rejected. Prepare is NOT loosened.
import sys,io,re
root=sys.argv[1]
def rw(path):
    p=root+'/'+path
    return p,io.open(p,'r',encoding='utf-8',newline='').read()
def sub_calls(path,expect):
    p,s=rw(path)
    n=[0]
    # replace "a.worldId" only inside NativeTravelLifecycle::{Start,InspectRequest,ReleaseOwned}( ... ) argument lists
    def fix(m):
        call=m.group(0)
        c=call.count('a.worldId')
        assert c==1,(path,call[:70],c)
        n[0]+=1
        return call.replace('a.worldId','NativeTravelLifecycle::WorldId()')
    s=re.sub(r'NativeTravelLifecycle::(?:Start|InspectRequest|ReleaseOwned)\((?:[^;]*?)(?=,\s*PlaythroughSession::Generation\(\)|,\s*\r?\n?\s*a\.scopeDigest,\s*a\.dispatchEnvelope|,\s*a\.scopeDigest)',fix,s)
    assert n[0]==expect,(path,n[0],expect)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
sub_calls('src/ActivityRuntimeBindings.cpp',6)
sub_calls('src/ActivityHandBack.cpp',4)
# guard: fail closed with a clear reason (logged via ACTIVITY_END_DIAG) when the lifecycle has no world id yet
p,s=rw('src/ActivityRuntimeBindings.cpp')
old=' if(NativeTravelLifecycle::Start(world_,actor,a.requester,NULL,'
nl='\r\n' if '\r\n' in s else '\n'
new=' if(NativeTravelLifecycle::WorldId().empty()){reason="travel_lifecycle_world_unset";return false;}'+nl+old
assert s.count(old)==1
s=s.replace(old,new)
io.open(p,'w',encoding='utf-8',newline='').write(s)
