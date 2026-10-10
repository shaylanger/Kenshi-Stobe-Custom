#!/usr/bin/env python3
"""take_sample_mock.py -- realistic offline check of the take sampler (no game): a fake harness folder on /mnt/c (9p, like
the real D:\\...\\AutomationHarness), polled every 250 ms one inbox at a time like Plugin.cpp, with KenshiFP-like replies,
while a fake take script sends its own commands as separate stobe-auto processes (python start + lock + poll each).
Reports the sampler's max gap per key (must be <= 1.0 s) and the take script's per-call latency with/without the sampler.
Usage: python3 take_sample_mock.py [--secs 12] [--sampler new|old] [--dir <fake harness dir on /mnt/c>]"""
import argparse, os, shutil, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
HARN = '/mnt/c/KenshiModding/Kenshi-Automation-Harness'
REPLY = {
    'fp_keys': 'hook=1 fault=0 fp=1 drawn=1 ui_state=ready in=0000 hud=1 hud_shown=1 hud_text=ready hud_changes=3',
    'fp_combat': 'enabled=1 native_ready=1 ammo=1 reloading=0 fp_ui_state=ready fire_pending=0 loaded=1 loaded_max=1',
    'where': 'Axima #1/2 [Nameless] pos=100,0,100 dist=0',
    'chars': '4 within 80: Axima #1/2 [Nameless] pos=100,0,100 dist=0 race=Greenlander | Shay #3/4 [Nameless] pos=101,0,100 '
             'dist=1 race=Greenlander | Hungry Bandit #5/6 [Hungry Bandits] pos=110,0,100 dist=10 race=Greenlander | '
             'Hungry Bandit #7/8 [Hungry Bandits] pos=105,0,100 dist=5 DEAD race=Shek',
}


class FakeHarness(threading.Thread):
    def __init__(self, d, per_cmd=0.02):
        super().__init__(daemon=True); self.d, self.per_cmd, self.stop, self.n_msgs, self.t0 = d, per_cmd, False, 1, time.time()

    def reply(self, f):
        if f[1] == 'messages':
            self.n_req = getattr(self, 'n_req', 0) + 1
            if self.n_req == 6:   # 'X is attacking!' appears after the sampler's 5th sample
                self.n_msgs = 2
            m = ['10:00:01 Saving...', '10:00:05 Tassilo is attacking!'][:self.n_msgs]
            return '%d message(s) since launch | %s (hook: MessageRoller+0x10)' % (self.n_msgs, ' | '.join(m))
        return REPLY.get(f[1], 'ok')

    def run(self):
        inbox = os.path.join(self.d, 'inbox.txt')
        while not self.stop:
            time.sleep(0.25)
            if not os.path.exists(inbox):
                continue
            try:
                os.replace(inbox, inbox + '.reading')
            except OSError:
                continue
            lines = [x for x in open(inbox + '.reading').read().split('\n') if x]
            os.remove(inbox + '.reading')
            with open(os.path.join(self.d, 'outbox.txt'), 'a') as o:
                for ln in lines:
                    f = ln.split('\t'); time.sleep(self.per_cmd)
                    o.write('%s\tok\t%s\n' % (f[0], self.reply(f))); o.flush()


def take_script(d, secs, lat):
    end = time.time() + secs
    env = dict(os.environ, KAH_DIR=d)
    while time.time() < end:
        t = time.time()
        subprocess.run(['python3', HARN + '/client/kah.py', 'fp_camera', 'wheel', '-120'], env=env, capture_output=True)
        lat.append(time.time() - t); time.sleep(0.3)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--secs', type=float, default=12); ap.add_argument('--sampler', default='new')
    ap.add_argument('--dir', default='/mnt/c/Users/Shay/AppData/Local/Temp/kah-fake-harness')
    a = ap.parse_args()
    d = a.dir; shutil.rmtree(d, True); os.makedirs(d); open(os.path.join(d, 'enabled.flag'), 'w').close()
    h = FakeHarness(d); h.start()
    base = []; take_script(d, 4, base)
    ev = os.path.join(d, 'ev.txt'); lab = os.path.join(d, 'lab.txt'); t0 = time.time()
    env = dict(os.environ, KAH_DIR=d)
    if a.sampler == 'new':
        run = os.path.join(d, 'run'); open(run, 'w').close()
        p = subprocess.Popen(['python3', HERE + '/take_sample.py', ev, '%.6f' % t0, 'Axima', '#5/6', '--run', run], env=env)
    else:   # the first sampler (git 02db56a take-sample.sh): 5 separate stobe-auto calls per sample
        os.makedirs(os.path.join(d, 'bin'), exist_ok=True); sa = os.path.join(d, 'bin', 'stobe-auto')
        open(sa, 'w').write('#!/bin/bash\nexec python3 %s/client/kah.py "$@"\n' % HARN); os.chmod(sa, 0o755)
        old = subprocess.run(['git', '-C', '/mnt/c/KenshiModding', 'show', '02db56a:components/KenshiFP/animlab/take-sample.sh'], capture_output=True, text=True).stdout
        open(os.path.join(d, 'old.sh'), 'w').write(old)
        env['PATH'] = os.path.join(d, 'bin') + ':' + env['PATH']
        p = subprocess.Popen(['bash', '-c', '. %s/old.sh; take_sample_start %s %.6f Axima "#5/6"; sleep %g; take_sample_stop' % (d, ev, t0, a.secs + 0.5)], env=env)
    time.sleep(0.5); lat = []; take_script(d, a.secs, lat)
    if a.sampler == 'new':
        os.remove(run)
    p.wait()
    h.stop = True
    open(lab, 'w').write('0.0 take\n%.2f end\n' % (a.secs))
    r = subprocess.run(['python3', HARN + '/tools/animlab/takecheck.py', '--labels', lab, '--ev', ev, '--rules', '/dev/stdin', '--name', 'mock-' + a.sampler],
                       input='set maxgap 1.0\ncover ui_state,loaded,near,msgs\n', capture_output=True, text=True).stdout
    S = {}
    for line in open(ev):
        x = line.split()
        for tok in x[2:]:
            k, _, v = tok.partition('=')
            S.setdefault(k, []).append((float(x[0]), v))
    gaps = {k: max([b[0] - a_[0] for a_, b in zip(v, v[1:])] or [99]) for k, v in S.items() if k in ('ui_state', 'loaded', 'near', 'msgs')}
    nearv = sorted(set(v for _, v in S.get('near', []))); msgv = [v for _, v in S.get('msg', [])]
    print('sampler=%s samples=%d max_gap=%s near=%s msg=%s' % (a.sampler, len(S.get('ui_state', [])), ' '.join('%s:%.2f' % kv for kv in sorted(gaps.items())), nearv, msgv))
    print('take script call latency: alone median %.2f s, with sampler median %.2f max %.2f s' % (
        sorted(base)[len(base) // 2], sorted(lat)[len(lat) // 2], max(lat)))
    print(r.strip().splitlines()[-1])
    return 0


if __name__ == '__main__':
    sys.exit(main())
