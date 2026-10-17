"""replay2_guard.py - GUARD RAILS arm: mechanical 'already done' list + mechanical post-filter (no second model).

  done_list(input_text)          -> dict of lists (spawned / acked / messages / commits / wakers / edits / commands) parsed from the point's own
                                    'Preceding conversation' (the coordinator's earlier tool calls).
  done_block(input_text)         -> text block injected into the Haiku prompt right before the final instruction.
  filter_decision(dec, input)    -> (filtered decision, [rejection records]) : removes every action that names an agent, alert, lane, row or file that
                                    does not occur in the point input (see kinds below); logs each rejection.
Kinds: agent, alert, lane, row, path, forbidden-target. A 'spawn' may introduce NEW agent names (a successor is legitimately not in the input), and
edit-file/commit actions may introduce new agent names inside text/paths; every other identifier still has to occur in the input.
Windows python, stdlib only. Reuses grade.check_paths (path existence) and tools/automation/shadow/shadow_validate.py (forbidden live targets).
"""
import os, re, sys, json

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
SHADOW_DIR = os.path.abspath(os.path.join(HERE, '..', 'shadow'))
if SHADOW_DIR not in sys.path:
    sys.path.insert(0, SHADOW_DIR)
import replay2_common as C  # noqa: E402

REPO = C.REPO

BLOCK_START = re.compile(r'^\[(coordinator|tool result|INBOUND[^\]]*|hook note)\]')
TOOL_LINE = re.compile(r'^(?:\[coordinator\] )?-> (\w+): ?(.*)$')
ACK_RE = re.compile(r'(alert-ack\.ps1|tail-ack\.ps1|agent-abandon\.ps1)')
WAKER_RE = re.compile(r'(event-wait\.sh|rearm-waker\.ps1|tail-wait\.ps1)')
RELAY_RE = re.compile(r'tail-relay\.ps1')

# identifier patterns (same families as replay2_common.ID_RE, split by kind)
ALERT_RE = re.compile(r'\b(?:lane-idle|lane-no-operator|lane-stuck|agent-(?:orphaned|stopped-context|stopped|dead|stall|stalled|killed|failed)|llm-health)-[A-Za-z0-9][\w.-]*')
AGENT_RE = re.compile(r'(?<![\w-])imm26-[A-Za-z0-9][\w-]*')
AGENTID_RE = re.compile(r'(?<![\w-])a[0-9a-f]{16}(?![\w-])')
LANE_RE = re.compile(r'(?<![\w-])(?:5090|4080)-i\d+(?![\w-])')
ROW_RE = re.compile(r'(?<![\w-])(?:\d{1,2}-[a-z]{1,2}|SR-?\d+|PI-\d+)(?![\w-])')
POS_RE = re.compile(r'(agent-status\.ps1|agent-abandon\.ps1|tail-ack\.ps1|alert-ack\.ps1)\s+(?:-\w+\s+)?([^\s;|&"\'`]+)')
TO_RE = re.compile(r'^\s*to=([^\s:,]+)')
REL_PATH = re.compile(r'(?<![\w./\\:-])((?:tools|docs|testing|pending-fixes|components|archive)[\\/][\w./\\-]+\.\w+)')
CMD_TYPES = {'run', 'ack', 'restart-waker', 'commit', 'hold-lane', 'release-lane', 'mark-row', 'stop-agent'}


def _norm(s):
    return s.lower().replace('\\', '/').replace('//', '/')


def conversation(input_text):
    a = input_text.find('## Preceding conversation')
    b = input_text.find('## EVENT BATCH')
    if a < 0:
        return ''
    return input_text[a:b if b > a else len(input_text)]


def tool_calls(input_text):
    """Yield (name, first line of the call) for each coordinator tool call in the preceding conversation (not tool results)."""
    cur = None
    for ln in conversation(input_text).split('\n'):
        m = BLOCK_START.match(ln)
        if m:
            cur = m.group(1)
        if cur != 'coordinator':
            continue
        t = TOOL_LINE.match(ln)
        if t:
            yield t.group(1), t.group(2)


def short(s, n=170):
    s = re.sub(r'\s+', ' ', s).strip()
    return s if len(s) <= n else s[:n] + '...'


