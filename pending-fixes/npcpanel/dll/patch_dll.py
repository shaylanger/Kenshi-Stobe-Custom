#!/usr/bin/env python3
"""NPC info panel (Stobe.dll). Usage: patch_dll.py <STOBE-src root>
Compact read-only panel for the current conversation target: hotkey NpcInfoHotkey (default \\),
Info button in the chat window, follows the chat target, refreshes every 10 s while open,
HTTP on a worker thread, late/stale replies dropped by generation + key. Harness command
stobe_npcinfo <open <target> [speaker]|chat|read|refresh|close>. Idempotent; asserts anchors."""
import os, sys

root = sys.argv[1]
MARK = 'NPC info panel'


def patch(rel, edits):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8', newline='').read()
    if MARK in s:
        print('skip (already patched)', rel); return
    crlf = '\r\n' in s
    if crlf:
        s = s.replace('\r\n', '\n')
    for old, new, where in edits:
        if s.count(old) != 1:
            sys.exit('anchor not unique/missing in %s (%d): %r' % (rel, s.count(old), old[:90]))
        if where == 'before':
            s = s.replace(old, new + old)
        elif where == 'after':
            s = s.replace(old, old + new)
        else:
            s = s.replace(old, new)
    if crlf:
        s = s.replace('\n', '\r\n')
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print('patched', rel)


# ---------------------------------------------------------------- Globals / Utils (hotkey, game time)
patch('src/Globals.cpp', [
    ('std::string g_pushToTalkHotkeyStr = "V";\n',
     '// NPC info panel hotkey (ini NpcInfoHotkey, "-" = off)\nint g_npcInfoHotkey = VK_OEM_5; // \'\\\' by default\nstd::string g_npcInfoHotkeyStr = "\\\\";\n', 'after'),
])
patch('src/Globals.h', [
    ('extern std::string g_pushToTalkHotkeyStr;\n',
     'extern int g_npcInfoHotkey;        // NPC info panel\nextern std::string g_npcInfoHotkeyStr;\n', 'after'),
])
patch('src/Utils.h', [
    ('void SetPushToTalkHotkeyFromString(const std::string &keyStr);\n',
     'void SetNpcInfoHotkeyFromString(const std::string &keyStr); // NPC info panel\n'
     'int CurrentGameTsSeconds(); // game seconds now (same clock as event gamets), 0 if no world\n', 'after'),
])
patch('src/Utils.cpp', [
    ('static Character *FindCharacterBySerialForEvent(GameWorld *world,',
     '// NPC info panel: exported game clock (deal deadlines are stamped with it).\n'
     'int CurrentGameTsSeconds() { return ResolveCurrentGameTsForEvent(); }\n\n', 'before'),
    ('void LoadStobeRuntimeConfig() {',
     '// NPC info panel hotkey: \\\\ [ ] F1-F12, a letter or digit; "-" turns it off.\n'
     'void SetNpcInfoHotkeyFromString(const std::string &keyStr) {\n'
     '  std::string n = TrimCopy(keyStr);\n'
     '  for (size_t i = 0; i < n.size(); ++i)\n'
     '    if (n[i] >= \'a\' && n[i] <= \'z\')\n'
     '      n[i] = static_cast<char>(n[i] - (\'a\' - \'A\'));\n'
     '  int vk = -1;\n'
     '  if (n == "-")\n'
     '    vk = 0;\n'
     '  else if (n == "\\\\")\n'
     '    vk = VK_OEM_5;\n'
     '  else if (n == "[")\n'
     '    vk = VK_OEM_4;\n'
     '  else if (n == "]")\n'
     '    vk = VK_OEM_6;\n'
     '  else if (n.size() >= 2 && n.size() <= 3 && n[0] == \'F\') {\n'
     '    int f = atoi(n.c_str() + 1);\n'
     '    if (f >= 1 && f <= 12)\n'
     '      vk = VK_F1 + f - 1;\n'
     '  } else if (n.size() == 1 && ((n[0] >= \'A\' && n[0] <= \'Z\') || (n[0] >= \'0\' && n[0] <= \'9\')))\n'
     '    vk = n[0];\n'
     '  if (vk < 0) {\n'
     '    vk = VK_OEM_5;\n'
     '    n = "\\\\";\n'
     '  }\n'
     '  g_npcInfoHotkey = vk;\n'
     '  g_npcInfoHotkeyStr = n;\n'
     '}\n\n', 'before'),
    ('      baseIniPath, customIniPath, "Settings", "PushToTalkHotkey", "V"));\n',
     '  SetNpcInfoHotkeyFromString(ReadLayeredIniString(\n'
     '      baseIniPath, customIniPath, "Settings", "NpcInfoHotkey", "\\\\"));\n', 'after'),
    ('  WritePrivateProfileStringA("Settings", "PushToTalkHotkey",\n'
     '                             g_pushToTalkHotkeyStr.c_str(), iniPath.c_str());\n',
     '  WritePrivateProfileStringA("Settings", "NpcInfoHotkey", // NPC info panel\n'
     '                             g_npcInfoHotkeyStr.c_str(), iniPath.c_str());\n', 'after'),
])
patch('mod/Stobe.ini', [
    ('PushToTalkHotkey=V\n', '; NPC info panel hotkey (\\ [ ] F1-F12, letter/digit, - = off)\nNpcInfoHotkey=\\\n', 'after'),
])

