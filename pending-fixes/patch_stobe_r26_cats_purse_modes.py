#!/usr/bin/env python3
"""Cap tiers (Stobe.dll): GIVE_CATS purse modes.

GIVE_CATS@<target>@<amount>@topup: a tier 3-5 NPC (elite, leader, ruler) pays the agreed
amount even when she carries less: her purse is topped up just before paying.
GIVE_CATS@<target>@<amount>@exact: a tier 0-2 NPC pays all or nothing: with too little
she pays nothing and the log says "skipped reason=insufficient" (the server marks the
term IMPOSSIBLE), instead of silently paying what she has.
Without a suffix, nothing changes (min(requested, available), as before).

Usage: patch_stobe_r26_cats_purse_modes.py <STOBE-src root>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])


def patch(rel, marker, pairs):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', f)
        return
    for old, new in pairs:
        assert s.count(old) == 1, f'{rel}: anchor not unique/missing: {old[:70]!r}'
        s = s.replace(old, new)
    assert marker in s, f'{rel}: marker missing after patch'
    f.write_text(s, encoding='utf-8')
    print('patched', f)


patch('src/Globals.h', 'catsMode', [(
    "  std::string autonomyDecisionId; // Set only for validated autonomy actions.\n",
    "  std::string autonomyDecisionId; // Set only for validated autonomy actions.\n"
    "  std::string catsMode; // GIVE_CATS purse mode: \"topup\", \"exact\" or empty (cap tiers).\n",
)])

patch('src/main.cpp', 'GIVE_CATS purse mode', [(
    '''          } else if (actionCommand == "GIVE_CATS") {
            std::string catsTargetToken = "";
            int catsAmount = 0;
            if (!parseCatsPayload(actionArgument, catsTargetToken, catsAmount)) {''',
    '''          } else if (actionCommand == "GIVE_CATS") {
            std::string catsTargetToken = "";
            int catsAmount = 0;
            // Cap tiers: GIVE_CATS purse mode, a trailing @topup / @exact.
            std::string catsMode = "";
            {
              size_t modeAt = actionArgument.rfind('@');
              if (modeAt != std::string::npos) {
                std::string tail = TrimCopy(actionArgument.substr(modeAt + 1));
                for (size_t i = 0; i < tail.size(); ++i)
                  tail[i] = (char)tolower((unsigned char)tail[i]);
                if (tail == "topup" || tail == "exact") {
                  catsMode = tail;
                  actionArgument = actionArgument.substr(0, modeAt);
                }
              }
            }
            if (!parseCatsPayload(actionArgument, catsTargetToken, catsAmount)) {'''
), (
    '''            act.type = ACT_GIVE_CATS;
            act.actor = targetHand;
            act.target = catsTarget;
            act.message = catsTargetToken;
            act.taskValue = catsAmount;''',
    '''            act.type = ACT_GIVE_CATS;
            act.actor = targetHand;
            act.target = catsTarget;
            act.message = catsTargetToken;
            act.taskValue = catsAmount;
            act.catsMode = catsMode;'''
)])

patch('src/Functions.cpp', 'reason=insufficient', [(
    '''            int actorMoney = npc->getMoney();
            if (actorMoney <= 0 && npc->getOwnerships()) {
              actorMoney = npc->getOwnerships()->getMoney();
            }
            int amt = (act.taskValue > actorMoney) ? actorMoney : act.taskValue;
            bool actorIsPlayer = false;''',
    '''            int actorMoney = npc->getMoney();
            if (actorMoney <= 0 && npc->getOwnerships()) {
              actorMoney = npc->getOwnerships()->getMoney();
            }
            if (act.catsMode == "topup" && act.taskValue > actorMoney) {
              // Cap tiers 3-5: the rest is brought; top her purse up to the agreed amount.
              int added = act.taskValue - actorMoney;
              npc->takeMoney(-added);
              Log("ACTION_EXEC: GIVE_CATS topup actor=" + SafeCharacterName(npc) +
                  " added=" + ToString(added) + " had=" + ToString(actorMoney));
              actorMoney = npc->getMoney();
              if (actorMoney <= 0 && npc->getOwnerships()) {
                actorMoney = npc->getOwnerships()->getMoney();
              }
            }
            int amt = (act.taskValue > actorMoney) ? actorMoney : act.taskValue;
            bool actorIsPlayer = false;'''
), (
    '''            if (actorIsPlayer && act.taskValue > actorMoney) {''',
    '''            if (!actorIsPlayer && act.catsMode == "exact" && act.taskValue > actorMoney) {
              // Cap tiers 0-2: all or nothing, never a silent part payment.
              thisptr->showPlayerAMessage_withLog(
                  SafeCharacterName(npc) + " only has " + ToString(actorMoney) + " cats.", true);
              Log("ACTION_EXEC: GIVE_CATS actor=" + SafeCharacterName(npc) +
                  " skipped reason=insufficient requested=" + ToString(act.taskValue) +
                  " available=" + ToString(actorMoney));
            } else if (actorIsPlayer && act.taskValue > actorMoney) {'''
)])
