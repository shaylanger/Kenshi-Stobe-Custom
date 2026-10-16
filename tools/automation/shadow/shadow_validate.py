"""Command validator for shadow decisions (docs/COORD_SHADOW_PLAN.md stage 2, mechanical command validity metric).
validate_action(action, runs_dir) -> {'ok': bool, 'errors': [...], 'warnings': [...]}
Checks per exact_command: syntax (bash -n / PowerShell parser), bare stobe-auto, forbidden targets (Shay's live install, saves, live server tree),
path existence, scripts used by a queued/running list or batch. Standard library only."""
import os, re, shutil, subprocess, sys, tempfile

RUNS_DEFAULT = r'C:\KenshiTestRuns'
REPO = 'c:/kenshimodding'

COMMAND_TYPES = {'ack', 'restart-waker', 'hold-lane', 'release-lane', 'mark-row', 'commit'}
FORBIDDEN = [  # (normalised prefix, why)
    ('d:/steam/steamapps/common/kenshi', "Shay's live Kenshi install"),
    ('c:/users/shay/appdata/local/kenshi', "Shay's live saves/config"),
    ('/var/www/html/stobeserver', "Shay's live server tree"),
    ('/mnt/wsl/var/www/html/stobeserver', "Shay's live server tree"),
]
WRITE_RE = re.compile(r'(\bsed\s+(-[A-Za-z]*i|--in-place)|\bcp\b|\bmv\b|\brm\b|\bmkdir\b|\btouch\b|\btee\b|\btruncate\b|\binstall\b|\bchmod\b|\bchown\b|'
                      r'(?<![0-9&])>>?(?!&)|\bSet-Content\b|\bOut-File\b|\bAdd-Content\b|\bRemove-Item\b|\bMove-Item\b|\bCopy-Item\b|\bNew-Item\b|'
                      r'\bgit\s+(checkout|restore|reset|apply|commit|push|add|rm|mv|stash|clean)\b|\binstall-dll\b|\bkenshi-ctl\b)', re.I)
PATH_RE = re.compile(r"""(?:[A-Za-z]:[\\/][^\s'"|;&<>()]+|/(?:mnt/[a-z]|[a-z]|root|var|tmp|home|etc|opt)/[^\s'"|;&<>()]+|(?<![\w./\\-])(?:tools|docs|testing|pending-fixes|components|handoff|archive|\.claude)[\\/][^\s'"|;&<>()]+)""")
SCRIPT_EXT = ('.ps1', '.sh', '.py', '.json', '.md', '.txt', '.php', '.cpp', '.bat', '.cmd', '.jsonl', '.tsv', '.status')


def norm(p):
    p = p.strip().strip('\'"').rstrip('.,;:)')
    p = p.replace('\\', '/')
    p = re.sub(r'^/mnt/([a-z])/', lambda m: m.group(1) + ':/', p)
    p = re.sub(r'^/([a-z])/', lambda m: m.group(1) + ':/', p)
    if re.match(r'^(tools|docs|testing|pending-fixes|components|handoff|archive|\.claude)/', p):
        p = REPO + '/' + p
    return p.lower().rstrip('/')


def to_win(p):
    """normalised path -> a path os.path.exists understands, or None (WSL-only paths cannot be checked)."""
    if re.match(r'^[a-z]:/', p):
        return p
    return None


def paths_in(cmd):
    out = []
    for m in PATH_RE.finditer(cmd):
        out.append((m.group(0), m.start()))
    return out


