#!/usr/bin/env python3
"""Bug 125: goals aimed at a bracketed name never find the person.

Run 9 (test 42): WAIT_FOR target "Lorn Hungry Bandit" (the server strips the
brackets); the recruit is "Lorn [Hungry Bandit]", so wgp_name_match never
matched and the goal stayed ACTIVE with Lorn standing next to her. Like bug
123 in Stobe: names are also compared with punctuation stripped and spaces
collapsed.

Usage: patch_r21_bug125_goal_name_brackets.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_work_planner.inc'
text = path.read_text(encoding='utf-8')
old = """static int wgp_name_match(const char *actual, const char *query)
{
    char a[192]={0}, q[192]={0};
    if (!actual || !query || !*actual || !*query) return 0;
    strncpy(a,actual,sizeof(a)-1); strncpy(q,query,sizeof(q)-1);
    stobe_ascii_lower(a); stobe_ascii_lower(q);
    if (!strcmp(a,q)) return 3;
    if (strstr(a,q) || strstr(q,a)) return 2;
"""
new = """/* Bug 125: lower-case letters/digits with single spaces ("Lorn [Hungry Bandit]"
 * -> "lorn hungry bandit"); the server's sanitizer strips the brackets. */
static void wgp_name_squash(const char *in, char *out, size_t outsz)
{
    size_t n=0; int space=0;
    for (; *in && n+2<outsz; in++) {
        unsigned char c=(unsigned char)*in;
        if (isalnum(c)) {
            if (space && n) out[n++]=' ';
            out[n++]=(char)tolower(c); space=0;
        } else space=1;
    }
    out[n]=0;
}

static int wgp_name_match(const char *actual, const char *query)
{
    char a[192]={0}, q[192]={0};
    if (!actual || !query || !*actual || !*query) return 0;
    strncpy(a,actual,sizeof(a)-1); strncpy(q,query,sizeof(q)-1);
    stobe_ascii_lower(a); stobe_ascii_lower(q);
    if (!strcmp(a,q)) return 3;
    if (strstr(a,q) || strstr(q,a)) return 2;
    {
        char sa[192], sq[192];
        wgp_name_squash(a,sa,sizeof(sa)); wgp_name_squash(q,sq,sizeof(sq));
        if (sa[0] && sq[0] && !strcmp(sa,sq)) return 3;
    }
"""
# The squad lookup (WAIT_FOR, GUARD targets) used its own exact compare: use the
# matcher, and accept a partial name ("Rovar") only if one squad member has it.
old2 = """    if (!stuff || count>4096 || !readable(stuff,count*sizeof(void*))) return NULL;
    for (uint32_t i=0;i<count;i++) {
        void *c=stuff[i];
        if (!char_valid(c) || !readable((void *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS),20)) continue;
        uint32_t *h=(uint32_t *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS);
        if (serial && h[4]==serial) return c;
        if (!serial && name && *name) {
            char display[128]={0};
            if (stobe_copy_native_string((void *)((uintptr_t)c+0x18),display,sizeof(display)) &&
                !_stricmp(display,name)) return c;
        }
    }
    return NULL;
}
"""
new2 = """    if (!stuff || count>4096 || !readable(stuff,count*sizeof(void*))) return NULL;
    void *partial=NULL; int partials=0;
    for (uint32_t i=0;i<count;i++) {
        void *c=stuff[i];
        if (!char_valid(c) || !readable((void *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS),20)) continue;
        uint32_t *h=(uint32_t *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS);
        if (serial && h[4]==serial) return c;
        if (!serial && name && *name) {
            char display[128]={0};
            if (stobe_copy_native_string((void *)((uintptr_t)c+0x18),display,sizeof(display))) {
                int m=wgp_name_match(display,name); /* bug 125: "Rovar Dust Bandit Bowman" */
                if (m==3) return c;
                if (m==2) { partial=c; partials++; }
            }
        }
    }
    return partials==1 ? partial : NULL;
}
"""

if 'Bug 125' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
assert text.count(old2) == 1, 'squad lookup anchor not found exactly once'
path.write_text(text.replace(old, new).replace(old2, new2), encoding='utf-8', newline='')
print('patched', path)
