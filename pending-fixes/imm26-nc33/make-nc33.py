# NC33 = NC32 + fix26apoll. Usage: python3 -I make-nc33.py <tree with src/> (edits in place, CRLF-exact, asserts anchors)
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

edit('ActivityNativeExecutor.cpp', [(
"""  if(now_>=op.agreement.expiresAt || !AliveActor(actor,op.request.actor) || !SameHand(actor->getHandle(),op.actorIdentity) ||
     !policy_.Revalidate(op.agreement,op.request,current,reason))
   return op.receipt=Result(Receipt::Interrupted,reason.empty()?"agreement_or_actor_unavailable":reason);
""",
"""  if(now_>=op.agreement.expiresAt || !AliveActor(actor,op.request.actor) || !SameHand(actor->getHandle(),op.actorIdentity))
   return op.receipt=Result(Receipt::Interrupted,"agreement_or_actor_unavailable");
  if(!policy_.Revalidate(op.agreement,op.request,current,reason)) {
   // fix26apoll (row 26-a NC32): one tick with reachable=0 (Revalidate -> "current_native_path_unconfirmed") used to Interrupt a dispatched Attack/Travel,
   // Goal::Replan then added the goat to attempted_ and the next empty scan stopped the Hunt. A transient path-unconfirmed reading is not a reason to drop
   // an order the engine still owns: keep it Pending ONLY for that exact reason and only while our owned order is still the single live order.
   // Every other Revalidate failure (scope, authorization, hunt_source_mismatch, target_not_observed, ...) still Interrupts as before.
   const bool unconfirmedOnly=reason=="current_native_path_unconfirmed";
   const bool keepPending=unconfirmedOnly && (op.request.command==Attack || op.request.command==Travel) && CaptureOwned(actor,op,false);
   if(unconfirmedOnly) {
    try { static unsigned pollKeepCount=0; if((pollKeepCount++%10)==0) { std::ostringstream d; d<<"ACTIVITY_POLL_DIAG id="<<op.request.id<<" cmd="<<static_cast<int>(op.request.command)
     <<" revalidate_path_unconfirmed keepPending="<<(keepPending?1:0)<<" n="<<pollKeepCount; ::Log(d.str()); } } catch (...) { /* diagnostics never change the outcome */ }
   }
   if(!keepPending) return op.receipt=Result(Receipt::Interrupted,reason.empty()?"agreement_or_actor_unavailable":reason);
   current=op.destination.facts; reason.clear();
  }
""")])

edit('ActivityRuntimeBindings.cpp', [(
"""   int rawPath=99; float d2=-1.0f; std::string prot="na"; int sees=-1;
""",
"""   int rawPath=99; float d2=-1.0f; std::string prot="na"; int sees=-1;
   int tOnMesh=-1; float ddx=0.0f,ddz=0.0f,ddy=0.0f; // fix26apoll: is the goat itself on/near mesh, and where is it relative to the actor
"""),(
"""    if(onMesh && world_->navmesh) rawPath=world_->navmesh->pathExists(av,ap);
""",
"""    if(onMesh && world_->navmesh) rawPath=world_->navmesh->pathExists(av,ap);
    ddx=ap.x-actor->getPosition().x; ddz=ap.z-actor->getPosition().z; ddy=ap.y-actor->getPosition().y;
    if(world_->navmesh) { Ogre::Vector3 snap; try { tOnMesh=(world_->navmesh->getClosestPoint(ap,Stobe::ActivityReach::kTargetSnapRadius,1.0f,false,snap)==1)?1:0; } catch(...) { tOnMesh=-2; } }
"""),(
"""<<" sees="<<sees<<" onMesh="<<(onMesh?1:0)<<" rawPath="<<rawPath<<" d2="<<d2<<" protected="<<prot
""",
"""<<" sees="<<sees<<" onMesh="<<(onMesh?1:0)<<" rawPath="<<rawPath<<" d2="<<d2<<" protected="<<prot
    <<" targetOnMesh="<<tOnMesh<<" dx="<<ddx<<" dz="<<ddz<<" dy="<<ddy
""")])
print('NC33 edits applied')
