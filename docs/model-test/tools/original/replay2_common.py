"""replay2_common.py - shared helpers for the three replay2 experiments (HAIKU PAIR, DRAFT-REVIEW, GUARD RAILS).

Windows python (python -I; the CLIs add this folder to sys.path themselves). Stdlib only. No network, no model calls.
Root dir C:\\KenshiTestRuns\\shadow\\replay2 (override with env REPLAY2_ROOT for selftests). Points + baseline runs are read from
C:\\KenshiTestRuns\\shadow\\replay (never written, grading\\key.json of the baseline is never opened).

Arms:  pair  = two Haiku agents (a, b) R1 -> R2 (see both R1 decisions) -> R3 reconciler only if R2 decisions still differ
       dr    = Haiku draft (existing baseline run P###-ra) reviewed/fixed by one Sonnet High agent
       gr    = Haiku alone + mechanical 'already done' list in the prompt + mechanical post-filter (no second model)
Run ids:  P001-pa1 P001-pb1 (R1)  P001-pa2 P001-pb2 (R2)  P001-pc3 (R3)  P001-dr  P001-gr
"""
import importlib.util, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
AUTOMATION = os.path.abspath(os.path.join(HERE, '..'))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
BASE = r'C:\KenshiTestRuns\shadow\replay'
POINTS = os.path.join(BASE, 'points')
R2 = os.environ.get('REPLAY2_ROOT', r'C:\KenshiTestRuns\shadow\replay2')
PROJ_ROOT = os.environ.get('REPLAY2_PROJ', r'C:\Users\Shay\.claude\projects\C--KenshiModding')

ROUNDS = {
    'r1': dict(suffixes=('pa1', 'pb1'), model='haiku', arm='pair'),
    'r2': dict(suffixes=('pa2', 'pb2'), model='haiku', arm='pair'),
    'r3': dict(suffixes=('pc3',), model='haiku', arm='pair'),
    'dr': dict(suffixes=('dr',), model='sonnet', arm='dr'),
    'gr': dict(suffixes=('gr',), model='haiku', arm='gr'),
}
SUFFIX_INFO = {s: (rd, v['model'], v['arm']) for rd, v in ROUNDS.items() for s in v['suffixes']}
ARMS = ['pair', 'dr', 'gr']
ARM_LABEL = {'pair': 'Haiku pair', 'dr': 'Draft-review', 'gr': 'Guard rails'}
NOOP = {'ignore', 'wait'}

PROMPT = 'replay-run: {rid}\nRead {job} and follow it exactly.'
MARK = '## Now output the decision JSON only.'
PLACEHOLDER_WORDS = {'coordinator', 'shay', 'relay', '*', 'tail', 'new-coordinator'}


def p2(*a):
    return os.path.join(R2, *a)


