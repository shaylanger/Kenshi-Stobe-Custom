#!/usr/bin/env python3
"""Shared helpers for the imm26 hardened-row assertion scripts (IMM-<nn>-<x>x rows).

Evidence bundle = one directory per sample, produced by the row scripts (4080-imm26-i4-row.sh /
5090-i4-imm26-row.sh): prompt.txt, events.txt (rowid|type|data|state), effects.txt (social_effect
rows after `count_before=..`), reply.txt (stobe.log lines), meta.txt. Hardened rows also ask the
operator to drop small DB/state dumps next to them (names are listed per row in the TESTS file and
in each script's docstring): haff.txt, inv.txt, state_after.txt, principle_rows.txt, ...

Output contract: exactly one line `RESULT <row> PASS|FAIL <evidence>` (exit 0 PASS, 1 FAIL, 2 usage).
Strict by default: a missing required evidence file or a failed check is FAIL.
`--lenient` (offline self-test only; never for a row verdict) turns missing files into SKIP and
tags the evidence `[LENIENT skipped=N]`.
"""
import difflib
import json
import os
import re
import sys

PLAYER_NAMES = ('shay', 'kint')  # speakers that are the player, not the NPC under test

# ---- word lists (documented pass criteria; keep here so every row uses the same ones) ----
COOP = re.compile(r"\b(sure|lead the way|let'?s go|i'?m in|count me in|sounds good|sounds like a plan|"
                  r"gladly|happy to|glad to|i'?d love to|why not|all right then|alright then|you got it|deal)\b", re.I)
RELUCTANT = re.compile(r"\b(no|not|don'?t|won'?t|can'?t|never|nothing|forget it|leave me|keep your distance|stay away|"
                       r"get lost|back off|no chance|not interested|i'?d rather not|some other time|go (alone|without)|"
                       r"with you\?|since when|why would)\b", re.I)
REFUSE = re.compile(r"\b(no|not|won'?t|will not|don'?t|never|refuse|line i (don'?t|won'?t) cross|not for|"
                    r"can'?t do that|i'?m not (doing|going to))\b", re.I)
GUSH = re.compile(r"\b(delighted|thrilled|overjoyed|ecstatic|wonderful|marvell?ous|so (very )?(happy|glad|good|"
                  r"wonderful)|missed you|can'?t tell you how|my dear|dearest|best friend|love to see|"
                  r"what a (joy|pleasure|delight)|embrace)\b", re.I)
UNKNOWN = re.compile(r"\b(don'?t know|haven'?t (really )?(thought|given)|not (really|sure)|nothing (in particular|"
                     r"that comes to mind)|no strong|can'?t say|never (given|thought)|hard to say|depends|"
                     r"why (do )?you ask|nothing much|nothing i('?d| would) (swear|die))\b", re.I)
EYEWITNESS = re.compile(r"\bi (saw|watched|was there|had a look|came in|caught)\b|saw the tail end|"
                        r"i (was|got) (a|the) (front|good)", re.I)
HEARSAY_OK = re.compile(r"\b(didn'?t see|did not see|wasn'?t there|was not there|can'?t say|no idea|heard|rumou?r|"
                        r"word is|nobody told|don'?t know|not there|missed it|asleep|away|only know)\b", re.I)
ADMIT = re.compile(r"\b(wrong|mistaken|my mistake|my fault|misplaced|must have|i thought|maybe i|i may have|"
                   r"i might have|sorry|apolog|turns out)\b", re.I)
FABRICATED = re.compile(r"\bi (saw|watched|remember seeing)\b|\bsomeone told me\b|\ba witness\b|\bthey said\b|"
                        r"\b(caravan|merchant|trader) (was|were|went|had)\b", re.I)
INVENTED_CAUSE = re.compile(r"\b(picked|found|took|grabbed) it (up |back )?(myself|earlier|just now|from)|turned up in|"
                            r"(found|had) it (all along|in my)", re.I)
HOLD = re.compile(r"\b(still|but|someone|missing|gone|where is|then who|can'?t find|not (in|on) my|someone took|"
                  r"you (did|have|took)|i know (it|what)|don'?t believe|doesn'?t add up)\b", re.I)
ABSOLUTE_ALONE = re.compile(r"\b(completely|totally|absolutely|definitely|certainly|for sure|100%)\b.*\b(alone|nobody|no one)\b|"
                            r"\b(alone|nobody|no one)\b.*\b(completely|totally|absolutely|definitely|certainly|for sure)\b|"
                            r"^(yes|yeah)[,.! ]+(we are|just us|only us)|\bwe('?re| are) (all )?alone\b|\bjust us\b|\bonly us\b|"
                            r"\bnobody (is )?(here|around)\b|\bno one (is )?(here|around)\b", re.I)
HEDGE = re.compile(r"\b(as far as|i can see|i think|looks like|seems|don'?t see|nobody i can see|no one i can see|"
                   r"not that i (can )?(see|know)|as i can tell|from here|i can'?t see)\b", re.I)
