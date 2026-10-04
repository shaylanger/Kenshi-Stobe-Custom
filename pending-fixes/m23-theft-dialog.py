#!/usr/bin/env python3
"""m23 fixer 8: Stobe captures the game's theft dialog events as an engine detection signal (REL SR13/SR14).

Run m22 batch E (and D): SR13 seen got the stolen pickup (item_gain stolen_items, owner Rel Tess [Nomads] in w= with
sees_actor) but never a "theft hunt" line: no character took the HUNT_MY_THIEF goal (hunters=0 even after the harness
raised the crime with notifyCrimeWitnessed), and no theft hunt line exists in any of the 265 archived stobe logs, so
HUNT_MY_THIEF alone is an unproven signal. The game's other own detection path is the dialog event it sends when a
character catches a thief: EV_THIEF_CAUGHT_STEALING_FROM_ME (8) and EV_WITNESS_THIEF_OR_LOCKPICK (43)
(Dialogue::sendEvent / sendEventOverride, Character::sendDialogEvent / sendDialogEventOverride). Stobe now hooks the
four, logs "SOCIAL_CAPTURE: theft dialog ev=<name> speaker=<who caught> thief=<target> delivered=<0|1>" for those two
events, and posts the same theft_caught event as the HUNT_MY_THIEF check (actor = thief, target = the speaker,
"goal":"<event name>"), once per speaker/thief/event per 60 s. The hooks only compare an int for every other event.

Usage: python3 m23-theft-dialog.py <STOBE-src root>   (marker M23_THEFT_DIALOG)
"""
import pathlib, sys

MARK = 'M23_THEFT_DIALOG'
p = pathlib.Path(sys.argv[1]) / 'src/main.cpp'
s = p.read_text()
if MARK in s:
    print('already patched'); sys.exit(0)

FUNCS = r'''
// M23_THEFT_DIALOG (SR13): the game's own "caught a thief" dialog events (EV_THIEF_CAUGHT_STEALING_FROM_ME = the
// victim/owner caught him, EV_WITNESS_THIEF_OR_LOCKPICK = a witness saw it). actor = thief, target = speaker.
static std::map<std::string, DWORD> g_socialTheftDialogSeen;
static bool SocialIsTheftDialogEvent(int what) {
  return what == (int)EV_THIEF_CAUGHT_STEALING_FROM_ME || what == (int)EV_WITNESS_THIEF_OR_LOCKPICK;
}
static void SocialTheftDialog(Character *speaker, Character *thief, int what, bool delivered, const char *via) {
  if (!speaker || (uintptr_t)speaker < 0x1000 || !thief || (uintptr_t)thief < 0x1000 || speaker == thief ||
      !SocialCaptureEnabled())
    return;
  try {
    const char *ev = what == (int)EV_THIEF_CAUGHT_STEALING_FROM_ME ? "EV_THIEF_CAUGHT_STEALING_FROM_ME"
                                                                   : "EV_WITNESS_THIEF_OR_LOCKPICK";
    unsigned int ss = ResolveCharacterSerialForEvent(speaker), ts = ResolveCharacterSerialForEvent(thief);
    std::string key = ToString(ss) + ":" + ToString(ts) + ":" + ToString(what);
    DWORD now = GetTickCount();
    std::map<std::string, DWORD>::iterator seen = g_socialTheftDialogSeen.find(key);
    if (seen != g_socialTheftDialogSeen.end() && now - seen->second < 60000)
      return;
    if (g_socialTheftDialogSeen.size() > 512)
      g_socialTheftDialogSeen.clear();
    g_socialTheftDialogSeen[key] = now;
    int stolenCount = -1;
    std::string crime = "none";
    try {
      Inventory *inv = thief->getInventory();
      if (inv && (uintptr_t)inv > 0x1000) {
        lektor<Item *> stolen;
        inv->getAllStolenItems(stolen, false);
        stolenCount = (int)stolen.size();
      }
      if (thief->crimes.isCommittingCrime())
        crime = BountyManager::crimeToStr(thief->crimes.committingCrime);
    } catch (...) {
    }
    std::map<std::string, int> stolenByKey;
    std::map<unsigned int, NpcWorldEventState>::const_iterator st = g_npcWorldEventStateBySerial.find(ts);
    if (st != g_npcWorldEventStateBySerial.end())
      stolenByKey = st->second.inventory.stolenByKey;
    Log(std::string("SOCIAL_CAPTURE: theft dialog ev=") + ev + " speaker=" + ResolveCharacterNameSafe(speaker) +
        " thief=" + ResolveCharacterNameSafe(thief) + " delivered=" + (delivered ? "1" : "0") + " via=" + via +
        " stolen=" + ToString(stolenCount) + " crime=" + crime);
    StobeSocial::EntityInfo t = SocialEntityFor(thief), h = SocialEntityFor(speaker);
    SocialPostStructured("theft_caught", &t, &h,
                         std::string("\"goal\":") + StobeSocial::JsonString(ev) +
                             ",\"stolen_items\":" + StobeSocial::JsonCountMap(stolenByKey, 32) +
                             ",\"thief_stolen_count\":" + ToString(stolenCount) +
                             ",\"crime\":" + StobeSocial::JsonString(crime));
  } catch (...) {
  }
}
bool (*dialogueSendEvent_orig)(Dialogue *, Character *, EventTriggerEnum) = nullptr;
bool (*dialogueSendEventOverride_orig)(Dialogue *, Character *, EventTriggerEnum, bool) = nullptr;
bool (*charSendDialogEvent_orig)(Character *, Character *, EventTriggerEnum) = nullptr;
bool (*charSendDialogEventOverride_orig)(Character *, Character *, EventTriggerEnum, bool) = nullptr;
static Character *SocialDialogueOwner(Dialogue *d) {
  try {
    return d && (uintptr_t)d > 0x1000 ? d->getCharacter() : nullptr;
  } catch (...) {
    return nullptr;
  }
}
bool dialogueSendEvent_hook(Dialogue *d, Character *who, EventTriggerEnum what) {
  bool r = dialogueSendEvent_orig(d, who, what);
  if (SocialIsTheftDialogEvent((int)what))
    SocialTheftDialog(SocialDialogueOwner(d), who, (int)what, r, "Dialogue::sendEvent");
  return r;
}
bool dialogueSendEventOverride_hook(Dialogue *d, Character *who, EventTriggerEnum what, bool force) {
  bool r = dialogueSendEventOverride_orig(d, who, what, force);
  if (SocialIsTheftDialogEvent((int)what))
    SocialTheftDialog(SocialDialogueOwner(d), who, (int)what, r, "Dialogue::sendEventOverride");
  return r;
}
bool charSendDialogEvent_hook(Character *c, Character *who, EventTriggerEnum what) {
  bool r = charSendDialogEvent_orig(c, who, what);
  if (SocialIsTheftDialogEvent((int)what))
    SocialTheftDialog(c, who, (int)what, r, "Character::sendDialogEvent");
  return r;
}
bool charSendDialogEventOverride_hook(Character *c, Character *who, EventTriggerEnum what, bool force) {
  bool r = charSendDialogEventOverride_orig(c, who, what, force);
  if (SocialIsTheftDialogEvent((int)what))
    SocialTheftDialog(c, who, (int)what, r, "Character::sendDialogEventOverride");
  return r;
}

static void EmitLimbLossEvent(Character *victim, const std::string &limbLabel) {'''