def load_path(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


_cache = {}


def replay_run():
    if 'rr' not in _cache:
        _cache['rr'] = load_path('replay_run_mod', os.path.join(HERE, 'replay-run.py'))
    return _cache['rr']


def grade_mod():
    if 'gr' not in _cache:
        if HERE not in sys.path:
            sys.path.insert(0, HERE)
        import grade
        _cache['gr'] = grade
    return _cache['gr']


def rowcmp():
    if 'rc' not in _cache:
        _cache['rc'] = load_path('rowcmp_mod', os.path.join(AUTOMATION, 'pilot-rowcmp.py'))
    return _cache['rc']


def point_ids():
    return sorted(f[:-len('.input.md')] for f in os.listdir(POINTS) if f.endswith('.input.md'))


def read_input(pid):
    with open(os.path.join(POINTS, pid + '.input.md'), encoding='utf-8') as f:
        return f.read()


def rid_of(pid, suf):
    return '%s-%s' % (pid, suf)


def out_path(rid):
    return p2('runs', rid + '.json')


def job_path(rid):
    return p2('jobs', rid + '.md')


def final_path(arm, pid):
    return p2('final', arm, pid + '.json')


def parse_rid(rid):
    m = re.match(r'^(P\d+)-([a-z0-9]+)$', rid)
    if not m or m.group(2) not in SUFFIX_INFO:
        return None
    return m.group(1), m.group(2)


def load_json(p):
    try:
        with open(p, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def valid_output(rid):
    """Return the parsed decision dict if runs/<rid>.json exists and passes the replay schema check, else None."""
    d = load_json(out_path(rid))
    if d is None or replay_run().check_schema(d):
        return None
    return d


def strip_extra(d):
    """Schema-identical copy (event_class, decision, checks) without round-private fields (peer_note, review_note)."""
    return {'event_class': d.get('event_class'), 'decision': d.get('decision') or [], 'checks': d.get('checks') or []}


# ------------------------------------------------------------------ action signature (do two decisions differ in actions?)
ID_RE = re.compile(r'(?:lane-idle|lane-no-operator|lane-stuck|agent-(?:orphaned|stopped-context|stopped|dead|stall|stalled|killed|failed)|llm-health)-[A-Za-z0-9][\w.-]*'
                   r'|\bimm26-[A-Za-z0-9][\w-]*|\ba[0-9a-f]{16}\b|\b(?:5090|4080)-i\d+\b|\b\d{1,2}-[a-z]{1,2}\b'
                   r'|[\w.-]+\.(?:ps1|sh|py|md|json|php|cpp|jsonl)\b')


def primary_target(text):
    m = ID_RE.search(text or '')
    return m.group(0).lower().rstrip('.-') if m else ''


def action_sig(decision):
    """Sorted list of (type, primary target) with ignore/wait collapsed to 'noop'; two decisions 'differ in actions' if the lists differ."""
    sig = []
    for a in decision or []:
        if not isinstance(a, dict):
            continue
        t = a.get('type')
        if t in NOOP:
            sig.append(('noop', ''))
        else:
            sig.append((t, primary_target(str(a.get('exact_command_or_message', '')))))
    return sorted(set(sig))


def differ(d1, d2):
    return action_sig((d1 or {}).get('decision')) != action_sig((d2 or {}).get('decision'))


# ------------------------------------------------------------------ job file builders
def split_input(txt):
    i = txt.rfind(MARK)
    if i < 0:
        return txt.rstrip() + '\n\n', ''
    return txt[:i].rstrip() + '\n\n', txt[i:]


def trailer(out):
    return ('\n\n---\nJOB RUNNER INSTRUCTION (last section): use the Write tool to write ONLY the decision JSON object (no prose, no code fence) to %s, '
            'then reply with the single word OK. Use no other tools than that one Read and that one Write.\n' % out)


def top_note():
    return ('JOB: this file is one replay moment plus your task. Read it all; the LAST section says where to write your answer.\n\n')


def dumps(d):
    return json.dumps(d, indent=1, ensure_ascii=False)


def build_job(rid, pid, suf, extra=None):
    """Return the job-file text for one run. extra = dict with the round-specific parts."""
    out = out_path(rid)
    inp = read_input(pid)
    head, tail = split_input(inp)
    rd = SUFFIX_INFO[suf][0]
    if rd == 'r1':
        body = inp.rstrip()
    elif rd == 'gr':
        body = head + extra['done_block'] + '\n\n' + tail
    elif rd == 'r2':
        body = head + R2_BLOCK.format(own=dumps(extra['own']), other=dumps(extra['other'])) + '\n\n' + tail
    elif rd == 'r3':
        body = head + R3_BLOCK.format(a=dumps(extra['a']), b=dumps(extra['b'])) + '\n\n' + tail
    elif rd == 'dr':
        body = DR_PREFACE + head + DR_BLOCK.format(draft=dumps(extra['draft'])) + '\n\n' + tail
    else:
        raise ValueError(rd)
    return top_note() + body + trailer(out)


R2_BLOCK = """\
## PEER REVIEW ROUND (you and one colleague decided this same event batch independently; now you see both decisions)
Both decisions below were written from the SAME input above. Neither is known to be right. Compare them action by action against the input:
where your colleague caught something you got wrong or missed (an action that duplicates something the coordinator ALREADY DID in the preceding
conversation, a missed required action, an invented agent/alert/lane/row/path/id that is not in the input, a wrong or malformed command), fix yours;
where your colleague is wrong, keep yours and say why. Do not add or remove actions out of politeness; only change what the input supports.
OUTPUT the same JSON object as before (event_class, decision, checks) plus one extra field "peer_note": ONE line starting with "agree:" or "disagree:"
saying whether you agree with your colleague's decision and why.

YOUR first decision (R1):
{own}

YOUR COLLEAGUE's first decision (R1):
{other}"""

R3_BLOCK = """\
## RECONCILIATION (final step)
Two coordinators decided this event batch independently, then each revised after seeing the other's decision, and their revised decisions STILL differ
in their actions. You are the reconciler. Check every action of both decisions against the input above (duplicates of already-done actions, missed
required actions, invented targets, command syntax, project rules) and write the FINAL decision: keep an action only if the input supports it; where
the two disagree, pick the one the input supports; do not add actions neither of them proposed unless the input clearly requires one.
OUTPUT the same JSON object (event_class, decision, checks) with no extra fields.

Revised decision of coordinator 1:
{a}

Revised decision of coordinator 2:
{b}"""

DR_PREFACE = """\
# REVIEW TASK (read this first)
You are the senior reviewer. Below is the replay input of one past coordinator moment (the coordinator instructions in it describe the same job and the
same output schema), followed by a DRAFT decision written quickly by a junior coordinator. Your output is the FINAL decision for the event batch, in the
same JSON schema (event_class, decision, checks). You may add one extra field "review_note" (<= 25 words: what you changed, or "unchanged").

"""

DR_BLOCK = """\
## DRAFT DECISION TO REVIEW (written by a junior coordinator from the input above)
{draft}

## HOW TO REVIEW (edit only what is wrong)
1. Check EACH draft action against the input above: is it needed for this event batch, is the target (agent, alert, lane, row, file, command) really named in
   the input, is the command syntactically valid, does it respect the project rules?
2. REMOVE any action that duplicates something the coordinator ALREADY DID in the preceding conversation (spawned, acked, sent, committed, started).
3. ADD any required action the draft MISSED for this event batch (an acknowledgement, a reply, a spawn the rules require, a status/handoff update).
4. FIX invented targets: replace an agent/alert/lane/row/path/id that is not in the input with the right one from the input, or drop the action.
5. DO NOT rewrite parts that are already correct; keep the draft's wording for correct actions. If the draft is already right, return it unchanged.
6. Output only the final JSON object (see the job runner instruction at the end)."""
