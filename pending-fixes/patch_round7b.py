#!/usr/bin/env python3
"""Round 7b: bug 3 server fallback didn't fire. conf_opts has no PLAYER_NAME, so
matching the row name against getSetting('PLAYER_NAME', 'Drifter') never hit. The two
player call sites now say so explicitly.

Usage: patch_round7b.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


patch("lib/negotiation_engine.php",
      """function stobeNegMoney(array $row): array {""",
      """function stobeNegMoney(array $row, bool $isPlayer = false): array {""")
patch("lib/negotiation_engine.php",
      """        if ($player !== '' && strcasecmp(normalizeParticipantNameToken(strval($row['name'] ?? '')), $player) === 0) {""",
      """        if ($isPlayer || ($player !== '' && strcasecmp(normalizeParticipantNameToken(strval($row['name'] ?? '')), $player) === 0)) {""")
patch("lib/negotiation_engine.php",
      """            'player_money'=>stobeNegMoney($playerRow),""",
      """            'player_money'=>stobeNegMoney($playerRow, true),""")
patch("lib/negotiation_voice.php",
      """        $money = stobeNegMoney(stobeNegNpcRow($player));""",
      """        $money = stobeNegMoney(stobeNegNpcRow($player), true);""")

# PLAYER_CATS lives in conf_opts (getConfOpt), not general_settings (getSetting).
patch("lib/negotiation_engine.php",
      """            $cats = trim(strval(getSetting('PLAYER_CATS', '')));""",
      """            $cats = trim(strval(function_exists('getConfOpt') ? getConfOpt('PLAYER_CATS', '') : ''));""")

print("patch_round7b: applied")
