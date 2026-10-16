"""shadow-feed: incrementally read the real coordinator transcript and write
  feed.jsonl         batches of INBOUND events {batch_id, ts, events:[{id, kind, ts, text}]}  (+ a final {"end":true,...} record)
  real-actions.jsonl the real coordinator's own tool calls / messages with timestamps (for later comparison)
Run detached: pythonw.exe -I shadow_feed.py   (options: --transcript F --dir D --max-min N --from-start)
Stops on file <dir>\\STOP or after --max-min minutes (default 100) and then writes END.
Batching: a new batch when 20 s pass without a new event, or 8 events are pending; a pending batch is also flushed after 45 s of age.
"""
import argparse, json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I removes the script dir; shadow_lib is ours
from shadow_lib import shadow_dir, now_iso, trunc, append_jsonl, TRANSCRIPT

QUIET_S, MAX_EVENTS, MAX_AGE_S, TXT = float(os.environ.get('SHADOW_QUIET_S', 20)), 8, float(os.environ.get('SHADOW_MAX_AGE_S', 45)), 3000


def block_text(c):
    if isinstance(c, str):
        return c
    parts = []
    if isinstance(c, list):
        for b in c:
            if not isinstance(b, dict):
                parts.append(str(b)); continue
            t = b.get('type')
            if t == 'text':
                parts.append(b.get('text', ''))
            elif t == 'tool_result':
                parts.append(block_text(b.get('content')))
            elif t == 'image':
                parts.append('[image]')
            else:
                parts.append('[%s]' % t)
    return '\n'.join(p for p in parts if p)


