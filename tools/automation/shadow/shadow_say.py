"""shadow-say <arm> <batch_id>  (decision JSON on stdin): validate, run the command validator, append to <shadow dir>\\ledger-<arm>.jsonl.
Decision schema (one record per batch):
  {"class": "<event class>", "event_ids": ["e1",...], "actions": [ {"type": "...", "exact_command_or_message": "...", "why": "..."} ], "note": "optional"}
  action types: ack, spawn, message-agent, message-shay, hold-lane, release-lane, restart-waker, ignore, mark-row, edit-file, commit, wait
  ignore needs a why; every other type needs exact_command_or_message (wait: why is enough); optional per action: path, shell (bash|powershell), case, agent.
Accepted also: {"decision": [..actions..]} or {"decision": {"actions": [...]}}. Schema errors are REJECTED (nothing written); validator verdicts are stored, never block."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shadow_lib import shadow_dir, read_jsonl, check_arm, now_iso, append_jsonl
from shadow_validate import validate_action

TYPES = {'ack', 'spawn', 'message-agent', 'message-shay', 'hold-lane', 'release-lane', 'restart-waker', 'ignore', 'mark-row', 'edit-file', 'commit', 'wait'}
CLASSES = {'relay/hand-back', 'setup-fail ticket', 'lane alert', 'waker digest', 'shay message', 'stop-hook feedback', 'agent stopped/dead',
           'build/compose result', 'other'}
CLASS_ALIAS = {'relay': 'relay/hand-back', 'hand-back': 'relay/hand-back', 'handback': 'relay/hand-back', 'setup-fail': 'setup-fail ticket', 'setupfail': 'setup-fail ticket',
               'lane-alert': 'lane alert', 'waker': 'waker digest', 'shay': 'shay message', 'user message': 'shay message', 'stop-hook': 'stop-hook feedback',
               'stop hook': 'stop-hook feedback', 'agent-stopped': 'agent stopped/dead', 'agent stopped': 'agent stopped/dead', 'agent dead': 'agent stopped/dead',
               'build': 'build/compose result', 'compose': 'build/compose result'}


def schema_check(dec):
    errs = []
    if not isinstance(dec, dict):
        return ['decision must be a JSON object'], None, []
    cls = str(dec.get('class', '')).strip().lower()
    cls = CLASS_ALIAS.get(cls, cls)
    if not cls:
        errs.append('missing "class"')
    acts = dec.get('actions')
    if acts is None:
        d = dec.get('decision')
        acts = d.get('actions') if isinstance(d, dict) else d
    if not isinstance(acts, list) or not acts:
        errs.append('"actions" must be a non-empty ordered list (use a single {"type":"ignore","why":"..."} to ignore)')
        acts = []
    for i, a in enumerate(acts):
        if not isinstance(a, dict):
            errs.append('action %d is not an object' % i); continue
        t = a.get('type')
        if t not in TYPES:
            errs.append('action %d: type %r not in %s' % (i, t, sorted(TYPES)))
            continue
        why = str(a.get('why', '')).strip()
        txt = str(a.get('exact_command_or_message', '')).strip()
        if not why:
            errs.append('action %d (%s): missing "why"' % (i, t))
        if t not in ('ignore', 'wait') and not txt:
            errs.append('action %d (%s): missing "exact_command_or_message"' % (i, t))
    return errs, cls, acts


def main():
    if len(sys.argv) < 3:
        raise SystemExit('usage: echo <decision json> | shadow-say.sh <H|S> <batch_id>')
    arm = check_arm(sys.argv[1])
    try:
        bid = int(sys.argv[2])
    except ValueError:
        raise SystemExit('batch_id must be an integer')
    raw = sys.stdin.buffer.read().decode('utf-8', 'replace')
    try:
        dec = json.loads(raw)
    except ValueError as e:
        print('REJECTED: not valid JSON (%s)' % e)
        sys.exit(1)
    errs, cls, acts = schema_check(dec)
    if errs:
        print('REJECTED (schema): ' + ' | '.join(errs))
        sys.exit(1)
    d = shadow_dir()
    warn = []
    if cls not in CLASSES:
        warn.append('class %r is not a known class: stored as given (known: %s)' % (cls, ', '.join(sorted(CLASSES))))
    batch = next((r for r in read_jsonl(os.path.join(d, 'feed.jsonl')) if r.get('batch_id') == bid), None)
    now = now_iso()
    lat = None
    if batch:
        try:
            import datetime
            f = lambda s: datetime.datetime.strptime(s, '%Y-%m-%dT%H:%M:%S.%fZ')
            lat = round((f(now) - f(batch['ts'])).total_seconds(), 1)
        except Exception:
            pass
    else:
        warn.append('batch %d not found in feed' % bid)
    out_actions, nerr = [], 0
    for i, a in enumerate(acts):
        v = validate_action(a)
        rec = dict(a); rec['validator'] = v
        out_actions.append(rec)
        for e in v['errors']:
            nerr += 1
            warn.append('INVALID action %d (%s): %s' % (i, a['type'], e))
        for w in v['warnings']:
            warn.append('warn action %d: %s' % (i, w))
    rec = {'ts': now, 'arm': arm, 'batch_id': bid, 'event_ids': dec.get('event_ids') or ([e['id'] for e in batch['events']] if batch else []),
           'class': cls, 'actions': out_actions, 'note': dec.get('note'), 'latency_s_from_batch': lat, 'validator_errors': nerr}
    append_jsonl(os.path.join(d, 'ledger-%s.jsonl' % arm), rec)
    print('recorded (batch %d, %d action(s), %d validator error(s))' % (bid, len(acts), nerr))
    for w in warn[:6]:
        print('  ' + w[:300])
    if len(warn) > 6:
        print('  ... %d more warning(s)' % (len(warn) - 6))


if __name__ == '__main__':
    main()
