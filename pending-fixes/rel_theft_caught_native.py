#!/usr/bin/env python3
"""REL SR09/SR13/SR14 native capture (run m18): the theft-caught signal.

Usage: python3 rel_theft_caught_native.py <STOBE-src root (has src/main.cpp)>
Asserts every anchor; refuses to run twice (marker REL_THEFT_CAUGHT_M18).

- new structured kind theft_caught: a character whose current goal (OrdersReceiver::currentGoal) is HUNT_MY_THIEF
  reports actor = thief, target = hunter, once per pair (again after 5 min real time while it lasts); facts: goal,
  stolen_items (thief's stolen-flagged items by key), thief_stolen_count, thief_bounty, crime. Log line
  "SOCIAL_CAPTURE: theft hunt hunter=... thief=..."
- item_gain (gain without a matching loss: shop/world goods, looting a KO'd body) carries stolen_items (the
  stolen-flagged part of the gain) and the witnesses (who saw the taker)
- item_transfer carries witnesses (who saw the taker), for SR09 better evidence
Server side: StobeServer cb3bc44 (kind theft_caught accepted there).
"""
import pathlib, sys

MARK = 'REL_THEFT_CAUGHT_M18'
root = pathlib.Path(sys.argv[1]) / 'src'


def patch(rel, pairs):
    p = root / rel
    s = p.read_text(encoding='utf-8', errors='surrogateescape')
    for old, new in pairs:
        n = s.count(old)
        if n != 1:
            raise SystemExit(f'{rel}: anchor found {n}x: {old[:90]!r}')
        s = s.replace(old, new)
    p.write_text(s, encoding='utf-8', errors='surrogateescape')
    print('patched', rel)


if MARK in (root / 'main.cpp').read_text(encoding='utf-8', errors='surrogateescape'):
    raise SystemExit('already applied')

patch('SocialEventProtocol.cpp', [(
    '"eat","trade","item_gain"};',
    '"eat","trade","item_gain","theft_caught"};')])

