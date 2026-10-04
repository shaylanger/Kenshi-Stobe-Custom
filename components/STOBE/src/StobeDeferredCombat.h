#pragma once

// Crash 2026-10-04 (kenshi_x64+0x5C8820, Character::getCombatClass on null):
// CombatClassAI::decisionState calls CombatClass::setAttackTarget(t), which
// stores currentTarget and then calls t->attackingYou(me, true, true). Our
// attackingYou/attackTarget hooks used to run the ceasefire reject right there
// (endCombatMode, attackingYou(false), taskImpossible, reThink...), which
// cleared the attacker's currentTarget; decisionState then read it again in
// isInMeiDistance and dereferenced null. The hooks must only suppress the event
// and queue the pair; the main-thread action pump applies the reject later.
//
// Portable (no Kenshi types) so the offline tests cover it. Not thread-safe:
// the caller holds a lock around Push/TakeAll.

#include <cstddef>
#include <string>
#include <vector>

namespace Stobe {

struct DeferredCombatReject {
  unsigned int attackerSerial;
  unsigned int targetSerial;
  std::string gate;
};

class DeferredCombatRejectQueue {
public:
  explicit DeferredCombatRejectQueue(size_t capacity = 256)
      : capacity_(capacity), dropped_(0) {}

  // Returns true when the pair was queued; false for a zero serial, a pair
  // already waiting (same attacker and target), or a full queue (counted).
  bool Push(unsigned int attackerSerial, unsigned int targetSerial,
            const std::string &gate) {
    if (attackerSerial == 0 || targetSerial == 0) {
      return false;
    }
    for (size_t i = 0; i < items_.size(); ++i) {
      if (items_[i].attackerSerial == attackerSerial &&
          items_[i].targetSerial == targetSerial) {
        return false;
      }
    }
    if (items_.size() >= capacity_) {
      ++dropped_;
      return false;
    }
    DeferredCombatReject item;
    item.attackerSerial = attackerSerial;
    item.targetSerial = targetSerial;
    item.gate = gate;
    items_.push_back(item);
    return true;
  }

  // Moves every queued pair into out (in queue order) and empties the queue.
  void TakeAll(std::vector<DeferredCombatReject> &out) {
    out.clear();
    out.swap(items_);
  }

  size_t Size() const { return items_.size(); }
  size_t Dropped() const { return dropped_; }

private:
  size_t capacity_;
  size_t dropped_;
  std::vector<DeferredCombatReject> items_;
};

} // namespace Stobe