GUARDED = re.compile(r"\b(no|not|don'?t|won'?t|what do you want|state your|keep (back|away|your)|stay back|enemy|"
                     r"enemies|your kind|your people|watch (it|yourself)|careful|move along|i don'?t know you|"
                     r"unfriendly|not (a )?friend|make it quick|speak up|who are you|what('?s| is) your business)\b", re.I)
OPEN = re.compile(r"\b(hello|hi|hey|welcome|good (day|morning|evening)|well met|friend|comrade|brother|sister|"
                  r"how can i help|what can i do|glad|nice to|greetings)\b", re.I)
COMBAT_WORDS = re.compile(r"\b(fight(ing)?|attack(ing)?|swing(ing)?|battle|combat|kill(ing)?|duel|brawl|axe|blade)\b", re.I)


class Result:
    def __init__(self, row, lenient=False):
        self.row, self.lenient = row, lenient
        self.ok, self.bad, self.good, self.skipped = True, [], [], 0

    def check(self, name, cond, detail=''):
        if cond:
            self.good.append(name + (f'={detail}' if detail != '' else ''))
        else:
            self.ok = False
            self.bad.append(f'{name}!{detail}')
        return bool(cond)

    def skip(self, name):
        self.skipped += 1
        self.good.append(f'{name}=SKIP')

    def need(self, path, label=None):
        """Required evidence file. Returns text or None (None records FAIL, or SKIP when lenient)."""
        label = label or os.path.basename(path)
        if os.path.isfile(path):
            return open(path, encoding='utf-8', errors='replace').read()
        if self.lenient:
            self.skip(f'file:{label}')
        else:
            self.check(f'file:{label}', False, 'missing')
        return None

    def emit(self):
        ev = '; '.join(self.bad + self.good)
        if self.lenient and self.ok:
            ev += f' [LENIENT skipped={self.skipped}]'
        print(f"RESULT {self.row} {'PASS' if self.ok else 'FAIL'} {ev[:1400]}")
        return 0 if self.ok else 1


