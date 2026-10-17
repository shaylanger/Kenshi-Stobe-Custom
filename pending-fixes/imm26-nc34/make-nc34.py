# NC34 = NC33 + fix26aonmesh. Usage: python3 -I make-nc34.py <tree with src/> (edits in place, CRLF-exact, asserts anchors)
import io, sys
src = sys.argv[1] + '/src/'
def edit(name, pairs):
    p = src + name
    s = io.open(p, 'rb').read().decode('utf-8')
    for old, new in pairs:
        old = old.replace('\n', '\r\n'); new = new.replace('\n', '\r\n')
        assert s.count(old) == 1, (name, old[:60])
        s = s.replace(old, new)
    io.open(p, 'wb').write(s.encode('utf-8'))

edit('ActivityRuntimeBindings.cpp', [
("""// visible, close (<= 35 u planar) and on/next to walkable mesh, an off-mesh actor is not evidence of an unreachable animal; the native order paths itself.
 if(!t.reachable && a.kind==Hunt && actor && avatar && world_->navmesh && t.visible && _finite(p.x)&&_finite(p.y)&&_finite(p.z) && !avatar->isOnNavmesh()) {
""",
"""// visible, close (<= 35 u planar) and on/next to walkable mesh, an off-mesh actor is not evidence of an unreachable animal; the native order paths itself.
 // fix26aonmesh (row 26-a NC33): the same fallback now also covers an ON-mesh actor whose pathExists verdict is unconfirmed (ACTIVITY_SCAN_DIAG onMesh=1 rawPath=0
 // reach=0 for a KO'd goat 9 u away -> TakeItem rejected with current_native_path_unconfirmed). Only reached when the native rule above already said "not reachable";
 // the same Hunt-only, visible, target-on-mesh, 35 u planar / 12 u vertical bounds apply (OffMeshShortRange), so far targets are never broadened.
 if(!t.reachable && a.kind==Hunt && actor && avatar && world_->navmesh && t.visible && _finite(p.x)&&_finite(p.y)&&_finite(p.z)) {
"""),
("""  try { static DWORD lastOffMeshLog=0; const DWORD nowTick=GetTickCount();
   if(nowTick-lastOffMeshLog>2000) { lastOffMeshLog=nowTick; std::ostringstream o; o<<"ACTIVITY_OFFMESH_REACH id="<<a.id<<" serial="<<t.serial<<" targetOnMesh="<<(targetOnMesh?1:0)
""",
"""  try { static DWORD lastOffMeshLog=0; const DWORD nowTick=GetTickCount();
   if(nowTick-lastOffMeshLog>2000) { lastOffMeshLog=nowTick; std::ostringstream o; o<<"ACTIVITY_OFFMESH_REACH id="<<a.id<<" serial="<<t.serial<<" actorOnMesh="<<(avatar->isOnNavmesh()?1:0)<<" targetOnMesh="<<(targetOnMesh?1:0)
"""),
])
