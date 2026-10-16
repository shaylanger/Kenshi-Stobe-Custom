#!/usr/bin/env python3
"""NC25 FIX B (row 23-b, imm26-nat25): the legacy FOLLOW 24 h (FollowExpiryGameHours) safety net never fired.
Cause (code + evidence, see README): the expiry check sat AFTER the `if (!follower || !target) continue;` guard in
ApplyFollowTargets, and FindCharacterBySerial only searches world->getCharacterUpdateList() (loaded/simulated characters).
A follower far from the player (23-b state_after: distance_to_player 1551, no FOLLOW_TICK) is not resolved -> `continue`
before the expiry -> no FOLLOW_EXPIRED. The squad hypothesis is refuted: state_after faction="Traders Guild".
Fix: run the expiry before the loaded guard (squad status cached from the last time the follower was loaded; unknown = not
squad), restore jobs/speed/goals when the follower is (or later becomes) loaded, and log a rate-limited FOLLOW_DIAG line.
Usage: python3 nc25b_edit.py <tree>   (src/main.cpp, CRLF-safe; refuses a second run)."""
import sys, io
tree = sys.argv[1]
p = tree + "/src/main.cpp"
s = io.open(p, encoding="utf-8", newline="").read()
nl = "\r\n" if s.count("\r\n") * 2 > s.count("\n") else "\n"
assert "FOLLOW_DIAG" not in s, "NC25 B already applied"


def rep(old, new):
    global s
    o2, n2 = old.replace("\n", nl), new.replace("\n", nl)
    assert s.count(o2) == 1, "anchor count %d: %r" % (s.count(o2), old[:70])
    s = s.replace(o2, n2)


# 1. helper + pending-restore processing
rep('''bool TryApplyJobsToggleSafe(Character *npc, bool enabled, const std::string &label);

static void ApplyFollowTargets(GameWorld *world) {
''', '''bool TryApplyJobsToggleSafe(Character *npc, bool enabled, const std::string &label);

// NC25: undo the hard-follow lock after FOLLOW_EXPIRED (jobs, speed, goals).
static void RestoreAfterFollowExpiry(Character *follower) {
  TryApplyJobsToggleSafe(follower, true, "FOLLOW_EXPIRED_RESTORE_JOBS");
  try {
    CharMovement *movement = follower->getMovement();
    if (movement && (uintptr_t)movement > 0x1000) movement->restoreDesiredSpeed();
  } catch (...) {
  }
  try {
    follower->clearAllAIGoals();
    follower->reThinkCurrentAIAction();
  } catch (...) {
  }
}

static void ApplyFollowTargets(GameWorld *world) {
''')
rep('''  lastFollowTick = nowTick;

  std::map<unsigned int, hand> followSnapshot = SnapshotFollowTargets();
  if (followSnapshot.empty()) {
    return;
  }
''', '''  lastFollowTick = nowTick;

  // NC25: expired while the follower was not loaded; restore once it is.
  static std::set<unsigned int> s_followRestorePending;
  static std::map<unsigned int, bool> s_followSquadCache;
  static std::map<unsigned int, DWORD> s_followDiagTick;
  for (std::set<unsigned int>::iterator pend = s_followRestorePending.begin();
       pend != s_followRestorePending.end();) {
    Character *late = FindCharacterBySerial(world, *pend);
    if (late && (uintptr_t)late >= 0x1000) {
      RestoreAfterFollowExpiry(late);
      Log("FOLLOW_EXPIRED_RESTORED: follower=" + ToString(static_cast<int>(*pend)));
      s_followRestorePending.erase(pend++);
    } else {
      ++pend;
    }
  }

  std::map<unsigned int, hand> followSnapshot = SnapshotFollowTargets();
  if (followSnapshot.empty()) {
    return;
  }
''')

