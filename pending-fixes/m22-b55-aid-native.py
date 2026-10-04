#!/usr/bin/env python3
"""m22 B55 treat (native): the player's first aid on a KO'd bandit never became a REL 'aid' fact (no structured
kind=aid with Shay as provider in ANY archived run). The aid session map refused new sessions at 64 open ones, and
after every load ~40-50 world medics open sessions at once; a refused or unresolved session vanished silently.
Fix: cap 512, a session involving a player character is always admitted, and refusals / unresolved flushes are logged.
Usage: python3 m22-b55-aid-native.py [/root/STOBE-src]   (asserts anchors, idempotent)"""
import sys
root = sys.argv[1] if len(sys.argv) > 1 else '/root/STOBE-src'
p = root + '/src/main.cpp'
s = open(p, encoding='utf-8').read()
marker = 'm22 B55: aid sessions never drop'
if marker in s:
    print('skip: already patched'); sys.exit(0)
def rep(old, new):
    global s
    assert s.count(old) == 1, ('anchor', old[:80], s.count(old))
    s = s.replace(old, new)
rep('''  std::map<unsigned long long, SocialAidSession>::iterator it = g_socialAidSessions.find(key);
  if (it == g_socialAidSessions.end() && g_socialAidSessions.size() < 64) {''',
'''  // m22 B55: aid sessions never drop the squad's first aid (a load opens ~50 world sessions at once; the old cap
  // was 64 and a refused session vanished silently).
  bool squadAid = false;
  try {
    squadAid = provider->isPlayerCharacter() || recipient->isPlayerCharacter();
  } catch (...) {
  }
  std::map<unsigned long long, SocialAidSession>::iterator it = g_socialAidSessions.find(key);
  bool refused = false;
  if (it == g_socialAidSessions.end() && !squadAid && g_socialAidSessions.size() >= 512) {
    refused = true;
  } else if (it == g_socialAidSessions.end()) {''')
rep('''    g_socialAidSessions[key] = s;
  } else if (it != g_socialAidSessions.end()) {
    it->second.lastTick = now;
  }
  LeaveCriticalSection(&g_eventMutex);
}''', '''    g_socialAidSessions[key] = s;
  } else {
    it->second.lastTick = now;
  }
  size_t open = g_socialAidSessions.size();
  LeaveCriticalSection(&g_eventMutex);
  static DWORD lastRefusedLog = 0;
  if (refused && now - lastRefusedLog > 10000) {
    lastRefusedLog = now;
    Log("SOCIAL_AID: session refused (" + ToString((unsigned int)open) + " open) provider=#" + ToString(ps) +
        " recipient=#" + ToString(rs));
  }
  if (squadAid && it == g_socialAidSessions.end())
    Log("SOCIAL_AID: squad session provider=#" + ToString(ps) + " recipient=#" + ToString(rs) + " item=" + item);
}''')
rep('''    if (!provider || !recipient || provider == recipient)
      continue; // self-treatment builds no relationship''',
'''    if (!provider || !recipient) {
      Log("SOCIAL_AID: dropped unresolved session provider=#" + ToString(s.provider) + (provider ? "" : "(gone)") +
          " recipient=#" + ToString(s.recipient) + (recipient ? "" : "(gone)"));
      continue;
    }
    if (provider == recipient)
      continue; // self-treatment builds no relationship''')
open(p, 'w', encoding='utf-8').write(s)
print('patched', p)
