#include "N2SocialWatch.h"
#include "AudioPlayback.h"
#include "ChatBox.h"
#include "Globals.h"
#include "Interaction.h"
#include "N2Policy.h"
#include "NativeAttention.h"
#include "Utils.h"
#include <kenshi/Character.h>
#include <kenshi/GameWorld.h>
#include <kenshi/PlayerInterface.h>
#include <kenshi/RootObject.h>
#include <stdint.h>
#include <string>
#include <vector>
#include <windows.h>

namespace Stobe { namespace N2SocialWatch {
namespace {
const DWORD kScanIntervalMs = 2000;
const size_t kMaxPendingCombat = 8;

struct CombatNote { unsigned actor, target; };
struct Cand { Character* c; float dist; };

CRITICAL_SECTION g_cs;
bool g_csInit = false;
std::vector<CombatNote> g_pendingCombat;
N2Policy::ProximityGate g_gate;
DWORD g_lastScan = 0;

void EnsureInit() {
  if (!g_csInit) { InitializeCriticalSection(&g_cs); g_csInit = true; }
}
bool Ok(const void* p) { return p && (uintptr_t)p >= 0x1000; }
unsigned SerialOf(Character* c) {
  try { return c->getHandle().serial; } catch (...) { return 0; }
}
bool Gates() {
  if (!g_enableBoredEvents) return false;
  if (!Stobe::Interaction::Allowed()) return false;
  if (IsTtsPlaybackActive()) return false;
  if (Stobe::UI::IsDirectorSceneActive()) return false;
  if (Stobe::UI::IsAiRequestActive()) return false;
  return true;
}
std::string NameOf(Character* c) {
  try { return c->getName(); } catch (...) { return ""; }
}
bool Fire(GameWorld* world, Character* npc, Character* anchor, const char* reason, float dist) {
  std::string attn = Stobe::NativeAttention::AttentionJson(npc);
  if (attn.size() > 600) attn = "{\"observed\":false}";
  bool sent = Stobe::UI::TriggerOptionalBoredTurn(world, npc, anchor, attn);
  Log(std::string("N2_PROXIMITY: ") + (sent ? "dispatched" : "not dispatched") + " reason=" + reason + " npc=" + NameOf(npc) +
      " dist=" + ToString((int)dist));
  return sent;
}
} // namespace

void Reset() {
  EnsureInit();
  EnterCriticalSection(&g_cs);
  g_gate.Reset();
  g_pendingCombat.clear();
  g_lastScan = 0;
  LeaveCriticalSection(&g_cs);
}

void NoteCombatStart(unsigned actorSerial, unsigned targetSerial) {
  if (!actorSerial && !targetSerial) return;
  EnsureInit();
  EnterCriticalSection(&g_cs);
  if (g_pendingCombat.size() < kMaxPendingCombat) {
    CombatNote n; n.actor = actorSerial; n.target = targetSerial;
    g_pendingCombat.push_back(n);
  }
  LeaveCriticalSection(&g_cs);
}

void Update(GameWorld* world, Character* selected) {
  EnsureInit();
  DWORD tick = GetTickCount();
  if (tick - g_lastScan < kScanIntervalMs) return;
  g_lastScan = tick;
  if (!Ok(world) || !Ok(world->player)) return;
  uint32_t n = world->player->playerCharacters.size();
  if (n < 2) {
    EnterCriticalSection(&g_cs); g_pendingCombat.clear(); LeaveCriticalSection(&g_cs);
    return;
  }
  const bool open = Gates();
  std::vector<CombatNote> pending;
  EnterCriticalSection(&g_cs);
  pending.swap(g_pendingCombat);
  LeaveCriticalSection(&g_cs);
  if (!open) return;

  const double now = (double)tick / 1000.0;
  try {
    Character* anchor = NULL;
    if (Ok(selected)) {
      try { if (selected->isPlayerCharacter()) anchor = selected; } catch (...) { anchor = NULL; }
    }
    if (!anchor) anchor = world->player->playerCharacters[0];
    if (!Ok(anchor) || !Stobe::NativeAttention::IsFree(anchor)) return;
    const Ogre::Vector3 apos = anchor->getPosition();
    const unsigned anchorSerial = SerialOf(anchor);

    // Combat starts: distance from the anchor to the nearest participant.
    if (!pending.empty()) {
      lektor<RootObject*> nearList;
      bool haveNear = false;
      try {
        world->getCharactersWithinSphere(nearList, apos, N2Policy::ProximityGate::CombatPlayerRange(), 0.0f, 0.0f, 24, 0, anchor);
        haveNear = true;
      } catch (...) { haveNear = false; }
      for (size_t i = 0; i < pending.size(); ++i) {
        float best = 1e9f;
        if (pending[i].actor == anchorSerial || pending[i].target == anchorSerial) best = 0.0f;
        for (uint32_t k = 0; haveNear && k < nearList.size(); ++k) {
          Character* c = (Character*)nearList.stuff[k];
          if (!Ok(c)) continue;
          unsigned s = SerialOf(c);
          if (!s || (s != pending[i].actor && s != pending[i].target)) continue;
          try {
            float d = apos.distance(c->getPosition());
            if (d < best) best = d;
          } catch (...) {}
        }
        g_gate.NoteCombatStart(now, best);
      }
    }

    // Companion scan: every other squad member, distance to the anchor.
    std::vector<Cand> able;
    for (uint32_t i = 0; i < n && i < 32; ++i) {
      Character* c = world->player->playerCharacters[i];
      if (!Ok(c) || c == anchor) continue;
      unsigned s = SerialOf(c);
      if (!s) continue;
      float d = 1e9f;
      try { d = apos.distance(c->getPosition()); } catch (...) { continue; }
      if (!Stobe::NativeAttention::IsFree(c)) continue;
      Cand k; k.c = c; k.dist = d;
      able.push_back(k);
      bool idle = Stobe::NativeAttention::IsIdle(c);
      if (g_gate.OnScan(s, now, idle, d, g_proximityRadius)) {
        Fire(world, c, anchor, "proximity", d);
        return; // one turn per scan
      }
    }

    if (g_gate.TakeCombatDue(now)) {
      Character* best = NULL;
      float bestD = N2Policy::ProximityGate::CombatCompanionRange();
      for (size_t i = 0; i < able.size(); ++i)
        if (able[i].dist <= bestD) { bestD = able[i].dist; best = able[i].c; }
      if (best && g_gate.TryFire(SerialOf(best), now)) Fire(world, best, anchor, "combat_start", bestD);
    }
  } catch (...) {
    Log("N2_PROXIMITY: scan exception");
  }
}
} }
