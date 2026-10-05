#pragma once
#include "ChatUIGlobals.h"
#include <mygui/MyGUI_Button.h>

namespace Stobe {
namespace UI {

extern MyGUI::Window *g_aiNpcInfoWindow;
extern MyGUI::ListBox *g_aiNpcInfoList;
extern MyGUI::ListBox *g_aiNpcInfoText;
extern MyGUI::Button *g_aiNpcInfoCloseButton;
extern std::vector<std::string> g_aiNpcInfoStorageIds;
extern MyGUI::Window *g_aiDiaryWindow;
extern MyGUI::ListBox *g_aiDiaryList;
extern MyGUI::ListBox *g_aiDiaryEntryList;
extern MyGUI::ListBox *g_aiDiaryText;
extern MyGUI::Button *g_aiDiaryAudioButton;
extern MyGUI::Button *g_aiDiaryCloseButton;
extern std::vector<std::string> g_aiDiaryKeys;
extern std::vector<std::string> g_aiDiaryEntryIds;

void CreateAiNpcInfoUI();
void CloseAiNpcInfoUI();
void PopulateAiNpcInfoUI(const std::string &data);
void SetAiNpcInfoText(const std::string &data);
void CreateAiDiaryUI();
void CloseAiDiaryUI(bool destroyWindow = true);
void PopulateAiDiaryUI(const std::string &data);
void PopulateAiDiaryEntries(const std::string &data);
void SetAiDiaryText(const std::string &data);
void SetAiDiaryAudioState(const std::string &data);

// NPC info panel: compact read-only view of the conversation target.
extern bool g_npcPanelOpenRequest;    // chat window Info button -> game thread
extern bool g_npcPanelRefreshRequest; // panel Refresh button -> game thread
bool IsNpcPanelOpen();
void RequestNpcPanel(const std::string &key, const std::string &title,
                     const std::string &json, bool showLoading);
void SetNpcPanelText(const std::string &data);
void CloseNpcPanelUI();
std::string NpcPanelKey();
std::string NpcPanelText();
int NpcPanelGeneration();

void OnAiNpcInfoNPCSelect(MyGUI::ListBox *sender, size_t index);
void OnAiNpcInfoWindowButtonPressed(MyGUI::Window *sender,
                                  const std::string &name);
DWORD WINAPI AiNpcInfoListThread(LPVOID lpParam);
DWORD WINAPI AiNpcInfoDetailThread(LPVOID lpParam);
void OnAiNpcInfoCloseClick(MyGUI::Widget *sender);
void OnAiDiarySelect(MyGUI::ListBox *sender, size_t index);
void OnAiDiaryEntrySelect(MyGUI::ListBox *sender, size_t index);
void OnAiDiaryWindowButtonPressed(MyGUI::Window *sender,
                                  const std::string &name);
DWORD WINAPI AiDiaryListThread(LPVOID lpParam);
DWORD WINAPI AiDiaryDetailThread(LPVOID lpParam);
DWORD WINAPI AiDiaryAudioThread(LPVOID lpParam);
void OnAiDiaryAudioClick(MyGUI::Widget *sender);
void OnAiDiaryCloseClick(MyGUI::Widget *sender);

} // namespace UI
} // namespace Stobe

