#!/usr/bin/env python3
"""NC23 row 26-a part (imm26-sfW): Attack cleanup completes once our own order is gone.
Usage: python3 nc23edit.py <tree>   (tree/src = NC22 (+ sfP) sources; edits src/ActivityNativeExecutor.cpp in place, CRLF-safe)
Cause: NativeExecutor::CancelOwned required NativeEnded (goal/action/movement idle) for Attack too; the actor's own combat AI keeps
fighting a retaliating target, so Release never completed, the Hunt stayed phase 4 and no terminal report was sent (record stuck accepted).
Fix: for Attack, once our captured order is no longer in the order list (we removed it, or the engine ended it) cleanup is complete.
Travel / WorkResource keep the NativeEnded test. Every false return in CancelOwned now logs ACTIVITY_CANCEL_DIAG (rate-limited, 5 s per request id+branch)."""
import sys, io
tree = sys.argv[1]
p = tree + "/src/ActivityNativeExecutor.cpp"
s = io.open(p, encoding="utf-8", newline="").read()
nl = "\r\n" if s.count("\r\n") * 2 > s.count("\n") else "\n"
assert "ACTIVITY_CANCEL_DIAG" not in s, "NC23 already applied"
def sub(old, new):
    global s
    old = old.replace("\n", nl); new = new.replace("\n", nl)
    assert s.count(old) == 1, "anchor count %d: %r" % (s.count(old), old[:80])
    s = s.replace(old, new)

sub('#include "KenshiBuildingCompat.h"\n', '#include "KenshiBuildingCompat.h"\n#include <sstream>\n#include <string>\nvoid Log(const std::string &msg); // Utils.h (not included: it pulls windows.h min/max macros)\n')

sub('bool NativeExecutor::CancelOwned(const std::string& id) {\n',
'''extern "C" __declspec(dllimport) unsigned long __stdcall GetTickCount(void);
// NC23: one diag line per false return, rate-limited per (request id, branch) so a stuck cleanup names its branch without flooding.
static void CancelDiag(const std::string& id,const char* branch,const std::string& extra) {
 static std::map<std::string,unsigned long> last;
 const std::string key=id+"|"+branch; const unsigned long now=GetTickCount();
 std::map<std::string,unsigned long>::iterator it=last.find(key);
 if(it!=last.end() && now-it->second<5000)return;
 if(last.size()>256)last.clear();
 last[key]=now;
 ::Log("ACTIVITY_CANCEL_DIAG id="+id+" branch="+branch+(extra.empty()?"":" "+extra));
}
bool NativeExecutor::CancelOwned(const std::string& id) {
''')

sub('''   if(!actor || !SameHand(actor->getHandle(),op.actorIdentity))return false;
   OrdersReceiver* orders=actor->getOrdersReciever();if(!orders)return false;
   if(!orders->orders.list.empty()) {
    // Validate actual task key, full subject, start timestamp and fixed travel
    // destination before using the shared pointer/count cancellation helper.
    if(!CaptureOwned(actor,op,false))return false;
    std::string reason;
    if(!Autonomy::TryCancelOwnedOrder(world_,op.request.actor,op.owned,reason))return false;
    op.orderRemoved=true;
   }
   // Empty order queue alone is not proof: GOAP/body/movement may still run.
   if(!NativeEnded(actor,op))return false;
   op.cleanupRequired=false;
''',
'''   if(!actor || !SameHand(actor->getHandle(),op.actorIdentity)){CancelDiag(id,"actor_mismatch","");return false;}
   OrdersReceiver* orders=actor->getOrdersReciever();if(!orders){CancelDiag(id,"no_orders_receiver","");return false;}
   const bool attack=op.request.command==Attack;
   if(!orders->orders.list.empty()) {
    bool listed=false;
    if(attack && op.orderCaptured && !op.orderRemoved)
     for(size_t k=0;k<orders->orders.list.size();++k){Tasker* t=orders->orders.list[k];
      if(t && reinterpret_cast<unsigned long long>(t)==op.owned.runtimePointer && t->startTime==op.orderStartTime){listed=true;break;}}
    if(attack && op.orderCaptured && !listed) {
     // NC23: our captured Attack order is no longer listed (engine ended it, or the list now holds only foreign orders).
     op.orderRemoved=true;
    } else {
     // Validate actual task key, full subject, start timestamp and fixed travel
     // destination before using the shared pointer/count cancellation helper.
     if(!CaptureOwned(actor,op,false)){CancelDiag(id,"capture_mismatch","orders="+std::to_string((long long)orders->orders.list.size()));return false;}
     std::string reason;
     if(!Autonomy::TryCancelOwnedOrder(world_,op.request.actor,op.owned,reason)){CancelDiag(id,"cancel_refused","reason="+reason);return false;}
     op.orderRemoved=true;
    }
   }
   // Empty order queue alone is not proof for Travel/WorkResource: GOAP/body/movement may still run.
   // Attack (NC23): our order is gone; the actor's own combat AI fighting a retaliating target is not an owned order.
   if(!attack && !NativeEnded(actor,op)){
    CancelDiag(id,"native_not_ended","moving="+std::string(actor->getMovement()&&actor->getMovement()->isCurrentlyMoving()?"1":"0"));
    return false;
   }
   op.cleanupRequired=false;
''')
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("nc23edit applied")
