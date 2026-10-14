#pragma once
#include <string>
namespace Stobe { namespace Activity {
// Game thread: actual accepted player manual/voice submission only.
std::string CaptureActivityChatTurn(unsigned actor, unsigned requester, const std::string& playerText);
// Existing chat HTTP worker; signed single-use ticket or ordinary chat on failure.
std::wstring PrepareActivityChatTurn(const std::string& turnId, const std::wstring& endpoint);
// Only after existing speech-delivery checks prove NPC speech was displayed.
void FinishActivityChatTurn(const std::string& turnId, bool displayed, const std::string& spokenText);
void UpdateActivityTransport();
void ResetActivityTransport();
} }