INSTALL = r'''
  // M23_THEFT_DIALOG: the game's theft dialog events (SR13 engine detection signal)
  {
    struct TheftDialogHook { const char *sym; void *hook; void **orig; };
    TheftDialogHook hooks[] = {
      {"?sendEvent@Dialogue@@QEAA_NPEAVCharacter@@W4EventTriggerEnum@@@Z", (void *)dialogueSendEvent_hook,
       (void **)&dialogueSendEvent_orig},
      {"?sendEventOverride@Dialogue@@QEAA_NPEAVCharacter@@W4EventTriggerEnum@@_N@Z",
       (void *)dialogueSendEventOverride_hook, (void **)&dialogueSendEventOverride_orig},
      {"?sendDialogEvent@Character@@QEAA_NPEAV1@W4EventTriggerEnum@@@Z", (void *)charSendDialogEvent_hook,
       (void **)&charSendDialogEvent_orig},
      {"?sendDialogEventOverride@Character@@QEAA_NPEAV1@W4EventTriggerEnum@@_N@Z",
       (void *)charSendDialogEventOverride_hook, (void **)&charSendDialogEventOverride_orig},
    };
    for (size_t hi = 0; hi < sizeof(hooks) / sizeof(hooks[0]); ++hi) {
      void *thunk = (void *)GetProcAddress(hLib, hooks[hi].sym);
      __int64 real = thunk ? KenshiLib::GetRealAddress(thunk) : 0;
      if (!real) {
        Log(std::string("HOOK_WARN: theft dialog hook not found: ") + hooks[hi].sym);
        continue;
      }
      KenshiLib::HookStatus st = KenshiLib::AddHook((void *)real, hooks[hi].hook, hooks[hi].orig);
      Log(std::string("HOOK_DIAG: theft dialog hook ") + hooks[hi].sym + " status=" + ToString((int)st));
    }
  }

  void *thunkAiGetCharacter ='''

pairs = [
    ('\nstatic void EmitLimbLossEvent(Character *victim, const std::string &limbLabel) {', FUNCS),
    ('\n  void *thunkAiGetCharacter =', INSTALL),
]
for old, new in pairs:
    c = s.count(old)
    if c != 1:
        raise SystemExit(f'anchor found {c}x: {old[:80]!r}')
    s = s.replace(old, new, 1)
p.write_text(s)
print('patched', p)
