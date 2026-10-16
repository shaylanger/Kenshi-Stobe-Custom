#pragma once
// NC27B (imm26-huntA1, Shay 2026-10-16): retry policy for the "I am giving up" line after an activity FAILED.
// Pure, std only (C++03 safe) so it is unit-tested without the game (tests/cpp/activity_ending_speech_policy_tests.cpp).
// The server records the failed outcome as a situated event when it accepts the terminal report; the game thread then asks the actor for
// one targeted optional turn (TriggerOptionalBoredTurn, the path the N2 proximity watch uses). Wall-clock milliseconds (GetTickCount).
namespace Stobe { namespace Activity { namespace EndingSpeechPolicy {
enum Action { Wait, Dispatch, Expire };
static const unsigned int kSettleMs = 1500;   // after the server accepted the report, give it a moment to store the event
static const unsigned int kRetryMs = 3000;    // gates closed (TTS playing, other AI request, ...) or dispatch refused: try again
static const unsigned int kGiveUpMs = 90000;  // stop asking; the event stays claimable by an ordinary bored turn for its server TTL
inline Action Decide(unsigned int nowMs, unsigned int queuedMs, unsigned int dueMs, bool gatesOpen) {
  if (nowMs - queuedMs >= kGiveUpMs) return Expire;       // unsigned subtraction: tick wrap safe
  if (static_cast<int>(nowMs - dueMs) < 0) return Wait;
  return gatesOpen ? Dispatch : Wait;
}
inline unsigned int NextDue(unsigned int nowMs) { return nowMs + kRetryMs; }
} } }
