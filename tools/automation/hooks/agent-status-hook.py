#!/usr/bin/env python3
"""agent-status-hook.py (cut3, Shay-approved credit cut 2026-10-16): subagent status without spending a model turn.

One hook script for three events (settings snippets: C:\\KenshiTestRuns\\inbox\\operators\\cut3.txt):
  SubagentStart  resolve the agent's status NAME from its brief, register agentId -> name, write RUNNING (agent-status.ps1, so the inflight
                 marker / respawn-todo / ledger-sync semantics are the single existing implementation).
  PostToolUse    (any tool, only calls made by a subagent = hook input has agent_id) at most once per STAMP_MIN minutes re-stamp the status
                 file: line 1 time + `latest: auto HH:mm [calls=N] Tool: arg`. Touches the inflight marker. A fresh manual `latest:` (the agent
                 called agent-status/agent-note in the last 10 min) is kept. Never resurrects: only a status that is still RUNNING and owned by this
                 agentId is stamped.
  SubagentStop   if the status is still RUNNING, close it from last_assistant_message: STOPPED-CONTEXT / FAILED (first line says so, or empty
                 final message) / else DONE. Goes through agent-status.ps1 (deletes the inflight marker on DONE, writes respawn todo on STOPPED-CONTEXT).

Dead-agent detection is unchanged by design:
  - an agent that dies/is killed makes no tool calls -> no stamps -> status mtime ages -> ORPHANED after 30 min (agent-guard-lib.ps1) exactly as before;
  - SubagentStop never DONEs an empty/killed ending (it writes FAILED, which the Stop hook and session-start flag as NO SUCCESSOR);
  - stamping stops after WAIT_CAP_MIN minutes with only wait-type calls (Monitor/sleep/event-wait/status reads), so a spinning poller still goes stale;
  - the hook never touches a status that is FAILED / STOPPED-CONTEXT / DONE / abandoned.

Env: KAH_RUNS_DIR (runs root, default C:\\KenshiTestRuns), KAH_STATUS_STAMP_MIN (default 5), KAH_STATUS_WAIT_CAP_MIN (default 20),
     KAH_STATUS_HOOK_ANYCWD=1 (tests: skip the cwd filter), KAH_STATUS_NO_PS=1 (tests: write via the built-in writer, no powershell).
Task text: <runs>/agents/<name>.task (first line) if present (lane-brief.ps1 candidate writes it), else `auto: <name> | <description>`.
Registry: <runs>\\agents\\auto\\<agentId>.json  and  <runs>\\agents\\auto\\by-name\\<name>.txt (= current agentId of that name).
Name resolution (first hit wins, read from the agent's own transcript first user message, meta.json description as fallback):
  1. `[status-name:NAME]` / `Status name: NAME`   2. `agent-status.ps1 NAME RUNNING|DONE|...`   3. `agents\\NAME.status`
  4. `You are NAME` when NAME looks like an id (contains - _ or a digit and is not a bare word).
Never blocks: any error -> exit 0 (SubagentStop never returns a block decision).
"""
import json, os, re, subprocess, sys, time

RUNS = os.environ.get('KAH_RUNS_DIR') or r'C:\KenshiTestRuns'
STAMP_MIN = float(os.environ.get('KAH_STATUS_STAMP_MIN') or 5)
WAIT_CAP_MIN = float(os.environ.get('KAH_STATUS_WAIT_CAP_MIN') or 20)
AGENT_STATUS_PS1 = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'agent-status.ps1')
AGENTS = os.path.join(RUNS, 'agents')
AUTO = os.path.join(AGENTS, 'auto')
NAME_OK = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,80}$')
STATES = ('RUNNING', 'DONE', 'FAILED', 'STOPPED-CONTEXT')


def now():
    return time.time()


def log(msg):
    try:
        os.makedirs(AUTO, exist_ok=True)
        p = os.path.join(AUTO, 'hook.log')
        if os.path.exists(p) and os.path.getsize(p) > 200000:
            os.replace(p, p + '.old')
        with open(p, 'a', encoding='utf-8') as f:
            f.write('%s %s\n' % (time.strftime('%Y-%m-%dT%H:%M:%S'), msg))
    except Exception:
        pass


def jload(p, default=None):
    try:
        with open(p, 'r', encoding='utf-8-sig') as f:
            return json.load(f)
    except Exception:
        return default


def jsave(p, obj):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + '.%d.tmp' % os.getpid()
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f)
    os.replace(tmp, p)


