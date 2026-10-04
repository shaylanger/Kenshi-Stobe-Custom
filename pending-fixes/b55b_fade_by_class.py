#!/usr/bin/env python3
"""B 55 item 1 follow-up (Shay 2026-10-03, plan 94761de): a fight grudge fades or not by WHAT HAPPENED (severity class
before the closeness multiplier), never by the size of the penalty. SOCIAL_GRUDGE_FADE_THRESHOLD is removed.
Usage: python3 b55b_fade_by_class.py <StobeServer tree with b55_fights_server.py applied>   (idempotent)
Copies the updated lib/social_fights.php, tests/social_fights_regression.php, rel-b55.sh from pending-fixes."""
import json
import os
import shutil
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '/var/www/html/StobeServer'
HERE = os.path.dirname(os.path.abspath(__file__))


def patch(rel, old, new, marker):
    path = os.path.join(ROOT, rel)
    text = open(path, encoding='utf-8').read()
    if marker in text or (new == '' and old not in text):  # removal hunks: done when the old text is gone
        print(f'skip  {rel}: {marker[:50]}')
        return
    if text.count(old) != 1:
        raise SystemExit(f'ANCHOR {rel}: found {text.count(old)}x: {old[:100]!r}')
    open(path, 'w', encoding='utf-8').write(text.replace(old, new, 1))
    print(f'patch {rel}: {marker[:50]}')


S = 'lib/social_store.php'
patch(S, """     * B 55 item 1: forgiveness over time, event-based. Each fight incident (per observer -> culprit) is its own grudge;
     * one with no knockout or worse and an unscaled worst charge of at most SOCIAL_GRUDGE_FADE_THRESHOLD fades back
     * linearly over SOCIAL_GRUDGE_FADE_DAYS game days (what treatment/deals already won back is not faded twice).""",
      """     * B 55 item 1: forgiveness over time, decided by what happened. Each fight incident (per observer -> culprit) is its
     * own grudge; one with no knockout or worse (STOBE_SOCIAL_NEVER_FADE, accidental KO/limb) fades back linearly over
     * SOCIAL_GRUDGE_FADE_DAYS game days whatever its size (what treatment/deals already won back is not faded twice).""",
      'B 55 item 1: forgiveness over time, decided by what happened')
patch(S, "        [$threshold, $days] = stobeSocialFadeSettings($this->rules);", "        $days = stobeSocialFadeDays($this->rules);",
      '$days = stobeSocialFadeDays($this->rules);')
patch(S, """              MIN(CASE WHEN component = ANY(\\$2::text[]) THEN COALESCE((detail->>'unscaled')::int, (detail->>'total')::int, delta) END) AS worst,
""", "", "@@never-present@@")
patch(S, "            if ($g['never'] === 't' || (int)$g['worst'] < -$threshold || $g['observer_key'] === null) continue;",
      "            if ($g['never'] === 't' || $g['observer_key'] === null) continue; // severity class, never the size (Shay 94761de)",
      'severity class, never the size (Shay 94761de)')

T = 'tools/social_relationship_inspect.php'
patch(T, """ *   php tools/social_relationship_inspect.php --set-switch SOCIAL_FIGHTS_LIVE|SOCIAL_FIGHT_RULES|SOCIAL_GRUDGE_FADE_DAYS|SOCIAL_GRUDGE_FADE_THRESHOLD <value|off>
 *                                                  B 55 settings (off = back to the default: live, b55, 14 days, 30)""",
      """ *   php tools/social_relationship_inspect.php --set-switch SOCIAL_FIGHTS_LIVE|SOCIAL_FIGHT_RULES|SOCIAL_GRUDGE_FADE_DAYS <value|off>
 *                                                  B 55 settings (off = back to the default: live, b55, 14 days)""",
      'B 55 settings (off = back to the default: live, b55, 14 days)')
patch(T, "'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS', 'SOCIAL_GRUDGE_FADE_THRESHOLD'], true) || $value === '') {",
      "'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS'], true) || $value === '') {",
      "'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS'], true) || $value === '') {")
patch(T, "\n        'SOCIAL_GRUDGE_FADE_THRESHOLD' => $setting('SOCIAL_GRUDGE_FADE_THRESHOLD'),", "", '@@never-present@@')

patch('tests/social_relationship/ingame/RUN_ORDER.md', "`SOCIAL_GRUDGE_FADE_DAYS` (14), `SOCIAL_GRUDGE_FADE_THRESHOLD` (30) |",
      "`SOCIAL_GRUDGE_FADE_DAYS` (14; fading is decided by what happened, no size threshold) |", 'no size threshold')

rp = os.path.join(ROOT, 'data/social_relationship_rules.json')
rules = json.load(open(rp, encoding='utf-8'))
if 'fade_threshold' in rules.get('fights', {}):
    del rules['fights']['fade_threshold']
    rules['fights']['note'] = rules['fights']['note'].replace(
        'incidents with no KO-or-worse and unscaled worst >= -fade_threshold fade linearly over fade_days (settings SOCIAL_GRUDGE_FADE_THRESHOLD/DAYS);',
        'incidents that stayed not-hurt/wounded-standing (no KO or worse, no accidental KO) fade linearly over fade_days whatever their size (setting SOCIAL_GRUDGE_FADE_DAYS);')
    open(rp, 'w', encoding='utf-8').write(json.dumps(rules, indent=1) + '\n')
    print('patch data/social_relationship_rules.json: fade_threshold removed')

shutil.copyfile(os.path.join(HERE, 'b55_social_fights.php'), os.path.join(ROOT, 'lib/social_fights.php'))
shutil.copyfile(os.path.join(HERE, 'b55_social_fights_regression.php'), os.path.join(ROOT, 'tests/social_fights_regression.php'))
shutil.copyfile(os.path.join(HERE, 'rel-b55.sh'), os.path.join(ROOT, 'tests/social_relationship/ingame/rel-b55.sh'))
print('copied lib/social_fights.php, tests/social_fights_regression.php, rel-b55.sh')
