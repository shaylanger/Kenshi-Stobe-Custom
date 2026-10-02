#!/usr/bin/env python3
"""Bug 123: actions aimed at an NPC with a bracketed name go to the player.

Run 9 (test 39): "Malzin, give Grenn 3 kits" -> server action
GIVE_ITEM@Grenn Hungry Bandit@... (its sanitizer strips '['); Stobe found no
"Grenn Hungry Bandit" (the NPC is "Grenn [Hungry Bandit]") and GIVE_ITEM fell
back to the player: the kits went to Shay. Both name matchers
(ResolveCharacterByTargetToken in Functions.cpp and resolveActionTargetHand
in main.cpp, which GIVE_ITEM uses) now also compare names with punctuation
stripped and spaces collapsed.

Usage: patch_r21_bug123_target_brackets.py <STOBE tree root>   (idempotent)
"""
import sys
from pathlib import Path

HELPER = """// Bug 123: lower-case letters/digits with single spaces ("Pax [Hungry Bandit]"
// -> "pax hungry bandit"); the server's sanitizer strips the brackets.
static std::string {name}(const std::string &value) {{
  std::string out;
  bool space = false;
  for (size_t i = 0; i < value.size(); ++i) {{
    unsigned char c = (unsigned char)value[i];
    if (isalnum(c)) {{
      if (space && !out.empty())
        out += ' ';
      out += (char)tolower(c);
      space = false;
    }} else {{
      space = true;
    }}
  }}
  return out;
}}

"""

root = Path(sys.argv[1]) / 'src'

# Functions.cpp
path = root / 'Functions.cpp'
text = path.read_text(encoding='utf-8')
old = """      } else if (candidateLow.find(tokenLow) != std::string::npos) {
        score = 180;
      } else if (!candidate->displayName.empty()) {"""
new = """      } else if (candidateLow.find(tokenLow) != std::string::npos) {
        score = 180;
      } else if (LettersAndSpacesOnly(candidateLow) == LettersAndSpacesOnly(tokenLow)) {
        score = 480; // bug 123: "grenn hungry bandit" == "grenn [hungry bandit]"
      } else if (!candidate->displayName.empty()) {"""
anchor = "Character *ResolveCharacterByTargetToken(GameWorld *world,\n"
if 'LettersAndSpacesOnly(candidateLow)' in text:
    print('already patched', path)
else:
    assert text.count(old) == 1 and text.count(anchor) == 1, 'Functions.cpp anchors'
    text = text.replace(old, new).replace(anchor, HELPER.format(name='LettersAndSpacesOnly') + anchor)
    path.write_text(text, encoding='utf-8', newline='')
    print('patched', path)

# main.cpp
path = root / 'main.cpp'
text = path.read_text(encoding='utf-8')
old = """                  } else if (candidateLow.find(tokenLow) != std::string::npos) {
                    score = 180;
                  } else if (!candidate->displayName.empty()) {"""
new = """                  } else if (candidateLow.find(tokenLow) != std::string::npos) {
                    score = 180;
                  } else if (LettersAndSpacesOnlyName(candidateLow) ==
                             LettersAndSpacesOnlyName(tokenLow)) {
                    score = 480; // bug 123: brackets stripped by the server
                  } else if (!candidate->displayName.empty()) {"""
anchor = "static std::string TestInboxLower(const std::string &value) {\n"
if 'LettersAndSpacesOnlyName(candidateLow)' in text:
    print('already patched', path)
else:
    assert text.count(old) == 1, 'main.cpp score anchor'
    assert text.count(anchor) == 1, 'main.cpp helper anchor'
    # The helper goes before the function using it: before the first top-level
    # function that precedes the use, found via the include block end.
    first_static = text.index('\nstatic ', 0) + 1
    text = text[:first_static] + HELPER.format(name='LettersAndSpacesOnlyName') + text[first_static:]
    text = text.replace(old, new)
    path.write_text(text, encoding='utf-8', newline='')
    print('patched', path)