# 2. expiry before the loaded guard
rep('''    if (!follower || (uintptr_t)follower < 0x1000 || !target ||
        (uintptr_t)target < 0x1000) {
      continue;
    }
    if (follower == target) {
      ClearFollowTarget(followerSerial);
      continue;
    }

    // Safety net: a non-squad NPC must not follow forever (FollowExpiryGameHours, default 24).
    {
      bool squadMember = false;
      try {
        Faction *followerFaction = follower->getFaction();
        squadMember = followerFaction && followerFaction->isThePlayer();
      } catch (...) {
        squadMember = true; // unknown faction: never expire
      }
      long long followStart = 0;
      if (!squadMember && GetFollowStart(followerSerial, followStart) &&
          Stobe::FollowExpiry::ShouldExpire(followStart, CurrentGameTsSeconds(),
                                            FollowExpiryLimitGameSeconds(), false, false)) {
        Log("FOLLOW_EXPIRED: follower=" + ToString(followerSerial) + " started_gamets=" +
            ToString(static_cast<int>(followStart)) + " now_gamets=" + ToString(CurrentGameTsSeconds()));
        ClearFollowTarget(followerSerial);
        TryApplyJobsToggleSafe(follower, true, "FOLLOW_EXPIRED_RESTORE_JOBS");
        try {
          CharMovement *movement = follower->getMovement();
          if (movement && (uintptr_t)movement > 0x1000) movement->restoreDesiredSpeed();
        } catch (...) {
        }
        try {
          follower->clearAllAIGoals();
          follower->reThinkCurrentAIAction();
        } catch (...) {
        }
        continue;
      }
    }
''', '''    // Safety net: a non-squad NPC must not follow forever (FollowExpiryGameHours, default 24).
    // NC25 (23-b): runs BEFORE the loaded guard. FindCharacterBySerial only sees the world's update list, so a
    // follower left far behind was skipped by `continue` and its follow never expired. Squad status is cached from
    // the last time the follower was loaded (never seen = not squad).
    const bool followerLoaded = follower && (uintptr_t)follower >= 0x1000;
    {
      bool squadMember = false;
      if (followerLoaded) {
        try {
          Faction *followerFaction = follower->getFaction();
          squadMember = followerFaction && followerFaction->isThePlayer();
        } catch (...) {
          squadMember = true; // unknown faction: never expire
        }
        s_followSquadCache[followerSerial] = squadMember;
      } else {
        std::map<unsigned int, bool>::const_iterator cached = s_followSquadCache.find(followerSerial);
        squadMember = cached != s_followSquadCache.end() && cached->second;
      }
      long long followStart = 0;
      const bool haveStart = GetFollowStart(followerSerial, followStart);
      const int nowGameTs = CurrentGameTsSeconds();
      DWORD &lastDiagTick = s_followDiagTick[followerSerial];
      if (nowTick - lastDiagTick >= 60000) {
        lastDiagTick = nowTick;
        Log("FOLLOW_DIAG: follower=" + ToString(static_cast<int>(followerSerial)) + " loaded=" +
            std::string(followerLoaded ? "1" : "0") + " squad=" + std::string(squadMember ? "1" : "0") +
            " start=" + (haveStart ? ToString(static_cast<int>(followStart)) : std::string("none")) +
            " now=" + ToString(nowGameTs) + " limit_s=" + ToString(static_cast<int>(FollowExpiryLimitGameSeconds())));
      }
      if (!squadMember && haveStart &&
          Stobe::FollowExpiry::ShouldExpire(followStart, nowGameTs,
                                            FollowExpiryLimitGameSeconds(), false, false)) {
        Log("FOLLOW_EXPIRED: follower=" + ToString(followerSerial) + " started_gamets=" +
            ToString(static_cast<int>(followStart)) + " now_gamets=" + ToString(nowGameTs) +
            " loaded=" + (followerLoaded ? "1" : "0"));
        ClearFollowTarget(followerSerial);
        s_followSquadCache.erase(followerSerial);
        s_followDiagTick.erase(followerSerial);
        if (followerLoaded) {
          RestoreAfterFollowExpiry(follower);
        } else {
          s_followRestorePending.insert(followerSerial);
        }
        continue;
      }
    }

    if (!followerLoaded || !target || (uintptr_t)target < 0x1000) {
      continue;
    }
    if (follower == target) {
      ClearFollowTarget(followerSerial);
      continue;
    }
''')
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("nc25b_edit applied")