# ---------------------------------------------------------------- live activity (game thread)
patch('src/AutonomySafetyProbe.h', [
    ('std::string DescribeCharacterAiStateJson(Character *character);\n',
     '\n// NPC info panel: short readable "what are they doing now" ("" if unreadable).\n'
     'std::string DescribeCharacterLiveActivity(Character *character);\n', 'after'),
])
patch('src/AutonomySafetyProbe.cpp', [
    ('void ResetAutonomySafetyProbe(const char *reason) {',
     '// NPC info panel: the observed state, never an order the NPC was only told about.\n'
     'std::string DescribeCharacterLiveActivity(Character *character) {\n'
     '  if (!IsValidCharacterPointer(character)) {\n'
     '    return "";\n'
     '  }\n'
     '  AiSnapshot s = CaptureSnapshot(character);\n'
     '  if (s.dead) {\n'
     '    return "Dead";\n'
     '  }\n'
     '  if (s.unconscious) {\n'
     '    return "Unconscious";\n'
     '  }\n'
     '  const bool moving = s.hasMovement && !s.movementIdle;\n'
     '  std::string goal;\n'
     '  if (s.currentGoalKey != (int)NULL_TASK && s.currentGoal != "unavailable") {\n'
     '    goal = s.currentGoal;\n'
     '    for (size_t i = 0; i < goal.size(); ++i) {\n'
     '      goal[i] = goal[i] == \'_\' ? \' \' : static_cast<char>(tolower((unsigned char)goal[i]));\n'
     '    }\n'
     '    if (!goal.empty()) {\n'
     '      goal[0] = static_cast<char>(toupper((unsigned char)goal[0]));\n'
     '    }\n'
     '  }\n'
     '  if (goal.empty()) {\n'
     '    return moving ? "Walking" : "Standing still";\n'
     '  }\n'
     '  return goal + (moving ? " (on the move)" : "");\n'
     '}\n\n', 'before'),
])

