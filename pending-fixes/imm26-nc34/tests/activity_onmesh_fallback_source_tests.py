# imm26 fix26aonmesh source test (row 26-a NC33 -> NC34). Supersedes activity_offmesh_reach_source_tests.py (NC31/NC32), which demanded the fallback ONLY for an
# off-mesh actor. After the goat was KO'd 9 u away the actor was ON the mesh with pathExists()!=1 (ACTIVITY_SCAN_DIAG onMesh=1 rawPath=0 reach=0) and
# Goal::Issue(TakeItem) was rejected with current_native_path_unconfirmed. ConcreteRuntimeBindings::Refresh must apply the bounded OffMeshShortRange fallback
# whenever the native rule left t.reachable=false (on-mesh or off-mesh actor), with every other gate kept. FAILS on NC33, PASSES on NC34.
# Usage: python3 activity_onmesh_fallback_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
fails = []
def rd(n):
    try: return io.open(src + '/' + n, encoding='utf-8', newline='').read()
    except IOError: fails.append('missing file ' + n); return ''
hdr = rd('ActivityOffMeshReach.h'); cpp = rd('ActivityRuntimeBindings.cpp')
if 'OffMeshShortRange' not in hdr or not re.search(r'kOffMeshShortRange\s*=\s*35\.0', hdr): fails.append('header lacks OffMeshShortRange / kOffMeshShortRange = 35.0')
if not re.search(r'if\(\s*!huntKind\s*\|\|\s*onMesh\s*\|\|\s*!visible\s*\|\|\s*!targetOnMesh\s*\)\s*return\s+false', hdr): fails.append('OffMeshShortRange must return false unless Hunt && off-mesh && visible && targetOnMesh')
if '#include "ActivityOffMeshReach.h"' not in cpp: fails.append('bindings do not include ActivityOffMeshReach.h')
m = re.search(r'bool ConcreteRuntimeBindings::Refresh\(.*?\nstd::vector<NativeDestination> ConcreteRuntimeBindings::Discover', cpp, re.S)
ref = m.group(0) if m else ''
if not m: fails.append('Refresh() body not found')
# the native rule must stay exactly as before (on-mesh actors keep the pathExists verdict)
if not re.search(r't\.reachable=_finite\(p\.x\)&&_finite\(p\.y\)&&_finite\(p\.z\)&&\s*world_->navmesh\s*&&\s*avatar\s*&&\s*avatar->isOnNavmesh\(\)\s*&&\s*world_->navmesh->pathExists\(avatar,p\)==1;', ref): fails.append('the native reachable rule (isOnNavmesh && pathExists==1) must remain')
b = re.search(r'if\(!t\.reachable\s*&&\s*a\.kind==Hunt\s*&&(.*?)\)\s*\{(.*?)\n \}\r?\n if\(!t\.reachable\) reason="current_native_path_unconfirmed";', ref, re.S)
if not b: fails.append('off-mesh Hunt block must sit between the native rule and the current_native_path_unconfirmed reason')
else:
    cond, body = b.group(1), b.group(2)
    for need in ('t.visible', 'world_->navmesh'):
        if need not in cond: fails.append('fallback block condition lacks ' + need)
    if re.search(r'isOnNavmesh', cond): fails.append('fallback block condition must NOT depend on avatar->isOnNavmesh() (on-mesh actor with unconfirmed path must also get the fallback)')
    if 'actorOnMesh=' not in body: fails.append('ACTIVITY_OFFMESH_REACH log must print actorOnMesh=')
    if 'getClosestPoint(p,Stobe::ActivityReach::kTargetSnapRadius' not in body: fails.append('block must prove the TARGET is on/near mesh via getClosestPoint(p,kTargetSnapRadius)')
    if 'pathExists' in body: fails.append('block must not call pathExists with an off-mesh avatar')
    if not re.search(r't\.reachable=Stobe::ActivityReach::OffMeshShortRange\(true,false,t\.visible,targetOnMesh,p\.x-ap\.x,p\.z-ap\.z,p\.y-ap\.y\);', body): fails.append('block must set t.reachable from OffMeshShortRange(true,false,visible,targetOnMesh,dx,dz,dy)')
    if 'ACTIVITY_OFFMESH_REACH' not in body: fails.append('ACTIVITY_OFFMESH_REACH log line missing')
if len(re.findall(r'OffMeshShortRange\(', cpp)) != 1: fails.append('OffMeshShortRange must be used exactly once in the bindings')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
