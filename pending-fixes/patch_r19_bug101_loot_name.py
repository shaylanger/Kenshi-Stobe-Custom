#!/usr/bin/env python3
"""Bug 101: "Loot everything from Pax's body" looted nothing. The server sends
the target as "Pax Hungry Bandit" (brackets dropped); the body is named
"Pax [Hungry Bandit]", so the plain substring match failed (match=0).
Fix: compare names with punctuation/brackets turned into single spaces;
if no match, retry a plural filter as singular ("these bandits" -> "bandit").
Usage: patch_r19_bug101_loot_name.py <KenshiFP tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("client/stobe_task_goals.inc", [
    ("static int stg_valid_downed(void *actor,void *c,const char *filter)\n{",
     """/* Bug 101: lower-case, punctuation/brackets -> one space ("Pax [Hungry Bandit]" -> "pax hungry bandit"). */
static void stg_norm_name(char *s)
{
    char *w=s;int sp=1;
    for(char *r=s;*r;r++){
        unsigned char ch=(unsigned char)*r;
        if(isalnum(ch)){*w++=(char)tolower(ch);sp=0;}
        else if(!sp){*w++=' ';sp=1;}
    }
    if(w>s&&w[-1]==' ')w--;
    *w='\\0';
}

static int stg_valid_downed(void *actor,void *c,const char *filter)
{"""),
    ("        if(strstr(cnlow,f)==NULL) return 0;\n",
     "        stg_norm_name(f);stg_norm_name(cnlow);\n"
     "        if(!*f) return 0;\n"
     "        if(strstr(cnlow,f)==NULL){ /* \"bandits\" vs \"[Hungry Bandit]\": try the singular */\n"
     "            size_t fl=strlen(f);\n"
     "            if(fl<4||f[fl-1]!='s') return 0;\n"
     "            f[fl-1]='\\0';\n"
     "            if(strstr(cnlow,f)==NULL) return 0;\n"
     "        }\n"),
])