def running_set(runs):
    """normalised script/list paths referenced by queued or running lists/batches + prefixes of inflight batch out dirs."""
    files, prefixes = set(), set()
    q = os.path.join(runs, 'queue')
    try:
        names = [n for n in os.listdir(q) if n not in ('done', 'failed', 'cancelled', 'quarantine-bsod')]
    except OSError:
        names = []
    for n in names:
        p = os.path.join(q, n)
        flist = []
        if os.path.isdir(p):
            for r, _d, fs in os.walk(p):
                flist += [os.path.join(r, f) for f in fs]
        else:
            flist.append(p)
        for f in flist[:400]:
            try:
                with open(f, 'r', encoding='utf-8', errors='replace') as fh:
                    txt = fh.read(200000)
            except OSError:
                continue
            files.add(norm(f))
            for pth, _ in paths_in(txt):
                files.add(norm(pth))
    inf = os.path.join(runs, 'inflight')
    try:
        for n in os.listdir(inf):
            try:
                with open(os.path.join(inf, n), 'r', encoding='utf-8', errors='replace') as fh:
                    txt = fh.read(2000)
            except OSError:
                continue
            for pth, _ in paths_in(txt):
                prefixes.add(norm(pth))
    except OSError:
        pass
    return files, prefixes


def bash_exe():
    for c in (r'C:\Program Files\Git\bin\bash.exe', r'C:\Program Files\Git\usr\bin\bash.exe'):
        if os.path.exists(c):
            return c
    return shutil.which('bash')


def check_bash_syntax(cmd):
    b = bash_exe()
    if not b:
        return None, 'bash not found, syntax not checked'
    try:
        r = subprocess.run([b, '-n'], input=cmd.encode('utf-8'), capture_output=True, timeout=20)
    except Exception as e:
        return None, 'bash -n could not run: %r' % (e,)
    if r.returncode != 0:
        return False, 'bash -n: ' + (r.stderr.decode('utf-8', 'replace').strip()[:200])
    return True, ''


def check_ps_syntax(cmd):
    fd, tmp = tempfile.mkstemp(suffix='.ps1', prefix='shadowv_')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8-sig') as f:
            f.write(cmd)
        script = ("$e=$null;$t=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('%s',[ref]$t,[ref]$e);"
                  "if($e){$e|ForEach-Object{$_.Message};exit 3}" % tmp.replace("'", "''"))
        r = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script], capture_output=True, timeout=40)
        if r.returncode != 0:
            return False, 'powershell parse: ' + r.stdout.decode('utf-8', 'replace').strip()[:200]
        return True, ''
    except Exception as e:
        return None, 'powershell parse could not run: %r' % (e,)
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


def guess_shell(cmd, hint=None):
    if hint in ('bash', 'powershell'):
        return hint
    s = cmd.lstrip()
    if re.match(r'^(powershell|pwsh)(\.exe)?\b', s, re.I):
        return 'bash'  # an outer command line that launches powershell is parsed by the calling shell
    if re.match(r'^(&\s|\$[A-Za-z_]|Get-|Set-|Start-|Stop-|Invoke-|Write-|Test-Path)', s):
        return 'powershell'
    return 'bash'


def looks_like_command(text):
    return bool(re.match(r'^\s*(bash|sh|powershell|pwsh|python3?|py|git|wsl(\.exe)?|cat|grep|ls|touch|echo|cd|&\s|\$|[A-Za-z]:[\\/]|\./|(tools|docs)/)', text, re.I))


