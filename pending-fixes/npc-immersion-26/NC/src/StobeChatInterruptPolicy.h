#pragma once
// Danger interrupts vs. in-flight chat replies (m50 D86, 2026-10-07).
//
// A danger interrupt (server lifelike_interrupt.flag on combat/knockout/...,
// or the squad entering combat) cuts speech/TTS by bumping the chat generation.
// Before this policy every stale-generation stream line aborted the HTTP read,
// so the action lines of the same reply (deal STOP_ATTACK, GIVE_CATS, ...) were
// dropped while the server had already recorded the deal as dispatched. Mid-fight
// every attack event re-fired the interrupt, so a truce reply could never land.
//
// Rules (no Kenshi types here; tests/cpp/chat_interrupt_policy_tests.cpp):
//  1. A reply superseded only by danger interrupts keeps reading: its speech is
//     dropped, its action lines are still queued (actions-only mode).
//  2. A hard interrupt (new player message, chat cancel, director scene, ...)
//     still ends the reply completely, actions included.
//  3. Director scenes never continue after any interrupt.
//  4. A danger interrupt whose recent danger events all come from NPCs we are
//     currently waiting on a reply from (e.g. the bandit we are negotiating a
//     truce with) is skipped: that reply plays in full.

namespace StobeChatInterrupt {

enum LineDecision {
  LINE_PROCESS = 0,      // generation current: speech + actions
  LINE_ACTIONS_ONLY = 1, // superseded by danger only: actions yes, speech no
  LINE_ABORT = 2         // hard interrupt (or director): stop reading
};

// streamGen: the reply's generation; currentGen: the global chat generation;
// lastHardGen: the generation set by the most recent hard interrupt.
inline LineDecision DecideStreamLine(long streamGen, long currentGen,
                                     long lastHardGen, bool director,
                                     bool interactionAllowed) {
  if (!interactionAllowed) return LINE_ABORT;
  if (streamGen == currentGen) return LINE_PROCESS;
  if (director) return LINE_ABORT;
  if (streamGen <= 0) return LINE_ABORT;
  if (streamGen >= lastHardGen) return LINE_ACTIONS_ONLY;
  return LINE_ABORT;
}

struct DangerActor {
  unsigned int serial;
  unsigned long ageMs;
};

// True when the danger interrupt should be skipped: at least one danger event
// within windowMs and every such event's actor is an active chat partner.
// isPartner(serial) answers "are we waiting on a reply from this NPC".
template <typename PartnerPred>
inline bool ShouldSkipDangerInterrupt(const DangerActor *actors, int count,
                                      unsigned long windowMs,
                                      PartnerPred isPartner) {
  int recent = 0;
  for (int i = 0; i < count; ++i) {
    if (actors[i].ageMs > windowMs) continue;
    if (actors[i].serial == 0) return false;
    ++recent;
    if (!isPartner(actors[i].serial)) return false;
  }
  return recent > 0;
}

} // namespace StobeChatInterrupt
