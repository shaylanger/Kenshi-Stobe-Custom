"""Phase 1: scan coordinator transcripts, find decision points, classify, derive outcome label.
Writes C:\\KenshiTestRuns\\shadow\\replay\\cands.jsonl (light metadata only; build_points.py renders the chosen ones).

Decision point = one inbound event (user string, task-notification, cross-session message, stop-hook feedback,
queued command) plus every entry up to the next inbound event. The event batch also includes the output of the
background task the notification names (waker output read by the coordinator), when the coordinator read it.

OUTCOME RULE (mechanical, window = the 15 assistant turns after the point's first assistant turn):
  bad       = Shay strong-negative message in the window (profanity, 'not acceptable', 'I told you', 'I said', '!!')
              OR the coordinator stopped/abandoned/reverted something the point itself created/changed
              (TaskStop or agent-abandon of an agent spawned in the point; git revert/reset/checkout -- of a file the
              point edited).
  corrected = Shay mild-correction message (no/don't/stop/why did/wrong/instead/shouldn't/...) in the window
              OR coordinator self-correction text in the window (my mistake / I was wrong / sorry / I should have /
              reverted / undo / incorrectly ...) OR the point's own mutating tool call was denied by the permission
              classifier/hook (tool result starts 'Permission for this action was denied' or '<tool_use_error>Blocked')
              OR the same alert/ticket id was acked twice.
  good      = none of the above.
Known noise: Shay messages in the window may concern other work; they are counted anyway (conservative).
"""
import sys, json, re, os, collections
from common import *

SELF_CORRECT = re.compile(r"(my mistake|i was wrong|i made a mistake|i should have|\bsorry\b|apolog|that was wrong|i wrongly|"
                          r"incorrectly|\boops\b|i mistakenly|should not have|shouldn't have|my error|i misread|i misjudged|"
                          r"\breverted\b|\breverting\b|\bundo\b|\bundoing\b|rolled back|roll back|false alarm on my side|"
                          r"that was a bug in my|i got that wrong|i was mistaken)", re.I)
SHAY_STRONG = re.compile(r"(fuck|shit|bullshit|wtf|not acceptable|furious|i told you|i said|!!|stop feeding|are you serious|"
                         r"what the hell|ridiculous|useless|unacceptable)", re.I)
SHAY_MILD = re.compile(r"(\bno[,. ]|\bdon'?t\b|\bdo not\b|\bstop\b|why (did|are|is|do|would|dont|don't)|\bwrong\b|"
                       r"not what i|i didn'?t|\bundo\b|\brevert|\bnever\b|\binstead\b|that'?s not|shouldn'?t|should not|"
                       r"\bthat is not\b|isnt|isn't|\bmissing\b|where is|why not)", re.I)
BUILDKW = re.compile(r'(?i)\b(compose[d]?|installed|DLL (built|compiled)|build (ok|passed|done|result)|built (ok|nc\d+)|Stobe\.dll|KenshiFP\.dll|NC\d\d [a-f0-9]{8})')
DENIED = re.compile(r'^(Permission for this action was denied|<tool_use_error>Blocked)')


def classify(trigger, event_out, hook_ctx=''):
    t = trigger.lstrip()
    ev = event_out or ''
    if t.startswith('Stop hook feedback'):
        return 'stop-hook'
    if t.startswith('<task-notification'):
        sm = re.search(r'<summary>(.*?)</summary>', t, re.S)
        s = sm.group(1) if sm else ''
        if re.search(r'Agent ".*" (finished|completed)', s):
            return 'build-compose' if BUILDKW.search(t[:1800]) else 'relay'
        if re.search(r'Agent ".*" (was stopped|failed)', s):
            return 'agent-stopped'
        if re.search(r'is waiting on its own background', s):
            return 'other'
        if 'Monitor event' in s:
            body = t
        else:
            body = ev
        if not body.strip():
            if re.search(r'event-wait|waker', s, re.I):
                return 'waker-digest'
            return 'build-compose' if BUILDKW.search(s) else 'other'
        return classify_events(body, '')
    if t.startswith('<agent-message'):
        return 'build-compose' if BUILDKW.search(t[:1800]) else 'relay'
    if t.startswith('Another Claude session') or t.startswith('<cross-session-message'):
        if re.search(r'Subagent hand-back|TAIL-RELAY', t):
            return classify_events(t, '') if re.search(r'STALL|FAILED|STOPPED', t[:1500]) and 'TAIL-RELAY' in t else 'relay'
        if re.search(r'SETUP-FAIL|setupfail', t):
            return 'setup-fail'
        if re.search(r'LANE (IDLE|STALL|NO-OPERATOR)', t):
            return 'lane-alert'
        return 'other'
    if t.startswith('<'):
        return 'other'
    # plain user text => Shay
    return 'shay-message'


