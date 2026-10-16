"""Selftest for the live shadow kit: fake transcript -> feeder -> wait -> say -> validator, and the read-only guard.
Run: python -I tools/automation/shadow/shadow_selftest.py   (needs Git Bash for the .sh wrappers; uses a temp dir, never the real shadow dir)"""
import json, os, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(os.path.dirname(HERE), 'hooks', 'shadow-readonly-guard.py')
PY = sys.executable
BASH = r'C:\Program Files\Git\bin\bash.exe'
fails, passes = [], 0


def chk(name, cond, extra=''):
    global passes
    if cond:
        passes += 1
        print('PASS', name)
    else:
        fails.append(name)
        print('FAIL', name, extra)


def line(**kw):
    return json.dumps(kw) + '\n'


def sh(script, args, env, stdin=None, timeout=60):
    script_u = script.replace('\\', '/')
    r = subprocess.run([BASH, script_u] + args, input=(stdin or '').encode(), capture_output=True, env=env, timeout=timeout)
    return r.returncode, r.stdout.decode('utf-8', 'replace'), r.stderr.decode('utf-8', 'replace')


def audit_tests(tmp):
    """shadow_audit.py against a temp git repo and a temp runs dir (offline, never the real ones)."""
    audit = os.path.join(HERE, 'shadow_audit.py')
    repo = os.path.join(tmp, 'arepo')
    runs = os.path.join(tmp, 'aruns')
    for d in ('tools', 'docs', 'testing', 'pending-fixes'):
        os.makedirs(os.path.join(repo, d))
    for d in ('shadow', 'agents', 'inflight', 'ledger', 'alerts', 'coordinator-x', 'queue'):
        os.makedirs(os.path.join(runs, d))
    gi = lambda *a: subprocess.run(['git', '-C', repo] + list(a), capture_output=True)
    gi('init', '-q')
    open(os.path.join(repo, 'tools', 'a.txt'), 'w').write('a')
    open(os.path.join(repo, 'docs', 'b.txt'), 'w').write('b')
    open(os.path.join(repo, 'testing', 't.txt'), 'w').write('t')
    open(os.path.join(repo, 'elsewhere.txt'), 'w').write('e')
    gi('add', '-A')
    gi('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'init')
    open(os.path.join(repo, 'docs', 'b.txt'), 'w').write('b changed before')  # dirty at baseline
    open(os.path.join(runs, 'queue', 'q1'), 'w').write('1')

    def run(*a):
        r = subprocess.run([PY, '-I', audit, '--repo', repo, '--runs', runs] + list(a), capture_output=True)
        return r.returncode, r.stdout.decode('utf-8', 'replace') + r.stderr.decode('utf-8', 'replace')

    snap = os.path.join(tmp, 'audit-snap.json')
    rc, out = run('snapshot', '--out', snap)
    chk('audit: snapshot writes the file', rc == 0 and os.path.exists(snap), out)
    rc, out = run('check', '--snapshot', snap)
    chk('audit: unchanged tree reports no change (rc 0)', rc == 0 and '0 change line(s)' in out, out)
    # mutate: new file, edit dirty file again, delete tracked file, new runs file, edit runs file
    time.sleep(0.05)
    open(os.path.join(repo, 'testing', 'new.txt'), 'w').write('n')
    open(os.path.join(repo, 'docs', 'b.txt'), 'w').write('b changed AGAIN longer')
    os.remove(os.path.join(repo, 'tools', 'a.txt'))
    open(os.path.join(repo, 'elsewhere.txt'), 'w').write('outside audited paths')
    open(os.path.join(runs, 'queue', 'q2'), 'w').write('2')
    open(os.path.join(runs, 'queue', 'q1'), 'w').write('1 and more')
    for d in ('shadow', 'agents', 'inflight', 'ledger', 'alerts', 'coordinator-x'):
        open(os.path.join(runs, d, 'ignored.txt'), 'w').write('x')
    open(os.path.join(runs, 'coordinator-heartbeat.txt'), 'w').write('hb')
    rc, out = run('check', '--snapshot', snap)
    chk('audit: rc 1 when changes exist', rc == 1, out)
    chk('audit: new untracked repo file listed', 'GIT + ?? testing/new.txt' in out, out)
    chk('audit: deleted tracked file listed', 'GIT +  D tools/a.txt' in out, out)
    chk('audit: re-edited already-dirty file listed via mtime/size', 'FILE ~ docs/b.txt' in out, out)
    chk('audit: new runs file listed', 'RUN  + queue/q2' in out, out)
    chk('audit: edited runs file listed', 'RUN  ~ queue/q1' in out, out)
    chk('audit: file outside the audited repo paths not listed', 'elsewhere.txt' not in out, out)
    chk('audit: excluded runs folders and coordinator* not listed', 'ignored.txt' not in out and 'coordinator' not in out, out)
    # baseline-git mode (no mtime snapshot), baseline text taken from the earlier state incl. a UTF-8 BOM and CRLF
    base = os.path.join(tmp, 'audit-base-git.txt')
    open(base, 'wb').write(b'\xef\xbb\xbf M docs/b.txt\r\n')
    rc, out = run('check', '--baseline-git', base, '--snapshot', os.path.join(tmp, 'no-such.json'))
    chk('audit: missing explicit --snapshot is an error (rc 2)', rc == 2 and 'ERROR' in out, out)
    rc, out = run('check', '--baseline-git', base)
    chk('audit: baseline-git only: new/removed git lines listed', rc == 1 and 'GIT + ?? testing/new.txt' in out and 'GIT +  D tools/a.txt' in out and 'no mtime check' in out, out)
    chk('audit: baseline-git only: a line present in the baseline is not reported', 'docs/b.txt' not in out, out)
    rc, out = run('check', '--baseline-git', base, '--since', '2000-01-01 00:00')
    chk('audit: baseline-git + --since lists dirty files and runs files by mtime', 'FILE ~ testing/new.txt' in out and 'RUN  ~ queue/q2' in out and 'RUN  ~ queue/q1' in out, out)
    rc, out = run('check', '--baseline-git', base, '--since', '2999-01-01 00:00')
    chk('audit: --since in the future lists no mtime changes', 'mtime-only' not in out, out)
    rc, out = run('check', '--baseline-git', os.path.join(tmp, 'missing.txt'))
    chk('audit: missing baseline file is an error (rc 2)', rc == 2, out)
    rc, out = run('check')
    chk('audit: no baseline at all is an error (rc 2)', rc == 2, out)
    # read-only: the audit must not have touched the repo or runs dir
    chk('audit: read-only (no stray files created in repo or runs)', not os.path.exists(os.path.join(repo, 'audit-snap.json')) and not os.path.exists(os.path.join(runs, 'shadow', 'audit-pre.json')))


def main():
    tmp = tempfile.mkdtemp(prefix='shadowtest_')
    sdir = os.path.join(tmp, 'shadow')
    os.makedirs(sdir)
    tr = os.path.join(tmp, 'coord.jsonl')
    open(tr, 'w').write(line(type='user', uuid='old', message={'role': 'user', 'content': 'old line before start'}))
    env = dict(os.environ, SHADOW_DIR=sdir, SHADOW_QUIET_S='2', SHADOW_MAX_AGE_S='6', SHADOW_RUNS_DIR=os.path.join(tmp, 'runs'))
    os.makedirs(env['SHADOW_RUNS_DIR'] + r'\queue\running')
    feeder = subprocess.Popen([PY, '-I', os.path.join(HERE, 'shadow_feed.py'), '--transcript', tr, '--dir', sdir, '--max-min', '2'], env=env)
    time.sleep(2.5)
    with open(tr, 'a') as f:
        f.write(line(type='assistant', uuid='a1', timestamp='2026-10-16T21:00:00.000Z', message={'role': 'assistant', 'content': [{'type': 'tool_use', 'id': 't1', 'name': 'Bash', 'input': {'command': 'echo hi'}}]}))
        f.write(line(type='user', uuid='u1', timestamp='2026-10-16T21:00:01.000Z', message={'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': 't1', 'content': 'hi\n' + 'x' * 5000}]}))
        f.write(line(type='user', uuid='u2', timestamp='2026-10-16T21:00:02.000Z', origin={'kind': 'peer', 'from': 'abc'}, isMeta=True,
                     message={'role': 'user', 'content': 'Another session sent:\n[Subagent hand-back] DONE x'}))
        f.write(line(type='attachment', uuid='at1', timestamp='2026-10-16T21:00:03.000Z', attachment={'type': 'hook_blocking_error', 'hookName': 'Stop', 'hookEvent': 'Stop', 'blockingError': {'blockingError': 'sweep please'}}))
        f.write(line(type='user', uuid='u3', timestamp='2026-10-16T21:00:04.000Z', origin={'kind': 'human'}, message={'role': 'user', 'content': 'hello coordinator'}))
        f.write(line(type='assistant', uuid='a2', timestamp='2026-10-16T21:00:05.000Z', message={'role': 'assistant', 'content': [{'type': 'text', 'text': 'I will do X'}]}))
        f.write('{"type":"user","partial')  # partial line must wait
    time.sleep(5)
    feed = [json.loads(x) for x in open(os.path.join(sdir, 'feed.jsonl'))] if os.path.exists(os.path.join(sdir, 'feed.jsonl')) else []
    evs = [e for b in feed if 'events' in b for e in b['events']]
    kinds = [e['kind'] for e in evs]
    chk('feeder: old line before start not fed', all('old line' not in e['text'] for e in evs))
    chk('feeder: kinds tool_result,subagent_handback,stop_hook_feedback,user_message', kinds == ['tool_result', 'subagent_handback', 'stop_hook_feedback', 'user_message'], kinds)
    chk('feeder: tool_result carries the tool name and is truncated <= ~3100 chars', evs and evs[0]['text'].startswith('[result of Bash: echo hi]') and len(evs[0]['text']) < 3100)
    acts = [json.loads(x) for x in open(os.path.join(sdir, 'real-actions.jsonl'))]
    chk('feeder: real-actions has the tool_use and the text', [a['kind'] for a in acts] == ['tool_use', 'text'], acts)
    # wait / say
    rc, out, err = sh(os.path.join(HERE, 'shadow-wait.sh'), ['H', '--timeout', '3'], env)
    chk('wait: prints the batch', rc == 0 and '=== BATCH 1' in out and 'hello coordinator' in out, out[:200] + err[:200])
    rc, out, err = sh(os.path.join(HERE, 'shadow-wait.sh'), ['H', '--timeout', '3'], env)
    chk('wait: second call has no new events', 'NO NEW EVENTS' in out, out)
    rc, out, err = sh(os.path.join(HERE, 'shadow-wait.sh'), ['S', '--timeout', '3'], env)
    chk('wait: other arm has its own cursor', '=== BATCH 1' in out, out[:100])
    say = os.path.join(HERE, 'shadow-say.sh')
    good = json.dumps({'class': 'relay/hand-back', 'event_ids': ['e2'], 'actions': [{'type': 'ack', 'exact_command_or_message': 'echo ack', 'why': 'x'}]})
    rc, out, err = sh(say, ['H', '1'], env, good)
    chk('say: good decision recorded', rc == 0 and out.startswith('recorded') and '0 validator error' in out, out + err)
    bad_stobe = json.dumps({'class': 'other', 'actions': [{'type': 'mark-row', 'exact_command_or_message': 'stobe-auto wait-world 120', 'why': 'x'}]})
    rc, out, err = sh(say, ['H', '1'], env, bad_stobe)
    chk('say: bare stobe-auto caught', 'bare stobe-auto' in out and '1 validator error' in out, out)
    bad_path = json.dumps({'class': 'other', 'actions': [{'type': 'ack', 'exact_command_or_message': 'bash C:/KenshiModding/tools/automation/does-not-exist-xyz.sh arg', 'why': 'x'}]})
    rc, out, err = sh(say, ['H', '1'], env, bad_path)
    chk('say: missing script path caught', 'script not found' in out, out)
    bad_syn = json.dumps({'class': 'other', 'actions': [{'type': 'ack', 'exact_command_or_message': 'echo "unterminated', 'why': 'x'}]})
    rc, out, err = sh(say, ['H', '1'], env, bad_syn)
    chk('say: bash syntax error caught', 'bash -n' in out, out)
    live = json.dumps({'class': 'other', 'actions': [{'type': 'edit-file', 'exact_command_or_message': 'patch x', 'path': 'D:/Steam/steamapps/common/Kenshi/mods/x.cfg', 'why': 'x'}]})
    rc, out, err = sh(say, ['H', '1'], env, live)
    chk("say: edit of Shay's live install caught", 'FORBIDDEN' in out, out)
    q = os.path.join(env['SHADOW_RUNS_DIR'], 'queue', 'running', 'list1')
    open(q, 'w').write('bash C:/KenshiModding/tools/automation/shadow/shadow_lib.py\n')
    run = json.dumps({'class': 'other', 'actions': [{'type': 'ack', 'exact_command_or_message': 'sed -i s/a/b/ C:/KenshiModding/tools/automation/shadow/shadow_lib.py', 'why': 'x'}]})
    rc, out, err = sh(say, ['H', '1'], env, run)
    chk('say: edit of a script used by a running list caught', 'running batch' in out, out)
    rc, out, err = sh(say, ['H', '1'], env, json.dumps({'class': 'other', 'actions': [{'type': 'ignore', 'exact_command_or_message': '', 'why': ''}]}))
    chk('say: ignore without why rejected', rc != 0 and 'REJECTED' in out, out)
    rc, out, err = sh(say, ['H', '1'], env, 'not json')
    chk('say: invalid JSON rejected', rc != 0 and 'REJECTED' in out, out)
    led = [json.loads(x) for x in open(os.path.join(sdir, 'ledger-H.jsonl'))]
    chk('say: ledger has validator verdicts, 6 lines', len(led) == 6 and all('validator' in a for l in led for a in l['actions']), len(led))
    # END
    open(os.path.join(sdir, 'STOP'), 'w').write('x')
    feeder.wait(timeout=20)
    rc, out, err = sh(os.path.join(HERE, 'shadow-wait.sh'), ['H', '--timeout', '3'], env)
    chk('wait: END after STOP once batches are printed', out.strip() == 'END', out)
    chk('feeder: END marker file', os.path.exists(os.path.join(sdir, 'END')))
    # guard
    proj = os.path.join(tmp, 'proj'); sess = 'sess1'
    sub = os.path.join(proj, sess, 'subagents'); os.makedirs(sub)
    json.dump({'description': '[case:bench] [shadow:H] shadow coordinator H'}, open(os.path.join(sub, 'agent-sh1.meta.json'), 'w'))
    json.dump({'description': '[case:generate] normal'}, open(os.path.join(sub, 'agent-nm1.meta.json'), 'w'))
    sd = sdir.replace('\\', '/')

    def g(tool, ti, agent='sh1'):
        inp = {'tool_name': tool, 'tool_input': ti, 'session_id': sess, 'transcript_path': os.path.join(proj, sess + '.jsonl'), 'cwd': 'C:\\KenshiModding'}
        if agent:
            inp['agent_id'] = agent
        r = subprocess.run([PY, '-I', GUARD], input=json.dumps(inp).encode(), capture_output=True, env=env)
        return r.returncode

    B = lambda c, **k: g('Bash', {'command': c}, **k)
    chk('guard: main session (no agent_id) is a no-op for Edit', g('Edit', {}, agent=None) == 0)
    chk('guard: non-shadow subagent is a no-op for Edit', g('Edit', {}, agent='nm1') == 0)
    chk('guard: non-shadow subagent may run rm', B('rm -rf /c/x', agent='nm1') == 0)
    for t in ('Edit', 'Write', 'NotebookEdit', 'Agent', 'SendMessage', 'TaskStop', 'Skill', 'Monitor', 'WebFetch'):
        chk('guard: shadow denied tool ' + t, g(t, {}) == 2)
    for t in ('Read', 'Glob', 'Grep', 'ToolSearch', 'SubagentHandback'):
        chk('guard: shadow allowed tool ' + t, g(t, {}) == 0)
    allow = ['cat /c/KenshiModding/CLAUDE.md | head -5', 'grep -n foo tools/automation/*.sh | wc -l', 'ls -la /c/KenshiTestRuns/agents', 'git log --oneline -3', 'git -C /c/KenshiModding diff --stat',
             'find /c/KenshiTestRuns -name "*.status" -mmin -10', 'sed -n 1,20p testing/HANDOFF.md', 'tail -n 20 /c/KenshiTestRuns/queue/running/x 2>&1', 'cat a.txt > ' + sd + '/note.txt',
             'rm ' + sd + '/old.txt', 'echo hi >/dev/null 2>&1', 'powershell -NoProfile -File "C:\\KenshiModding\\tools\\automation\\setupfail.ps1" list',
             'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\\KenshiModding\\tools\\automation\\agent-rollcall.ps1"',
             'powershell -NoProfile -File C:/KenshiModding/tools/automation/program-ledger.ps1 show', 'bash /c/KenshiModding/tools/automation/shadow/shadow-wait.sh H',
             "bash tools/automation/shadow/shadow-say.sh H 3 <<'EOF'\n{\"class\":\"other\",\"actions\":[{\"type\":\"ignore\",\"why\":\"a $(x) b\"}]}\nEOF",
             'MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root -- cat /root/imm26/codemap/x.txt',
             "MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root bash -c 'grep -c foo /root/x | head -1'",
             'cd /c/KenshiModding && git status --short | head']
    for c in allow:
        chk('guard: allow ' + c[:60].replace('\n', ' '), B(c) == 0)
    deny = ['echo x > /c/KenshiModding/testing/HANDOFF.md', 'cat a >> ../x.txt', 'rm -rf /c/KenshiTestRuns/queue', 'mv a b', 'cp a /c/KenshiModding/b', 'tee /c/x < a', 'sed -i s/a/b/ f', 'git commit -m x',
            'git push', 'git checkout -- f', 'git add .', 'python -c "print(1)"', 'python3 x.py', 'echo $(rm -rf /)', 'echo `id`', 'kenshi-ctl.ps1 stop', 'stobe-auto wait-world 120',
            'powershell -File C:/KenshiModding/tools/automation/session-start.ps1 -Brief', 'powershell -File C:/KenshiModding/tools/automation/setupfail.ps1 close 24-b', 'powershell -Command "Remove-Item x"',
            'powershell -File C:/KenshiModding/tools/automation/agent-status.ps1 a RUNNING t', 'bash tools/automation/lane-setup.sh', 'bash tools/automation/mark-row.py', 'find . -delete', 'find . -exec rm {} ;',
            'awk \'BEGIN{system("rm x")}\'', 'curl http://x', 'ssh 4080 ls', 'xargs rm', 'eval ls', 'wsl.exe -d D -u root -- rm -rf /root/x', "wsl.exe -d D -u root bash -c 'rm -rf /root/x'",
            'cat x | tee /c/KenshiModding/y', 'ls; rm /c/x', 'touch /c/KenshiModding/x', 'git diff --output=/c/x', 'bash -c "echo hi"', 'nohup foo &']
    for c in deny:
        chk('guard: deny ' + c[:60], B(c) == 2)
    P = lambda c: g('PowerShell', {'command': c})
    for c in ('Get-Content C:\\KenshiTestRuns\\agents\\x.status | Select-Object -First 5', 'Get-ChildItem C:\\KenshiTestRuns\\agents | Where-Object { $_.Length -gt 1 } | Measure-Object', 'Test-Path C:\\x', 'git log --oneline -3'):
        chk('guard PS: allow ' + c[:50], P(c) == 0)
    for c in ('Set-Content x y', 'Remove-Item x', 'Get-Content a > C:\\KenshiModding\\b.txt', 'Start-Process notepad', 'kenshi-ctl.ps1 stop', '[IO.File]::WriteAllText("a","b")', 'rm x', 'Invoke-Expression "x"'):
        chk('guard PS: deny ' + c[:50], P(c) == 2)
    chk('guard: denials are logged', os.path.exists(os.path.join(sdir, 'guard.log')))
    audit_tests(tmp)
    try:
        feeder.kill()
    except Exception:
        pass
    print('\nSELFTEST %s: %d passed, %d failed (temp %s)' % ('PASS' if not fails else 'FAIL', passes, len(fails), tmp))
    for f in fails:
        print('  failed:', f)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
