"""Shared helpers for the coordinator shadow replay (stage 1).

Windows python, stdlib only. Parses coordinator transcripts line by line (never whole).
"""
import json, re, os, glob, subprocess, bisect, datetime

PROJ = r'C:\Users\Shay\.claude\projects\C--KenshiModding'
REPO = r'C:\KenshiModding'
REPLAY = r'C:\KenshiTestRuns\shadow\replay'
POINTS = os.path.join(REPLAY, 'points')

# Coordinator (main-thread) sessions used for the dataset. The current coordinator #19 (efc58758) is excluded.
COORD_SESSIONS = ['5720e5b8', '2b1a8eca', '6cd72ef5', '6d1f3011', '4cdf261b', '2a0cfe9b', 'bea16970',
                  'ded82aa7', '48b778a7', '245d8ad7', '60ad9d7d', '3a21a7b9', '277ebe12', '322d19f5',
                  '880f6d36', '06891207', '3566926d', '1aac0ede', '5270be03']
EXCLUDE = ['efc58758']

CLASSES = ['relay', 'setup-fail', 'lane-alert', 'waker-digest', 'shay-message', 'stop-hook',
           'agent-stopped', 'build-compose', 'other']

SECRET_PATTERNS = [
    (re.compile(r'sk-[A-Za-z0-9_\-]{16,}'), 'sk-REDACTED'),
    (re.compile(r'(?i)(api[_-]?key|apikey|secret|password|passwd|token|bearer)(["\'\s:=]+)([A-Za-z0-9_\-\.=/+]{12,})'), r'\1\2REDACTED'),
    (re.compile(r'\bghp_[A-Za-z0-9]{20,}'), 'ghp_REDACTED'),
    (re.compile(r'\bxox[bap]-[A-Za-z0-9\-]{10,}'), 'xox-REDACTED'),
    (re.compile(r'AKIA[0-9A-Z]{16}'), 'AKIAREDACTED'),
    (re.compile(r'eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'), 'JWT_REDACTED'),
]


def redact(s):
    for pat, rep in SECRET_PATTERNS:
        s = pat.sub(rep, s)
    return s


def trunc(s, n):
    s = s if isinstance(s, str) else str(s)
    if len(s) <= n:
        return s
    return s[:n] + '...[truncated %d chars]' % (len(s) - n)


def session_path(prefix):
    g = glob.glob(os.path.join(PROJ, prefix + '*.jsonl'))
    return g[0] if g else None


def result_text(block):
    cc = block.get('content')
    if isinstance(cc, list):
        cc = '\n'.join(x.get('text', '') for x in cc if isinstance(x, dict))
    return str(cc if cc is not None else '').lstrip('\ufeff')


def load_stream(path):
    """Normalise a transcript into ordered entries.
    ('U', ts, text) user/queued inbound; ('R', ts, tool_use_id, text) tool result;
    ('A', ts, [blocks]) assistant (consecutive lines of one message merged); ('H', ts, text) hook context.
    """
    ent = []
    last_msg = None
    with open(path, encoding='utf-8') as f:
        for line in f:
            try:
                o = json.loads(line)
            except Exception:
                continue
            t = o.get('type')
            ts = o.get('timestamp') or ''
            if t == 'user':
                m = o['message']['content']
                if isinstance(m, str):
                    ent.append(['U', ts, m]); last_msg = None
                else:
                    for b in m:
                        if b.get('type') == 'tool_result':
                            ent.append(['R', ts, b.get('tool_use_id'), result_text(b)])
                        elif b.get('type') == 'text':
                            ent.append(['U', ts, b.get('text', '')])
                    last_msg = None
            elif t == 'assistant':
                mid = o['message'].get('id')
                blocks = [b for b in o['message']['content'] if isinstance(b, dict)]
                if ent and ent[-1][0] == 'A' and last_msg == mid and mid:
                    ent[-1][2].extend(blocks)
                else:
                    ent.append(['A', ts, blocks])
                last_msg = mid
            elif t == 'attachment':
                a = o.get('attachment') or {}
                at = a.get('type')
                if at == 'queued_command':
                    p = a.get('prompt')
                    if isinstance(p, list):
                        p = '\n'.join(x.get('text', '') for x in p if isinstance(x, dict))
                    ent.append(['U', ts, str(p or '')]); last_msg = None
                elif at == 'hook_additional_context':
                    c = a.get('content')
                    c = '\n'.join(c) if isinstance(c, list) else str(c)
                    ent.append(['H', ts, c])
    return ent


SKIP_PREFIXES = ('Permission granted for', '<local-command', '<command-name', '<bash-input', '<bash-stdout',
                 '<bash-stderr', 'This session is being continued', '## Context Usage', 'Read the handoff at',
                 '<command-message', '[Request interrupted')


def is_inbound(e):
    if e[0] != 'U':
        return False
    t = e[2].lstrip()
    if not t:
        return False
    return not any(t.startswith(p) for p in SKIP_PREFIXES)


def tool_uses(entry):
    return [b for b in entry[2] if b.get('type') == 'tool_use']


def a_text(entry):
    return '\n'.join(b.get('text', '') for b in entry[2] if b.get('type') == 'text').strip()


