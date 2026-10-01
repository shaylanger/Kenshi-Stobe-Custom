#!/usr/bin/env python3
"""Adds the test inbox to Stobe.dll (DLL source tree, not StobeServer).

Tooling can submit chat lines as if the player had spoken them, and read back
the target NPC's state. Active only while mods\\Stobe\\test_inbox.flag exists.

Usage: patch_test_inbox.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:60]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


# --- AutonomySafetyProbe: public AI state dump ------------------------------
patch("src/AutonomySafetyProbe.h",
      "void ResetAutonomySafetyProbe(const char *reason);",
      """void ResetAutonomySafetyProbe(const char *reason);

// One-line JSON of the character's AI/order/movement state (test inbox).
std::string DescribeCharacterAiStateJson(Character *character);

// mods\Stobe folder next to the executable (same as the config dir).
std::string GetTestInboxDir();""")

patch("src/AutonomySafetyProbe.h", "#pragma once\n", "#pragma once\n\n#include <string>\n")

patch("src/AutonomySafetyProbe.cpp",
      "} // namespace\n\nvoid ResetAutonomySafetyProbe(const char *reason) {",
      r'''} // namespace

std::string GetTestInboxDir() { return GetExecutableDir() + "\\mods\\Stobe"; }

std::string DescribeCharacterAiStateJson(Character *character) {
  if (!IsValidCharacterPointer(character)) {
    return "{}";
  }
  AiSnapshot s = CaptureSnapshot(character);
  std::string json = "{";
  json += "\"dead\":" + std::string(s.dead ? "true" : "false");
  json += ",\"unconscious\":" + std::string(s.unconscious ? "true" : "false");
  json += ",\"can_take_orders\":" + std::string(s.canTakeOrders ? "true" : "false");
  json += ",\"has_orders\":" + std::string(s.hasOrders ? "true" : "false");
  json += ",\"has_player_orders\":" + std::string(s.hasPlayerOrders ? "true" : "false");
  json += ",\"jobs_enabled\":" + std::string(s.jobsEnabled ? "true" : "false");
  json += ",\"first_order\":\"" + EscapeJSON(s.firstOrder) + "\"";
  json += ",\"current_goal\":\"" + EscapeJSON(s.currentGoal) + "\"";
  json += ",\"permajobs\":" + (s.permajobs.empty() ? std::string("[]") : s.permajobs);
  json += ",\"position\":[" + ToString(s.position.x) + "," + ToString(s.position.y) +
          "," + ToString(s.position.z) + "]";
  json += ",\"moving\":" + std::string(s.hasMovement && !s.movementIdle ? "true" : "false");
  json += ",\"destination_reached\":" +
          std::string(s.destinationReached ? "true" : "false");
  json += ",\"path_failed\":" + std::string(s.pathFailed ? "true" : "false");
  json += ",\"destination\":[" + ToString(s.destination.x) + "," +
          ToString(s.destination.y) + "," + ToString(s.destination.z) + "]";
  json += "}";
  return json;
}

void ResetAutonomySafetyProbe(const char *reason) {''')

# --- main.cpp: inbox polling on the player update tick ----------------------
INBOX = r'''// Test inbox: lets tooling submit chat lines as if the player had spoken them.
// Active only while mods\Stobe\test_inbox.flag exists. Tooling writes
// test_inbox.txt (one command per line: id<TAB>command<TAB>args...), the DLL
// consumes and deletes it, and appends id<TAB>ok|error<TAB>detail lines to
// test_outbox.txt.
static std::string TestInboxLower(const std::string &value) {
  std::string out = value;
  for (size_t i = 0; i < out.size(); ++i)
    out[i] = (char)tolower((unsigned char)out[i]);
  return out;
}

static std::string TestInboxOneLine(const std::string &value) {
  std::string out = value;
  for (size_t i = 0; i < out.size(); ++i)
    if (out[i] == '\r' || out[i] == '\n' || out[i] == '\t')
      out[i] = ' ';
  return out;
}

static Character *ResolveTestInboxSpeaker(GameWorld *world, Character *sel) {
  if (sel && (uintptr_t)sel > 0x1000) {
    try {
      if (sel->isPlayerCharacter())
        return sel;
    } catch (...) {
    }
  }
  if (world && world->player && world->player->playerCharacters.size() > 0)
    return world->player->playerCharacters[0];
  return nullptr;
}

// "@nearest", "@selected", or a character name (nearest match to speaker).
static Character *ResolveTestInboxTarget(GameWorld *world, Character *sel,
                                         Character *speaker,
                                         const std::string &name) {
  if (!world)
    return nullptr;
  if (name == "@nearest")
    return speaker ? ResolveNearestNpcTargetForSelection(world, speaker) : nullptr;
  if (name == "@selected")
    return (sel && (uintptr_t)sel > 0x1000) ? sel : nullptr;
  std::string wanted = TestInboxLower(name);
  Ogre::Vector3 origin(0, 0, 0);
  bool haveOrigin = false;
  if (speaker) {
    try {
      origin = speaker->getPosition();
      haveOrigin = true;
    } catch (...) {
    }
  }
  Character *best = nullptr;
  float bestDist = 0.0f;
  const ogre_unordered_set<Character *>::type &chars =
      world->getCharacterUpdateList();
  for (auto it = chars.begin(); it != chars.end(); ++it) {
    Character *candidate = *it;
    if (!candidate || (uintptr_t)candidate <= 0x1000)
      continue;
    std::string candidateName;
    try {
      candidateName = candidate->getName();
    } catch (...) {
      continue;
    }
    if (TestInboxLower(candidateName) != wanted)
      continue;
    float dist = 0.0f;
    if (haveOrigin) {
      try {
        dist = candidate->getPosition().distance(origin);
      } catch (...) {
      }
    }
    if (!best || dist < bestDist) {
      best = candidate;
      bestDist = dist;
    }
  }
  return best;
}

static std::string RunTestInboxCommand(GameWorld *world, Character *sel,
                                       const std::vector<std::string> &f,
                                       bool &ok) {
  ok = false;
  const std::string &cmd = f[1];
  Character *speaker = ResolveTestInboxSpeaker(world, sel);
  if (cmd == "ping") {
    Character *nearest =
        speaker ? ResolveNearestNpcTargetForSelection(world, speaker) : nullptr;
    ok = true;
    std::string detail = "mode=" + Stobe::ChatMode::Normalize(g_chatMode);
    try {
      detail += " speaker=" + (speaker ? speaker->getName() : std::string("none"));
      detail += " nearest=" + (nearest ? nearest->getName() : std::string("none"));
    } catch (...) {
    }
    return detail;
  }
  if (cmd == "mode") {
    if (f.size() < 3)
      return "usage: mode <mode>";
    g_chatMode = Stobe::ChatMode::Normalize(f[2]);
    g_lastChatModeIndex = Stobe::ChatMode::ToIndex(g_chatMode);
    ok = true;
    return "mode=" + g_chatMode;
  }
  if (cmd == "say") {
    if (f.size() < 4 || f[3].empty())
      return "usage: say <target> <text>";
    if (!speaker)
      return "no player character to speak as";
    if (!Stobe::Interaction::ManualInputAllowed())
      return "manual input not allowed right now";
    std::string mode = Stobe::ChatMode::Normalize(g_chatMode);
    bool narratorMode = (mode == "narrator");
    Character *target = narratorMode
                            ? nullptr
                            : ResolveTestInboxTarget(world, sel, speaker, f[2]);
    if (!narratorMode && !target)
      return "target not found: " + f[2];
    std::string speakerName, speakerSerial, targetName, targetSerial;
    try {
      speakerName = speaker->getName();
      speakerSerial = ToString(speaker->getHandle().serial);
      if (narratorMode) {
        targetName = GetNarratorDisplayName();
      } else {
        targetName = target->getName();
        targetSerial = ToString(target->getHandle().serial);
      }
    } catch (...) {
      return "could not read speaker/target";
    }
    if (narratorMode) {
      g_talkTargetHand = hand();
    } else {
      g_talkTargetHand = target->getHandle();
      SyncInventoryForCharacter(target, true, "test_inbox");
    }
    InterruptTtsPlayback();
    Log("TEST_INBOX: say id=" + f[0] + " mode=" + mode + " speaker=" +
        speakerName + " target=" + targetName + " text=" + f[3]);
    SubmitVoiceChatText(f[3], speakerName, speakerSerial, targetName,
                        targetSerial, mode);
    ok = true;
    return "target=" + targetName + " serial=" + targetSerial + " mode=" + mode;
  }
  if (cmd == "state") {
    if (f.size() < 3)
      return "usage: state <target>";
    Character *target = ResolveTestInboxTarget(world, sel, speaker, f[2]);
    if (!target)
      return "target not found: " + f[2];
    std::string inventoryJson, inventoryHash;
    int itemCount = 0;
    BuildInventorySnapshot(target, inventoryJson, inventoryHash, itemCount);
    int playerCats = 0;
    float distance = -1.0f;
    std::string name, faction;
    unsigned int serial = 0;
    try {
      name = target->getName();
      serial = target->getHandle().serial;
      faction = SafeFactionName(target->getFaction());
      if (speaker) {
        distance = target->getPosition().distance(speaker->getPosition());
        playerCats = speaker->getMoney();
        if (playerCats <= 0 && speaker->getOwnerships())
          playerCats = speaker->getOwnerships()->getMoney();
      }
    } catch (...) {
    }
    std::string json = "{\"name\":\"" + EscapeJSON(name) + "\"";
    json += ",\"serial\":" + ToString(serial);
    json += ",\"faction\":\"" + EscapeJSON(faction) + "\"";
    json += ",\"distance_to_player\":" + ToString(distance);
    json += ",\"player_cats\":" + ToString(playerCats);
    json += ",\"ai\":" + DescribeCharacterAiStateJson(target);
    json += ",\"inventory\":" + inventoryJson + "}";
    ok = true;
    return json;
  }
  return "unknown command: " + cmd;
}

static void UpdateTestInbox(GameWorld *world, Character *sel) {
  static DWORD lastPoll = 0;
  DWORD now = GetTickCount();
  if (now - lastPoll < 500)
    return;
  lastPoll = now;
  const std::string dir = GetTestInboxDir();
  if (GetFileAttributesA((dir + "\\test_inbox.flag").c_str()) ==
      INVALID_FILE_ATTRIBUTES)
    return;
  const std::string inboxPath = dir + "\\test_inbox.txt";
  std::vector<std::string> lines;
  {
    std::ifstream in(inboxPath.c_str());
    if (!in)
      return;
    std::string line;
    while (std::getline(in, line)) {
      if (!line.empty() && line[line.size() - 1] == '\r')
        line.erase(line.size() - 1);
      if (!line.empty())
        lines.push_back(line);
    }
  }
  DeleteFileA(inboxPath.c_str());
  std::ofstream out((dir + "\\test_outbox.txt").c_str(), std::ios::app);
  for (size_t i = 0; i < lines.size(); ++i) {
    std::vector<std::string> fields;
    size_t start = 0;
    while (true) {
      size_t tab = lines[i].find('\t', start);
      fields.push_back(lines[i].substr(start, tab == std::string::npos
                                                  ? std::string::npos
                                                  : tab - start));
      if (tab == std::string::npos)
        break;
      start = tab + 1;
    }
    bool ok = false;
    std::string detail;
    if (fields.size() < 2) {
      detail = "malformed line";
    } else {
      try {
        detail = RunTestInboxCommand(world, sel, fields, ok);
      } catch (...) {
        detail = "exception";
      }
    }
    out << fields[0] << "\t" << (ok ? "ok" : "error") << "\t"
        << TestInboxOneLine(detail) << "\n";
    out.flush();
    if (!ok)
      Log("TEST_INBOX: error id=" + fields[0] + " " + detail);
  }
}

void Hook_PlayerUpdateTick(PlayerInterface *thisptr) {'''

patch("src/main.cpp", "void Hook_PlayerUpdateTick(PlayerInterface *thisptr) {", INBOX)

patch("src/main.cpp",
      "  pushToTalkWasDown = pushToTalkDown;\n  if (pushToTalkEnabled)\n    Stobe::Voice::Update();\n",
      "  pushToTalkWasDown = pushToTalkDown;\n  if (pushToTalkEnabled)\n    Stobe::Voice::Update();\n  UpdateTestInbox(worldUi, sel);\n")

print("patch_test_inbox: applied")
