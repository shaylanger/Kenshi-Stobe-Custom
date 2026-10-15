#include "StobeEventPolicy.h"

#include <sstream>

namespace Stobe {
namespace EventPolicy {

namespace {

bool IsOneOf(const std::string &value, const char *const *list, std::size_t count) {
  for (std::size_t i = 0; i < count; ++i) {
    if (value == list[i]) {
      return true;
    }
  }
  return false;
}

} // namespace

int PriorityForEventType(const std::string &normalizedType) {
  static const char *const kHigh[] = {
      "init",        "chat",       "rechat",     "inputtext",   "inputtext_s",
      "injection",   "action",     "infoaction", "healing",     "trade",
      "item_pickup", "carry",      "slavery",    "death",       "knockout",
      "recovered",   "limb_loss",  "horn_cut",   "combat_start", "combat_end",
      "lockpicked",  "recruit",    "relationship"};
  static const char *const kLow[] = {"combat"};
  if (IsOneOf(normalizedType, kHigh, sizeof(kHigh) / sizeof(kHigh[0]))) {
    return PriorityHigh;
  }
  if (IsOneOf(normalizedType, kLow, sizeof(kLow) / sizeof(kLow[0]))) {
    return PriorityLow;
  }
  return PriorityNormal;
}

std::uint32_t DebounceWindowMsForEventType(const std::string &normalizedType) {
  // Short on purpose: the server must still see an attack resume after a truce.
  if (normalizedType == "combat") {
    return 4000;
  }
  if (normalizedType == "major_damage") {
    return 3000;
  }
  return 0;
}

std::string DebounceKey(const std::string &normalizedType,
                        const std::string &actor, unsigned int actorSerial,
                        const std::string &target, unsigned int targetSerial) {
  std::ostringstream key;
  key << normalizedType << '|';
  if (actorSerial != 0) {
    key << '#' << actorSerial;
  } else {
    key << actor;
  }
  key << '|';
  if (targetSerial != 0) {
    key << '#' << targetSerial;
  } else {
    key << target;
  }
  return key.str();
}

Debouncer::Debouncer(std::size_t maxEntries)
    : maxEntries_(maxEntries < 16 ? 16 : maxEntries), dropped_(0) {}

bool Debouncer::ShouldDrop(const std::string &key, std::uint32_t nowMs,
                           std::uint32_t windowMs) {
  if (windowMs == 0) {
    return false;
  }
  std::map<std::string, std::uint32_t>::iterator it = lastSent_.find(key);
  if (it != lastSent_.end() && (std::uint32_t)(nowMs - it->second) < windowMs) {
    ++dropped_;
    return true;
  }
  lastSent_[key] = nowMs;
  if (lastSent_.size() > maxEntries_) {
    Prune(nowMs, windowMs);
  }
  return false;
}

void Debouncer::Prune(std::uint32_t nowMs, std::uint32_t keepMs) {
  std::map<std::string, std::uint32_t>::iterator it = lastSent_.begin();
  while (it != lastSent_.end()) {
    if ((std::uint32_t)(nowMs - it->second) >= keepMs) {
      lastSent_.erase(it++);
    } else {
      ++it;
    }
  }
  // Still full of live keys: forget everything rather than grow without bound.
  if (lastSent_.size() > maxEntries_) {
    lastSent_.clear();
  }
}

} // namespace EventPolicy
} // namespace Stobe