# ---------------------------------------------------------------- action typing
READ_CMD = re.compile(r'^(cat|ls|grep|rg|tail|head|date|wc|find|stat|test|\[|echo|sed -n|diff|cmp|file|pwd|which|type|'
                      r'Get-Content|Get-ChildItem|Select-String|Get-Item|Test-Path|Get-Process|Get-Date|ps|df|du|'
                      r'git (status|log|diff|show|rev-parse|branch|ls-files|remote|config)|'
                      r'python3? -c|awk|sort|uniq|jq|tasklist|wsl\.exe .*(cat|ls|grep|tail|head) )', re.I)
READ_SCRIPTS = re.compile(r'(session-start\.ps1|agent-rollcall\.ps1|setupfail\.ps1\s+(list|show|status)|'
                          r'program-ledger\.ps1\s+(show|list|records|status)|agent-health|rig-health|'
                          r'tail-mode\.ps1\s+(status|list)|alert-scan\.ps1|pilot-audit\.py|cost-audit\.py|codemap\.sh)', re.I)


def strip_prefix(cmd):
    c = cmd.strip()
    while True:
        m = re.match(r'^(cd\s+[^;&|\n]+?\s*(;|&&)\s*|Set-Location\s+[^;\n]+;\s*|MSYS_NO_PATHCONV=1\s+)', c)
        if not m:
            break
        c = c[m.end():].lstrip()
    return c


def split_segments(cmd):
    return [s.strip() for s in re.split(r'(?:\n|;|&&|\|\|)', cmd) if s.strip()]


def is_readonly_cmd(cmd):
    segs = [strip_prefix(s) for s in split_segments(strip_prefix(cmd))]
    if not segs:
        return True
    for s in segs:
        s0 = s
        if re.search(r'(?<![0-9&])>(?!&|/dev/null)\s*[^\s&]', re.sub(r'2>&1|>\s*/dev/null|2>\s*/dev/null|2>\$null', '', s0)):
            return False
        if re.search(r'\b(Set-Content|Out-File|Add-Content|Remove-Item|rm |mv |cp |sed -i|tee |Start-Process|kill|Stop-Process|'
                     r'git (add|commit|push|checkout|reset|apply|merge|rebase|stash)|touch |mkdir|New-Item|Move-Item|Copy-Item)', s0):
            return False
        if READ_SCRIPTS.search(s0):
            continue
        if re.match(r'^(powershell|pwsh)\b', s0, re.I):
            return False if not READ_SCRIPTS.search(s0) else True
        if READ_CMD.match(s0):
            continue
        if re.match(r'^(\||\)|\}|fi|done|then|else|do)\b', s0):
            continue
        return False
    return True


def action_of(tu):
    """Map one tool_use to (type, text) in the decision schema, or None to drop bookkeeping."""
    n = tu.get('name'); inp = tu.get('input') or {}
    if n in ('Agent', 'Task'):
        return ('spawn', 'description: %s\nprompt: %s' % (inp.get('description', ''), trunc(inp.get('prompt', ''), 2500)))
    if n == 'SendMessage':
        to = str(inp.get('to', ''))
        kind = 'message-agent' if (re.match(r'^a[0-9a-f]{16}$', to) or 'coordinator' in to or to.startswith('imm26') or to == '*') else 'message-shay'
        return (kind, 'to=%s: %s' % (to, trunc(inp.get('message', ''), 2000)))
    if n == 'TaskStop':
        return ('stop-agent', json.dumps(inp)[:300])
    if n in ('Edit', 'Write', 'NotebookEdit'):
        fp = inp.get('file_path', '')
        intent = inp.get('old_string') if n == 'Edit' else inp.get('content')
        return ('edit-file', '%s :: %s' % (fp, trunc(redact(str(intent or '')), 300)))
    if n in ('Read', 'Grep', 'Glob', 'ToolSearch', 'ListAgents'):
        return ('investigate', n + ' ' + trunc(json.dumps(inp), 200))
    if n == 'Monitor':
        return ('restart-waker', trunc(json.dumps(inp), 300))
    if n in ('Bash', 'PowerShell'):
        cmd = inp.get('command', '')
        if re.search(r'agent-ids\.ps1\s+add', cmd) and len(cmd) < 400:
            return None
        if re.search(r'(alert-ack\.ps1|tail-ack\.ps1|agent-abandon\.ps1)', cmd):
            return ('ack', trunc(cmd, 700))
        if re.search(r'(bash\s+\S*event-wait\.sh|rearm-waker\.ps1|tail-wait\.ps1)', cmd) and not re.search(r'(sed -i|cat >|tail -c|^\s*grep )', cmd):
            return ('restart-waker', trunc(cmd, 500))
        if re.search(r'tail-relay\.ps1', cmd):
            return ('message-agent', trunc(cmd, 700))
        if re.search(r'lanes\.held', cmd) and not is_readonly_cmd(cmd):
            return ('release-lane' if re.search(r'(sed -i|grep -v|Where-Object|-notmatch|remove)', cmd, re.I) else 'hold-lane', trunc(cmd, 500))
        if re.search(r'(mark-row\.py|setupfail\.ps1\s+(mark|resolve|close|done))', cmd):
            return ('mark-row', trunc(cmd, 700))
        if re.search(r'git\s+(\S+\s+)*commit', cmd) or re.search(r'git\s+(\S+\s+)*push', cmd):
            return ('commit', trunc(redact(cmd), 900))
        if is_readonly_cmd(cmd):
            return ('investigate', trunc(cmd, 300))
        return ('run', trunc(redact(cmd), 900))
    return ('run', n + ' ' + trunc(json.dumps(inp), 200))