main_pairs = [
    ('#include <kenshi/SensoryData.h>\n',
     '#include <kenshi/SensoryData.h>\n#include <kenshi/AI/AITaskSystem.h> // REL_THEFT_CAUGHT_M18: OrdersReceiver::currentGoal\n#include <kenshi/BountyManager.h>\n'),
    # item_gain: stolen part + witnesses
    ('          SocialPostStructured("item_gain", &gainer, nullptr, "\\"items\\":" + StobeSocial::JsonCountMap(gained, 8));\n',
     '          // REL_THEFT_CAUGHT_M18: the stolen-flagged part of the gain (shop/world goods) and who saw the taker.\n'
     '          int stolenGain = 0;\n'
     '          {\n'
     '            std::map<std::string, int>::const_iterator sa = toDelta.afterSnapshot.stolenByKey.find(itemKey);\n'
     '            std::map<std::string, int>::const_iterator sb = toDelta.beforeSnapshot.stolenByKey.find(itemKey);\n'
     '            stolenGain = (sa != toDelta.afterSnapshot.stolenByKey.end() ? sa->second : 0) -\n'
     '                         (sb != toDelta.beforeSnapshot.stolenByKey.end() ? sb->second : 0);\n'
     '            if (stolenGain > gainRemaining)\n'
     '              stolenGain = gainRemaining;\n'
     '            if (stolenGain < 0)\n'
     '              stolenGain = 0;\n'
     '          }\n'
     '          std::map<std::string, int> stolenGained;\n'
     '          if (stolenGain > 0)\n'
     '            stolenGained[itemKey] = stolenGain;\n'
     '          std::vector<StobeSocial::EntityInfo> gainWho;\n'
     '          std::vector<int> gainSense;\n'
     '          // Who saw the taker: SR09 evidence when he loots a knocked-out body (only the gain shows then).\n'
     '          SocialCollectWitnesses(toDelta.npc, toDelta.npc, gainWho, gainSense);\n'
     '          SocialPostStructuredW("item_gain", &gainer, nullptr,\n'
     '                                "\\"items\\":" + StobeSocial::JsonCountMap(gained, 8) +\n'
     '                                    ",\\"stolen_items\\":" + StobeSocial::JsonCountMap(stolenGained, 8),\n'
     '                                gainWho, gainSense);\n'),
    # item_transfer: witnesses
    ('            SocialPostStructured("item_transfer", isGroundDrop ? nullptr : &taker, &loser,\n',
     '            // REL_THEFT_CAUGHT_M18 (SR09): who saw the taker take it.\n'
     '            std::vector<StobeSocial::EntityInfo> transferWho;\n'
     '            std::vector<int> transferSense;\n'
     '            if (!isGroundDrop && toChar && fromChar)\n'
     '              SocialCollectWitnesses(toChar, fromChar, transferWho, transferSense);\n'
     '            SocialPostStructuredW("item_transfer", isGroundDrop ? nullptr : &taker, &loser,\n'),
    ('                                     ",\\"loser_hunger\\":" + loserHunger);\n',
     '                                     ",\\"loser_hunger\\":" + loserHunger,\n'
     '                                 transferWho, transferSense);\n'),
    # the hunt watch (definition)
    ('static void EmitLimbLossEvent(Character *victim, const std::string &limbLabel) {\n',
     '// REL_THEFT_CAUGHT_M18 (SR13): the game\'s own "caught a thief" signal. A character whose current goal is\n'
     '// HUNT_MY_THIEF reports it once per hunter/thief pair (again after 5 min real time while it lasts):\n'
     '// actor = thief, target = hunter. The server pairs it with the stolen goods.\n'
     'static std::map<unsigned long long, DWORD> g_socialTheftHunts;\n'
     'static void SocialTheftHuntCheck(Character *hunter, unsigned int hunterSerial, DWORD now) {\n'
     '  if (!hunter || (uintptr_t)hunter < 0x1000 || !SocialCaptureEnabled())\n'
     '    return;\n'
     '  hand subject;\n'
     '  try {\n'
     '    OrdersReceiver *orders = hunter->getOrdersReciever();\n'
     '    if (!orders || (uintptr_t)orders < 0x1000 || !orders->currentGoal.taskData)\n'
     '      return;\n'
     '    if (orders->currentGoal.key() != HUNT_MY_THIEF)\n'
     '      return;\n'
     '    subject = orders->currentGoal.subject;\n'
     '  } catch (...) {\n'
     '    return;\n'
     '  }\n'
     '  Character *thief = nullptr;\n'
     '  try {\n'
     '    if (subject.isValid() && !subject.isNull())\n'
     '      thief = subject.getCharacter();\n'
     '  } catch (...) {\n'
     '    thief = nullptr;\n'
     '  }\n'
     '  if (!thief || (uintptr_t)thief < 0x1000 || thief == hunter)\n'
     '    return;\n'
     '  unsigned int thiefSerial = ResolveCharacterSerialForEvent(thief);\n'
     '  unsigned long long key = ((unsigned long long)hunterSerial << 32) | (unsigned long long)thiefSerial;\n'
     '  std::map<unsigned long long, DWORD>::iterator seen = g_socialTheftHunts.find(key);\n'
     '  if (seen != g_socialTheftHunts.end() && now - seen->second < 300000)\n'
     '    return;\n'
     '  if (g_socialTheftHunts.size() > 512)\n'
     '    g_socialTheftHunts.clear();\n'
     '  g_socialTheftHunts[key] = now;\n'
     '  int stolenCount = -1, bounty = -1;\n'
     '  std::string crime = "none";\n'
     '  try {\n'
     '    Inventory *inv = thief->getInventory();\n'
     '    if (inv && (uintptr_t)inv > 0x1000) {\n'
     '      lektor<Item *> stolen;\n'
     '      inv->getAllStolenItems(stolen, false);\n'
     '      stolenCount = (int)stolen.size();\n'
     '    }\n'
     '  } catch (...) {\n'
     '  }\n'
     '  try {\n'
     '    BountyManager &b = thief->crimes;\n'
     '    bounty = b.getTotalBounty();\n'
     '    if (b.isCommittingCrime())\n'
     '      crime = BountyManager::crimeToStr(b.committingCrime);\n'
     '  } catch (...) {\n'
     '  }\n'
     '  std::map<std::string, int> stolenByKey;\n'
     '  std::map<unsigned int, NpcWorldEventState>::const_iterator ts = g_npcWorldEventStateBySerial.find(thiefSerial);\n'
     '  if (ts != g_npcWorldEventStateBySerial.end())\n'
     '    stolenByKey = ts->second.inventory.stolenByKey;\n'
     '  Log("SOCIAL_CAPTURE: theft hunt hunter=" + ResolveCharacterNameSafe(hunter) + " thief=" + ResolveCharacterNameSafe(thief) +\n'
     '      " stolen=" + ToString(stolenCount) + " bounty=" + ToString(bounty) + " crime=" + crime);\n'
     '  StobeSocial::EntityInfo t = SocialEntityFor(thief), h = SocialEntityFor(hunter);\n'
     '  SocialPostStructured("theft_caught", &t, &h,\n'
     '                       "\\"goal\\":\\"HUNT_MY_THIEF\\",\\"stolen_items\\":" + StobeSocial::JsonCountMap(stolenByKey, 32) +\n'
     '                           ",\\"thief_stolen_count\\":" + ToString(stolenCount) + ",\\"thief_bounty\\":" + ToString(bounty) +\n'
     '                           ",\\"crime\\":" + StobeSocial::JsonString(crime));\n'
     '}\n\n'
     'static void EmitLimbLossEvent(Character *victim, const std::string &limbLabel) {\n'),
    # the hunt watch (call, in the NPC sweep)
    ('    if (currentTaskSubjectSerialNow != 0 && IsLiberationTask((int)currentTaskNow)) {\n',
     '    SocialTheftHuntCheck(npc, serial, nowTick); // REL_THEFT_CAUGHT_M18\n'
     '    if (currentTaskSubjectSerialNow != 0 && IsLiberationTask((int)currentTaskNow)) {\n'),
]
patch('main.cpp', main_pairs)
print('done')