# ---------------------------------------------------------------- UI window
patch('src/AiNpcInfoWindow.h', [
    ('void OnAiNpcInfoNPCSelect(MyGUI::ListBox *sender, size_t index);\n',
     '// NPC info panel: compact read-only view of the conversation target.\n'
     'extern bool g_npcPanelOpenRequest;    // chat window Info button -> game thread\n'
     'extern bool g_npcPanelRefreshRequest; // panel Refresh button -> game thread\n'
     'bool IsNpcPanelOpen();\n'
     'void RequestNpcPanel(const std::string &key, const std::string &title,\n'
     '                     const std::string &json, bool showLoading);\n'
     'void SetNpcPanelText(const std::string &data);\n'
     'void CloseNpcPanelUI();\n'
     'std::string NpcPanelKey();\n'
     'std::string NpcPanelText();\n'
     'int NpcPanelGeneration();\n\n', 'before'),
])
patch('src/AiNpcInfoWindow.cpp', [
    ('void CloseAiDiaryUI(bool destroyWindow) {',
     r'''// ---------------------------------------------------------------- NPC info panel
// Compact, read-only view of one NPC as the speaking squad character knows them
// (ai_npcs.php action player_view: no LLM call). Requests run on a worker thread;
// a reply is shown only if it carries the newest generation and the key
// ("<target serial>|<speaker>") still on screen, so a late answer for an older
// target never overwrites the current one.
MyGUI::Window *g_npcPanelWindow = nullptr;
MyGUI::ListBox *g_npcPanelText = nullptr;
volatile LONG g_npcPanelGeneration = 0;
std::string g_npcPanelKey;
std::string g_npcPanelLastText;
bool g_npcPanelOpenRequest = false;
bool g_npcPanelRefreshRequest = false;

namespace {
struct NpcPanelTask {
  std::string json;
  std::string key;
  LONG generation;
};

DWORD WINAPI NpcPanelThread(LPVOID lpParam) {
  NpcPanelTask *task = static_cast<NpcPanelTask *>(lpParam);
  std::string response =
      PostToStobeWithResponse(L"/ai_npcs/player_view", task->json);
  std::string content = JsonReadField(response, "text");
  if (content.empty()) {
    std::string error = JsonReadField(response, "error");
    content = response.empty() ? "Unable to reach the Stobe server."
                               : (error.empty() ? "The server returned an unreadable answer."
                                                : error);
  }
  QueueUiCommand("SET_NPCPANEL_TEXT", ToString((int)task->generation) + "\n" +
                                          task->key + "\n" + content);
  delete task;
  return 0;
}

void OnNpcPanelCloseClick(MyGUI::Widget *sender) { CloseNpcPanelUI(); }
void OnNpcPanelRefreshClick(MyGUI::Widget *sender) {
  g_npcPanelRefreshRequest = true;
}
void OnNpcPanelWindowButtonPressed(MyGUI::Window *sender,
                                   const std::string &name) {
  if (name == "close") {
    CloseNpcPanelUI();
  }
}

void EnsureNpcPanelWindow() {
  if (g_npcPanelWindow) {
    return;
  }
  MyGUI::Gui *gui = MyGUI::Gui::getInstancePtr();
  if (!gui) {
    return;
  }
  g_npcPanelWindow = gui->createWidgetReal<MyGUI::Window>(
      "Kenshi_WindowCX", 0.68f, 0.10f, 0.30f, 0.62f, MyGUI::Align::Default,
      "Popup", "Stobe_NpcPanelWindow");
  if (!g_npcPanelWindow) {
    return;
  }
  g_npcPanelWindow->setCaption(WideFromUtf8(T("NPC Info")).c_str());
  g_npcPanelWindow->eventWindowButtonPressed +=
      MyGUI::newDelegate(OnNpcPanelWindowButtonPressed);
  MyGUI::Widget *client = g_npcPanelWindow->getClientWidget();
  if (!client) {
    return;
  }
  g_npcPanelText = client->createWidgetReal<MyGUI::ListBox>(
      "Kenshi_ListBox", 0.03f, 0.02f, 0.94f, 0.84f, MyGUI::Align::Stretch,
      "Stobe_NpcPanelText");
  MyGUI::Button *refresh = client->createWidgetReal<MyGUI::Button>(
      "Kenshi_Button1", 0.03f, 0.88f, 0.34f, 0.09f,
      MyGUI::Align::Bottom | MyGUI::Align::Left, "Stobe_NpcPanelRefreshBtn");
  refresh->setCaption(WideFromUtf8(T("Refresh")).c_str());
  refresh->eventMouseButtonClick += MyGUI::newDelegate(OnNpcPanelRefreshClick);
  MyGUI::Button *close = client->createWidgetReal<MyGUI::Button>(
      "Kenshi_Button1", 0.63f, 0.88f, 0.34f, 0.09f,
      MyGUI::Align::Bottom | MyGUI::Align::Right, "Stobe_NpcPanelCloseBtn");
  close->setCaption(WideFromUtf8(T("Close")).c_str());
  close->eventMouseButtonClick += MyGUI::newDelegate(OnNpcPanelCloseClick);
}
} // namespace

bool IsNpcPanelOpen() { return g_npcPanelWindow != nullptr; }
std::string NpcPanelKey() { return g_npcPanelKey; }
std::string NpcPanelText() { return g_npcPanelLastText; }
int NpcPanelGeneration() { return (int)g_npcPanelGeneration; }

void RequestNpcPanel(const std::string &key, const std::string &title,
                     const std::string &json, bool showLoading) {
  EnsureNpcPanelWindow();
  if (!g_npcPanelWindow || !g_npcPanelText) {
    Log("NPC_PANEL_WARN: window could not be created");
    return;
  }
  const bool targetChanged = key != g_npcPanelKey;
  g_npcPanelKey = key;
  LONG generation = InterlockedIncrement(&g_npcPanelGeneration);
  if (targetChanged || showLoading) {
    g_npcPanelWindow->setCaption(WideFromUtf8(T("NPC Info") + ": " + title).c_str());
    g_npcPanelLastText.clear();
    SetReadOnlyText(g_npcPanelText, T("Loading what you know about ") + title + "...");
  }
  NpcPanelTask *task = new NpcPanelTask();
  task->json = json;
  task->key = key;
  task->generation = generation;
  StartUiWorker(NpcPanelThread, task, "NPC panel");
}

void SetNpcPanelText(const std::string &data) {
  size_t a = data.find('\n');
  size_t b = a == std::string::npos ? std::string::npos : data.find('\n', a + 1);
  if (b == std::string::npos) {
    return;
  }
  int generation = atoi(data.substr(0, a).c_str());
  std::string key = data.substr(a + 1, b - a - 1);
  if (!g_npcPanelWindow || generation != (int)g_npcPanelGeneration ||
      key != g_npcPanelKey) {
    Log("NPC_PANEL: dropped stale reply gen=" + ToString(generation) +
        " key=" + key + " current_gen=" + ToString((int)g_npcPanelGeneration) +
        " current_key=" + g_npcPanelKey);
    return;
  }
  std::string text = SanitizeUiText(data.substr(b + 1));
  if (text == g_npcPanelLastText) {
    return; // periodic refresh, nothing changed: keep the scroll position
  }
  g_npcPanelLastText = text;
  SetReadOnlyText(g_npcPanelText, text);
  Log("NPC_PANEL: shown key=" + key + " gen=" + ToString(generation) +
      " chars=" + ToString((int)text.size()));
}

void CloseNpcPanelUI() {
  if (g_npcPanelWindow && !TryDestroyWidgetSafe(g_npcPanelWindow)) {
    Log("UI_WARN: CloseNpcPanelUI destroyWidget failed; clearing stale pointer.");
  }
  const bool wasOpen = g_npcPanelWindow != nullptr;
  g_npcPanelWindow = nullptr;
  g_npcPanelText = nullptr;
  g_npcPanelKey.clear();
  g_npcPanelLastText.clear();
  g_npcPanelRefreshRequest = false;
  InterlockedIncrement(&g_npcPanelGeneration); // replies in flight are dropped
  if (wasOpen) {
    Log("NPC_PANEL: closed");
  }
}

''', 'before'),
])

