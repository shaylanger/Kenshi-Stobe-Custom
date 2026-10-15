#pragma once
#include <string>
namespace Stobe { namespace Activity {
// Game thread: actual accepted player manual/voice submission only.
std::string CaptureActivityChatTurn(unsigned actor, unsigned requester, const std::string& playerText);
// Existing chat HTTP worker; signed single-use ticket or ordinary chat on failure.
std::wstring PrepareActivityChatTurn(const std::string& turnId, const std::wstring& endpoint);
// Only after existing speech-delivery checks prove NPC speech was displayed.
void FinishActivityChatTurn(const std::string& turnId, bool displayed, const std::string& spokenText);
// Game thread. Queue one structured in-progress event (operation "event"; JSON object text built by
// Events::Tracker). Delivered best-effort, at most a few per poll, dropped after 3 failed sends or ~90 s.
void QueueActivityEvent(const std::string& agreementId, unsigned actor, unsigned requester, unsigned long gameNow, const std::string& eventJson);
void UpdateActivityTransport();
void ResetActivityTransport();
} }