def validate_command(cmd, runs, hint=None, target_hint=None):
    errors, warnings = [], []
    # 1. syntax
    sh = guess_shell(cmd, hint)
    ok, msg = (check_ps_syntax(cmd) if sh == 'powershell' else check_bash_syntax(cmd))
    if ok is False:
        errors.append(msg)
    elif ok is None:
        warnings.append(msg)
    # 2. bare stobe-auto
    for m in re.finditer(r'(?:^|[\s;&|(`])stobe-auto(?=\s|$|;|\)|`)', cmd):
        if 'KAH_DIR=' not in cmd:
            errors.append('bare stobe-auto (no KAH_DIR=<lane harness dir>): talks to the LIVE install')
        elif not re.search(r'KenshiInst|KAH', cmd):
            warnings.append('stobe-auto with KAH_DIR that does not look like a lane dir')
        break
    # 3. paths
    writeish = bool(WRITE_RE.search(cmd))
    files, prefixes = running_set(runs)
    seen = set()
    exec_paths = set()
    for m in re.finditer(r'(?:\bbash|\bsh|\bpython3?|-File)\s+(?:-\w+\s+)*([\'"]?)([^\s\'"|;&<>()]+)', cmd):
        exec_paths.add(norm(m.group(2)))
    for raw, pos in paths_in(cmd):
        n = norm(raw)
        if n in seen:
            continue
        seen.add(n)
        for pref, why in FORBIDDEN:
            if n == pref or n.startswith(pref + '/'):
                (errors if writeish else warnings).append('%s: touches %s (%s)' % ('FORBIDDEN' if writeish else 'mentions', raw, why))
        if writeish:
            if n in files:
                errors.append('write-ish command touches %s, a script/list used by a queued or running batch' % raw)
            elif any(n.startswith(p + '/') for p in prefixes if p):
                warnings.append('write-ish command inside the out dir of an in-flight batch: %s' % raw)
        w = to_win(n)
        before = cmd[max(0, pos - 6):pos]
        is_out = bool(re.search(r'(>|tee\s+(-a\s+)?|mkdir\s+(-p\s+)?|-o\s*|touch\s+)$', before))
        if w and not is_out and not os.path.exists(w):
            if n in exec_paths:
                errors.append('script not found: %s' % raw)
            elif n.endswith(SCRIPT_EXT):
                warnings.append('path not found: %s' % raw)
    if target_hint:
        n = norm(target_hint)
        for pref, why in FORBIDDEN:
            if n == pref or n.startswith(pref + '/'):
                errors.append('FORBIDDEN target %s (%s)' % (target_hint, why))
        if n in files:
            errors.append('target %s is used by a queued or running batch' % target_hint)
    return errors, warnings


def validate_action(a, runs=None):
    runs = runs or os.environ.get('SHADOW_RUNS_DIR') or RUNS_DEFAULT
    t = a.get('type')
    text = a.get('exact_command_or_message') or ''
    errors, warnings = [], []
    path = a.get('path')
    if t in COMMAND_TYPES or (t in ('wait', 'restart-waker', 'edit-file') and looks_like_command(text)) or (t not in ('message-shay', 'message-agent', 'spawn', 'ignore') and looks_like_command(text)):
        e, w = validate_command(text, runs, a.get('shell'), path)
        errors += e; warnings += w
    elif t == 'edit-file':
        tgt = path or (re.match(r'\s*(\S+)', text).group(1) if text.strip() else None)
        if tgt:
            n = norm(tgt)
            for pref, why in FORBIDDEN:
                if n == pref or n.startswith(pref + '/'):
                    errors.append('FORBIDDEN edit target %s (%s)' % (tgt, why))
            files, _ = running_set(runs)
            if n in files:
                errors.append('edit target %s is used by a queued or running batch' % tgt)
            w = to_win(n)
            if w and not os.path.exists(w) and not os.path.isdir(os.path.dirname(w)):
                errors.append('edit target directory does not exist: %s' % tgt)
            elif w and not os.path.exists(w):
                warnings.append('edit target does not exist yet: %s' % tgt)
    elif t == 'spawn':
        if '[case:' not in text and not a.get('case'):
            warnings.append('spawn without a [case:<name>] tag in the description/brief')
        for raw, _ in paths_in(text):
            n = norm(raw); w = to_win(n)
            if w and n.endswith(('.md', '.txt', '.json')) and not os.path.exists(w):
                warnings.append('brief/path not found: %s' % raw)
    elif t in ('message-shay', 'message-agent'):
        if len(text) > 4000:
            warnings.append('message longer than 4000 chars')
    return {'ok': not errors, 'errors': errors, 'warnings': warnings}


if __name__ == '__main__':
    import json
    print(json.dumps(validate_action(json.load(sys.stdin)), indent=1))