# ---------------------------------------------------------------- chat window Info button
patch('src/ChatBox.cpp', [
    ('void CreateChatUI(const std::string &npcName, const std::string &playerName,',
     '// NPC info panel: the game thread opens it for the current chat target.\n'
     'extern bool g_npcPanelOpenRequest; // AiNpcInfoWindow.cpp\n'
     'static void OnChatNpcInfoClick(MyGUI::Widget *sender) {\n'
     '  g_npcPanelOpenRequest = true;\n'
     '}\n\n', 'before'),
    ('      "Kenshi_Button1", primaryRenameX, primaryRowY, primaryBtnW, rowH,\n'
     '      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_ChatRenameBtn");\n',
     '      "Kenshi_Button1", primaryRenameX, primaryRowY, (primaryBtnW - primaryRowGap) / 2.0f, rowH,\n'
     '      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_ChatRenameBtn");\n', 'replace'),
    ('  renameBtn->eventMouseButtonClick += MyGUI::newDelegate(OnRenameClick);\n',
     '\n  // NPC info panel: Rename and Info share the third primary slot.\n'
     '  MyGUI::Button *npcInfoBtn = client->createWidgetReal<MyGUI::Button>(\n'
     '      "Kenshi_Button1", primaryRenameX + (primaryBtnW + primaryRowGap) / 2.0f,\n'
     '      primaryRowY, (primaryBtnW - primaryRowGap) / 2.0f, rowH,\n'
     '      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_ChatNpcInfoBtn");\n'
     '  npcInfoBtn->setCaption(WideFromUtf8(T("Info")).c_str());\n'
     '  npcInfoBtn->eventMouseButtonClick += MyGUI::newDelegate(OnChatNpcInfoClick);\n', 'after'),
])

