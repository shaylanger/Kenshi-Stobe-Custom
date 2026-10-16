"""Shared helpers for the live coordinator shadow kit (docs/COORD_SHADOW_PLAN.md stage 2). Standard library only; run with python -I."""
import json, os, datetime

DEFAULT_DIR = r'C:\KenshiTestRuns\shadow'
TRANSCRIPT = r'C:\Users\Shay\.claude\projects\C--KenshiModding\efc58758-86f8-4786-a138-4e53f075016d.jsonl'


def shadow_dir():
    d = os.environ.get('SHADOW_DIR') or DEFAULT_DIR
    os.makedirs(d, exist_ok=True)
    return d


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'


def trunc(s, n=3000, tail=700):
    """Keep head and tail of a long text so both the command start and the final result lines survive."""
    s = '' if s is None else str(s)
    if len(s) <= n:
        return s
    head = n - tail - 40
    return s[:head] + '\n...[truncated %d chars]...\n' % (len(s) - head - tail) + s[-tail:]


def read_jsonl(path):
    out = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass  # partially written line
    except FileNotFoundError:
        pass
    return out


def append_jsonl(path, obj):
    line = json.dumps(obj, ensure_ascii=False) + '\n'
    with open(path, 'a', encoding='utf-8', newline='\n') as f:
        f.write(line)


def check_arm(arm):
    if arm not in ('H', 'S'):
        raise SystemExit('arm must be H or S (got %r)' % arm)
    return arm