def classify_events(body, summary=''):
    if re.search(r'EVENT LANE|LANE (IDLE|STALLED|STUCK|NO-OPERATOR)|HEALTH STALL', body):
        lane = True
    else:
        lane = False
    dead = bool(re.search(r'(EVENT STATUS \S+ (STOPPED-CONTEXT|FAILED)|\s(STOPPED-CONTEXT|FAILED)[: ]|ORPHANED|NO SUCCESSOR|AGENT (STALL|DEAD|KILLED)|'
                          r'TAIL-RELAY \S+ (STALL|FAILED|STOPPED))', body))
    sf = bool(re.search(r'SETUP-FAIL|setupfail-', body))
    relay = bool(re.search(r'TAIL-RELAY|EVENT STATUS \S+ DONE|hand-back|PILOT-ESCALATE', body))
    build = bool(re.search(r'(?i)\b(compose|installed|NC\d\d|build (done|result|ok|failed)|build-stobe|dll built|kfp-pipeline)\b', body + summary))
    digest = bool(re.search(r'EVENT (DIGEST|BATCH)|EVENT DONE', body))
    if digest and not dead:
        return 'waker-digest'
    if dead:
        return 'agent-stopped'
    if lane:
        return 'lane-alert'
    if sf:
        return 'setup-fail'
    if relay:
        return 'relay'
    if build:
        return 'build-compose'
    if digest:
        return 'waker-digest'
    return 'other'


def find_event_read(entries, lo, hi, trigger):
    """Return (event_text, tool_use_id of the read) for a task-notification's output file."""
    m = re.search(r'<task-id>(\w+)</task-id>', trigger)
    if not m:
        return '', None
    tid = m.group(1)
    for k in range(lo, hi):
        e = entries[k]
        if e[0] != 'A':
            continue
        for tu in tool_uses(e):
            inp = tu.get('input') or {}
            s = inp.get('command', '') + inp.get('file_path', '')
            if tid + '.output' in s or ('/tasks/' + tid) in s.replace('\\', '/'):
                for k2 in range(k + 1, min(hi, k + 3)):
                    if entries[k2][0] == 'R' and entries[k2][2] == tu.get('id'):
                        return entries[k2][3], tu.get('id')
                return '', tu.get('id')
    # fallback: first tool result of the point that carries waker EVENT lines
    for k in range(lo, hi):
        e = entries[k]
        if e[0] == 'R' and re.search(r"(?m)^EVENT (INBOX|LANE|STATUS|DIGEST|BATCH|DONE)", e[3] or ""):
            return e[3], None
    return '', None