# ---------------------------------------------------------------- status file
def read_status(name):
    """-> dict(state, hdr_name, lines[list of raw lines], task, latest, outputs, next, extra[list]) or None"""
    p = os.path.join(AGENTS, name + '.status')
    try:
        with open(p, 'r', encoding='utf-8-sig') as f:
            lines = f.read().splitlines()
    except Exception:
        return None
    if not lines:
        return None
    parts = [x.strip() for x in lines[0].split('|')]
    d = {'path': p, 'hdr_name': parts[0] if parts else '', 'state': parts[1] if len(parts) > 1 else '',
         'task': '', 'latest': '', 'outputs': '', 'next': '', 'extra': []}
    for ln in lines[1:]:
        m = re.match(r'^(task|latest|outputs|next):\s?(.*)$', ln)
        if m:
            d[m.group(1)] = m.group(2)
        elif ln.strip():
            d['extra'].append(ln)
    return d


def write_status(name, state, task, latest, outputs, nxt, extra=()):
    """Same 5-line format as agent-status.ps1 (UTF-8 with BOM). Used for RUNNING re-stamps only (no marker/ledger side effects needed)."""
    p = os.path.join(AGENTS, name + '.status')
    body = ['%s | %s | %s' % (name, state, time.strftime('%Y-%m-%d %H:%M')),
            'task: ' + task, 'latest: ' + latest, 'outputs: ' + outputs, 'next: ' + nxt] + list(extra)
    tmp = p + '.%d.tmp' % os.getpid()
    with open(tmp, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write('\r\n'.join(body) + '\r\n')
    os.replace(tmp, p)


def call_agent_status(name, state, task, step, outputs='', nxt=''):
    """Transition writes go through the one existing implementation (marker, respawn todo, program-ledger sync)."""
    if os.environ.get('KAH_STATUS_NO_PS') == '1':
        write_status(name, state, task, step, outputs, nxt)
        mk = os.path.join(RUNS, 'inflight', name)
        try:
            if state == 'RUNNING':
                os.makedirs(os.path.dirname(mk), exist_ok=True)
                if os.path.exists(mk):
                    os.utime(mk, None)
                else:
                    with open(mk, 'w') as f:
                        f.write(os.path.join(AGENTS, name + '.status'))
            elif state == 'DONE':
                for q in (mk, os.path.join(RUNS, 'respawn', name + '.todo')):
                    if os.path.exists(q):
                        os.remove(q)
        except Exception:
            pass
        return
    cmd = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', AGENT_STATUS_PS1, name, state, task, step, outputs, nxt]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25)


# ---------------------------------------------------------------- name resolution
def transcript_candidates(inp):
    aid = inp.get('agent_id') or ''
    out = []
    atp = inp.get('agent_transcript_path') or ''
    if atp:
        out.append(atp)
    tp = inp.get('transcript_path') or ''
    sid = inp.get('session_id') or ''
    base = os.path.dirname(tp) if tp else ''
    stem = os.path.splitext(os.path.basename(tp))[0] if tp else ''
    for s in (sid, stem):
        if s and base:
            out.append(os.path.join(base, s, 'subagents', 'agent-%s.jsonl' % aid))
    if base and os.path.basename(base) == 'subagents':
        out.append(os.path.join(base, 'agent-%s.jsonl' % aid))
    seen, res = set(), []
    for c in out:
        if c not in seen:
            seen.add(c)
            res.append(c)
    return res


def first_prompt_text(inp):
    """prompt of this subagent = first user message in its transcript (plus meta description)."""
    txt = ''
    for tp in transcript_candidates(inp):
        try:
            with open(tp, 'r', encoding='utf-8-sig', errors='replace') as f:
                line = f.readline(400000)
            j = json.loads(line)
            c = (j.get('message') or {}).get('content')
            if isinstance(c, list):
                c = '\n'.join(b.get('text', '') for b in c if isinstance(b, dict))
            txt = str(c or '')
            meta = jload(re.sub(r'\.jsonl$', '.meta.json', tp), {}) or {}
            txt += '\n' + str(meta.get('description') or '')
            if txt.strip():
                return txt, tp
        except Exception:
            continue
    return '', ''


def resolve_name(text):
    if not text:
        return ''
    def ok(n):
        return bool(NAME_OK.match(n)) and n.upper() not in STATES and n not in ('NAME', 'name', 'name>')

    for p in (r'\[status-name:([A-Za-z0-9._-]+)\]', r'[Ss]tatus name:\s*`?([A-Za-z0-9._-]+)`?', r'Your name is\s+`?([A-Za-z0-9._-]+)`?'):
        m = re.search(p, text)
        if m and ok(m.group(1).rstrip('._-')):
            return m.group(1).rstrip('._-')
    # "You are [operator|lane operator|agent] NAME": first id-like token (has - _ or a digit) after the first "You are" (a Routing: header line may precede it)
    m = re.search(r"(?m)^\s*(?:Routing:[^\n]*\n\s*)?You are\s+(?:an?\s+|the\s+)?(?:lane\s+|pilot\s+)?(?:operator\s+|agent\s+)?[`'\"]?([A-Za-z0-9][A-Za-z0-9._-]+)", text)
    if m and ok(m.group(1).rstrip('._-')) and re.search(r"[-_0-9]", m.group(1)):
        return m.group(1).rstrip('._-')
    for p in (r"agent-status\.ps1['\"]?\s+(?:-Name\s+)?['\"]?([A-Za-z0-9][A-Za-z0-9._-]+)['\"]?\s+(?:RUNNING|DONE|FAILED|STOPPED-CONTEXT)\b",
              r"agent-note\.ps1['\"]?\s+(?:-Name\s+)?['\"]?([A-Za-z0-9][A-Za-z0-9._-]+)['\"]?\s+['\"]",
              r"agents[\/]+([A-Za-z0-9][A-Za-z0-9._-]+)\.status\b"):
        m = re.search(p, text)
        if m and ok(m.group(1).rstrip('._-')):
            return m.group(1).rstrip('._-')
    return ''



def reg_path(aid):
    return os.path.join(AUTO, re.sub(r'[^A-Za-z0-9_-]', '_', aid) + '.json')


def register(inp, aid, wait=0.0):
    deadline = now() + wait
    while True:
        txt, tp = first_prompt_text(inp)
        name = resolve_name(txt)
        if name or now() >= deadline:
            break
        time.sleep(0.25)
    reg = jload(reg_path(aid), {}) or {}
    reg.update({'agent_id': aid, 'name': name, 'attempts': int(reg.get('attempts', 0)) + 1,
                'transcript': tp or reg.get('transcript', ''),
                'desc': (txt.splitlines()[-1] if txt else '')[:120],
                'started': reg.get('started') or now()})
    reg.setdefault('last_stamp', now())   # first auto stamp one STAMP_MIN after the start (RUNNING was just written)
    jsave(reg_path(aid), reg)
    if name:
        os.makedirs(os.path.join(AUTO, 'by-name'), exist_ok=True)
        with open(os.path.join(AUTO, 'by-name', name + '.txt'), 'w') as f:
            f.write(aid)
        st = read_status(name)
        # a fresh agent owns this name now (by-name file). Write RUNNING unless the agent already did (status is RUNNING).
        if st is None or st['state'] != 'RUNNING':
            # task text: <runs>gents\<name>.task (lane-brief.ps1 writes the exact text the successor rule needs), else an auto text that carries the name
            task = ''
            try:
                with open(os.path.join(AGENTS, name + '.task'), 'r', encoding='utf-8-sig') as f:
                    task = f.readline().strip()
            except Exception:
                pass
            call_agent_status(name, 'RUNNING', task or ('auto: %s | %s' % (name, reg.get('desc') or '')), 'started (auto, SubagentStart hook)', '', '')
    return reg


def owner_ok(reg):
    try:
        with open(os.path.join(AUTO, 'by-name', reg['name'] + '.txt')) as f:
            return f.read().strip() == reg['agent_id']
    except Exception:
        return True


def abandoned(name):
    return os.path.exists(os.path.join(AGENTS, name + '.abandoned'))


# ---------------------------------------------------------------- events
WAIT_TOOLS = {'Monitor', 'TaskOutput', 'ScheduleWakeup', 'TaskList', 'TaskGet'}
WAIT_CMD = re.compile(r'^\s*(?:bash\s+\S*)?(?:sleep\b|start-sleep\b|.*event-wait\.sh|.*agent-rollcall|.*status-digest|.*session-start)', re.I)


def tool_summary(inp):
    tool = str(inp.get('tool_name') or '?')
    ti = inp.get('tool_input') or {}
    arg = ''
    if tool in ('Bash', 'PowerShell'):
        arg = str(ti.get('command') or '')
    elif tool in ('Read', 'Edit', 'Write', 'NotebookEdit'):
        arg = str(ti.get('file_path') or '')
    elif tool in ('Grep', 'Glob'):
        arg = str(ti.get('pattern') or '')
    else:
        arg = str(ti.get('description') or ti.get('prompt') or '')
    arg = re.sub(r'\s+', ' ', arg).strip()
    return tool, arg[:90], arg


def is_wait(tool, full):
    if tool in WAIT_TOOLS:
        return True
    if tool in ('Bash', 'PowerShell') and WAIT_CMD.match(full or ''):
        return True
    return False


def on_post_tool(inp, aid):
    reg = jload(reg_path(aid))
    if reg is None or (not reg.get('name') and int(reg.get('attempts', 0)) < 4):
        reg = register(inp, aid)
    name = reg.get('name') or ''
    if not name:
        return
    tool, arg, full = tool_summary(inp)
    t = now()
    reg['calls'] = int(reg.get('calls', 0)) + 1
    if re.search(r'agent-status\.ps1|agent-note\.ps1', full):
        reg['manual_at'] = t
    if not is_wait(tool, full):
        reg['progress_at'] = t
    reg.setdefault('progress_at', reg.get('started') or t)
    reg['last_tool'] = '%s: %s' % (tool, arg)
    due = (t - float(reg.get('last_stamp', 0))) >= STAMP_MIN * 60
    if due and (t - float(reg['progress_at'])) <= WAIT_CAP_MIN * 60:
        st = read_status(name)
        if st and st['state'] == 'RUNNING' and st['hdr_name'] == name and not abandoned(name) and owner_ok(reg):
            keep_manual = (t - float(reg.get('manual_at', 0))) < 600 and not st['latest'].startswith('auto')
            latest = st['latest'] if keep_manual else 'auto %s [calls=%d] %s' % (time.strftime('%H:%M'), reg['calls'], reg['last_tool'])
            write_status(name, 'RUNNING', st['task'], latest, st['outputs'], st['next'],
                         [x for x in st['extra'] if not x.startswith('pulse:')][:6] + ['pulse: %s calls=%d %s' % (time.strftime('%H:%M:%S'), reg['calls'], reg['last_tool'][:80])])
            mk = os.path.join(RUNS, 'inflight', name)
            try:
                if os.path.exists(mk):
                    os.utime(mk, None)
            except Exception:
                pass
            reg['last_stamp'] = t
    jsave(reg_path(aid), reg)


def classify_end(msg):
    msg = (msg or '').strip()
    if not msg:
        return 'FAILED', 'ended with an empty final message'
    first = next((ln for ln in msg.splitlines() if ln.strip()), '')
    if re.search(r'\bSTOPPED-CONTEXT\b', msg):
        return 'STOPPED-CONTEXT', first[:160]
    if re.match(r'^\W*(?:(?:status|verdict|result)\W+)?FAILED\b', first, re.I):
        return 'FAILED', first[:160]
    return 'DONE', first[:160]


def on_stop(inp, aid):
    reg = jload(reg_path(aid))
    if reg is None or not reg.get('name'):
        reg = register(inp, aid)
    name = reg.get('name') or ''
    if not name:
        return
    st = read_status(name)
    if not st or st['state'] != 'RUNNING' or abandoned(name) or not owner_ok(reg):
        return  # the agent already reported (or someone else owns the name): leave it
    state, why = classify_end(inp.get('last_assistant_message'))
    if state == 'FAILED' and not (inp.get('last_assistant_message') or '').strip():
        # Hand-back delivered through SubagentHandback leaves an empty final message: a report saved by this agent means DONE, not FAILED.
        try:
            od = os.path.join(AGENTS, 'out', name)
            started = float(reg.get('started') or 0)
            if os.path.isdir(od) and any(os.path.getmtime(os.path.join(od, f)) >= started for f in os.listdir(od)):
                state, why = 'DONE', 'ended with an empty final message but a report was saved in agents/out/' + name
        except Exception:
            pass
    nxt = st['next']
    if state == 'STOPPED-CONTEXT':
        nxt = (nxt + ' | ' if nxt else '') + 'see ' + os.path.join(AGENTS, name + '.handoff.md') + ' / hand-back text'
    call_agent_status(name, state, st['task'], 'auto-closed by SubagentStop: ' + why, st['outputs'], nxt)
    reg['ended'] = now()
    reg['ended_state'] = state
    jsave(reg_path(aid), reg)


def sweep():
    try:
        cut = now() - 3 * 86400
        for fn in os.listdir(AUTO):
            p = os.path.join(AUTO, fn)
            if fn.endswith('.json') and os.path.getmtime(p) < cut:
                os.remove(p)
    except Exception:
        pass


def main():
    try:
        inp = json.loads(sys.stdin.buffer.read().decode('utf-8-sig', 'replace'))
    except Exception:
        return
    aid = inp.get('agent_id') or ''
    if not aid:
        return  # main session / not a subagent
    if os.environ.get('KAH_STATUS_HOOK_ANYCWD') != '1' and not re.match(r'^[Cc]:[\\/]KenshiModding([\\/]|$)', str(inp.get('cwd') or '')):
        return
    ev = inp.get('hook_event_name') or ''
    try:
        if ev == 'SubagentStart':
            sweep()
            register(inp, aid, wait=1.5)
        elif ev == 'SubagentStop':
            on_stop(inp, aid)
        elif ev == 'PostToolUse':
            on_post_tool(inp, aid)
    except Exception as e:
        log('error %s agent=%s: %r' % (ev, aid, e))


if __name__ == '__main__':
    main()
    sys.exit(0)
