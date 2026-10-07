#include "AiNpcInfoWindow.h"
#include "Interaction.h"
#include "AudioPlayback.h"
#include "Comm.h"
#include "Globals.h"
#include "Utils.h"
#include <algorithm>
#include <cctype>
#include <mygui/MyGUI_Button.h>
#include <mygui/MyGUI_Delegate.h>
#include <mygui/MyGUI_EditBox.h>
#include <mygui/MyGUI_Gui.h>
#include <mygui/MyGUI_ImageBox.h>
#include <mygui/MyGUI_ListBox.h>
#include <mygui/MyGUI_TextBox.h>
#include <mygui/MyGUI_Window.h>
#include <string>
#include <vector>

namespace Stobe {
namespace UI {

MyGUI::Window *g_aiNpcInfoWindow = nullptr;
MyGUI::ListBox *g_aiNpcInfoList = nullptr;
MyGUI::ListBox *g_aiNpcInfoText = nullptr;
MyGUI::Button *g_aiNpcInfoCloseButton = nullptr;
std::vector<std::string> g_aiNpcInfoStorageIds;
MyGUI::Window *g_aiDiaryWindow = nullptr;
MyGUI::ListBox *g_aiDiaryList = nullptr;
MyGUI::ListBox *g_aiDiaryEntryList = nullptr;
MyGUI::ListBox *g_aiDiaryText = nullptr;
MyGUI::Button *g_aiDiaryAudioButton = nullptr;
MyGUI::Button *g_aiDiaryCloseButton = nullptr;
std::vector<std::string> g_aiDiaryKeys;
std::vector<std::string> g_aiDiaryEntryIds;

namespace {
MyGUI::EditBox *g_aiNpcSearch = nullptr;
std::vector<std::string> g_aiNpcAllDisplays;
std::vector<std::string> g_aiNpcAllStorageIds;
std::string g_aiNpcPendingKey;
std::string g_aiDiaryPendingPerson;
std::string g_aiDiaryPendingEntry;
LONG g_aiDiaryAudioGeneration = 1;
int g_aiDiaryAudioState = 0;

struct AiDiaryAudioTask {
  std::string entryId;
  LONG generation;
  LONG interactionEpoch;
};

LONG CurrentAiDiaryAudioGeneration() {
  return InterlockedCompareExchange(&g_aiDiaryAudioGeneration, 0, 0);
}

void CancelAiDiaryAudio(bool enableSelectedEntry) {
  InterlockedIncrement(&g_aiDiaryAudioGeneration);
  InterruptTtsPlaybackIfOwner(TTS_PLAYBACK_OWNER_DIARY);
  g_aiDiaryAudioState = 0;
  if (g_aiDiaryAudioButton) {
    g_aiDiaryAudioButton->setCaption(WideFromUtf8("Play Audio").c_str());
    g_aiDiaryAudioButton->setEnabled(enableSelectedEntry &&
                                     !g_aiDiaryPendingEntry.empty());
  }
}

std::string SanitizeUiText(std::string input) {
  std::string out;
  out.reserve(input.size());
  for (size_t i = 0; i < input.size(); ++i) {
    unsigned char ch = static_cast<unsigned char>(input[i]);
    if (ch == '\0') {
      continue;
    }
    if (ch < 32 && ch != '\n' && ch != '\r' && ch != '\t') {
      continue;
    }
    out.push_back(static_cast<char>(ch));
  }
  return out;
}

void TrimInline(std::string &value) {
  size_t first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) {
    value.clear();
    return;
  }
  size_t last = value.find_last_not_of(" \t\r\n");
  value = value.substr(first, last - first + 1);
}

std::string LowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
  return value;
}

void ParsePipeEntryArray(const std::string &dataInput,
                         std::vector<std::string> &displayOut,
                         std::vector<std::string> &valueOut) {
  displayOut.clear();
  valueOut.clear();

  std::string data = dataInput;
  if (!data.empty() && data[0] == '[') {
    data = data.substr(1);
  }
  if (!data.empty() && data[data.length() - 1] == ']') {
    data = data.substr(0, data.length() - 1);
  }

  size_t cur = 0;
  while (cur < data.length()) {
    size_t next = data.find(",", cur);
    std::string entry = next == std::string::npos
                            ? data.substr(cur)
                            : data.substr(cur, next - cur);
    TrimInline(entry);
    if (!entry.empty()) {
      if (entry[0] == '"') {
        entry = entry.substr(1);
      }
      if (!entry.empty() && entry[entry.length() - 1] == '"') {
        entry = entry.substr(0, entry.length() - 1);
      }

      size_t pipePos = entry.find("|");
      std::string display = entry;
      std::string value = entry;
      if (pipePos != std::string::npos) {
        display = entry.substr(0, pipePos);
        value = entry.substr(pipePos + 1);
      }
      TrimInline(display);
      TrimInline(value);
      if (!display.empty()) {
        displayOut.push_back(display);
        valueOut.push_back(value.empty() ? display : value);
      }
    }
    if (next == std::string::npos) {
      break;
    }
    cur = next + 1;
  }
}

bool TryDestroyWidgetSafe(MyGUI::Widget *widget) {
  if (!widget) {
    return true;
  }
  MyGUI::Gui *gui = MyGUI::Gui::getInstancePtr();
  if (!gui) {
    return true;
  }
  __try {
    gui->destroyWidget(widget);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// Render detail text as list rows because Kenshi's EditBox skin only shows
// the first line of read-only multiline captions.
void SetReadOnlyText(MyGUI::ListBox *list, const std::string &text) {
  if (!list) {
    return;
  }

  std::string payload = SanitizeUiText(text);
  if (!payload.empty() && payload[0] == ' ') {
    payload.erase(0, 1);
  }
  std::replace(payload.begin(), payload.end(), '\t', ' ');

  list->removeAllItems();
  const size_t wrapColumns =
      std::max<size_t>(24, static_cast<size_t>(list->getWidth()) / 9);
  size_t cursor = 0;
  do {
    size_t next = payload.find('\n', cursor);
    std::string line = next == std::string::npos
                           ? payload.substr(cursor)
                           : payload.substr(cursor, next - cursor);
    if (!line.empty() && line[line.length() - 1] == '\r') {
      line.erase(line.length() - 1);
    }
    TrimInline(line);

    if (line.empty()) {
      list->addItem(WideFromUtf8(" ").c_str());
    } else {
      while (line.length() > wrapColumns) {
        size_t breakPosition = line.find_last_of(' ', wrapColumns);
        if (breakPosition == std::string::npos || breakPosition == 0) {
          breakPosition = line.find(' ', wrapColumns);
        }
        if (breakPosition == std::string::npos) {
          break;
        }

        std::string wrappedLine = line.substr(0, breakPosition);
        TrimInline(wrappedLine);
        if (!wrappedLine.empty()) {
          list->addItem(WideFromUtf8(wrappedLine).c_str());
        }
        line.erase(0, breakPosition + 1);
        TrimInline(line);
      }
      if (!line.empty()) {
        list->addItem(WideFromUtf8(line).c_str());
      }
    }

    if (next == std::string::npos) {
      break;
    }
    cursor = next + 1;
  } while (cursor <= payload.length());

  if (list->getItemCount() == 0) {
    list->addItem(WideFromUtf8(" ").c_str());
  }
  list->setScrollPosition(0);
}

void QueueUiCommand(const std::string &command, const std::string &data) {
  EnterCriticalSection(&g_msgMutex);
  g_messageQueue.push_back("CMD: " + command + ":" + data);
  LeaveCriticalSection(&g_msgMutex);
}

void StartUiWorker(LPTHREAD_START_ROUTINE worker, LPVOID task,
                   const std::string &name) {
  HANDLE thread = CreateThread(NULL, 0, worker, task, 0, NULL);
  if (!thread) {
    Log("UI_WARN: failed to start " + name + " worker.");
    return;
  }
  CloseHandle(thread);
}

void ApplyNpcFilter() {
  if (!g_aiNpcInfoList) {
    return;
  }

  std::string query =
      g_aiNpcSearch ? LowerAscii(g_aiNpcSearch->getCaption()) : "";
  TrimInline(query);
  g_aiNpcInfoList->removeAllItems();
  g_aiNpcInfoStorageIds.clear();
  for (size_t i = 0;
       i < g_aiNpcAllDisplays.size() && i < g_aiNpcAllStorageIds.size(); ++i) {
    if (!query.empty() &&
        LowerAscii(g_aiNpcAllDisplays[i]).find(query) == std::string::npos) {
      continue;
    }
    g_aiNpcInfoList->addItem(WideFromUtf8(g_aiNpcAllDisplays[i]).c_str());
    g_aiNpcInfoStorageIds.push_back(g_aiNpcAllStorageIds[i]);
  }

  if (g_aiNpcInfoStorageIds.empty()) {
    SetReadOnlyText(g_aiNpcInfoText, query.empty() ? "No NPC profiles found."
                                                  : "No NPCs match this search.");
  }
}

void OnAiNpcSearchChange(MyGUI::EditBox *sender) { ApplyNpcFilter(); }

void SetDiaryEntriesLoading(const std::string &message) {
  if (g_aiDiaryEntryList) {
    g_aiDiaryEntryList->removeAllItems();
    g_aiDiaryEntryIds.clear();
    g_aiDiaryEntryList->addItem(WideFromUtf8(message).c_str());
  }
}
} // namespace

void CloseAiNpcInfoUI() {
  if (g_aiNpcInfoWindow && !TryDestroyWidgetSafe(g_aiNpcInfoWindow)) {
    Log("UI_WARN: CloseAiNpcInfoUI destroyWidget failed; clearing stale pointer.");
  }
  g_aiNpcInfoWindow = nullptr;
  g_aiNpcInfoList = nullptr;
  g_aiNpcInfoText = nullptr;
  g_aiNpcInfoCloseButton = nullptr;
  g_aiNpcSearch = nullptr;
  g_aiNpcInfoStorageIds.clear();
  g_aiNpcAllDisplays.clear();
  g_aiNpcAllStorageIds.clear();
  g_aiNpcPendingKey.clear();
}

void PopulateAiNpcInfoUI(const std::string &dataInput) {
  ParsePipeEntryArray(dataInput, g_aiNpcAllDisplays, g_aiNpcAllStorageIds);
  ApplyNpcFilter();
}

void SetAiNpcInfoText(const std::string &data) {
  size_t split = data.find('\n');
  if (split != std::string::npos) {
    std::string key = data.substr(0, split);
    if (!g_aiNpcPendingKey.empty() && key != g_aiNpcPendingKey) {
      Log("UI: ignored stale NPC detail response key=" + key);
      return;
    }
    SetReadOnlyText(g_aiNpcInfoText, data.substr(split + 1));
    return;
  }
  SetReadOnlyText(g_aiNpcInfoText, data);
}

void OnAiNpcInfoNPCSelect(MyGUI::ListBox *sender, size_t index) {
  if (index == MyGUI::ITEM_NONE || index >= g_aiNpcInfoStorageIds.size()) {
    return;
  }

  std::string displayName = sender->getItemNameAt(index);
  std::string sid = g_aiNpcInfoStorageIds[index];
  g_aiNpcPendingKey = sid;
  SetReadOnlyText(g_aiNpcInfoText,
                  T("Loading profile for ") + displayName + "...");

  AiNpcInfoTask *task = new AiNpcInfoTask();
  task->npcName = displayName;
  task->requestKey = sid;
  task->json = "{\"action\":\"detail\",\"sid\":\"" + EscapeJSON(sid) + "\"}";
  StartUiWorker(AiNpcInfoDetailThread, task, "NPC detail");
}

void OnAiNpcInfoWindowButtonPressed(MyGUI::Window *sender,
                                    const std::string &name) {
  if (name == "close") {
    CloseAiNpcInfoUI();
  }
}

DWORD WINAPI AiNpcInfoListThread(LPVOID lpParam) {
  std::string response =
      PostToStobeWithResponse(L"/ai_npcs/list", "{\"action\":\"list\"}");
  if (response.empty()) {
    QueueUiCommand("SET_AINPCINFO_TEXT",
                   "Unable to load NPCs. Check the StobeServer connection.");
    return 0;
  }

  std::string names = JsonReadField(response, "names");
  if (names.empty()) {
    names = JsonReadField(response, "characters");
  }
  if (names.empty()) {
    std::string error = JsonReadField(response, "error");
    QueueUiCommand("SET_AINPCINFO_TEXT",
                   error.empty() ? "No NPC profiles found." : error);
    return 0;
  }
  QueueUiCommand("POPULATE_AINPCINFO", names);
  return 0;
}

DWORD WINAPI AiNpcInfoDetailThread(LPVOID lpParam) {
  AiNpcInfoTask *task = static_cast<AiNpcInfoTask *>(lpParam);
  std::string key = task->requestKey;
  std::string response = PostToStobeWithResponse(L"/ai_npcs/detail", task->json);
  delete task;

  std::string content = JsonReadField(response, "text");
  if (content.empty()) {
    content = JsonReadField(response, "content");
  }
  if (content.empty()) {
    content = JsonReadField(response, "error");
  }
  if (content.empty()) {
    content = response.empty() ? "Unable to load this NPC profile."
                               : "The server returned an unreadable NPC profile.";
  }
  QueueUiCommand("SET_AINPCINFO_TEXT", key + "\n" + SanitizeUiText(content));
  return 0;
}

void OnAiNpcInfoCloseClick(MyGUI::Widget *sender) { CloseAiNpcInfoUI(); }

void CreateAiNpcInfoUI() {
  MyGUI::Gui *gui = MyGUI::Gui::getInstancePtr();
  if (!gui) {
    return;
  }
  CloseAiNpcInfoUI();

  g_aiNpcInfoWindow = gui->createWidgetReal<MyGUI::Window>(
      "Kenshi_WindowCX", 0.12f, 0.08f, 0.76f, 0.84f, MyGUI::Align::Center,
      "Popup", "Stobe_AiNpcWindow");
  if (!g_aiNpcInfoWindow) {
    return;
  }
  g_aiNpcInfoWindow->setCaption(WideFromUtf8(T("Stobe NPCs")).c_str());
  g_aiNpcInfoWindow->eventWindowButtonPressed +=
      MyGUI::newDelegate(OnAiNpcInfoWindowButtonPressed);

  MyGUI::Widget *client = g_aiNpcInfoWindow->getClientWidget();
  if (!client) {
    return;
  }

  g_aiNpcSearch = client->createWidgetReal<MyGUI::EditBox>(
      "Kenshi_EditBox", 0.02f, 0.03f, 0.30f, 0.07f,
      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_AiNpcSearch");
  g_aiNpcSearch->setCaption(WideFromUtf8("").c_str());
  g_aiNpcSearch->setEditMultiLine(false);
  g_aiNpcSearch->setEditWordWrap(false);
  g_aiNpcSearch->setVisibleVScroll(false);
  g_aiNpcSearch->eventEditTextChange +=
      MyGUI::newDelegate(OnAiNpcSearchChange);

  g_aiNpcInfoList = client->createWidgetReal<MyGUI::ListBox>(
      "Kenshi_ListBox", 0.02f, 0.12f, 0.30f, 0.73f,
      MyGUI::Align::Left | MyGUI::Align::VStretch, "Stobe_AiNpcList");
  g_aiNpcInfoList->eventListChangePosition +=
      MyGUI::newDelegate(OnAiNpcInfoNPCSelect);

  g_aiNpcInfoText = client->createWidgetReal<MyGUI::ListBox>(
      "Kenshi_ListBox", 0.34f, 0.03f, 0.64f, 0.82f,
      MyGUI::Align::Default, "Stobe_AiNpcDetail");
  SetReadOnlyText(
      g_aiNpcInfoText,
      T("Search or select an NPC to view their profile settings, biography, "
        "live status, relationships, and recent events."));

  g_aiNpcInfoCloseButton = client->createWidgetReal<MyGUI::Button>(
      "Kenshi_Button1", 0.84f, 0.88f, 0.14f, 0.08f,
      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_AiNpcCloseBtn");
  g_aiNpcInfoCloseButton->setCaption(WideFromUtf8(T("Close")).c_str());
  g_aiNpcInfoCloseButton->eventMouseButtonClick +=
      MyGUI::newDelegate(OnAiNpcInfoCloseClick);

  StartUiWorker(AiNpcInfoListThread, NULL, "NPC list");
}

// ---------------------------------------------------------------- NPC info panel
// Biography card of one NPC as the speaking squad character knows them
// (ai_npcs.php action player_view). Header: in-game portrait + name, job, faction,
// looks, relationship, how often you talked; body (scrolling list): About them,
// What you've learned, Dealings with you, Right now. Requests run on a worker
// thread in two phases: phase 1 never calls the LLM; if the server says the bio is
// stale (new dialogue since the cached one) phase 2 asks again with bio=1 and the
// card is filled when it arrives. A reply is shown only if it carries the newest
// generation and the key ("<target serial>|<speaker>") still on screen.
MyGUI::Window *g_npcPanelWindow = nullptr;
MyGUI::ListBox *g_npcPanelText = nullptr;
volatile LONG g_npcPanelGeneration = 0;
std::string g_npcPanelKey;
std::string g_npcPanelLastText;
bool g_npcPanelOpenRequest = false;
bool g_npcPanelRefreshRequest = false;

namespace {
MyGUI::ImageBox *g_npcPanelPortrait = nullptr;
MyGUI::TextBox *g_npcPanelInitial = nullptr;
MyGUI::TextBox *g_npcPanelName = nullptr;
MyGUI::TextBox *g_npcPanelHeader[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
std::string g_npcPanelPortraitTex;    // texture shown now ("" = fallback initial)
std::string g_npcPanelPortraitCoord;  // "l,t,w,h" shown now
std::string g_npcPanelBioState;       // empty|cached|pending|updated (last shown reply)

struct NpcPanelTask {
  std::string json;
  std::string key;
  LONG generation;
};

void QueueNpcPanelReply(const NpcPanelTask *task, const std::string &payload) {
  QueueUiCommand("SET_NPCPANEL_TEXT", ToString((int)task->generation) + "\n" +
                                          task->key + "\n" + payload);
}

// Reply payload: the server JSON, or "!<message>" when there is no usable answer.
std::string NpcPanelFetch(const std::string &json) {
  std::string response = PostToStobeWithResponse(L"/ai_npcs/player_view", json);
  if (!JsonReadField(response, "text").empty()) {
    return response;
  }
  std::string error = JsonReadField(response, "error");
  return "!" + (response.empty() ? std::string("Unable to reach the Stobe server.")
                                 : (error.empty() ? std::string("The server returned an unreadable answer.")
                                                  : error));
}

DWORD WINAPI NpcPanelThread(LPVOID lpParam) {
  NpcPanelTask *task = static_cast<NpcPanelTask *>(lpParam);
  std::string reply = NpcPanelFetch(task->json);
  QueueNpcPanelReply(task, reply);
  // Phase 2: the bio is stale and the card is still the same request -> let the
  // server write the new bio (one LLM call, a few seconds) and show it.
  if (!reply.empty() && reply[0] != '!' && JsonReadField(reply, "bio_stale") == "1" &&
      task->generation == g_npcPanelGeneration) {
    std::string json = task->json;
    size_t brace = json.find_last_of('}');
    if (brace != std::string::npos) {
      json.insert(brace, ",\"bio\":1");
      std::string second = NpcPanelFetch(json);
      if (!second.empty() && second[0] != '!') {
        QueueNpcPanelReply(task, second);
      } else {
        Log("NPC_PANEL_WARN: bio update failed: " + second.substr(0, 160));
      }
    }
  }
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

MyGUI::TextBox *NpcPanelLabel(MyGUI::Widget *parent, int left, int top, int width,
                              int height, const char *name) {
  MyGUI::TextBox *t = parent->createWidget<MyGUI::TextBox>(
      "Kenshi_TextboxStandardText", MyGUI::IntCoord(left, top, width, height),
      MyGUI::Align::Left | MyGUI::Align::Top | MyGUI::Align::HStretch, name);
  if (t) {
    t->setTextAlign(MyGUI::Align::Left | MyGUI::Align::VCenter);
  }
  return t;
}

void SetLabel(MyGUI::TextBox *t, const std::string &text) {
  if (t) {
    t->setCaption(WideFromUtf8(SanitizeUiText(text)).c_str());
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
      "Kenshi_WindowCX", 0.60f, 0.08f, 0.36f, 0.72f, MyGUI::Align::Default,
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
  // Pixel layout from the client size so the header keeps its shape at any resolution.
  const int cw = (std::max)(320, client->getWidth());
  const int ch = (std::max)(360, client->getHeight());
  const int pad = (std::max)(8, cw / 40);
  const int lineH = (std::max)(20, ch / 34);
  const int nameH = lineH + lineH / 2;
  const int headerH = nameH + 5 * lineH + 4;
  const int portrait = headerH;
  // No portrait: the name's initial, large, in the same square.
  g_npcPanelInitial = client->createWidget<MyGUI::TextBox>(
      "Kenshi_TextboxStandardText", MyGUI::IntCoord(pad, pad, portrait, portrait),
      MyGUI::Align::Left | MyGUI::Align::Top, "Stobe_NpcPanelInitial");
  if (g_npcPanelInitial) {
    g_npcPanelInitial->setTextAlign(MyGUI::Align::Center);
    g_npcPanelInitial->setFontName("Kenshi_StandardFont_Large");
  }
  g_npcPanelPortrait = client->createWidget<MyGUI::ImageBox>(
      "ImageBox", MyGUI::IntCoord(pad, pad, portrait, portrait),
      MyGUI::Align::Left | MyGUI::Align::Top, "Stobe_NpcPanelPortrait");
  if (g_npcPanelPortrait) {
    g_npcPanelPortrait->setVisible(false);
  }
  const int hx = pad + portrait + pad;
  const int hw = (std::max)(120, cw - hx - pad);
  g_npcPanelName = NpcPanelLabel(client, hx, pad, hw, nameH, "Stobe_NpcPanelName");
  if (g_npcPanelName) {
    g_npcPanelName->setFontName("Kenshi_StandardFont_Large");
  }
  for (int i = 0; i < 5; ++i) {
    g_npcPanelHeader[i] = NpcPanelLabel(client, hx, pad + nameH + i * lineH, hw, lineH,
                                        ("Stobe_NpcPanelHeader" + ToString(i)).c_str());
  }
  const int bodyTop = pad + headerH + pad;
  const int btnH = (std::max)(30, ch / 14);
  const int bodyH = (std::max)(80, ch - bodyTop - btnH - 2 * pad);
  g_npcPanelText = client->createWidget<MyGUI::ListBox>(
      "Kenshi_ListBox", MyGUI::IntCoord(pad, bodyTop, cw - 2 * pad, bodyH),
      MyGUI::Align::Stretch, "Stobe_NpcPanelText");
  const int btnW = (cw - 3 * pad) / 3;
  MyGUI::Button *refresh = client->createWidget<MyGUI::Button>(
      "Kenshi_Button1", MyGUI::IntCoord(pad, ch - pad - btnH, btnW, btnH),
      MyGUI::Align::Bottom | MyGUI::Align::Left, "Stobe_NpcPanelRefreshBtn");
  refresh->setCaption(WideFromUtf8(T("Refresh")).c_str());
  refresh->eventMouseButtonClick += MyGUI::newDelegate(OnNpcPanelRefreshClick);
  MyGUI::Button *close = client->createWidget<MyGUI::Button>(
      "Kenshi_Button1", MyGUI::IntCoord(cw - pad - btnW, ch - pad - btnH, btnW, btnH),
      MyGUI::Align::Bottom | MyGUI::Align::Right, "Stobe_NpcPanelCloseBtn");
  close->setCaption(WideFromUtf8(T("Close")).c_str());
  close->eventMouseButtonClick += MyGUI::newDelegate(OnNpcPanelCloseClick);
}

void ClearNpcPanelHeader(const std::string &title) {
  SetLabel(g_npcPanelName, title);
  for (int i = 0; i < 5; ++i) {
    SetLabel(g_npcPanelHeader[i], "");
  }
  std::string initial = title.empty() ? std::string("?") : title.substr(0, 1);
  SetLabel(g_npcPanelInitial, initial);
}

bool SetNpcPanelImageUnsafe(MyGUI::ImageBox *box, const std::string &texture, int left,
                            int top, int width, int height) {
  try {
    box->setImageInfo(texture, MyGUI::IntCoord(left, top, width, height),
                      MyGUI::IntSize(width, height));
    box->setImageIndex(0);
    return true;
  } catch (...) {
    return false;
  }
}

bool SetNpcPanelImageSafe(MyGUI::ImageBox *box, const std::string &texture, int left,
                          int top, int width, int height) {
  __try {
    return SetNpcPanelImageUnsafe(box, texture, left, top, width, height);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}
} // namespace

bool IsNpcPanelOpen() { return g_npcPanelWindow != nullptr; }
std::string NpcPanelKey() { return g_npcPanelKey; }
std::string NpcPanelText() { return g_npcPanelLastText; }
int NpcPanelGeneration() { return (int)g_npcPanelGeneration; }
std::string NpcPanelStatus() {
  return std::string("portrait=") + (g_npcPanelPortraitTex.empty() ? "0" : "1") +
         " tex=" + (g_npcPanelPortraitTex.empty() ? std::string("-") : g_npcPanelPortraitTex) +
         " bio_state=" + (g_npcPanelBioState.empty() ? std::string("-") : g_npcPanelBioState);
}

void SetNpcPanelPortrait(bool ok, const std::string &texture, int left, int top,
                         int width, int height, const std::string &reason) {
  static bool s_disabled = false;
  if (!g_npcPanelWindow || !g_npcPanelPortrait) {
    return;
  }
  std::string coord = ToString(left) + "," + ToString(top) + "," + ToString(width) +
                      "," + ToString(height);
  if (ok && !s_disabled && !texture.empty() && width > 0 && height > 0) {
    if (texture == g_npcPanelPortraitTex && coord == g_npcPanelPortraitCoord) {
      return; // unchanged
    }
    if (SetNpcPanelImageSafe(g_npcPanelPortrait, texture, left, top, width, height)) {
      g_npcPanelPortrait->setVisible(true);
      if (g_npcPanelInitial) {
        g_npcPanelInitial->setVisible(false);
      }
      g_npcPanelPortraitTex = texture;
      g_npcPanelPortraitCoord = coord;
      Log("NPC_PANEL: portrait=1 tex=" + texture + " coord=" + coord);
      return;
    }
    s_disabled = true; // a fault once: fallback for the rest of the session
    Log("NPC_PANEL_WARN: portrait image fault; portraits off for this session");
  }
  if (!g_npcPanelPortraitTex.empty() || g_npcPanelPortraitCoord != "-") {
    Log("NPC_PANEL: portrait=0 reason=" +
        (s_disabled ? std::string("disabled") : (reason.empty() ? std::string("none") : reason)));
  }
  g_npcPanelPortrait->setVisible(false);
  if (g_npcPanelInitial) {
    g_npcPanelInitial->setVisible(true);
  }
  g_npcPanelPortraitTex.clear();
  g_npcPanelPortraitCoord = "-";
}

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
  if (targetChanged) {
    ClearNpcPanelHeader(title);
    g_npcPanelBioState.clear();
  }
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
  std::string payload = data.substr(b + 1);
  if (!payload.empty() && payload[0] == '!') {
    std::string error = SanitizeUiText(payload.substr(1));
    g_npcPanelLastText = error;
    SetReadOnlyText(g_npcPanelText, error);
    Log("NPC_PANEL_WARN: no card key=" + key + " error=" + error.substr(0, 160));
    return;
  }
  std::string text = SanitizeUiText(JsonReadField(payload, "text"));
  std::string bioState = JsonReadField(payload, "bio_state");
  if (text == g_npcPanelLastText && bioState == g_npcPanelBioState) {
    return; // periodic refresh, nothing changed: keep the scroll position
  }
  g_npcPanelLastText = text;
  g_npcPanelBioState = bioState;
  std::string name = JsonReadField(payload, "name");
  SetLabel(g_npcPanelName, name);
  if (!name.empty()) {
    SetLabel(g_npcPanelInitial, name.substr(0, 1));
  }
  SetLabel(g_npcPanelHeader[0], T("Job") + ": " + JsonReadField(payload, "job"));
  SetLabel(g_npcPanelHeader[1], T("Faction") + ": " + JsonReadField(payload, "faction"));
  SetLabel(g_npcPanelHeader[2], JsonReadField(payload, "race_line"));
  std::string relLine = JsonReadField(payload, "relation_line");
  if (!relLine.empty()) {
    relLine[0] = static_cast<char>(std::tolower(static_cast<unsigned char>(relLine[0])));
  }
  SetLabel(g_npcPanelHeader[3], JsonReadField(payload, "relation_label") +
                                    (relLine.empty() ? std::string("") : " - " + relLine));
  SetLabel(g_npcPanelHeader[4], JsonReadField(payload, "talked_line"));
  std::string body = JsonReadField(payload, "body");
  SetReadOnlyText(g_npcPanelText, body.empty() ? text : body);
  Log("NPC_PANEL: shown key=" + key + " gen=" + ToString(generation) +
      " chars=" + ToString((int)text.size()) + " bio_state=" + bioState);
}

void CloseNpcPanelUI() {
  if (g_npcPanelWindow && !TryDestroyWidgetSafe(g_npcPanelWindow)) {
    Log("UI_WARN: CloseNpcPanelUI destroyWidget failed; clearing stale pointer.");
  }
  const bool wasOpen = g_npcPanelWindow != nullptr;
  g_npcPanelWindow = nullptr;
  g_npcPanelText = nullptr;
  g_npcPanelPortrait = nullptr;
  g_npcPanelInitial = nullptr;
  g_npcPanelName = nullptr;
  for (int i = 0; i < 5; ++i) {
    g_npcPanelHeader[i] = nullptr;
  }
  g_npcPanelPortraitTex.clear();
  g_npcPanelPortraitCoord.clear();
  g_npcPanelBioState.clear();
  g_npcPanelKey.clear();
  g_npcPanelLastText.clear();
  g_npcPanelRefreshRequest = false;
  InterlockedIncrement(&g_npcPanelGeneration); // replies in flight are dropped
  if (wasOpen) {
    Log("NPC_PANEL: closed");
  }
}

void CloseAiDiaryUI(bool destroyWindow) {
  CancelAiDiaryAudio(false);
  if (destroyWindow && g_aiDiaryWindow &&
      !TryDestroyWidgetSafe(g_aiDiaryWindow)) {
    Log("UI_WARN: CloseAiDiaryUI destroyWidget failed; clearing stale pointer.");
  }
  g_aiDiaryWindow = nullptr;
  g_aiDiaryList = nullptr;
  g_aiDiaryEntryList = nullptr;
  g_aiDiaryText = nullptr;
  g_aiDiaryAudioButton = nullptr;
  g_aiDiaryCloseButton = nullptr;
  g_aiDiaryKeys.clear();
  g_aiDiaryEntryIds.clear();
  g_aiDiaryPendingPerson.clear();
  g_aiDiaryPendingEntry.clear();
}

void PopulateAiDiaryUI(const std::string &dataInput) {
  if (!g_aiDiaryList) {
    return;
  }
  g_aiDiaryList->removeAllItems();
  g_aiDiaryKeys.clear();

  std::vector<std::string> displays;
  std::vector<std::string> values;
  ParsePipeEntryArray(dataInput, displays, values);
  for (size_t i = 0; i < displays.size() && i < values.size(); ++i) {
    g_aiDiaryList->addItem(WideFromUtf8(displays[i]).c_str());
    g_aiDiaryKeys.push_back(values[i]);
  }
  if (g_aiDiaryKeys.empty()) {
    SetReadOnlyText(g_aiDiaryText, "No diary entries have been recorded.");
  }
}

void PopulateAiDiaryEntries(const std::string &data) {
  size_t split = data.find('\n');
  if (split == std::string::npos || !g_aiDiaryEntryList) {
    return;
  }
  std::string person = data.substr(0, split);
  if (person != g_aiDiaryPendingPerson) {
    Log("UI: ignored stale diary entry list for " + person);
    return;
  }

  g_aiDiaryEntryList->removeAllItems();
  g_aiDiaryEntryIds.clear();
  std::vector<std::string> displays;
  std::vector<std::string> values;
  ParsePipeEntryArray(data.substr(split + 1), displays, values);
  for (size_t i = 0; i < displays.size() && i < values.size(); ++i) {
    g_aiDiaryEntryList->addItem(WideFromUtf8(displays[i]).c_str());
    g_aiDiaryEntryIds.push_back(values[i]);
  }
  if (g_aiDiaryEntryIds.empty()) {
    SetReadOnlyText(g_aiDiaryText, "No diary entries found for this NPC.");
    CancelAiDiaryAudio(false);
  }
}

void SetAiDiaryText(const std::string &data) {
  size_t split = data.find('\n');
  if (split != std::string::npos) {
    std::string key = data.substr(0, split);
    if (!g_aiDiaryPendingEntry.empty() && key != g_aiDiaryPendingEntry) {
      Log("UI: ignored stale diary detail response key=" + key);
      return;
    }
    SetReadOnlyText(g_aiDiaryText, data.substr(split + 1));
    return;
  }
  SetReadOnlyText(g_aiDiaryText, data);
}

void SetAiDiaryAudioState(const std::string &data) {
  size_t split = data.find('\n');
  if (split == std::string::npos || !g_aiDiaryWindow ||
      !g_aiDiaryAudioButton) {
    return;
  }
  std::string entryId = data.substr(0, split);
  std::string state = data.substr(split + 1);
  if (entryId != g_aiDiaryPendingEntry) {
    return;
  }

  if (state == "ready" || state == "idle") {
    g_aiDiaryAudioState = 0;
    g_aiDiaryAudioButton->setCaption(WideFromUtf8("Play Audio").c_str());
    g_aiDiaryAudioButton->setEnabled(true);
  } else if (state == "playing") {
    g_aiDiaryAudioState = 2;
    g_aiDiaryAudioButton->setCaption(WideFromUtf8("Stop Audio").c_str());
    g_aiDiaryAudioButton->setEnabled(true);
  } else if (state == "error") {
    g_aiDiaryAudioState = 0;
    g_aiDiaryAudioButton->setCaption(WideFromUtf8("Retry Audio").c_str());
    g_aiDiaryAudioButton->setEnabled(true);
  }
}

void OnAiDiarySelect(MyGUI::ListBox *sender, size_t index) {
  if (index == MyGUI::ITEM_NONE || index >= g_aiDiaryKeys.size()) {
    return;
  }
  std::string person = g_aiDiaryKeys[index];
  CancelAiDiaryAudio(false);
  g_aiDiaryPendingPerson = person;
  g_aiDiaryPendingEntry.clear();
  SetDiaryEntriesLoading("Loading...");
  SetReadOnlyText(g_aiDiaryText,
                  "Select a dated entry after the diary list loads.");

  AiDiaryTask *task = new AiDiaryTask();
  task->requestKey = person;
  task->action = "entries";
  task->json = "{\"action\":\"entries\",\"sid\":\"" + EscapeJSON(person) +
               "\"}";
  StartUiWorker(AiDiaryDetailThread, task, "diary entry list");
}

void OnAiDiaryEntrySelect(MyGUI::ListBox *sender, size_t index) {
  if (index == MyGUI::ITEM_NONE || index >= g_aiDiaryEntryIds.size()) {
    return;
  }
  CancelAiDiaryAudio(false);
  std::string entryId = g_aiDiaryEntryIds[index];
  g_aiDiaryPendingEntry = entryId;
  SetReadOnlyText(g_aiDiaryText, "Loading diary entry...");
  if (g_aiDiaryAudioButton) {
    g_aiDiaryAudioButton->setCaption(WideFromUtf8("Loading...").c_str());
    g_aiDiaryAudioButton->setEnabled(false);
  }

  AiDiaryTask *task = new AiDiaryTask();
  task->requestKey = entryId;
  task->action = "entry";
  task->json = "{\"action\":\"entry\",\"rowid\":" + entryId + "}";
  StartUiWorker(AiDiaryDetailThread, task, "diary detail");
}

void OnAiDiaryWindowButtonPressed(MyGUI::Window *sender,
                                  const std::string &name) {
  if (name == "close") {
    CloseAiDiaryUI();
  }
}

DWORD WINAPI AiDiaryListThread(LPVOID lpParam) {
  std::string response =
      PostToStobeWithResponse(L"/ai_diaries/list", "{\"action\":\"list\"}");
  if (response.empty()) {
    QueueUiCommand("SET_AIDIARY_TEXT",
                   "Unable to load diaries. Check the StobeServer connection.");
    return 0;
  }

  std::string names = JsonReadField(response, "names");
  if (names.empty()) {
    std::string error = JsonReadField(response, "error");
    QueueUiCommand("SET_AIDIARY_TEXT",
                   error.empty() ? "No diary entries have been recorded." : error);
    return 0;
  }
  QueueUiCommand("POPULATE_AIDIARIES", names);
  return 0;
}

DWORD WINAPI AiDiaryDetailThread(LPVOID lpParam) {
  AiDiaryTask *task = static_cast<AiDiaryTask *>(lpParam);
  std::string key = task->requestKey;
  std::string action = task->action;
  std::wstring endpoint =
      action == "entries" ? L"/ai_diaries/entries" : L"/ai_diaries/entry";
  std::string response = PostToStobeWithResponse(endpoint, task->json);
  delete task;

  if (action == "entries") {
    std::string entries = JsonReadField(response, "entries");
    if (entries.empty()) {
      entries = "[]";
    }
    QueueUiCommand("POPULATE_AIDIARY_ENTRIES", key + "\n" + entries);
    return 0;
  }

  std::string content = JsonReadField(response, "text");
  bool hasDiaryContent = !content.empty();
  if (content.empty()) {
    content = JsonReadField(response, "error");
  }
  if (content.empty()) {
    content = response.empty() ? "Unable to load this diary entry."
                               : "The server returned an unreadable diary entry.";
  }
  QueueUiCommand("SET_AIDIARY_TEXT", key + "\n" + SanitizeUiText(content));
  if (hasDiaryContent) {
    QueueUiCommand("SET_AIDIARY_AUDIO_STATE", key + "\nready");
  }
  return 0;
}

DWORD WINAPI AiDiaryAudioThread(LPVOID lpParam) {
  AiDiaryAudioTask *task = static_cast<AiDiaryAudioTask *>(lpParam);
  std::string entryId = task->entryId;
  LONG generation = task->generation;
  LONG interactionEpoch = task->interactionEpoch;
  delete task;

  std::string response = PostToStobeWithResponse(
      L"/diary_audio", "{\"rowid\":" + entryId + "}");
  if (generation != CurrentAiDiaryAudioGeneration() || !Interaction::IsCurrent(interactionEpoch)) {
    return 0;
  }

  std::string ok = LowerAscii(JsonReadField(response, "ok"));
  std::string hash = JsonReadField(response, "hash");
  bool validHash = hash.length() == 32 &&
                   std::all_of(hash.begin(), hash.end(), [](unsigned char ch) {
                     return std::isxdigit(ch) != 0;
                   });
  if ((ok != "true" && ok != "1") || !validHash) {
    std::string error = JsonReadField(response, "error");
    Log("DIARY_AUDIO: generation failed entry=" + entryId +
        " error=" + (error.empty() ? "unreadable_response" : error));
    QueueUiCommand("SET_AIDIARY_AUDIO_STATE", entryId + "\nerror");
    return 0;
  }

  InterruptTtsPlayback();
  if (generation != CurrentAiDiaryAudioGeneration()) {
    return 0;
  }
  if (!QueueTtsPlayback(hash, -1, 0, 1.0f, TTS_PLAYBACK_OWNER_DIARY)) {
    QueueUiCommand("SET_AIDIARY_AUDIO_STATE", entryId + "\nerror");
    return 0;
  }

  Log("DIARY_AUDIO: playback started entry=" + entryId);
  QueueUiCommand("SET_AIDIARY_AUDIO_STATE", entryId + "\nplaying");
  while (generation == CurrentAiDiaryAudioGeneration() &&
         IsTtsPlaybackActiveForOwner(TTS_PLAYBACK_OWNER_DIARY)) {
    Sleep(100);
  }
  if (generation == CurrentAiDiaryAudioGeneration()) {
    Log("DIARY_AUDIO: playback finished entry=" + entryId);
    QueueUiCommand("SET_AIDIARY_AUDIO_STATE", entryId + "\nidle");
  }
  return 0;
}

void OnAiDiaryAudioClick(MyGUI::Widget *sender) {
  if (!Interaction::ManualInputAllowed()) return;
  if (g_aiDiaryPendingEntry.empty()) {
    return;
  }
  if (g_aiDiaryAudioState != 0) {
    CancelAiDiaryAudio(true);
    Log("DIARY_AUDIO: playback cancelled entry=" + g_aiDiaryPendingEntry);
    return;
  }

  LONG generation = InterlockedIncrement(&g_aiDiaryAudioGeneration);
  g_aiDiaryAudioState = 1;
  if (g_aiDiaryAudioButton) {
    g_aiDiaryAudioButton->setCaption(WideFromUtf8("Stop Audio").c_str());
    g_aiDiaryAudioButton->setEnabled(true);
  }

  AiDiaryAudioTask *task = new AiDiaryAudioTask();
  task->entryId = g_aiDiaryPendingEntry;
  task->generation = generation;
  task->interactionEpoch = Interaction::Epoch();
  StartUiWorker(AiDiaryAudioThread, task, "diary audio");
}

void OnAiDiaryCloseClick(MyGUI::Widget *sender) { CloseAiDiaryUI(); }

void CreateAiDiaryUI() {
  MyGUI::Gui *gui = MyGUI::Gui::getInstancePtr();
  if (!gui) {
    return;
  }
  CloseAiDiaryUI();

  g_aiDiaryWindow = gui->createWidgetReal<MyGUI::Window>(
      "Kenshi_WindowCX", 0.08f, 0.08f, 0.84f, 0.84f, MyGUI::Align::Center,
      "Popup", "Stobe_AiDiaryWindow");
  if (!g_aiDiaryWindow) {
    return;
  }
  g_aiDiaryWindow->setCaption(WideFromUtf8(T("Stobe Diaries")).c_str());
  g_aiDiaryWindow->eventWindowButtonPressed +=
      MyGUI::newDelegate(OnAiDiaryWindowButtonPressed);

  MyGUI::Widget *client = g_aiDiaryWindow->getClientWidget();
  if (!client) {
    return;
  }

  MyGUI::TextBox *peopleLabel = client->createWidgetReal<MyGUI::TextBox>(
      "Kenshi_TextboxStandardText", 0.02f, 0.02f, 0.24f, 0.05f,
      MyGUI::Align::Default, "Stobe_AiDiaryPeopleLabel");
  peopleLabel->setCaption(WideFromUtf8("People").c_str());
  MyGUI::TextBox *entriesLabel = client->createWidgetReal<MyGUI::TextBox>(
      "Kenshi_TextboxStandardText", 0.28f, 0.02f, 0.30f, 0.05f,
      MyGUI::Align::Default, "Stobe_AiDiaryEntriesLabel");
  entriesLabel->setCaption(WideFromUtf8("Entries").c_str());
  MyGUI::TextBox *detailLabel = client->createWidgetReal<MyGUI::TextBox>(
      "Kenshi_TextboxStandardText", 0.60f, 0.02f, 0.38f, 0.05f,
      MyGUI::Align::Default, "Stobe_AiDiaryDetailLabel");
  detailLabel->setCaption(WideFromUtf8("Diary").c_str());

  g_aiDiaryList = client->createWidgetReal<MyGUI::ListBox>(
      "Kenshi_ListBox", 0.02f, 0.08f, 0.24f, 0.77f,
      MyGUI::Align::Default, "Stobe_AiDiaryList");
  g_aiDiaryList->eventListChangePosition +=
      MyGUI::newDelegate(OnAiDiarySelect);

  g_aiDiaryEntryList = client->createWidgetReal<MyGUI::ListBox>(
      "Kenshi_ListBox", 0.28f, 0.08f, 0.30f, 0.77f,
      MyGUI::Align::Default, "Stobe_AiDiaryEntryList");
  g_aiDiaryEntryList->eventListChangePosition +=
      MyGUI::newDelegate(OnAiDiaryEntrySelect);

  g_aiDiaryText = client->createWidgetReal<MyGUI::ListBox>(
      "Kenshi_ListBox", 0.60f, 0.08f, 0.38f, 0.77f,
      MyGUI::Align::Default, "Stobe_AiDiaryDetail");
  SetReadOnlyText(g_aiDiaryText,
                  T("Select an NPC, then select a dated diary entry."));

  g_aiDiaryAudioButton = client->createWidgetReal<MyGUI::Button>(
      "Kenshi_Button1", 0.60f, 0.88f, 0.22f, 0.08f,
      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_AiDiaryAudioBtn");
  g_aiDiaryAudioButton->setCaption(WideFromUtf8(T("Play Audio")).c_str());
  g_aiDiaryAudioButton->setEnabled(false);
  g_aiDiaryAudioButton->eventMouseButtonClick +=
      MyGUI::newDelegate(OnAiDiaryAudioClick);

  g_aiDiaryCloseButton = client->createWidgetReal<MyGUI::Button>(
      "Kenshi_Button1", 0.84f, 0.88f, 0.14f, 0.08f,
      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_AiDiaryCloseBtn");
  g_aiDiaryCloseButton->setCaption(WideFromUtf8(T("Close")).c_str());
  g_aiDiaryCloseButton->eventMouseButtonClick +=
      MyGUI::newDelegate(OnAiDiaryCloseClick);

  StartUiWorker(AiDiaryListThread, NULL, "diary people");
}

} // namespace UI
} // namespace Stobe