def done_list(input_text):
    d = {'spawned': [], 'acked': [], 'messages': [], 'commits': [], 'wakers': [], 'edits': [], 'commands': []}
    for name, line in tool_calls(input_text):
        if name in ('Agent', 'Task'):
            desc, _, prm = line.partition(' | ')
            nm = AGENT_RE.search(prm) or AGENT_RE.search(desc)
            d['spawned'].append(short(desc, 140) + (' [agent name: %s]' % nm.group(0).rstrip('-') if nm else ''))
        elif name == 'SendMessage':
            m = re.search(r'"to":\s*"([^"]*)"', line)
            msg = re.search(r'"message":\s*"(.*)', line)
            d['messages'].append('to=%s: %s' % (m.group(1) if m else '?', short(msg.group(1) if msg else line, 110)))
        elif name in ('Edit', 'Write', 'NotebookEdit'):
            m = re.search(r'"file_path":\s*"([^"]+)"', line)
            d['edits'].append((m.group(1) if m else short(line, 100)).replace('\\\\', '\\'))
        elif name in ('Bash', 'PowerShell'):
            if ACK_RE.search(line):
                d['acked'].append(short(line))
            elif RELAY_RE.search(line):
                d['messages'].append('tail-relay: ' + short(line, 130))
            elif re.search(r'git\s+(\S+\s+)*(commit|push)', line):
                d['commits'].append(short(line, 150))
            elif WAKER_RE.search(line):
                d['wakers'].append(short(line, 120))
            else:
                try:
                    ro = _is_readonly(line)
                except Exception:
                    ro = False
                if not ro:
                    d['commands'].append(short(line))
        elif name == 'Monitor':
            d['wakers'].append(short(line, 120))
        elif name == 'TaskStop':
            d['commands'].append('TaskStop ' + short(line, 100))
    return d


def _is_readonly(cmd):
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import common
    return common.is_readonly_cmd(cmd)


def done_block(input_text, cap=14):
    d = done_list(input_text)
    titles = [('spawned', 'AGENTS ALREADY SPAWNED (Agent calls)'), ('acked', 'ALERTS / AGENTS ALREADY ACKED OR ABANDONED'),
              ('messages', 'MESSAGES ALREADY SENT'), ('commits', 'COMMITS / PUSHES ALREADY DONE'), ('wakers', 'WAKERS / MONITORS ALREADY STARTED'),
              ('edits', 'FILES ALREADY EDITED OR WRITTEN'), ('commands', 'OTHER MUTATING COMMANDS ALREADY RUN')]
    L = ['## ALREADY DONE (extracted mechanically from the preceding conversation above)',
         'The coordinator has ALREADY executed everything listed here. Do NOT repeat, re-spawn, re-ack, re-send or re-run any of it. Your job is the NEW event',
         'batch at the bottom: decide only what is still missing for it. If everything it needs was already done, the correct decision is ignore/wait.',
         'Only name agents, alerts, lanes, rows and files that occur in this file (a new agent you spawn may get a new name).']
    for k, title in titles:
        items = d[k]
        L.append('')
        if not items:
            L.append('%s: (none in the preceding conversation)' % title)
            continue
        extra = len(items) - cap
        L.append('%s (%d%s):' % (title, len(items), ', showing the latest %d' % cap if extra > 0 else ''))
        for it in items[-cap:]:
            L.append('  - ' + it)
    return '\n'.join(L)


# ------------------------------------------------------------------ post-filter
def input_tokens(input_text):
    return _norm(input_text)


def present(token, itext_norm):
    t = _norm(token).rstrip('.-')
    if not t:
        return True
    return re.search(r'(?<![\w-])' + re.escape(t) + r'(?![\w-])', itext_norm) is not None


def _skip_token(t):
    return (not t or t[0] in '<$%-@' or t.upper() == t and t.isalpha() or t.lower() in C.PLACEHOLDER_WORDS)