class Bundle:
    def __init__(self, d):
        self.dir = d
        self.name = os.path.basename(os.path.normpath(d))

    def read(self, name):
        p = os.path.join(self.dir, name)
        return open(p, encoding='utf-8', errors='replace').read() if os.path.isfile(p) else None

    @property
    def prompt(self):
        return self.read('prompt.txt') or ''

    def events(self):
        out = []
        for ln in (self.read('events.txt') or '').splitlines():
            p = ln.split('|', 3)
            if len(p) >= 3 and p[0].strip().isdigit():
                out.append((int(p[0]), p[1].strip(), p[2], p[3].strip() if len(p) > 3 else ''))
        return out

    def inputs(self):
        """Distinct player utterances (inputtext rows)."""
        res = []
        for _, t, d, _ in self.events():
            if t == 'inputtext':
                m = re.match(r'\s*([^:]+):\s*(.*?)\s*\(talking to:', d)
                if m:
                    res.append(m.group(2))
        return res

    def replies(self, npc=None):
        """NPC chat replies in order (speaker not a player name; optional substring filter)."""
        out = []
        for _, t, d, st in self.events():
            if t != 'chat':
                continue
            m = re.match(r'\s*([^:]+?):\s*(.*?)\s*\(talking to:', d)
            if not m:
                continue
            spk, txt = m.group(1), m.group(2)
            if spk.strip().lower() in PLAYER_NAMES:
                continue
            if npc and npc.lower() not in spk.lower():
                continue
            out.append(txt)
        if not out:  # fall back to stobe.log SAY lines
            for ln in (self.read('reply.txt') or '').splitlines():
                m = re.search(r'ACTION_EXEC: SAY \[(.+?)\]: (.*) \(NPC\)\s*$', ln)
                if m and (not npc or npc.lower() in m.group(1).lower()):
                    out.append(m.group(2))
        return out

    def first_sentence(self, text=None):
        t = text if text is not None else ' '.join(self.replies()[:1])
        return re.split(r'(?<=[.!?])\s', t.strip(), 1)[0] if t else ''

    def foreign_actions(self, allowed=('SAY', 'IDLE')):
        """ACTION_EXEC kinds (stobe.log) and eventlog `action` rows other than SAY/IDLE."""
        acts = []
        for ln in (self.read('reply.txt') or '').splitlines():
            m = re.search(r'ACTION_EXEC: ([A-Z][A-Z_]+)', ln)
            if m and m.group(1).upper() not in allowed:
                acts.append(m.group(1))
        for _, t, d, _ in self.events():
            if t == 'action':
                m = re.search(r':\s*([A-Za-z_]+)@', d)
                k = m.group(1) if m else d[:30]
                if k.upper() not in allowed:
                    acts.append(k)
        return acts

    def event_types(self, *types):
        return [e for e in self.events() if e[1] in types]

    def effects(self):
        """Parse social_effect rows from effects.txt (4080 `'|'` layout and 5090 `select *` layout) -> list of dicts.
        Tolerates detail JSON truncated by `left(detail,200)` (fields recovered by regex; observer name may then be
        missing -> match by key through ids.txt, see ids())."""
        rows = []
        for ln in (self.read('effects.txt') or '').splitlines():
            m = re.search(r'(\{.*)$', ln)
            if not m or ln.startswith('count_'):
                continue
            blob, js = m.group(1), {}
            try:
                js = json.loads(blob)
            except ValueError:
                pass
            fields = [f.strip("'") for f in ln[:m.start()].replace("'|'", '|').split('|') if f.strip("'") != '']
            kind = next((f for f in fields if re.fullmatch(r'[a-z][a-z_]{2,}', f)), '')
            incident = next((f for f in fields if re.match(r'[a-z_]+:\S+', f) and not re.match(r'[0-9a-f]{32}:', f)), '')
            keys = [f for f in fields if re.fullmatch(r'[0-9a-f]{32}:\d+:\w+', f)]

            def pick(name, rx, cast=str, default=None):
                if name in js:
                    return js[name]
                mm = re.search(rx, blob)
                return cast(mm.group(1)) if mm else default
            delta = pick('delta', r'"delta": (-?[\d.]+)', float, 0)
            rows.append({'kind': kind, 'incident': incident, 'delta': delta,
                         'weight': (js.get('modifiers') or {}).get('weight') if js else pick('weight', r'"weight": ([\d.]+)', float),
                         'observer': pick('observer_name', r'"observer_name": "([^"]*)"', str, ''),
                         'culprit': pick('culprit_name', r'"culprit_name": "([^"]*)"', str, ''),
                         'new_aff': pick('new_affinity', r'"new_affinity": (-?\d+)', int),
                         'obs_key': keys[0] if keys else '', 'cul_key': keys[1] if len(keys) > 1 else ''})
        return rows

    def new_effects(self):
        """Only the rows created by this sample: the dump lists the newest 6-10 rows, header gives how many are new."""
        rows, head = self.effects(), (self.read('effects.txt') or '').splitlines()[:1]
        n = None
        if head:
            m = re.match(r'count_before=(\d+) count_after=(\d+)', head[0]) or re.match(r'^(\d+)$', head[0].strip())
            if m:
                n = int(m.group(2)) - int(m.group(1)) if m.lastindex == 2 else int(m.group(1))
        return rows if n is None else rows[:max(n, 0)]

    def ids(self):
        """ids.txt: lines `Name|numeric_id` (storage ids of the NPCs named in the row) -> {name.lower(): id}."""
        out = {}
        for ln in (self.read('ids.txt') or '').splitlines():
            p = [x.strip() for x in ln.split('|')]
            if len(p) >= 2 and p[1]:
                out[p[0].lower()] = p[1]
        return out

    def roster(self):
        """Names listed under '## Nearby People Awareness' (### Person blocks)."""
        m = re.search(r'^## Nearby People Awareness\n(.*?)(?=^## |\Z)', self.prompt, re.S | re.M)
        names = []
        if m:
            for blk in re.split(r'^### Person\s*$', m.group(1), flags=re.M)[1:]:
                ln = next((l for l in blk.splitlines() if l.strip()), '')
                nm = ln.split('|')[0].strip()
                if nm.split(' ')[0].lower() not in PLAYER_NAMES:  # the player is listed too; not an "other person"
                    names.append(nm)
        return names

    def stance(self):
        m = re.search(r'Current conversational stance toward ([^:]+): (\w+)', self.prompt)
        return (m.group(1), m.group(2)) if m else (None, None)

    def listener_in_combat(self):
        """True when the prompt marks the speaking NPC itself as in combat (not just overheard combat events)."""
        return bool(re.search(r'Action Flags: .*in combat|Priority Instruction: .*is in active combat', self.prompt))

    def affinity_in_prompt(self):
        m = re.search(r'affinity toward the actual speaker .*? is (-?\d+)/100', self.prompt)
        return int(m.group(1)) if m else None


def similar(a, b):
    return difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio()


def num_file(text, pattern):
    m = re.search(pattern, text or '')
    return float(m.group(1)) if m else None


def parse_args(argv, flags_multi=(), flags_single=(), bools=('--lenient',)):
    """Tiny arg parser: repeatable --x D1 D2 ... (values until next --flag), --y V, --lenient."""
    a = {k: [] for k in flags_multi}
    a.update({k: None for k in flags_single})
    a.update({b: False for b in bools})
    pos, cur = [], None
    for tok in argv:
        if tok in bools:
            a[tok], cur = True, None
        elif tok in flags_multi:
            cur = tok
        elif tok in flags_single:
            cur = tok
            a[tok] = ''
        elif tok.startswith('--'):
            raise SystemExit(f'RESULT usage FAIL unknown flag {tok}')
        elif cur in flags_multi:
            a[cur].append(tok)
        elif cur in flags_single:
            a[cur] = tok
            cur = None
        else:
            pos.append(tok)
    return pos, a


def distinct_inputs(bundles, n, res):
    ins = []
    for b in bundles:
        ins += b.inputs()[-1:]  # the utterance of this sample
    uniq = {i.lower().strip() for i in ins}
    return res.check('distinct_utterances>=%d' % n, len(uniq) >= n, f'{len(uniq)}/{len(ins)}')


def reply_of(b, npc=None):
    r = b.replies(npc)
    return ' '.join(r)
