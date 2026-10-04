#!/usr/bin/env python3
"""B 55 item 7 (native): the REL 'recovered' fact carries the victim's vitals on waking (health/blood/bleed/wound/untreated),
so the server can tell "knocked out, moderate wounds" from "wakes up with severe wounds, bleeding out" (critical_harm).
Usage: python3 b55_recovered_vitals_native.py [/root/STOBE-src]   (idempotent, asserts its anchor)"""
import sys

root = sys.argv[1] if len(sys.argv) > 1 else '/root/STOBE-src'
path = root + '/src/main.cpp'
text = open(path, encoding='utf-8').read()
marker = 'B 55: vitals on waking'
old = '''    StobeSocial::EntityInfo target = SocialEntityFor(victim);
    SocialPostStructured("recovered", nullptr, &target, SocialInventoryFacts(inventory, money));'''
new = '''    StobeSocial::EntityInfo target = SocialEntityFor(victim);
    // B 55: vitals on waking (server: bleeding out / near death on waking = critical_harm in the attacker's fight budget).
    std::string facts = SocialInventoryFacts(inventory, money);
    facts += (facts.empty() ? "" : ",") + SocialVitalsFacts("", victim);
    SocialPostStructured("recovered", nullptr, &target, facts);'''
if marker in text:
    print('skip: already patched')
else:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'ANCHOR main.cpp found {n}x')
    open(path, 'w', encoding='utf-8', newline='').write(text.replace(old, new, 1))
    print('patched src/main.cpp (EmitRecoveredEvent)')