def refs_of(a):
    """List of (kind, token) referenced by one action."""
    typ = a.get('type'); txt = str(a.get('exact_command_or_message', ''))
    refs = []
    for m in ALERT_RE.finditer(txt):
        refs.append(('alert', m.group(0).rstrip('.-')))
    if typ not in ('spawn', 'edit-file', 'commit'):
        for m in AGENT_RE.finditer(txt):
            if m.group(0).endswith('-') or txt[m.end():m.end() + 1] in ('*', '?'):
                continue  # a glob / prefix such as imm26-4080-* is not a name
            refs.append(('agent', m.group(0).rstrip('-')))
    for m in AGENTID_RE.finditer(txt):
        refs.append(('agent', m.group(0)))
    for m in LANE_RE.finditer(txt):
        refs.append(('lane', m.group(0)))
    for m in ROW_RE.finditer(txt):
        refs.append(('row', m.group(0)))
    for m in POS_RE.finditer(txt):
        tok = m.group(2).rstrip('.,;:)')
        if _skip_token(tok) or tok in ('RUNNING', 'DONE', 'FAILED', 'STOPPED-CONTEXT'):
            continue
        script = m.group(1)
        if typ == 'spawn' or (script == 'agent-status.ps1' and typ in ('edit-file', 'commit')):
            continue
        refs.append(('alert' if script == 'alert-ack.ps1' else 'agent', tok))
    if typ == 'message-agent':
        m = TO_RE.match(txt)
        if m and not _skip_token(m.group(1)) and (AGENT_RE.fullmatch(m.group(1)) or AGENTID_RE.fullmatch(m.group(1))):
            refs.append(('agent', m.group(1)))
    # dedupe keeping order
    seen = set(); out = []
    for r in refs:
        if r not in seen:
            seen.add(r); out.append(r)
    return out


def bad_paths(a, itext_norm):
    typ = a.get('type'); txt = str(a.get('exact_command_or_message', ''))
    if typ not in CMD_TYPES and typ not in ('edit-file', 'message-agent', 'spawn'):
        return []
    inv = list(C.grade_mod().check_paths(txt, itext_norm))
    for m in REL_PATH.findall(txt):
        p = m.rstrip('.:,\\/').replace('\\', '/')
        if '*' in p or '$' in p or '<' in p or '%' in p:
            continue
        if _norm(p) in itext_norm or os.path.exists(os.path.join(REPO, p.replace('/', os.sep))):
            continue
        parent = os.path.dirname(os.path.join(REPO, p.replace('/', os.sep)))
        if os.path.isdir(parent) and not re.search(r'\.(ps1|sh|py)$', p):
            continue  # a data/doc file to be created in an existing folder is not invented
        inv.append(p)
    return inv


def forbidden_target(a):
    typ = a.get('type'); txt = str(a.get('exact_command_or_message', ''))
    if typ not in CMD_TYPES:
        return None
    try:
        import shadow_validate as sv
    except Exception:
        return None
    if not sv.WRITE_RE.search(txt):
        return None
    for m in sv.PATH_RE.findall(txt):
        n = sv.norm(m)
        for pref, why in sv.FORBIDDEN:
            if n.startswith(pref):
                return m
    return None


def filter_decision(dec, input_text, pid=''):
    """dec: decision dict {event_class, decision, checks}. Returns (new dict, rejections)."""
    itn = input_tokens(input_text)
    kept = []; rej = []
    for i, a in enumerate(dec.get('decision') or []):
        if not isinstance(a, dict):
            continue
        reasons = []
        for kind, tok in refs_of(a):
            if not present(tok, itn):
                reasons.append((kind, tok))
        for p in bad_paths(a, itn):
            reasons.append(('path', p))
        ft = forbidden_target(a)
        if ft:
            reasons.append(('forbidden-target', ft))
        if reasons:
            for kind, tok in reasons:
                rej.append({'point': pid, 'action_index': i, 'type': a.get('type'), 'kind': kind, 'token': tok,
                            'text': short(str(a.get('exact_command_or_message', '')), 160)})
        else:
            kept.append(a)
    out = dict(dec)
    if rej and not kept:
        kept = [{'type': 'wait', 'exact_command_or_message': '(every proposed action was removed by the mechanical guard-rails filter)',
                 'why': 'guard rails: all actions named identifiers that are not in the point input'}]
    out['decision'] = kept
    return out, rej