class Feeder:
    def __init__(self, a):
        self.a = a
        self.dir = a.dir
        self.feed = os.path.join(self.dir, 'feed.jsonl')
        self.acts = os.path.join(self.dir, 'real-actions.jsonl')
        self.state_f = os.path.join(self.dir, 'feeder.state.json')
        self.tool_map = {}
        self.seen = set()
        self.pending = []      # events waiting for a batch
        self.first_pending = 0.0
        self.last_event = 0.0
        self.offset = 0
        self.next_event = 1
        self.next_batch = 1
        self.act_seq = 1
        self.start = time.time()
        self.load_state()

    def load_state(self):
        try:
            with open(self.state_f, 'r', encoding='utf-8') as f:
                s = json.load(f)
            self.offset, self.next_event, self.next_batch, self.act_seq = s['offset'], s['next_event'], s['next_batch'], s.get('act_seq', 1)
            self.start = s.get('start', self.start)
            return
        except Exception:
            pass
        self.offset = 0 if self.a.from_start else (os.path.getsize(self.a.transcript) if os.path.exists(self.a.transcript) else 0)

    def save_state(self):
        tmp = self.state_f + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump({'offset': self.offset, 'next_event': self.next_event, 'next_batch': self.next_batch, 'act_seq': self.act_seq,
                       'start': self.start, 'saved': now_iso()}, f)
        os.replace(tmp, self.state_f)

    # ---- event extraction
    def add_event(self, kind, text, ts):
        text = trunc(text, TXT)
        if not text.strip():
            return
        ev = {'id': 'e%d' % self.next_event, 'kind': kind, 'ts': ts or now_iso(), 'text': text}
        self.next_event += 1
        if not self.pending:
            self.first_pending = time.time()
        self.pending.append(ev)
        self.last_event = time.time()

    def add_action(self, kind, name, text, tid, ts):
        rec = {'seq': self.act_seq, 'ts': ts or now_iso(), 'kind': kind, 'name': name, 'id': tid, 'text': trunc(text, 2500, 400)}
        self.act_seq += 1
        append_jsonl(self.acts, rec)

    def handle(self, d):
        if d.get('isSidechain'):
            return
        uid = d.get('uuid')
        if uid:
            if uid in self.seen:
                return
            self.seen.add(uid)
        t = d.get('type'); ts = d.get('timestamp')
        m = d.get('message') if isinstance(d.get('message'), dict) else {}
        if t == 'assistant':
            c = m.get('content')
            if isinstance(c, list):
                for b in c:
                    bt = b.get('type')
                    if bt == 'tool_use':
                        inp = b.get('input') or {}
                        brief = inp.get('command') or inp.get('description') or inp.get('file_path') or inp.get('prompt') or json.dumps(inp, ensure_ascii=False)
                        self.tool_map[b.get('id')] = (b.get('name'), str(brief)[:160].replace('\n', ' '))
                        if len(self.tool_map) > 2000:
                            self.tool_map.pop(next(iter(self.tool_map)))
                        self.add_action('tool_use', b.get('name'), json.dumps(inp, ensure_ascii=False), b.get('id'), ts)
                    elif bt == 'text' and b.get('text', '').strip():
                        self.add_action('text', None, b.get('text'), None, ts)
            elif isinstance(c, str) and c.strip():
                self.add_action('text', None, c, None, ts)
        elif t == 'user':
            c = m.get('content')
            origin = d.get('origin') if isinstance(d.get('origin'), dict) else {}
            ok = origin.get('kind')
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get('type') == 'tool_result':
                        nm, br = self.tool_map.get(b.get('tool_use_id'), ('?', ''))
                        pre = '[result of %s%s%s] ' % (nm, ': ' + br if br else '', ' ERROR' if b.get('is_error') else '')
                        self.add_event('tool_result', pre + block_text(b.get('content')), ts)
                    elif isinstance(b, dict) and b.get('type') == 'text' and b.get('text', '').strip():
                        self.add_event(self.kind_for(ok, b.get('text', ''), d), b.get('text', ''), ts)
            elif isinstance(c, str):
                self.add_event(self.kind_for(ok, c, d), c, ts)
        elif t == 'attachment':
            a = d.get('attachment') or {}
            at = a.get('type')
            if at == 'hook_blocking_error':
                be = a.get('blockingError')
                be = be.get('blockingError') if isinstance(be, dict) else be
                self.add_event('stop_hook_feedback', '[%s hook %s blocked] %s' % (a.get('hookEvent'), a.get('hookName'), be), ts)
            elif at in ('hook_additional_context', 'hook_context'):
                self.add_event('hook_context', block_text(a.get('content') or a.get('text')), ts)
        elif t == 'system' and d.get('subtype') == 'stop_hook_summary':
            if d.get('preventedContinuation') and d.get('hasOutput'):
                self.add_event('stop_hook_feedback', 'Stop hook prevented continuation: ' + str(d.get('stopReason') or ''), ts)

    @staticmethod
    def kind_for(ok, text, d):
        if ok == 'human':
            return 'user_message'
        if ok == 'task-notification':
            return 'task_notification'
        if ok == 'peer':
            return 'subagent_handback' if '[Subagent hand-back]' in text else 'peer_message'
        if d.get('isMeta'):
            return 'meta_message'
        return 'user_other'

    # ---- batching
    def flush(self, n=None):
        evs = self.pending if n is None else self.pending[:n]
        self.pending = self.pending[len(evs):]
        if not evs:
            return
        append_jsonl(self.feed, {'batch_id': self.next_batch, 'ts': now_iso(), 'events': evs})
        self.next_batch += 1
        if self.pending:
            self.first_pending = time.time()

    def maybe_flush(self):
        while len(self.pending) >= MAX_EVENTS:
            self.flush(MAX_EVENTS)
        if self.pending:
            now = time.time()
            if now - self.last_event >= QUIET_S or now - self.first_pending >= MAX_AGE_S:
                self.flush()

    def poll(self):
        p = self.a.transcript
        try:
            size = os.path.getsize(p)
        except OSError:
            return
        if size < self.offset:
            self.offset = 0
        if size == self.offset:
            return
        with open(p, 'rb') as f:
            f.seek(self.offset)
            data = f.read(size - self.offset)
        cut = data.rfind(b'\n')
        if cut < 0:
            return
        chunk = data[:cut + 1]
        self.offset += len(chunk)
        for raw in chunk.split(b'\n'):
            raw = raw.strip()
            if not raw:
                continue
            try:
                d = json.loads(raw.decode('utf-8', 'replace'))
            except ValueError:
                continue
            try:
                self.handle(d)
            except Exception as e:  # never die on one odd line
                self.log('handle error: %r' % (e,))

    def log(self, s):
        try:
            with open(os.path.join(self.dir, 'feeder.log'), 'a', encoding='utf-8') as f:
                f.write('%s %s\n' % (now_iso(), s))
        except Exception:
            pass

    def run(self):
        with open(os.path.join(self.dir, 'feeder.pid'), 'w') as f:
            f.write(str(os.getpid()))
        self.log('start pid=%d offset=%d transcript=%s' % (os.getpid(), self.offset, self.a.transcript))
        stop_f = os.path.join(self.dir, 'STOP')
        reason = None
        while reason is None:
            self.poll()
            self.maybe_flush()
            self.save_state()
            if os.path.exists(stop_f):
                reason = 'STOP file'
            elif time.time() - self.start >= self.a.max_min * 60:
                reason = 'max %d min' % self.a.max_min
            else:
                time.sleep(1.0)
        self.poll()
        self.flush()
        append_jsonl(self.feed, {'end': True, 'ts': now_iso(), 'reason': reason, 'last_batch_id': self.next_batch - 1})
        with open(os.path.join(self.dir, 'END'), 'w') as f:
            f.write(reason)
        self.log('END (%s)' % reason)
        try:
            os.remove(os.path.join(self.dir, 'feeder.pid'))
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--transcript', default=TRANSCRIPT)
    ap.add_argument('--dir', default=None)
    ap.add_argument('--max-min', type=float, default=100)
    ap.add_argument('--from-start', action='store_true')
    a = ap.parse_args()
    if a.dir:
        os.environ['SHADOW_DIR'] = a.dir
    a.dir = shadow_dir()
    Feeder(a).run()


if __name__ == '__main__':
    main()
