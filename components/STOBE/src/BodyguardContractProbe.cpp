#include "BodyguardContractProbe.h"
#include "NativeAiAwareness.h"
#include "Utils.h"
#include <kenshi/Character.h>
#include <kenshi/Dialogue.h>
#include <kenshi/GameWorld.h>
#include <kenshi/Platoon.h>
#include <kenshi/RootObject.h>
#include <kenshi/util/lektor.h>
#include <map>
#include <set>
#include <sstream>
#include <windows.h>

namespace Stobe { namespace BodyguardContractProbe { namespace {
bool g_enabled = false;
DWORD g_lastSample = 0;
std::map<uintptr_t, std::string> g_lastSquadState;
const char kRequiredSaveSha256[] =
    "98DAF7F0A0E3A8D3505EBE9DF059FE45E957D5154F86292FDA33D0BDF917F868";
std::string g_saveSha256;
std::string g_copyId;
unsigned long long g_eventId = 0;

unsigned long long UnixMillis() {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  ULARGE_INTEGER value;
  value.LowPart = ft.dwLowDateTime;
  value.HighPart = ft.dwHighDateTime;
  return (value.QuadPart - 116444736000000000ULL) / 10000ULL;
}

std::string Context(const char* event) {
  ++g_eventId;
  std::ostringstream out;
  out << "BODYGUARD_PROBE: event=" << event << " event_id=" << g_eventId
      << " unix_ms=" << UnixMillis() << " monotonic_ms=" << GetTickCount()
      << " save_sha256=" << g_saveSha256 << " copy_id=" << g_copyId;
  return out.str();
}

bool IsSha256(const std::string& value) {
  if (value.size() != 64) return false;
  for (size_t i = 0; i < value.size(); ++i) {
    const char c = value[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
          (c >= 'A' && c <= 'F'))) return false;
  }
  return true;
}

bool ParseStart(const std::string& action, std::string& saveSha,
                std::string& copyId) {
  const std::string prefix = "start:";
  if (action.compare(0, prefix.size(), prefix) != 0) return false;
  const size_t sep = action.find(':', prefix.size());
  if (sep == std::string::npos) return false;
  saveSha = action.substr(prefix.size(), sep - prefix.size());
  copyId = action.substr(sep + 1);
  if (!IsSha256(saveSha) || saveSha != kRequiredSaveSha256 ||
      copyId.empty() || copyId.size() > 48) return false;
  for (size_t i = 0; i < copyId.size(); ++i) {
    const char c = copyId[i];
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
  }
  return true;
}

std::string SquadPart(const std::string& json) {
  const std::string key = "\"squad\":";
  size_t at = json.find(key);
  if (at == std::string::npos) return "{\"observed\":false}";
  at += key.size();
  size_t end = json.rfind("}}");
  if (end == std::string::npos || end < at) return "{\"observed\":false}";
  return json.substr(at, end - at + 1);
}

std::string Roster(ActivePlatoon* active) {
  std::ostringstream out;
  out << "[";
  bool first = true;
  if (active) {
    lektor<RootObject*>* things = active->getThings();
    if (things && things->valid()) {
      for (uint32_t i = 0; i < things->size(); ++i) {
        Character* c = dynamic_cast<Character*>((*things)[i]);
        if (!c) continue;
        if (!first) out << ",";
        first = false;
        out << "{\"serial\":" << c->getHandle().serial
            << ",\"name\":\"" << EscapeJSON(c->getName()) << "\"}";
      }
    }
  }
  out << "]";
  return out.str();
}
} // namespace

std::string Command(const std::string& action) {
  std::string saveSha;
  std::string copyId;
  if (ParseStart(action, saveSha, copyId)) {
    g_lastSquadState.clear();
    g_lastSample = 0;
    g_eventId = 0;
    g_saveSha256 = saveSha;
    g_copyId = copyId;
    g_enabled = true;
    Log(Context("start") + " mode=read_only");
    return "started; read-only; sample interval=500ms; radius=250m";
  }
  if (action == "stop") {
    if (!g_enabled || g_saveSha256.empty() || g_copyId.empty()) {
      g_enabled = false;
      return "stopped; no active probe";
    }
    g_enabled = false;
    Log(Context("stop"));
    return "stopped";
  }
  if (action == "status") return g_enabled ?
      ("running save_sha256=" + g_saveSha256 + " copy_id=" + g_copyId) : "stopped";
  return "usage: bodyguard_probe start:<quick.save-sha256>:<copy-id>|stop|status";
}

void Reset() {
  if (g_enabled)
    Log(Context("world_load_boundary") + " baseline_cleared=1");
  g_lastSquadState.clear();
  g_lastSample = 0;
}

void RecordDialogueChoice(void* rawDialogue, const std::string& reply,
                          const char* sourceTag) {
  if (!g_enabled) return;
  Dialogue* dialogue = static_cast<Dialogue*>(rawDialogue);
  Character* owner = nullptr;
  try { owner = dialogue ? dialogue->getCharacter() : nullptr; } catch (...) {}
  std::string actor = "unknown";
  unsigned int serial = 0;
  try {
    if (owner) {
      actor = owner->getName();
      serial = owner->getHandle().serial;
    }
  } catch (...) {}
  Log(Context("dialogue_choice") + " npc=\"" + EscapeJSON(actor) +
      "\" npc_serial=" + ToString(serial) + " source=" +
      (sourceTag ? sourceTag : "unknown") + " reply=\"" +
      EscapeJSON(reply.substr(0, 240)) + "\"");
}

void Observe(GameWorld* world, Character* anchor) {
  if (!g_enabled || !world || !anchor) return;
  DWORD now = GetTickCount();
  if (g_lastSample && now - g_lastSample < 500) return;
  g_lastSample = now;

  lektor<RootObject*> nearby;
  try {
    world->getCharactersWithinSphere(nearby, anchor->getPosition(), 250.0f,
                                     0.0f, 0.0f, 256, 256, anchor);
  } catch (...) {
    Log(Context("sample_failed") + " reason=native_enumeration_exception");
    return;
  }
  std::set<uintptr_t> seen;
  for (uint32_t i = 0; i < nearby.size(); ++i) {
    Character* actor = dynamic_cast<Character*>(nearby[i]);
    if (!actor) continue;
    ActivePlatoon* active = nullptr;
    try { active = actor->getPlatoon(); } catch (...) { continue; }
    if (!active || !seen.insert(reinterpret_cast<uintptr_t>(active)).second) continue;
    std::string squad = SquadPart(NativeAiAwareness::CaptureJson(world, actor));
    std::map<uintptr_t, std::string>::iterator old =
        g_lastSquadState.find(reinterpret_cast<uintptr_t>(active));
    if (old == g_lastSquadState.end() || old->second != squad) {
      std::string squadId;
      std::string squadName;
      unsigned int serial = 0;
      double gameTs = 0.0;
      try {
        squadId = active->me ? active->me->getPlatoonStringID() : "";
        squadName = active->getName();
        serial = actor->getHandle().serial;
        gameTs = world->getTimeStamp_inGameHours().getTotalSeconds();
      } catch (...) {}
      Log(Context(old == g_lastSquadState.end() ? "baseline" : "transition") +
          " game_ts=" + ToString(static_cast<float>(gameTs)) +
          " squad_id=\"" + EscapeJSON(squadId) + "\" name=\"" +
          EscapeJSON(squadName) + "\" anchor_serial=" +
          ToString(anchor->getHandle().serial) + " anchor_name=\"" +
          EscapeJSON(anchor->getName()) + "\" observed_actor=" + ToString(serial) +
          " roster=" + Roster(active) + " state=" + squad);
      g_lastSquadState[reinterpret_cast<uintptr_t>(active)] = squad;
    }
  }
}
} }
