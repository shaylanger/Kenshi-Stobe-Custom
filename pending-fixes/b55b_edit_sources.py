#!/usr/bin/env python3
"""One-off: edits the canonical B 55 sources in pending-fixes for the fade-by-severity-class rule (Shay 94761de)."""
import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))


def edit(p, pairs):
    t = open(p, encoding='utf-8').read()
    for a, b in pairs:
        if b and b in t and a not in t:
            continue
        assert t.count(a) == 1, (p, a[:90])
        t = t.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(t)


edit('b55_social_fights.php', [
("""/** [threshold (abs, unscaled worst charge), days] */
function stobeSocialFadeSettings(SocialRules $rules): array
{
    $section = $rules->section('fights');
    $threshold = abs((int)getSetting('SOCIAL_GRUDGE_FADE_THRESHOLD', strval($section['fade_threshold'] ?? 30)));
    $days = (float)getSetting('SOCIAL_GRUDGE_FADE_DAYS', strval($section['fade_days'] ?? 14));
    return [$threshold, $days];
}""",
"""/** Item 1: game days a fading grudge takes to reach 0 (setting SOCIAL_GRUDGE_FADE_DAYS, rules fights.fade_days, 14). */
function stobeSocialFadeDays(SocialRules $rules): float
{
    return (float)getSetting('SOCIAL_GRUDGE_FADE_DAYS', strval($rules->section('fights')['fade_days'] ?? 14));
}"""),
])

edit('b55_fights_server.py', [
("""     * B 55 item 1: forgiveness over time, event-based. Each fight incident (per observer -> culprit) is its own grudge;
     * one with no knockout or worse and an unscaled worst charge of at most SOCIAL_GRUDGE_FADE_THRESHOLD fades back
     * linearly over SOCIAL_GRUDGE_FADE_DAYS game days (what treatment/deals already won back is not faded twice).""",
 """     * B 55 item 1: forgiveness over time, decided by what happened. Each fight incident (per observer -> culprit) is its
     * own grudge; one with no knockout or worse (STOBE_SOCIAL_NEVER_FADE, accidental KO/limb) fades back linearly over
     * SOCIAL_GRUDGE_FADE_DAYS game days whatever its size (what treatment/deals already won back is not faded twice)."""),
("""        [$threshold, $days] = stobeSocialFadeSettings($this->rules);""", """        $days = stobeSocialFadeDays($this->rules);"""),
("""              MIN(CASE WHEN component = ANY(\\$2::text[]) THEN COALESCE((detail->>'unscaled')::int, (detail->>'total')::int, delta) END) AS worst,
""", ""),
("""            if ($g['never'] === 't' || (int)$g['worst'] < -$threshold || $g['observer_key'] === null) continue;""",
 """            if ($g['never'] === 't' || $g['observer_key'] === null) continue; // severity class, never the size (Shay 94761de)"""),
("""        'fade_threshold': 30,
""", ""),
("""incidents with no KO-or-worse and unscaled worst >= -fade_threshold fade linearly over fade_days (settings SOCIAL_GRUDGE_FADE_THRESHOLD/DAYS);""",
 """incidents that stayed not-hurt/wounded-standing (no KO or worse, no accidental KO) fade linearly over fade_days whatever their size (setting SOCIAL_GRUDGE_FADE_DAYS);"""),
("""`SOCIAL_GRUDGE_FADE_DAYS` (14), `SOCIAL_GRUDGE_FADE_THRESHOLD` (30) |""", """`SOCIAL_GRUDGE_FADE_DAYS` (14; fading is decided by what happened, no size threshold) |"""),
(""" *   php tools/social_relationship_inspect.php --set-switch SOCIAL_FIGHTS_LIVE|SOCIAL_FIGHT_RULES|SOCIAL_GRUDGE_FADE_DAYS|SOCIAL_GRUDGE_FADE_THRESHOLD <value|off>
 *                                                  B 55 settings (off = back to the default: live, b55, 14 days, 30)""",
 """ *   php tools/social_relationship_inspect.php --set-switch SOCIAL_FIGHTS_LIVE|SOCIAL_FIGHT_RULES|SOCIAL_GRUDGE_FADE_DAYS <value|off>
 *                                                  B 55 settings (off = back to the default: live, b55, 14 days)"""),
("""'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS', 'SOCIAL_GRUDGE_FADE_THRESHOLD'], true) || $value === '') {",
      "'SOCIAL_GRUDGE_FADE_DAYS', 'SOCIAL_GRUDGE_FADE_THRESHOLD'], true) || $value === '') {")""",
 """'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS'], true) || $value === '') {",
      "'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS'], true) || $value === '') {")"""),
("""
        'SOCIAL_GRUDGE_FADE_THRESHOLD' => $setting('SOCIAL_GRUDGE_FADE_THRESHOLD'),""", ""),
])