# ---------------------------------------------------------------- endpoint route
patch('src/Comm.cpp', [
    ('  if (endpoint == L"/ai_npcs/list" || endpoint == L"/ai_npcs/detail") {\n',
     '  if (endpoint == L"/ai_npcs/list" || endpoint == L"/ai_npcs/detail" ||\n'
     '      endpoint == L"/ai_npcs/player_view") { // NPC info panel\n', 'replace'),
])

# ---------------------------------------------------------------- harness command
patch('src/StobeHarnessBridge.cpp', [
    ('    {"shopprice", "stobe_shopprice <trader> [player]"},\n',
     '    {"npcinfo", "stobe_npcinfo <open <target> [speaker]|chat|read|refresh|close>"}, // NPC info panel\n', 'after'),
    ('std::string(registered == 7 ? "7 commands" : "SOME COMMANDS REFUSED") +\n'
     '      " (stobe_ping/mode/say/state/give_cats/give_item/shopprice)");',
     'std::string(registered == 8 ? "8 commands" : "SOME COMMANDS REFUSED") +\n'
     '      " (stobe_ping/mode/say/state/give_cats/give_item/shopprice/npcinfo)");', 'replace'),
])

# ---------------------------------------------------------------- main.cpp: game thread
patch('src/main.cpp', [
    ('          } else if (command == "SET_AINPCINFO_TEXT") {\n',
     '          } else if (command == "SET_NPCPANEL_TEXT") { // NPC info panel\n'
     '            Stobe::UI::SetNpcPanelText(data);\n', 'before'),
    ('static std::string RunTestInboxCommand(GameWorld *world, Character *sel,',
     r'''// ---------------------------------------------------------------- NPC info panel
// Game-thread side: who the panel is about and who is asking. Live fields (what the
// NPC is doing, faction, trader) are read here and sent with the request; the server
// adds stored deals/goals/relationship/learned facts. No LLM call.
static unsigned int g_npcPanelTargetSerial = 0;
static std::string g_npcPanelTargetName;
static unsigned int g_npcPanelSpeakerSerial = 0;
static std::string g_npcPanelSpeakerName;
static DWORD g_npcPanelLastRequestTick = 0;
static const DWORD kNpcPanelRefreshMs = 10000;

static void NpcPanelSend(GameWorld *world, const char *why, bool showLoading) {
  if (g_npcPanelTargetSerial == 0) {
    return;
  }
  Character *target = FindCharacterBySerial(world, g_npcPanelTargetSerial);
  std::string activity, faction;
  bool trader = false;
  if (target) {
    activity = DescribeCharacterLiveActivity(target);
    try {
      faction = SafeFactionName(target->getFaction());
    } catch (...) {
    }
    try {
      trader = !target->isPlayerCharacter() && target->isATrader();
    } catch (...) {
    }
    try {
      std::string liveName = target->getName();
      if (!liveName.empty())
        g_npcPanelTargetName = liveName; // renamed NPCs follow their new name
    } catch (...) {
    }
  }
  const std::string serial = ToString(g_npcPanelTargetSerial);
  const std::string key = serial + "|" + g_npcPanelSpeakerName;
  std::string json = "{\"action\":\"player_view\",\"storage_id\":\"hand_" + serial +
                     "\",\"serial\":" + serial + ",\"name\":\"" +
                     EscapeJSON(g_npcPanelTargetName) + "\",\"speaker\":\"" +
                     EscapeJSON(g_npcPanelSpeakerName) + "\",\"gamets\":" +
                     ToString(CurrentGameTsSeconds()) + ",\"live_activity\":\"" +
                     EscapeJSON(target ? activity : std::string("")) +
                     "\",\"live_faction\":\"" + EscapeJSON(faction) +
                     "\",\"trader\":" + (trader ? "true" : "false") +
                     ",\"key\":\"" + EscapeJSON(key) + "\"}";
  g_npcPanelLastRequestTick = GetTickCount();
  if (showLoading)
    Log(std::string("NPC_PANEL: request why=") + why + " target=" +
        g_npcPanelTargetName + " serial=" + serial + " speaker=" +
        g_npcPanelSpeakerName + " visible=" + (target ? "1" : "0"));
  Stobe::UI::RequestNpcPanel(key, g_npcPanelTargetName, json, showLoading);
}

static bool NpcPanelOpenFor(GameWorld *world, Character *speaker, Character *target,
                            const char *why) {
  if (!target || (uintptr_t)target <= 0x1000 || target == speaker)
    return false;
  try {
    g_npcPanelTargetSerial = target->getHandle().serial;
    g_npcPanelTargetName = target->getName();
    g_npcPanelSpeakerSerial = 0;
    g_npcPanelSpeakerName.clear();
    if (speaker && (uintptr_t)speaker > 0x1000) {
      g_npcPanelSpeakerSerial = speaker->getHandle().serial;
      g_npcPanelSpeakerName = speaker->getName();
    }
  } catch (...) {
    return false;
  }
  NpcPanelSend(world, why, true);
  return true;
}

// Same pick as the chat hotkey: a selected squad member talks to the nearest NPC,
// a selected NPC is talked to by the nearest squad member.
static bool NpcPanelOpenForSelection(GameWorld *world, Character *sel, const char *why) {
  if (!sel || (uintptr_t)sel <= 0x1000)
    return false;
  Character *speaker = nullptr;
  Character *target = nullptr;
  try {
    if (sel->isPlayerCharacter()) {
      speaker = sel;
      target = ResolveNearestNpcTargetForSelection(world, sel);
    } else {
      target = sel;
      speaker = ResolveNearestPlayerSpeakerForTarget(world, sel);
    }
  } catch (...) {
    return false;
  }
  return NpcPanelOpenFor(world, speaker, target, why);
}

// The chat window's current target and speaking character, if a chat is open.
static bool NpcPanelChatPair(GameWorld *world, Character *sel, Character *&speaker,
                             Character *&target) {
  speaker = nullptr;
  target = nullptr;
  if (!Stobe::UI::g_chatWindow)
    return false;
  unsigned int serial = (unsigned int)strtoul(Stobe::UI::g_chatTargetHandleStr.c_str(), nullptr, 10);
  if (serial == 0)
    return false;
  target = FindCharacterBySerial(world, serial);
  if (!Stobe::UI::g_chatPlayerNameStr.empty())
    speaker = ResolveTestInboxTarget(world, sel, nullptr, Stobe::UI::g_chatPlayerNameStr);
  return target != nullptr;
}

// Per tick: chat Info button, follow the chat target, Refresh button, periodic refresh.
static void NpcPanelTick(GameWorld *world, Character *sel) {
  if (Stobe::UI::g_npcPanelOpenRequest) {
    Stobe::UI::g_npcPanelOpenRequest = false;
    Character *speaker = nullptr, *target = nullptr;
    if (NpcPanelChatPair(world, sel, speaker, target))
      NpcPanelOpenFor(world, speaker, target, "chat_info_button");
    else if (!NpcPanelOpenForSelection(world, sel, "chat_info_button_selection"))
      Log("NPC_PANEL: Info pressed but no conversation target");
  }
  if (!Stobe::UI::IsNpcPanelOpen())
    return;
  Character *speaker = nullptr, *target = nullptr;
  if (NpcPanelChatPair(world, sel, speaker, target)) {
    std::string speakerName;
    try {
      speakerName = speaker ? speaker->getName() : std::string("");
    } catch (...) {
    }
    if (target->getHandle().serial != g_npcPanelTargetSerial ||
        (!speakerName.empty() && speakerName != g_npcPanelSpeakerName)) {
      NpcPanelOpenFor(world, speaker, target, "chat_target_changed");
      return;
    }
  }
  if (Stobe::UI::g_npcPanelRefreshRequest) {
    Stobe::UI::g_npcPanelRefreshRequest = false;
    NpcPanelSend(world, "refresh_button", true);
    return;
  }
  if (GetTickCount() - g_npcPanelLastRequestTick >= kNpcPanelRefreshMs)
    NpcPanelSend(world, "periodic", false);
}

static std::string NpcPanelOneLine(const std::string &text) {
  std::string out;
  for (size_t i = 0; i < text.size(); ++i) {
    char c = text[i];
    if (c == '\r')
      continue;
    if (c == '\n')
      out += " | ";
    else
      out += c;
  }
  return out;
}

''', 'before'),
    ('  if (cmd == "shopprice") {',
     r'''  if (cmd == "npcinfo") { // NPC info panel: drive and read the panel like a player would
    std::string sub = f.size() >= 3 ? f[2] : "";
    if (sub == "open") {
      if (f.size() < 4)
        return "usage: npcinfo open <target> [speaker]";
      Character *target = ResolveTestInboxTarget(world, sel, speaker, f[3]);
      if (!target)
        return "target not found: " + f[3];
      Character *asker = speaker;
      if (f.size() >= 5 && !f[4].empty()) {
        asker = ResolveTestInboxTarget(world, sel, speaker, f[4]);
        if (!asker)
          return "speaker not found: " + f[4];
      }
      if (!NpcPanelOpenFor(world, asker, target, "test_open"))
        return "cannot open the panel for " + f[3];
      ok = true;
      return "open key=" + Stobe::UI::NpcPanelKey() +
             " gen=" + ToString(Stobe::UI::NpcPanelGeneration());
    }
    if (sub == "chat") { // same path as the chat window's Info button
      Stobe::UI::g_npcPanelOpenRequest = true;
      ok = true;
      return "queued";
    }
    if (sub == "refresh") {
      if (!Stobe::UI::IsNpcPanelOpen())
        return "panel not open";
      Stobe::UI::g_npcPanelRefreshRequest = true;
      ok = true;
      return "queued";
    }
    if (sub == "close") {
      Stobe::UI::CloseNpcPanelUI();
      ok = true;
      return "closed";
    }
    if (sub == "read") {
      ok = true;
      if (!Stobe::UI::IsNpcPanelOpen())
        return "open=0";
      std::string text = Stobe::UI::NpcPanelText();
      return "open=1 key=" + Stobe::UI::NpcPanelKey() +
             " gen=" + ToString(Stobe::UI::NpcPanelGeneration()) +
             " loaded=" + (text.empty() ? std::string("0") : std::string("1")) +
             " text=" + NpcPanelOneLine(text);
    }
    return "usage: npcinfo <open <target> [speaker]|chat|read|refresh|close>";
  }
''', 'before'),
    ('  // Rename checks are now queued only for dialogue-tagged NPCs.\n',
     r'''  // NPC info panel: hotkey toggles it for the current conversation pair (not while
  // typing in a text box); the panel follows the chat target and refreshes itself.
  if (StobeHotkeyDown(g_npcInfoHotkey) &&
      !MyGUI::InputManager::getInstance().isFocusKey()) {
    static DWORD lastNpcPanelTick = 0;
    if (GetTickCount() - lastNpcPanelTick > 500) {
      lastNpcPanelTick = GetTickCount();
      if (Stobe::UI::IsNpcPanelOpen()) {
        Stobe::UI::CloseNpcPanelUI();
      } else {
        Character *chatSpeaker = nullptr, *chatTarget = nullptr;
        if (NpcPanelChatPair(world, sel, chatSpeaker, chatTarget))
          NpcPanelOpenFor(world, chatSpeaker, chatTarget, "hotkey_chat");
        else if (!NpcPanelOpenForSelection(world, sel, "hotkey"))
          Log("NPC_PANEL: hotkey pressed but no conversation target");
      }
    }
  }
  NpcPanelTick(world, sel);

''', 'before'),
])
