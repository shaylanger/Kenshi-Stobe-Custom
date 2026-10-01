#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>

namespace Stobe {
namespace EventPolicy {

// Serial event-stream lanes. Lower value is sent first.
enum Priority {
  PriorityHigh = 0,   // player-relevant outcomes: healing, trades, deaths, dialogue, actions
  PriorityNormal = 1, // everything else
  PriorityLow = 2     // repetitive combat telemetry ("X initiated attack on Y")
};

const int kPriorityCount = 3;

// Lane for a lower-cased game event type (as passed to LogGameEvent).
int PriorityForEventType(const std::string &normalizedType);

// Minimum gap between two sends of the same event key; 0 means never debounced.
std::uint32_t DebounceWindowMsForEventType(const std::string &normalizedType);

// Identity used for debouncing: type plus actor and target (serials when known).
std::string DebounceKey(const std::string &normalizedType,
                        const std::string &actor, unsigned int actorSerial,
                        const std::string &target, unsigned int targetSerial);

// Remembers when each key was last sent. Not thread-safe; callers lock.
class Debouncer {
public:
  explicit Debouncer(std::size_t maxEntries);

  // True when the key was sent less than windowMs ago; the caller then drops
  // the event. A dropped event does not extend the window, so a continuous
  // stream still sends one event per window. Tick wraparound is handled.
  bool ShouldDrop(const std::string &key, std::uint32_t nowMs,
                  std::uint32_t windowMs);

  std::uint32_t DroppedCount() const { return dropped_; }
  std::size_t Size() const { return lastSent_.size(); }

private:
  void Prune(std::uint32_t nowMs, std::uint32_t keepMs);

  std::map<std::string, std::uint32_t> lastSent_;
  std::size_t maxEntries_;
  std::uint32_t dropped_;
};

} // namespace EventPolicy
} // namespace Stobe