edit('b55_social_fights_regression.php', [
("""$t3 = 101600 + 15 * 86400;
setting('SOCIAL_GRUDGE_FADE_THRESHOLD', '5');
attack('Fight Shay', 'Bandit Fen Three', $t3);
$g3 = affOf('Bandit Fen Three', 'Fight Shay');
tick($t3 + 15 * 86400);
ok(affOf('Bandit Fen Three', 'Fight Shay') === $g3 && $g3 < 0, 'item 1: SOCIAL_GRUDGE_FADE_THRESHOLD setting (5: aggression no longer fades)');
setting('SOCIAL_GRUDGE_FADE_THRESHOLD', null);""",
"""// Shay 94761de: fading is decided by what happened, not by the size (the old size-threshold setting is ignored).
$t3 = 101600 + 15 * 86400;
setting('SOCIAL_GRUDGE_FADE_THRESHOLD', '5');
RelationshipManager::setRelationship('Bandit Fen Three', 'Fight Shay', 60);
attack('Fight Shay', 'Bandit Fen Three', $t3);
harm('Fight Shay', 'Bandit Fen Three', 'injury', $t3 + 10);
$g3 = affOf('Bandit Fen Three', 'Fight Shay') - 60;
ok($g3 >= -60 && $g3 <= -46, "item 1 setup: Fond wound x2 = -46..-60 ($g3)");
RelationshipManager::setRelationship('Bandit Fen Five', 'Fight Shay', 60);
attack('Fight Shay', 'Bandit Fen Five', $t3 + 100);
harm('Fight Shay', 'Bandit Fen Five', 'knockout', $t3 + 110, false);
$g5 = affOf('Bandit Fen Five', 'Fight Shay');
tick($t3 + 15 * 86400);
ok(affOf('Bandit Fen Three', 'Fight Shay') === 60, "item 1: a Fond victim's wound (x2, $g3) fades back fully: what happened decides, not the size (" . affOf('Bandit Fen Three', 'Fight Shay') . ')');
ok(affOf('Bandit Fen Five', 'Fight Shay') === $g5 && $g5 <= -20, "item 1: a Fond victim's KO never fades ($g5)");
setting('SOCIAL_GRUDGE_FADE_THRESHOLD', null);"""),
("""'Bandit Fen Four'=>[614,'Dust Bandits',false],""", """'Bandit Fen Four'=>[614,'Dust Bandits',false], 'Bandit Fen Five'=>[619,'Dust Bandits',false],"""),
])

edit('rel-b55.sh', [
("""  elif [ -n "$r0" ] && [ "$r0" -le -40 ]; then v "fade: INCONCLUSIVE the light fight reached the KO band ($r0): never fades by rule\"""",
 """  elif grep -q -e serious_assault -e critical_harm -e '"maiming"' "$O/fade.inspect.txt"; then v "fade: INCONCLUSIVE the light fight became a KO or worse ($r0): never fades by rule\""""),
])
print('ok')
