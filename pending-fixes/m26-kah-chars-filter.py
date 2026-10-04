#!/usr/bin/env python3
# m26: harness `chars [radius] [filter]` (raid guard). Run from the harness repo root (WSL python3).
import pathlib
p=pathlib.Path("src/Commands.cpp"); s=open(p,encoding="utf-8",newline="").read(); NL=chr(10); CRLF=chr(13)+chr(10); crlf=CRLF in s
old='''  if (cmd == "chars") {
    float radius = f.size() >= 3 ? (float)atof(f[2].c_str()) : 100.0f;
    std::string out;
    int n = 0;
    std::vector<Character *> chars;
    CollectCharacters(world, origin, radius, chars);
    for (size_t i = 0; i < chars.size() && n < 40; ++i) {
      Character *c = chars[i];
      try {
        if (c->getPosition().distance(origin) > radius)
          continue;
      } catch (...) {
        continue;
      }
      out += (n ? " | " : "") + Describe(c, &origin);
      ++n;
    }'''
new='''  if (cmd == "chars") { // chars [radius] [filter]: filter = '|'-separated case-insensitive substrings of the line
    float radius = f.size() >= 3 ? (float)atof(f[2].c_str()) : 100.0f;
    // stobe raid guard (m26): Full-Base has more than 40 characters within 1500 m, so the cap hid the raiders;
    // a filter applies before the 40 cap
    std::vector<std::string> alts;
    if (f.size() >= 4) {
      std::string flt;
      for (size_t k = 3; k < f.size(); ++k)
        flt += (k > 3 ? " " : "") + f[k];
      std::string cur;
      for (size_t k = 0; k <= flt.size(); ++k) {
        if (k == flt.size() || flt[k] == '|') {
          if (!cur.empty())
            alts.push_back(cur);
          cur.clear();
        } else
          cur += (char)tolower((unsigned char)flt[k]);
      }
    }
    std::string out;
    int n = 0;
    std::vector<Character *> chars;
    CollectCharacters(world, origin, radius, chars);
    for (size_t i = 0; i < chars.size() && n < 40; ++i) {
      Character *c = chars[i];
      try {
        if (c->getPosition().distance(origin) > radius)
          continue;
      } catch (...) {
        continue;
      }
      std::string d = Describe(c, &origin);
      if (!alts.empty()) {
        std::string ld = d;
        for (size_t k = 0; k < ld.size(); ++k)
          ld[k] = (char)tolower((unsigned char)ld[k]);
        bool hit = false;
        for (size_t k = 0; k < alts.size() && !hit; ++k)
          hit = ld.find(alts[k]) != std::string::npos;
        if (!hit)
          continue;
      }
      out += (n ? " | " : "") + d;
      ++n;
    }'''
if crlf:
    old=old.replace(NL,CRLF); new=new.replace(NL,CRLF)
assert s.count(old)==1
s=s.replace(old,new)
s=s.replace('"chars [radius] | traders','"chars [radius] [filter] | traders',1)
open(p,"w",encoding="utf-8",newline="").write(s)
d=pathlib.Path("docs/COMMANDS.md"); t=open(d,encoding="utf-8",newline="").read()
o='| `chars [radius]` | characters within radius (default 100) of the player |'
assert t.count(o)==1
t=t.replace(o,'| `chars [radius] [filter]` | characters within radius (default 100) of the player (at most 40). `filter`: `|`-separated case-insensitive substrings of a character\'s line (e.g. `"[band of bones]|[kral"`), applied before the 40 cap |')
open(d,"w",encoding="utf-8",newline="").write(t)
print("ok")