def outcome_for(entries, bounds, pi, pts_meta):
    lo, hi = bounds[pi]
    a_idx = [k for k in range(lo, hi) if entries[k][0] == 'A']
    if not a_idx:
        return 'good', 'no coordinator action in the point'
    # window: 15 assistant turns starting at first A of this point
    win_start = a_idx[0]
    cnt = 0; win_end = len(entries)
    for k in range(win_start, len(entries)):
        if entries[k][0] == 'A':
            cnt += 1
            if cnt > 15:
                win_end = k; break
    win = entries[win_start:win_end]
    pt = entries[lo:hi]
    # collect point's mutating actions
    spawned = []; edited = set(); acked = []
    for e in pt:
        if e[0] != 'A':
            continue
        for tu in e[2]:
            if tu.get('type') != 'tool_use':
                continue
            a = action_of(tu)
            if not a:
                continue
            if a[0] == 'spawn':
                nm = re.search(r'(imm26-[\w-]+)', json.dumps(tu.get('input')))
                if nm: spawned.append(nm.group(1))
            if a[0] == 'edit-file':
                edited.add((tu.get('input') or {}).get('file_path', ''))
            if a[0] == 'ack':
                acked.append((tu.get('input') or {}).get('command', ''))
    # denial of point's own tool calls
    point_ids = {tu.get('id') for e in pt if e[0] == 'A' for tu in tool_uses(e)}
    for e in pt:
        if e[0] == 'R' and e[2] in point_ids and DENIED.match(e[3] or ''):
            return 'corrected', 'own tool call denied: ' + e[3][:80]
    wins_after = win
    for e in wins_after:
        if e[0] == 'U' and is_inbound(e) and classify(e[2], '') == 'shay-message':
            if e is entries[lo]:
                continue
            if SHAY_STRONG.search(e[2]):
                return 'bad', 'Shay strong-negative: ' + e[2][:100].replace('\n', ' ')
    for e in wins_after:
        if e[0] == 'A':
            for tu in tool_uses(e):
                inp = tu.get('input') or {}
                c = inp.get('command', '')
                if tu.get('name') == 'TaskStop' and spawned:
                    return 'bad', 'TaskStop after spawn in the point'
                if re.search(r'agent-abandon\.ps1', c) and any(s in c for s in spawned):
                    return 'bad', 'abandoned an agent spawned in the point'
                if re.search(r'git (revert|reset|checkout --)', c) and any(os.path.basename(p) in c for p in edited if p):
                    return 'bad', 'reverted a file the point edited'
    for e in wins_after:
        if e[0] == 'U' and is_inbound(e) and e is not entries[lo] and classify(e[2], '') == 'shay-message':
            if SHAY_MILD.search(e[2]):
                return 'corrected', 'Shay mild correction: ' + e[2][:100].replace('\n', ' ')
    for e in wins_after:
        if e[0] == 'A':
            txt = a_text(e)
            mm = SELF_CORRECT.search(txt)
            if mm and e is not None:
                # ignore the very first turn text of the point (it narrates the point's own action)
                return 'corrected', 'coordinator self-correction: ...' + txt[max(0, mm.start() - 40):mm.end() + 40].replace('\n', ' ')
    # same ack id twice
    ack_ids = []
    for e in wins_after:
        if e[0] == 'A':
            for tu in tool_uses(e):
                c = (tu.get('input') or {}).get('command', '')
                m = re.search(r'alert-ack\.ps1\s+(\S+)', c)
                if m: ack_ids.append(m.group(1))
    if len(ack_ids) != len(set(ack_ids)):
        return 'corrected', 'same alert acked twice'
    return 'good', 'no correction signal in the 15 following turns'


def scan(prefix):
    path = session_path(prefix)
    entries = load_stream(path)
    inb = [k for k, e in enumerate(entries) if is_inbound(e)]
    bounds = []
    for n, k in enumerate(inb):
        hi = inb[n + 1] if n + 1 < len(inb) else len(entries)
        bounds.append((k, hi))
    out = []
    for pi, (lo, hi) in enumerate(bounds):
        e0 = entries[lo]
        trig = e0[2]
        ev_text, read_id = find_event_read(entries, lo + 1, hi, trig) if trig.lstrip().startswith('<task-notification') else ('', None)
        cls = classify(trig, ev_text)
        acts = []
        for k in range(lo + 1, hi):
            e = entries[k]
            if e[0] == 'A':
                for tu in tool_uses(e):
                    if tu.get('id') == read_id:
                        continue
                    a = action_of(tu)
                    if a and a[0] != 'investigate':
                        acts.append(a[0])
        has_a = any(entries[k][0] == 'A' for k in range(lo + 1, hi))
        oc, why = outcome_for(entries, bounds, pi, None)
        out.append(dict(session=prefix, pi=pi, lo=lo, hi=hi, ts=e0[1], cls=cls, trig_len=len(trig),
                        ev_len=len(ev_text), n_actions=len(acts), types=sorted(set(acts)), has_a=has_a,
                        outcome=oc, outcome_why=why, trig=trig[:160].replace('\n', ' ')))
    return out


if __name__ == '__main__':
    os.makedirs(REPLAY, exist_ok=True)
    allp = []
    for pre in COORD_SESSIONS:
        try:
            r = scan(pre)
        except Exception as ex:
            print('ERR', pre, ex); continue
        allp += r
        print(pre, len(r), dict(collections.Counter(x['cls'] for x in r)), file=sys.stderr)
    with open(os.path.join(REPLAY, 'cands.jsonl'), 'w', encoding='utf-8') as f:
        for x in allp:
            f.write(json.dumps(x) + '\n')
    c = collections.Counter((x['cls']) for x in allp)
    print('TOTAL', len(allp), dict(c))
    print('with actions', dict(collections.Counter(x['cls'] for x in allp if x['n_actions'] > 0)))
    print('outcomes', dict(collections.Counter(x['outcome'] for x in allp)))
