#!/usr/bin/env python3
"""kahstub.py -- the dry-run fake game behind `stobe-auto` / kah.py (tools/automation/dryrun).

Answers every harness / KenshiFP / Stobe command a take script sends with a plausible canned reply, keeps a small world
model (fixture squad, inventories, drawn weapon, block/aim/reload timeline, camera, game time) so the scripts' own checks
(pf_* preflight, fp_vm state, loaded=, free block log lines) see a consistent game, and flags:
  FAIL  a command the spec (gen_spec.py: COMMANDS.md + harness src + registerCommand) doesn't know, an unknown first
        argument for a KenshiFP command, too few arguments, an empty argument, a character / save that doesn't exist,
        `kenshi-ctl focus`-style input that would take over Shay's screen
  NOTE  known commands the stub only answers generically
Each call advances the virtual clock by DR_LATENCY (default 0.3 s: one 250 ms harness poll + client start).
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dr  # noqa: E402
import kfpreply  # noqa: E402

LAT = float(os.environ.get('DR_LATENCY', '0.3'))
SPEC = os.environ.get('DR_SPEC', os.path.join(dr.ST, 'spec.tsv'))
SAVES = os.environ.get('DR_SAVES', os.path.join(dr.ST, 'saves.txt'))
SAVEDIR = '/mnt/c/Users/Shay/AppData/Local/kenshi/save'   # both rigs' sandboxes mount C: there (4080: also /c)
WEAPON_LISTS = '/mnt/c/KenshiModding/components/KenshiFP/animlab/weapons'


def sid_names():
    """stringID -> item name from the weapon-matrix lists (sid|name|type|...): the real harness finds items by name or
    stringID (FindDataTypes); the stub knows the sids the take scripts use"""
    m = {}
    if os.path.isdir(WEAPON_LISTS):
        for fn in os.listdir(WEAPON_LISTS):
            if fn.endswith(('.list', '.tsv', '.txt')):
                for l in open(os.path.join(WEAPON_LISTS, fn), errors='replace'):
                    f = l.rstrip('\r\n').split('|')
                    if len(f) >= 2 and not l.startswith('#') and re.match(r'^\d+-\S', f[0]):
                        m[f[0]] = f[1]
                        if len(f) >= 5 and f[4]:
                            m.setdefault(f[4], f[4])
    return m


def item_name(ref):
    return sid_names().get(ref, ref)
SPOT = (-54190.0, 633.0, 4380.0)
# ranged weapon names (crossbows: "Oldworld Bow", "Eagle's Cross", "Toothpick", "Spring Bow", "Harpoon"); "Paladin's Cross" is a sword
RANGED = re.compile(r"(?i)\bbow\b|crossbow|harpoon|toothpick|eagle'?s cross|spring")
_RN = []


def is_ranged(name):
    """a crossbow/bow: by name (RANGED) or typed crossbow in the weapon-matrix lists (mod crossbows like "Ranger",
    wm-76: the stub said class=melee)"""
    if RANGED.search(name):
        return True
    if not _RN:
        rn = set()
        if os.path.isdir(WEAPON_LISTS):
            for fn in os.listdir(WEAPON_LISTS):
                if fn.endswith(('.list', '.tsv', '.txt')):
                    for l in open(os.path.join(WEAPON_LISTS, fn), errors='replace'):
                        f = l.rstrip('\r\n').split('|')
                        if len(f) >= 3 and f[2].strip().lower() in ('crossbow', 'bow', 'ranged'):
                            rn.add(f[1].strip().lower())
        _RN.append(rn)
    return name.strip().lower() in _RN[0]


# worn gear (not a weapon); whole words: "Ronin Hatchet" is an axe, not a hat (wm-g8 drew the bow)
ARMOR = re.compile(r"(?i)\b(hat|helmet|armou?r|shirt|boots|pants|coat|vest|cap|mask|shoes|gloves)\b")


def fixture(save):
    """world model of the fixture saves FP takes use (kah-fpxbow = C:\\KenshiTestFixtures\\FP-crossbow; a studio
    fixture is described by DR_FIXTURE_JSON). Squad at the take spot, bandits far away."""
    js = os.environ.get('DR_FIXTURE_JSON')
    if js and os.path.exists(js):
        return json.load(open(js))
    x, y, z = SPOT
    c = lambda i, n, fac, pos, items, eq: dict(id='#%d/%d' % (i, i + 1), fac=fac, pos=list(pos), items=items, eq=eq,
                                               ko=0, ranged=None, name=n)
    chars = {
        'Shay': c(10, 'Shay', 'Nameless', (x + 300, y, z + 2470), ['Iron Hat'], []),
        'Malzin': c(12, 'Malzin', 'Nameless', (x + 20, y, z + 10), ['Chisa Katana', 'Oldworld Bow MkII'],
                    ['Chisa Katana', 'Oldworld Bow MkII']),
        'Axima': c(14, 'Axima', 'Nameless', (x, y, z), ['Oldworld Bow MkI', 'Iron Hat'], ['Oldworld Bow MkI', 'Iron Hat']),
        'Tassilo': c(16, 'Tassilo', 'Nameless', (x + 250, y, z + 2470), [], []),
        'Skaera': c(30, 'Skaera', 'Hungry Bandits', (x + 2600, y, z + 300), ['Rusty Junk Sword'], ['Rusty Junk Sword']),
        'Hungry Bandit': c(32, 'Hungry Bandit', 'Hungry Bandits', (x + 4500, y, z - 900), [], []),
        'Dust Bandit': c(34, 'Dust Bandit', 'Dust Bandits', (x - 5200, y, z + 1200), [], []),
    }
    return dict(chars=chars, squad=['Shay', 'Malzin', 'Axima', 'Tassilo'], hour=float(os.environ.get('DR_HOUR', '11')))


def seed_gate():
    """the animlab gate (components/KenshiFP/animlab/gate.sh, ~2 min offline, judged by its own RESULT) is not a take
    step: fp-viewmodel.sh VMQUICK uses /root/animlab-gate/result-<hash>.txt or runs gate.sh. In the sandbox (overlay root,
    writes discarded) a missing result gets a canned PASS so the row's take steps run; NOTE says the real run computes
    it first. A cached real result is used as it is (a real gate FAIL still fails the dry run)."""
    g = '/mnt/c/KenshiModding/components/KenshiFP/animlab/gate.sh'
    once = os.path.join(dr.ST, 'gate-seeded')
    if os.path.exists(once):
        return
    open(once, 'w').close()
    if not os.path.exists(g) or not os.path.isdir('/root/KenshiFP'):
        return
    import subprocess
    try:
        h = subprocess.run(['/bin/bash', g, 'hash'], capture_output=True, text=True, timeout=60).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return
    if not h:
        return
    f = '/root/animlab-gate/result-%s.txt' % h
    if not os.path.exists(f):
        os.makedirs(os.path.dirname(f), exist_ok=True)
        with open(f, 'w') as o:
            o.write('RESULT ANIMLAB-REGRESS PASS dryrun-canned (no gate result for %s yet)\n' % h)
        dr.flag('NOTE', 'animlab gate not run for source %s: the real VMQUICK runs gate.sh first (~2 min); run it now: '
                        'bash components/KenshiFP/animlab/gate.sh' % h)


def new_state(save):
    seed_gate()
    ensure_ini()
    f = fixture(save)
    s = dict(save=save, chars=f['chars'], squad=f['squad'], hour=f['hour'], hour_vt=dr.vnow(), speed=1.0, paused=0,
             selected=f['squad'][0], fpchar=None, chatter='on', cursor=[800, 450], cam=dict(dist=0, orbit=0, yaw=0, pitch=0),
             fp=(dict(drawn=1, melee=1, loaded=0 if f.get('xbow_empty') else 1, ui_state='ready', hud_text='ready', vm='ready',
                      weapon=f['melee_in_hands']) if f.get('melee_in_hands') else
                 dict(drawn=0, melee=0, loaded=0 if f.get('xbow_empty') else 1, ui_state='holstered', hud_text='holstered', vm='holstered')),
             tl=[], hist=[], rec=dict(on=0, t=0), keys={}, sets={}, zoom_switch=1, bandhide=1,
             turret=dict(on=0, ammo=1, power=1, shots=0, enters=0, leaves=0), fight=int(f.get('fight', 0)),
             swing_ko=int(f.get('swing_ko', 0)),
             off_sheathes=int(f.get('off_sheathes', 0)),
             give_noroom=f.get('give_noroom'),
             # fixtures/spawn-hostile.json (23-rg02 ST02/ST03): spawns of these templates/factions ('*' = all) read
             # isEnemy=1 whatever the relation; sneak_aware_lag: see sneak_aware
             spawn_hostile=f.get('spawn_hostile', []), sneak_aware_lag=float(f.get('sneak_aware_lag', 0)),
             # fixtures/dialog.json (2026-10-10 20-rg04 M08): NPC conversations that open the dialogue window `at` s after
             # the load and stay open until `dialog close` (KenshiFP fp_state ui_open=1 ui_why=panels meanwhile)
             dlg=[dict(e, vt=dr.vnow() + float(e.get('at', 0)), closed=0) for e in f.get('dialog', [])],
             iso=0 if os.environ.get('RIG') == '4080' or os.environ.get('DRYRUN_ISO') == 'off' else 1)
    # iso: 5090 kenshi-ctl launch turns input isolation on; the 4080 C:\KAH\ctl.ps1 launch does not (b4080c setup FAIL)
    t = dr.vnow()
    for k, v in s['fp'].items():
        s['hist'].append([t - 3600, k, v])
    # KenshiFP startup line fp-stealth.sh's setup checks (resolved stealth symbols, kfp_controls.inc)
    kfplog(t, '[controls] stealth: sensory=7ff6a1000000 aware=7ff6a1000100 kochance=7ff6a1000200 uncon=7ff6a1000300 '
              'dead=7ff6a1000400')
    return s


def load_state():
    p = os.path.join(dr.ST, 'state.json')
    if os.path.exists(p):
        return json.load(open(p))
    return new_state(os.environ.get('DR_SAVE') or 'kah-fpxbow')


def save_state(s):
    p = os.path.join(dr.ST, 'state.json')
    with open(p + '.tmp', 'w') as f:
        json.dump(s, f)
    os.replace(p + '.tmp', p)


def settle(s, now):
    """apply scheduled transitions up to now (history keeps them for the sampler)"""
    keep = []
    for e in sorted(s['tl'], key=lambda e: e[0]):
        if e[0] <= now:
            if e[1] == '_ammo':
                s['turret']['ammo'] = e[2]
                continue
            s['fp'][e[1]] = e[2]
            s['hist'].append(e[:3])
        else:
            keep.append(e)
    s['tl'] = keep
    if s['speed'] >= 2 and not s['paused']:
        h = s['hour'] + (now - s['hour_vt']) * s['speed'] / 120.0
        s['day'] = s.get('day', 12) + int(h // 24)
        s['hour'] = h % 24
    s['hour_vt'] = now
    mtick(s, now)
    sk = s.get('sk')
    if sk and sk.get('pend') and now >= sk['pend']:   # the pending sneak knockout lands (KenshiFP fpc_sneak_watch)
        t = s['chars'].get(sk['t'])
        sk['pend'] = 0
        if t:
            t['ko'] = 1
        sk['result'], sk['elapsed'] = 'ko', 1500
        kfplog(now, '[controls] sneak result=ko target=%s elapsed_ms=1500 target_aware_now=0 ko_chance=158.000' % uname(t['name'] if t else 'none'))


# ---- FP stealth model (fp-stealth.sh ST01-ST03; KenshiFP client/kfp_controls.inc sneak probe / fpc_sneak_click) ----
def uname(n):
    return n.replace(' ', '_').replace('=', '_')


def is_enemy(s, c):
    """PlayerInterface::isEnemy: faction at war (relation < 0) or a game-side enemy flag the relation command doesn't
    clear (fixtures/spawn-hostile.json: every spawn of the listed templates/factions, 23-rg02 ST02/ST03 hostile=1)"""
    if c.get('enemy'):
        return 1
    rel = s.get('relations', {}).get(c['fac'], -50.0 if 'Bandit' in c['fac'] else 0.0)
    return 1 if rel < 0 else 0


def sneak_aware(s, t, now):
    """t sees the FP character now: pinned facing him, unless he sneaks with stealth >= 50; fixtures sneak_aware_lag =
    seconds after sneak goes on in which the facing target reads target_aware=0 (23-rg02 ST02 single probe)"""
    me = s['chars'].get(s['fpchar'] or '') if s.get('fpchar') else None
    if not me or not t or t.get('ko') or t.get('face') != me['name']:
        return 0
    if me.get('sneak'):
        if now - me.get('sneak_t', 0) < s.get('sneak_aware_lag', 0):
            return 0
        if me.get('stats', {}).get('stealth', 10.0) >= 50:
            return 0
    return 1


def fight_on(s, key):   # fpc_engage: a native fight of the FP character on him (press() shadows melee())
    melee(s)['tgt'] = key


def crosshair(s):
    t = s['chars'].get(s.get('pick_t') or '')
    return t if t and not t.get('ko') else None


def desc_item(s, it):
    """harness DescribeItem (Commands.cpp): '<name> handle=... h.index=.. h.serial=.. ...'; stable fake handles"""
    h = s.setdefault('handles', {})
    if it not in h:
        h[it] = [200 + len(h) * 2, 9000 + len(h)]
    i, sr = h[it]
    return '%s handle=%d/%d h.index=%d h.serial=%d h.type=6 h.container=0 h.containerSerial=0' % (it, sr, i, i, sr)


def item_by_ref(s, ref):
    if ref.startswith('#'):
        for it, (i, sr) in s.get('handles', {}).items():
            if ref == '#%d/%d' % (sr, i):
                return it
    return ref


def world(s, now=None, allow=()):
    """what a camera would show right now (bug-replay fixtures: dryrun/fixtures/*.json): game hour + night, hostile NPCs
    (not squad, not Nameless, not KO) within 30 m of the FP / selected character, the popup a fight near the spot puts on
    screen ("<name> is attacking!", fixture "fight": 1). Read by fakeexe (recordings), pyshim (sampler, frames.py)."""
    h = s.get('hour', 11.0)
    if now is not None and s.get('speed', 1) >= 2 and not s.get('paused'):
        h = (h + (now - s.get('hour_vt', now)) * s['speed'] / 120.0) % 24
    me = s['chars'].get(s.get('fpchar') or s.get('selected'), {}).get('pos')
    host, near = [], []
    rel = s.get('relations', {})
    for n, c in s['chars'].items():
        if me is None or n in s['squad'] or c.get('fac') == 'Nameless' or c.get('ko'):
            continue
        # take_sample.py's allow list (names / #ids, e.g. the T6 dummy) is not counted as "near" (real sampler too)
        if n in allow or c.get('name') in allow or c.get('id') in allow or any(c.get('id', '').startswith(x + '/') for x in allow):
            continue
        d = sum((c['pos'][i] - me[i]) ** 2 for i in range(3)) ** 0.5
        # hostile = a faction at war with the player (relation < 0; `relation <npc> 20` makes a neutral dummy, T6)
        if d < 3000 and rel.get(c['fac'], -50.0 if 'Bandit' in c['fac'] else 0.0) < 0:
            host.append(n)
        if d < 2000:
            near.append(n)
    return dict(hour=round(h, 2), night=h < 6.5 or h >= 18.5, hostiles=host, near=near,
                popup=('%s is attacking!' % host[0]) if host and s.get('fight') else None)


def dlg_open(s, now):
    """the fixture conversation open right now (opened, not closed by `dialog close`), else None"""
    for d in s.get('dlg', []):
        if d['vt'] <= now and not d['closed']:
            return d
    return None


def sched(s, t, tag, **kv):
    for k, v in kv.items():
        s['tl'].append([t, k, v, tag])


_VMP, _VMSW = None, None


def vm_pose(cls, st):
    """real `fp_vm state` reply for <class>/<state> (vm_poses.json: picked from game outbox.txt nearest PT PASS captures)"""
    global _VMP
    if _VMP is None:
        try:
            _VMP = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vm_poses.json')))
        except (OSError, ValueError):
            _VMP = {}
    return _VMP.get('%s/%s' % (cls, st))


def vmsw_frames():
    global _VMSW
    if _VMSW is None:
        try:
            _VMSW = [l.strip() for l in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vmsw_swing.txt'))
                     if l.strip() and not l.startswith('#')]
        except OSError:
            _VMSW = []
    return _VMSW


def kfplog(t, text):
    import time as _t
    os.makedirs(dr.KDIR, exist_ok=True)
    lt = _t.localtime(t)
    with open(os.path.join(dr.KDIR, 'KenshiFP.log'), 'a') as f:
        f.write('[%02d:%02d:%02d.%03d] %s\n' % (lt.tm_hour, lt.tm_min, lt.tm_sec, int((t % 1) * 1000), text))


def spec():
    d = {}
    if os.path.exists(SPEC):
        for l in open(SPEC):
            p = l.rstrip('\n').split('\t')
            if len(p) >= 5:
                d[p[0]] = dict(src=p[1], minargs=int(p[2] or 0), subs=set(p[3].split(',')) if p[3] else None, usage=p[4])
    return d


def char(s, ref):
    if ref in ('@selected', '@player'):
        ref = s['selected'] if ref == '@selected' else s['squad'][0]
    if ref.startswith('#'):
        for c in s['chars'].values():
            if c['id'] == ref:
                return c
        return None
    if ref in s['chars']:
        return s['chars'][ref]
    for n, c in s['chars'].items():
        if n.lower() == ref.lower():
            return c
    return None


def line(c, me=None):
    p = c['pos']
    d = 0 if me is None else sum((p[i] - me[i]) ** 2 for i in range(3)) ** 0.5
    return '%s %s [%s] pos=%.0f,%.0f,%.0f dist=%.0f%s race=Greenlander' % (c['name'], c['id'], c['fac'], p[0], p[1], p[2], d,
                                                                       ' KO' if c['ko'] else '')


def weapon_drawn(s, c):
    """the weapon R draws: ranged when the char has one equipped and its ranged mode isn't off (kah-fpxbow Malzin with
    katana + bow drew the bow: 4080 proof take 1)"""
    rng = [w for w in c['eq'] if is_ranged(w)]
    mel = [w for w in c['eq'] if not is_ranged(w) and not ARMOR.search(w)]
    if rng and c.get('ranged') is not False:
        return rng[0], 0
    if mel:
        return mel[0], 1
    if rng:
        return rng[0], 0
    return 'fists', 1


def press(s, btn, ms, now):
    fp = s['fp']
    if not s['fpchar']:
        dr.flag('NOTE', 'fp_keys/inject %s with no `fp_control take` first: KenshiFP ignores it' % btn)
        return 'no fp character'
    c = s['chars'][s['fpchar']]
    end = now + ms / 1000.0
    if btn == 'r':
        if fp['drawn']:
            sched(s, now + 0.6, 'r', drawn=0, ui_state='holstered', hud_text='holstered', vm='holstered')
        else:
            w, melee = weapon_drawn(s, c)
            # off_sheathes fixture (xbmesh-c2): the R draw of a sheathed crossbow shows as 'ready' at once (KenshiFP.log same ms)
            sched(s, now + (0.05 if s.get('off_sheathes') else 0.8), 'r', drawn=1, melee=melee, ui_state='ready',
                  hud_text='ready', vm='ready', weapon=w)
        return 'press r'
    tu = s.get('turret', {})
    if tu.get('on') and btn == 'lmb':
        if tu['power'] and tu['ammo']:
            tu['ammo'] = 0; tu['shots'] += 1
            kfplog(now + 0.2, 'harpoon hit a character victim=00a1 (target=00a1)')
            sched(s, now + 0.3, 'turret', hud_text='reloading 6')
            sched(s, now + 6.3, 'turret', hud_text='loaded')
            s['tl'].append([now + 6.3, '_ammo', 1, 'turret'])
        return 'turret fire'
    if not fp['drawn']:
        return 'press %s (nothing drawn)' % btn
    s['keys'][btn] = end
    s['tl'] = [e for e in s['tl'] if not (e[3] == btn and e[0] > now)]   # a re-press extends the hold
    if btn == 'rmb':
        if fp['melee']:
            busy = fp['ui_state'] == 'swinging'
            sched(s, now + 0.1, 'rmb', ui_state='blocking', vm='blocking', hud_text='block')
            sched(s, end + 0.15, 'rmb', ui_state='ready', vm='ready', hud_text='ready')
            if busy:
                kfplog(now + 0.1, "E4 free swing cut by block")
            kfplog(now + 0.1, "free block start tech=0 anim='st' live=1")
        else:
            t = now + 0.1
            if not fp['loaded']:
                sched(s, t, 'rmb', ui_state='reloading', hud_text='reloading', vm='reloading')
                t += 2.0
                sched(s, t, 'rmb', loaded=1, hud_text='loaded')
            if t < end:
                sched(s, t + 0.05, 'rmb', ui_state='aiming', vm='aiming', hud_text='aiming')
            sched(s, max(end, t) + 0.1, 'rmb', ui_state='ready', vm='ready', hud_text='ready')
    elif btn == 'lmb' and fp['melee'] and crosshair(s):
        # LMB drawn on a crosshair character (kfp_controls.inc): sneaking + unaware = vanilla sneak KO order (task 228),
        # else fpc_engage (task 5 on an enemy, 61 unprovoked) and a native fight on him
        t = crosshair(s)
        sk = s.setdefault('sk', {})
        if c.get('sneak'):
            aw = sneak_aware(s, t, now)
            sk['clicks'] = sk.get('clicks', 0) + 1
            if aw == 0:
                sk['attacks'] = sk.get('attacks', 0) + 1
                sk.update(path='vanilla_sneak', last_task=228, result='pending', t=s['pick_t'], pend=now + 1.5)
            else:
                sk['engages'] = sk.get('engages', 0) + 1
                sk.update(path='engage_aware', last_task=5 if is_enemy(s, t) else 61)
                fight_on(s, s['pick_t'])
            kfplog(now + 0.02, '[controls] LMB sneak=1 target=%s target_aware=%d aware_any=%d ko_chance=%.3f path=%s task=%d' % (
                uname(t['name']), aw, 1 if t.get('seen_once') else 0, 0.0 if aw else 158.0, sk['path'], sk['last_task']))
        else:
            sk['engages'] = sk.get('engages', 0) + 1
            sk['last_task'] = 5 if is_enemy(s, t) else 61
            fight_on(s, s['pick_t'])
    elif btn == 'lmb':
        if fp['melee'] and fp.get('weapon') == 'fists':
            fs = s.setdefault('fist', dict(force=-1, swings=0, ikfail=0))
            fs['swings'] += 1
            tn = ['badpunch', 'ma chudan', 'ma 2strike', 'shoteiL'][max(fs['force'], 0) % 4]
            kfplog(now + 0.05, "[vm] fist swing tech='%s' table=%s fallback=0" % (tn, tn.split()[0]))
        if fp['melee']:
            sched(s, now + 0.05, 'lmb', ui_state='swinging', vm='swinging')
            sched(s, now + 1.1, 'lmb', ui_state='ready', vm='ready')
            kfplog(now + 0.05, "free swing start live=1")
            # KenshiFP: native free swing counted (fp_keys free_swings) + viewmodel swing lines (kfp_viewmodel.inc)
            s['free_swings'] = s.get('free_swings', 0) + 1
            n = s['vm_swings'] = s.get('vm_swings', 0) + 1
            # kfp_viewmodel.inc vm_stroke_pick: forced stroke, else round robin over the `strokes` mask
            force, mask = s.get('vm_force', -1), s.get('vm_strokes', 1)
            k = force if 0 <= force < 4 else 0
            if not 0 <= force < 4:
                for i in range(4):
                    j = (s.get('vm_next', 0) + i) % 4
                    if mask & (1 << j):
                        s['vm_next'] = (j + 1) % 4; k = j; break
            kfplog(now + 0.05, '[vm] swing #%d stroke %d (mask 0x%x force %d)' % (n, k, mask, force))
            t = now + 0.05
            for fl in vmsw_frames():
                t += float(re.search(r'dt=([0-9.]+)', fl).group(1)); kfplog(t, '[vmsw] #%d %s' % (n, fl))
            kfplog(now + 1.1, '[vm] swing #%d 1.05s u_end=1.00 prog=1.00 frames=63 maxstep=4.0 rate_max=300 rate_med=150 '
                              'ratio=2.00 elev=-10.0..20.0 az=-30.0..40.0' % n)
        elif fp['ui_state'] == 'aiming' and fp['loaded']:
            sched(s, now + 0.05, 'lmb', loaded=0, hud_text='reload')
            # auto reload while RMB stays held (KenshiFP crossbow: aim -> reload pose -> aim again when loaded)
            sched(s, now + 0.6, 'rmb', ui_state='reloading', vm='reloading', hud_text='reloading')
            sched(s, now + 4.6, 'shot', loaded=1)
            sched(s, now + 4.65, 'rmb', ui_state='aiming', vm='aiming', hud_text='aiming')
            kfplog(now + 0.05, 'crossbow fired')
            n = s['vm_kicks'] = s.get('vm_kicks', 0) + 1
            s['shots'] = s.get('shots', 0) + 1
            kfplog(now + 0.05, '[vm] fire #%d: aim pose held 0.80s + kick (state=aiming)' % n)
    return 'press %s %dms' % (btn, ms)


def release(s, btn, now):
    s['tl'] = [e for e in s['tl'] if not (e[3] == btn and e[0] > now)]
    if s['fp']['drawn']:
        sched(s, now + 0.1, btn, ui_state='ready', vm='ready', hud_text='ready' if s['fp']['loaded'] or s['fp']['melee'] else 'reload')
    s['keys'].pop(btn, None)
    return 'release %s' % btn


# every field of the real reply (KenshiFP client/kfp_controls.inc fp_keys state), in its order; unmodelled ones = 0 / -
FPKEYS_FIELDS = 'hook fault swallow fp drawn wih ranged fists hold ui_state in mmb_selects mmb_none last_select ctx_opens ctx_none ctx_freed rmb_swallowed lmb_swallowed mmb_cam_frames r_keys r_draws r_holsters r_draw_fail sheathe_kept lmb_clicks engages last_task last_target free_swings fs_active fs_prog fs_prog_max fs_ends fs_notech fs_faults fs_dead free_block_frames block_checks native_injected ticks hud hud_shown hud_text hud_changes test_focus sneak sneak_clicks sneak_attacks sneak_ko sneak_failed sneak_timeout sneak_path sneak_target sneak_aware sneak_aware_any sneak_chance sneak_result sneak_elapsed_ms hud_hist mouse_keys_swallowed ctx_hold_opens ctx_tap_opens lmb_why lmb_dist lmb_squad_refused lmb_far_refused r_path mmb_objects mmb_self hud_flashes hud_silent carried down speed_changes speed_long_frames speed_clicks speed_peak_click speed_now ctx_keep ctx_hook ctx_game_shows ctx_game_hides ctx_reshow_blocked ctx_closes ctx_close_where ctx_upd_hook ctx_upd_calls ctx_upd_fed ctx_upd_req ctx_why ctx_tap_refused speed_guard speed_fixed speed_synced speed_target speed_idx speed_peak_input speed_fix_run free free_toggles free_refocus free_load_resets rmb_free_swallowed gui_hook gui_swallowed gui_rel_swallowed holster_pending holster_prog holster_delay holster_done holster_cancels unheld draws_refused redraws_undone hud_hide_why hud_flash_cut hud_flash hud_native_vis hud_guard_skips holster_aim_ends '.split()


def fpkeys_state(s):
    f = s['fp']
    w = f.get('weapon')
    v = dict(hook=1, fp=1 if s['fpchar'] else 0, drawn=f['drawn'], wih=0 if w in (None, 'fists') else 1,
             ranged=0 if f['melee'] else 1, fists=1 if w == 'fists' else 0, ui_state=f['ui_state'], hud=1, hud_shown=1,
             hud_text=f['hud_text'], hud_changes=3, speed_now='%.2f' % s.get('speed', 1), speed_target='%.2f' % s.get('speed', 1),
             speed_guard=1, ctx_hook=1, gui_hook=1, hud_native_vis=0, ticks=1000, free_swings=s.get('free_swings', 0))
    sk, me = s.get('sk', {}), s['chars'].get(s.get('fpchar') or '') or {}
    v.update(sneak=me.get('sneak', 0), sneak_clicks=sk.get('clicks', 0), sneak_attacks=sk.get('attacks', 0),
             sneak_path=sk.get('path', 'none'), sneak_result=sk.get('result', 'none'), engages=sk.get('engages', 0),
             last_task=sk.get('last_task', -1), sneak_elapsed_ms=sk.get('elapsed', 0),
             sneak_ko=1 if sk.get('result') == 'ko' else 0)
    return ' '.join('%s=%s' % (k, v.get(k, '-' if k.endswith(('_why', '_path', '_target', '_result', '_where', '_hist', 'last_select', 'last_target')) else 0))
                    for k in FPKEYS_FIELDS)


# ---------------- KenshiFP.ini + manual melee fight (fp_combat on/input, fp_melee, hp flesh) ----------------
def ini_path():
    return os.path.join(dr.KDIR, 'mods', 'KenshiFP', 'KenshiFP.ini')


def ensure_ini():
    """the sandbox Kenshi dir starts empty: put the installed KenshiFP.ini there (snapshot in kfp_formats.json _ini,
    gen_kfp_formats.py) so scripts that edit it in place (fp-swing-hits-all.sh setini) find it like on the rig"""
    p = ini_path()
    if not os.path.exists(p) and kfpreply._F.get('_ini'):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            f.write(kfpreply._F['_ini'])


def ini_get(key, default=0):
    """KenshiFP hot-reloads edited ini values (~0.5 s): read the file at every use"""
    try:
        for l in open(ini_path(), errors='replace'):
            k, _, v = l.strip().partition('=')
            if k == key:
                return int(float(v))
    except (OSError, ValueError):
        pass
    return default


REACH = 25.0          # dm: a native melee swing reaches the target / others in the zone (pin dist 12 = in reach)
SWING_LEN = 1.1       # s CHOP per native swing; clicks inside it are rejected (M02 native pace)


def serial(c):
    return int(c['id'][1:].split('/')[0])


def flat(a, b):
    return ((a['pos'][0] - b['pos'][0]) ** 2 + (a['pos'][2] - b['pos'][2]) ** 2) ** 0.5


def flesh_of(c):
    return c.setdefault('flesh', [100.0] * 7)


def melee(s):
    return s.setdefault('melee', dict(on=0, armed=0, inj=0, fire=0, aim=0, passive=0, tgt=None, swings=0, clicks=0,
                                      rejected=0, oor=0, expired=0, blocks=0, block_ok=0, ai_ref=0.0, ab_ref=0.0,
                                      pas_ref=0.0, sw_t=-1e9, spam=None, fc=0, forced=0.0, cdrops=0, cswings=0, lat=0,
                                      maxlat=0, hits=0, zt=0, ends=0, swtime=0.0, slack_n=0, min_slack=0.0, min_gap=0.0,
                                      last_len=0.0, t=None, inj_cmds=0, inj_aim=0, ever=0,
                                      sha=dict(swings=0, widened=0, last_zone=0, last_extra=0, skipped_off=0,
                                               skipped_unowned=0)))


def fighter(s):
    return s['chars'].get(s['fpchar']) if s.get('fpchar') else None


def fight_target(s):
    """the native fight of the controlled fighter (set by `attack` either way), live while both stand"""
    m, f = melee(s), fighter(s)
    t = s['chars'].get(m['tgt']) if m['tgt'] else None
    if not f or not t or t.get('ko') or f.get('ko'):
        return None
    return t


def owned(s):
    m = melee(s)
    return bool(m['on'] and m['armed'] and fighter(s))


def mstate(s, now):
    """native CombatClass state: 0 CHOP (swing), 1 BLOCK, 4 WAIT, 11 chase lock (force_chase)"""
    m = melee(s)
    if now - m['sw_t'] < SWING_LEN:
        return 0
    if not fight_target(s):
        return 4
    if m['aim'] and owned(s):
        return 1
    return 11 if m['fc'] and owned(s) else 4


def do_click(s, t):
    """one LMB press edge on the manual melee path (kfp_combat_melee.inc): native swing when legal and in reach"""
    m, f = melee(s), fighter(s)
    m['clicks'] += 1
    if not owned(s):
        return
    tg = fight_target(s)
    if not tg or t - m['sw_t'] < SWING_LEN or m['aim']:
        m['rejected'] += 1
        return
    if flat(f, tg) > REACH:
        m['oor'] += 1          # pending click times out out of reach: no swing, no approach (M06)
        return
    if m['sw_t'] > 0:
        gap = t - m['sw_t']
        m['ends'] += 1; m['swtime'] += SWING_LEN; m['last_len'] = SWING_LEN
        m['min_gap'] = gap if m['slack_n'] == 0 else min(m['min_gap'], gap)
        m['min_slack'] = gap - SWING_LEN if m['slack_n'] == 0 else min(m['min_slack'], gap - SWING_LEN)
        m['slack_n'] += 1
    m['swings'] += 1; m['sw_t'] = t; m['lat'] = 85; m['maxlat'] = max(m['maxlat'], 85)
    if m['fc']:
        m['cdrops'] += 1; m['cswings'] += 1
    # impact: the target always; with swing_hits_all=1 every other character in the swing zone (pending
    # kfp-swing-hits-all: attackImpactCheck widened to allies/neutrals)
    dx, dz = tg['pos'][0] - f['pos'][0], tg['pos'][2] - f['pos'][2]
    L = max((dx * dx + dz * dz) ** 0.5, 1.0)
    extra = []
    for n, c in s['chars'].items():
        if c is f or c is tg or c.get('ko'):
            continue
        ex, ez = c['pos'][0] - f['pos'][0], c['pos'][2] - f['pos'][2]
        d = (ex * ex + ez * ez) ** 0.5
        if 0 < d <= REACH and (ex * dx + ez * dz) / (d * L) >= 0.5:    # within 60 deg of the swing line
            extra.append(c)
    on = ini_get('swing_hits_all')
    hit = [tg] + (extra if on else [])
    if s.get('swing_ko'):
        # op-swa4 (fixture swing_ko): vanilla melee also hits a neutral in the zone, and one katana hit on a defence-1
        # Hungry Bandit knocks him out; `health 100` keeps the KO (only `wake` stands him up)
        for c in extra:
            if c['name'] not in s['squad'] and not c.get('protected'):
                c['ko'] = 1
    for c in hit:
        if not c.get('protected'):
            fl = flesh_of(c)
            fl[1] -= 12.0
    m['hits'] += 1; m['zt'] = len(hit)
    st = f.setdefault('stats', {})
    st['attack'] = st.get('attack', 10.0) + 0.15
    sh = m['sha']
    sh['swings'] += 1; sh['last_zone'] = len(hit); sh['last_extra'] = len(extra) if on else 0
    if on and extra:
        sh['widened'] += 1
        kfplog(t, '[melee] swing_all: zone=%u extra=%u (allies/neutrals in the swing area)' % (len(hit), len(extra)))
    if not on:
        sh['skipped_off'] += 1


def mtick(s, now):
    """advance the melee model to now: arming, AI initiative refused while owned, the target's attacks (refused by
    passive / auto-block refused with RMB up), force_chase frames, `fp_melee spam` clicks at their own times"""
    m = melee(s)
    t0 = m['t'] if m['t'] is not None else now
    dt = max(0.0, now - t0)
    m['t'] = now
    if m['on'] and not m['armed'] and not m['fire'] and not m['aim']:
        m['armed'] = 1
    tg, f = fight_target(s), fighter(s)
    if owned(s) and tg:
        m['ai_ref'] += dt / 1.5
        if flat(f, tg) <= 3 * REACH:
            if m['passive'] == serial(f):
                m['pas_ref'] += dt / 2.0
            elif not m['aim']:
                m['ab_ref'] += dt / 2.5
        if m['fc'] and now - m['sw_t'] >= SWING_LEN:
            m['forced'] += dt * 60
    sp = m['spam']
    if sp:
        while sp['done'] < sp['n'] and sp['t0'] + sp['done'] * sp['p'] / 1000.0 <= now:
            do_click(s, sp['t0'] + sp['done'] * sp['p'] / 1000.0)
            sp['done'] += 1
        if sp['done'] >= sp['n']:
            m['spam'] = None


def fp_melee_cmd(s, a, now):
    m = melee(s)
    sub = a[0] if a else 'state'
    if sub == 'passive' and len(a) == 2:
        if a[1].lower() == 'off':
            m['passive'] = 0
            return True, 'passive off'
        if not a[1].isdigit() or int(a[1]) == 0:
            return False, 'usage: fp_melee passive <serial>|off'
        m['passive'] = int(a[1])
        return True, 'passive on: AI attacks aimed at that serial are refused'
    if sub == 'spam' and len(a) in (2, 3):
        if len(a) == 2 and a[1].lower() == 'off':
            m['spam'] = None
            return True, 'spam off'
        n, p = int(a[1]) if a[1].isdigit() else 0, int(a[2]) if len(a) == 3 and a[2].isdigit() else (200 if len(a) == 2 else 0)
        if not 1 <= n <= 1000 or not 20 <= p <= 5000:
            return False, 'usage: fp_melee spam <clicks 1-1000> [period_ms 20-5000, default 200] | fp_melee spam off'
        m['spam'] = dict(n=n, p=p, t0=now, done=0)
        return True, 'spam on: %d clicks every %d ms' % (n, p)
    if sub == 'force_chase' and len(a) == 2:
        if a[1].lower() not in ('on', 'off'):
            return False, 'usage: fp_melee force_chase on|off'
        m['fc'] = 1 if a[1].lower() == 'on' else 0
        return True, 'force_chase on: owned fighter forced into the native chase lock (state 11) each tick' if m['fc'] else 'force_chase off'
    if sub == 'swing_all':
        if len(a) == 2:
            if a[1].lower() != 'reset':
                return False, 'usage: fp_melee swing_all [reset]'
            m['sha'] = dict(swings=0, widened=0, last_zone=0, last_extra=0, skipped_off=0, skipped_unowned=0)
        return True, kfpreply.render('swingall', setting=ini_get('swing_hits_all'), ready=1, owned=1 if owned(s) else 0,
                                     **m['sha'])
    if sub != 'state' or len(a) > 2:
        dr.flag('NOTE', 'fp_melee %s answered generically' % ' '.join(a))
        return True, 'fp_melee %s ok (dryrun)' % ' '.join(a)
    f = char(s, a[1]) if len(a) == 2 else fighter(s)
    if not f:
        return False, 'controlled actor unavailable' if len(a) == 1 else 'character not found'
    me = f is fighter(s)
    tg = fight_target(s) if me else None
    st = mstate(s, now) if me else 4
    why = 'init' if not m['ever'] else ('arming' if m['on'] and not m['armed'] else ('ok' if m['on'] else 'init'))
    th = '#%s' % tg['id'][1:] if tg else '#0/0'
    base = kfpreply.render('melee', actor='%x' % (0x7ff600000000 + serial(f)), controlled=1 if me else 0,
                           combat='%x' % (0x7ff700000000 + serial(f)), active=1 if tg else 0, state=st,
                           next=0 if st == 0 else 4, target_h=th, zone_targets=m['zt'] if me and tg else 0,
                           threats=1 if tg else 0, frame_dt='0.016667')
    sl = m['spam']
    app = kfpreply.render('meleeapp', manual_ready=1, owned=1 if owned(s) else 0, why=why, armed=m['armed'], pending=0,
                          clicks=m['clicks'], swings=m['swings'], ai_refused=int(m['ai_ref']), rejected=m['rejected'],
                          blocks=m['blocks'], block_ok=m['block_ok'], autoblock_refused=int(m['ab_ref']),
                          out_of_reach=m['oor'], passive=1 if m['passive'] else 0, passive_refused=int(m['pas_ref']),
                          chase_drops=m['cdrops'], chase_swings=m['cswings'], force_chase=m['fc'],
                          forced_chase=int(m['forced']), expired=m['expired'], last_latency_ms=m['lat'],
                          max_latency_ms=m['maxlat'], spam_left=(sl['n'] - sl['done']) if sl else 0,
                          swing_ends=m['ends'], swing_time='%.3f' % m['swtime'], last_swing_len='%.3f' % m['last_len'],
                          min_swing_gap='%.3f' % m['min_gap'], slack_n=m['slack_n'],
                          min_swing_slack='%.3f' % m['min_slack'], in_aim=m['aim'], in_fire=m['fire'],
                          injection=m['inj'], inj_cmds=m['inj_cmds'], inj_aim_cmds=m['inj_aim'], melee_hits=m['hits'],
                          melee_cut='%.1f' % (12.0 * m['hits']), wounds_any=m['hits'], focus=0, prone=0, unconscious=0,
                          ko_timer='0.0', st_found=1, st_vt=1, get_state=1, last_reject='-' if not m['rejected'] else 'chop')
    return True, base + ' ' + app


def fp_combat_melee(s, a, now):
    """fp_combat on/off/physical/input (kfp_combat_native.inc replies); input edges drive the melee model"""
    m = melee(s)
    sub = a[0]
    if sub == 'on' and len(a) == 1:
        m['on'] = 1; m['ever'] = 1; m['armed'] = 0; s['combat_on'] = 1
        mtick(s, now)
        return True, 'manual ownership requested; release all combat buttons to arm'
    if sub == 'off' and len(a) == 1:
        m['on'] = 0; m['armed'] = 0; m['inj'] = 0; s['combat_on'] = 0
        if s.get('off_sheathes') and s['fp']['drawn'] and not s['fp']['melee']:
            # fixture off_sheathes (xbmesh-c2): the manual release lets the native AI sheathe the crossbow (back sheath)
            sched(s, now + 0.3, 'cin', drawn=0, ui_state='holstered', hud_text='holstered', vm='holstered')
        return True, 'manual ownership release requested'
    if sub == 'physical' and len(a) == 1:
        m['inj'] = 0; m['fire'] = 0; m['aim'] = 0
        return True, 'physical combat input restored'
    if sub == 'input' and len(a) == 4:
        if any(x not in ('0', '1') for x in a[1:]):
            return False, 'input values must be 0 or 1'
        aim, fire = int(a[1]), int(a[2])
        m['inj_cmds'] += 1; m['inj_aim'] += aim; m['inj'] = 1
        pf, pa = m['fire'], m['aim']
        m['fire'], m['aim'] = fire, aim
        fp = s['fp']
        if fp['drawn'] and not fp['melee'] and m['on'] and m['armed']:   # crossbow: aim hold / fire edge / auto reload
            if aim and not pa and not fp['loaded'] and s.get('autoreload', 1):
                # xbow_empty fixture (xbmesh-c): an empty bow auto-reloads on the first aim; shot_ready came ~8.2 s later
                sched(s, now + 0.1, 'cin', ui_state='reloading', vm='reloading', hud_text='reloading')
                sched(s, now + 8.3, 'cin', loaded=1, ui_state='aiming', vm='aiming', hud_text='aiming')
            elif aim and not pa:
                sched(s, now + 0.1, 'cin', ui_state='aiming', vm='aiming', hud_text='aiming')
            if fire and not pf and aim and fp['loaded']:
                fp['loaded'] = 0; s['shots'] = s.get('shots', 0) + 1
                n = s['vm_kicks'] = s.get('vm_kicks', 0) + 1
                kfplog(now + 0.05, 'crossbow fired')
                kfplog(now + 0.05, '[vm] fire #%d: aim pose held 0.80s + kick (state=aiming)' % n)
                sched(s, now + 0.9, 'cin', ui_state='reloading', vm='reloading', hud_text='reloading')
                sched(s, now + 2.9, 'cin', loaded=1, ui_state='aiming', vm='aiming', hud_text='aiming')
            if not aim and pa:
                s['tl'] = [e for e in s['tl'] if not (e[3] == 'cin' and e[0] > now and e[1] != 'loaded')]
                sched(s, now + 0.1, 'cin', ui_state='ready', vm='ready', hud_text='ready')
            return True, 'combat input published; same controller/native gates as physical input'
        if m['on'] and not m['armed'] and not fire and not aim:
            m['armed'] = 1
        elif owned(s):
            if aim and not pa and fight_target(s):
                m['blocks'] += 1; m['block_ok'] += 1
            if fire and not pf:
                do_click(s, now)
        c = s['chars'].get(s['fpchar'] or s['selected'])
        if (m['on'] and m['armed'] and not fp['drawn'] and c and any(is_ranged(e) for e in c.get('eq', []))
                and not any(e[1] == 'drawn' and e[3] == 'cin' and e[0] > now for e in s['tl'])):
            # the ranged adapter draws a holstered crossbow itself (kfp_combat_native.inc holstered draw)
            w, _ = weapon_drawn(s, c)
            sched(s, now + 0.5, 'cin', drawn=1, melee=0, ui_state='ready', hud_text='ready' if fp['loaded'] else 'reload',
                  vm='ready', weapon=w)
        return True, 'combat input published; same controller/native gates as physical input'
    return None


def handle(s, cmd, a, now, sp):
    """returns (ok, reply)"""
    def need_char(i):
        if len(a) <= i:
            return None
        c = char(s, a[i])
        if c is None:
            dr.flag('FAIL', '%s: no character "%s" in %s (fixture model)' % (cmd, a[i], s['save']))
        return c
    fp = s['fp']
    # harness FrameCap (Plugin.cpp): framecap.txt re-read about once a second, every change logged "KAH: frame cap N fps|off";
    # the fake game renders 60 fps capped, 140 uncapped (gfx-measure.sh GFXM)
    try:
        cap = int(open(os.path.join(dr.KDIR, 'mods', 'AutomationHarness', 'framecap.txt')).read().split()[0])
    except (OSError, ValueError, IndexError):
        cap = 0
    if cap != s.get('fcap', 0):
        s['fcap'] = cap
        with open(os.path.join(dr.KDIR, 'mods', 'AutomationHarness', 'harness.log'), 'a') as f:
            f.write('[dryrun] KAH: frame cap %s\n' % ('%d fps' % cap if cap > 0 else 'off'))
    if cmd == 'fps':
        v = float(cap) if 0 < cap < 140 else 140.0
        return True, 'avg=%.1f min=%.1f worst_ms=%.1f frames=%d seconds=10.0%s' % (
            v, v - 5, 1000.0 / (v - 5), int(v * 10), ' (reset)' if a[:1] == ['reset'] else '')
    if cmd in ('status', 'wait-world', 'wait-game'):
        return True, 'phase=world save=%s last_saved=%s paused=%d speed=%g squad=%d player=%s' % (
            s['save'], s.get('last_saved', s['save']), s['paused'], s['speed'], len(s['squad']), s['squad'][0])
    if cmd == 'on' or cmd == 'off':
        return True, 'harness %s' % cmd
    if cmd == 'load':
        names = set(open(SAVES).read().split('\n')) if os.path.exists(SAVES) else set()
        if names and a[0] not in names and not os.path.isdir(os.path.join(SAVEDIR, a[0])):
            dr.flag('FAIL', 'load: save "%s" does not exist in this rig\'s save dir' % a[0])
            return False, 'no save named %s' % a[0]
        ns = new_state(a[0])
        ns['hist'] = s['hist'] + [[now, k, v] for k, v in ns['fp'].items()]
        ns['iso'] = s.get('iso', ns['iso'])   # harness input isolation survives a load (game-process state)
        s.clear(); s.update(ns)
        dr.advance(1.0)
        return True, 'loading %s' % a[0]
    if cmd == 'save':
        # Kenshi writes %LOCALAPPDATA%\kenshi\save\<name>\ (sandbox C: overlay: discarded after the row)
        d = os.path.join(SAVEDIR, a[0])
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'quick.save'), 'w') as f:
            f.write('dryrun save of %s\n' % s['save'])
        s['last_saved'] = a[0]
        return True, 'saving %s' % a[0]
    if cmd == 'time':
        h, d = s['hour'], s.get('day', 12)   # WorldCommands.inc time
        return True, 'game_hours=%.4f day=%d time=%02d:%02d speed=%.1f paused=%d' % (
            d * 24 + h, d, int(h), int((h % 1) * 60), s['speed'], s['paused'])
    if cmd == 'speed':
        try:
            v = float(a[0])
        except ValueError:
            dr.flag('FAIL', 'speed: "%s" is not a number' % a[0])
            return False, 'bad speed'
        s['speed'], s['paused'] = (v, 0) if v > 0 else (s['speed'], 1)
        return True, 'speed %g%s' % (v, ' hold' if 'hold' in a else '')
    if cmd == 'chatter':
        if a and a[0] in ('on', 'off'):
            s['chatter'] = a[0]
            return True, 'chatter %s (muted 0 bubbles so far)' % a[0]
        return True, 'status: chatter=%s muted=0' % s['chatter']
    if cmd == 'select':
        c = need_char(0)
        if c:
            s['selected'] = c['name']
            return True, 'selected %s' % c['name']
        return False, 'no character'
    if cmd == 'chars':
        r = float(a[0]) if a and re.match(r'^[\d.]+$', a[0]) else 100.0
        flt = a[1] if len(a) > 1 else (a[0] if a and not re.match(r'^[\d.]+$', a[0]) else '')
        me = s['chars'][s['selected']]['pos']
        out = []
        for c in s['chars'].values():
            ln = line(c, me)
            d = sum((c['pos'][i] - me[i]) ** 2 for i in range(3)) ** 0.5
            if d > r:
                continue
            if flt:
                alts = [x.strip().lower() for x in flt.split('|') if x.strip()]
                inc = [x for x in alts if not x.startswith('!')]
                exc = [x[1:] for x in alts if x.startswith('!')]
                if inc and not any(x in ln.lower() for x in inc):
                    continue
                if any((x == 'ko' and c['ko']) or (x not in ('ko', 'dead') and x in ln.lower()) for x in exc):
                    continue
            out.append(ln)
        return True, '%d within %g: %s' % (len(out), r, ' | '.join(out))
    if cmd == 'where':
        c = need_char(0)
        return (True, line(c, s['chars'][s['selected']]['pos'])) if c else (False, 'no character %s' % a[0])
    if cmd in ('pin', 'ko', 'wake', 'health', 'hunger', 'protect', 'hp', 'stat', 'setstat', 'sections', 'weight', 'senses',
               'blood', 'kill', 'relation', 'attack', 'money', 'stealth'):
        if cmd == 'protect' and not a:
            return True, 'protect: none'
        c = need_char(0)
        if not c:
            return False, 'no character %s' % (a[0] if a else '')
        nm = c['name']
        if cmd == 'pin':   # harness BalanceCommands.inc pin
            pins = s.setdefault('pins', [])
            was = nm in pins
            if was:
                pins.remove(nm)
            if len(a) > 1 and a[1].lower() == 'off':
                return True, ('unpinned %s put_back=0' % nm) if was else '%s was not pinned' % nm
            at = list(c['pos'])
            if 'at' in a:
                i = a.index('at')
                xyz = a[i + 1:i + 4]
                if len(xyz) == 3 and all(re.match(r'^-?[\d.]+$', v) for v in xyz):
                    at = [float(v) for v in xyz]
                else:
                    o = char(s, a[i + 1]) if len(a) > i + 1 else None
                    if not o:
                        dr.flag('FAIL', 'pin: at "%s" is no character / x y z' % ' '.join(a[i + 1:i + 2]))
                        return False, 'no character %s' % ' '.join(a[i + 1:i + 2])
                    at = list(o['pos'])
            if 'dist' in a:
                at[0] += float(a[a.index('dist') + 1])
            face = None
            if 'face' in a:
                face = char(s, a[a.index('face') + 1])
                if not face:
                    return False, 'no character %s' % a[a.index('face') + 1]
            pins.append(nm)
            c['face'] = face['name'] if face else None
            if s.get('swing_ko') and c.get('ko'):
                # op-swa4 (fixture swing_ko): a KO ragdoll ignores teleport; the real pin answers ERROR with the miss
                return False, 'pinned %s at %.1f,%.1f,%.1f off=10.2%s pins=%d' % (nm, at[0], at[1], at[2],
                                                                                ' facing ' + face['name'] if face else '', len(pins))
            c['pos'] = at
            return True, 'pinned %s at %.1f,%.1f,%.1f off=0.0%s pins=%d' % (nm, at[0], at[1], at[2],
                                                                           ' facing ' + face['name'] if face else '', len(pins))
        if cmd == 'ko':
            c['ko'] = 1
            return True, 'knocked out %s for %.1f s' % (nm, float(a[1]) if len(a) > 1 else 30.0)
        if cmd == 'wake':
            c['ko'] = 0
        if cmd == 'kill':
            c['ko'] = 2
            c['flesh'] = [-200.0] * 7
            return True, 'killed %s (body parts at -200%%)' % nm
        if cmd == 'health':
            pct = float(a[1])
            c['flesh'] = [100.0 * pct / 100.0] * 7
            return True, 'set every body part of %s to %.1f%%' % (nm, pct)
        if cmd == 'hp' and len(a) == 1:   # Commands.cpp hp: per body part flesh/max
            fl = flesh_of(c)
            w = min(fl) / 100.0
            return True, '%s worst=%d%% blood=100.0/100.0%s parts %s' % (
                nm, int(w * 100), ' KO' if c['ko'] else '', ' '.join('%d:%.1f/100.0' % (i, v) for i, v in enumerate(fl)))
        if cmd == 'protect':
            c['protected'] = len(a) > 1 and a[1].lower() == 'on'
            return True, '%s protect=%s' % (nm, 'on' if c['protected'] else 'off')
        if cmd == 'setstat' and len(a) >= 3:
            st = c.setdefault('stats', {})
            b = st.get(a[1], 10.0)
            st[a[1]] = float(a[2])
            return True, '%s %s %.1f -> %.1f' % (nm, a[1], b, st[a[1]])
        if cmd == 'stat' and len(a) >= 2 and a[1] != 'all':
            v = c.get('stats', {}).get(a[1], 10.0)
            return True, '%s %s base=%.1f effective=%.1f mod=1.000 hunger=1.000 wounds=1.000 dark=1.000 robot=1.000 ' \
                         'weather=1.000 gear=1.000 light=1.000' % (nm, a[1], v, v)
        if cmd == 'relation' and len(a) >= 2:
            b = s.setdefault('relations', {}).get(c['fac'], -50.0 if 'Bandit' in c['fac'] else 0.0)
            s['relations'][c['fac']] = float(a[1])
            # enemy = the faction's enemy state (a per-character spawn_hostile flag stays: 23-rg02 enemy=0->0, hostile=1)
            return True, '%s <-> Nameless: %.1f -> %.1f enemy=%d->%d' % (c['fac'], b, float(a[1]), 1 if b < 0 else 0,
                                                                        1 if float(a[1]) < 0 else 0)
        if cmd == 'stealth':
            if len(a) > 1 and a[1].lower() in ('on', 'off'):
                was = c.get('sneak', 0)
                c['sneak'] = 1 if a[1].lower() == 'on' else 0
                if c['sneak'] and not was:
                    c['sneak_t'] = now
            return True, 'stealth_mode=%d' % c.get('sneak', 0)
        if cmd == 'senses':
            aw = sneak_aware(s, c, now) if s.get('fpchar') and len(a) > 1 and a[1] == s['fpchar'] else 0
            return True, 'sees=%d hears=0 aware=%d entry=%d last_seen_s=%s fov=0.0 dist=15.0 observer_ko=%d' % (
                aw, aw, aw, '0.0' if aw else '-1', 1 if c.get('ko') else 0)
        if cmd == 'attack':   # Commands.cpp attack <attacker> <target>: a native fight between them
            o = need_char(1)
            if not o:
                return False, 'no character %s' % a[1]
            if s.get('fpchar') in (c['name'], o['name']):
                melee(s)['tgt'] = o['name'] if s['fpchar'] == c['name'] else c['name']
            return True, '%s attacks %s' % (nm, o['name'])
        if cmd == 'hunger':
            return True, '%s hunger 100.0%s' % (nm, (' -> %.1f' % float(a[1])) if len(a) > 1 else '')
        return True, '%s %s ok' % (cmd, c['name'])
    if cmd == 'sync_flash':   # harness d2a9ff2: full-frame marker for label sync (take-sample.sh take_mark)
        ms = int(a[0]) if a and a[0].isdigit() else 120
        n = int(a[1]) if len(a) > 1 and a[1].isdigit() else 0
        dr.log('sync', 'flash n=%d ms=%d' % (n, ms))
        return True, 'sync_flash n=%d ms=%d view=1600x900' % (n, ms)
    if cmd == 'stamp':   # harness 0c6c695: per-frame sync code (take-sample.sh TAKE_STAMP=1)
        on = bool(a) and a[0] == 'on'
        if a and a[0] in ('on', 'off'):
            dr.log('sync', 'stamp %s' % a[0])
        if on and 'log' in a[:-1]:   # <HarnessDir>\<file>: one line per change `<fc> <epoch> <lo> <hi> <mark> <flags>`
            try:
                with open(os.path.join(dr.KDIR, 'mods', 'AutomationHarness', a[a.index('log') + 1]), 'a') as f:
                    f.write('\t'.join(['1', '0.000', '0', '0', '0', '1']) + '\n')
            except OSError as e:
                return False, 'stamp: log %s' % e
        return True, 'stamp %s cell=8 fc=0 mark=0' % ('on' if on else 'off')
    if cmd == 'rangedinfo':
        c = need_char(0)
        if not c:
            return False, 'no character %s' % (a[0] if a else '')
        bows = [w for w in c['eq'] if is_ranged(w)]
        r = '%s turret_hand={none} turret_valid=0 turret_live=0 bow=%s' % (line(c), bows[0] if bows else 'none')
        if bows:
            r += ' has_ammo=1 gun_active=0 shots=1/1 ammo_type=Bolts gun_user={none} reload_state=0'
        return True, r
    if cmd == 'teleport':
        c = need_char(0)
        if not c:
            return False, 'no character'
        rest = a[1:]
        if len(rest) >= 3 and all(re.match(r'^-?[\d.]+$', v) for v in rest[:3]):
            c['pos'] = [float(v) for v in rest[:3]]
        elif rest and rest[0] != 'building':
            o = need_char(1)
            if o:
                c['pos'] = list(o['pos'])
        else:
            dr.flag('FAIL', 'teleport: bad target %s' % ' '.join(rest))
            return False, 'bad target'
        return True, 'teleported %s moved=1 off_target=0.4 method=teleport' % c['name']
    if cmd == 'combatmode':
        c = need_char(0)
        if c and len(a) >= 3 and a[1] == 'ranged':
            c['ranged'] = a[2] == 'on'
        return (True, 'combatmode %s %s' % (a[0], ' '.join(a[1:]))) if c else (False, 'no character')
    if cmd == 'inv':
        c = need_char(0)
        if not c:
            return False, 'no character'
        # real harness (Commands.cpp): "<Describe> items=<n> [json]", weapons carry "weapon_model"
        its = []
        for i in sorted(set(c['items']), key=c['items'].index):
            d = dict(name=i, count=c['items'].count(i), equipped=i in c['eq'])
            if not ARMOR.search(i):
                d['weapon_model'] = i.lower().replace(' ', '_')
            its.append(d)
        return True, '%s items=%d %s' % (line(c), len(its), json.dumps(its, separators=(',', ':')))
    if cmd in ('equip', 'unequip', 'iteminfo'):
        c = need_char(0)
        if not c or len(a) < 2:
            return False, 'no character'
        # Commands.cpp FindInventoryItem: stringID or exact name (case-insensitive), else a unique substring
        want = ' '.join(a[1:])
        it = item_name(want)
        if it not in c['items']:
            low = [i for i in dict.fromkeys(c['items']) if i.lower() == it.lower()]
            part = [i for i in dict.fromkeys(c['items']) if it.lower() in i.lower()]
            if low:
                it = low[0]
            elif len(part) > 1:
                return False, 'ambiguous inventory item: %s' % want
            elif part:
                it = part[0]
            else:
                return False, 'no inventory item matching: %s' % want
        if cmd == 'equip':
            if it not in c['eq']:
                c['eq'].append(it)
            return True, 'equipped ' + desc_item(s, it)
        if cmd == 'unequip':
            if it not in c['eq']:
                return True, 'not equipped: ' + desc_item(s, it)
            c['eq'].remove(it)
            if s['fpchar'] == c['name'] and fp['drawn'] and fp.get('weapon') == it:
                sched(s, now + 0.2, 'r', drawn=0, ui_state='holstered', hud_text='holstered', vm='holstered')
            return True, 'unequipped (%s -> main) %s' % ('back' if is_ranged(it) else 'hip', desc_item(s, it))
        return True, desc_item(s, it)
    if cmd == 'transfer':
        c, o = need_char(0), need_char(1)
        it = item_name(' '.join(a[2:]))
        if not c or not o or it not in c['items']:
            return False, 'transfer failed'
        c['items'].remove(it); o['items'].append(it)
        if it in c['eq']:
            c['eq'].remove(it)
        return True, 'transferred %s from %s to %s' % (desc_item(s, it), c['name'], o['name'])
    if cmd == 'give':   # real (Commands.cpp give): "<char> got <real>/<count> <item name> (now <n>)"
        c = need_char(0)
        if not c or len(a) < 2:
            return False, 'usage: give <npc> <item> [count]'
        n = int(a[2]) if len(a) > 2 and a[2].isdigit() else 1
        if n < 1 or n > 50:
            return False, 'count must be 1..50'
        it = item_name(a[1])
        # fixtures/studio-noroom.json (04-twohand-b 2026-10-11): a long weapon fits no section while a blocker (the
        # studio Axima's bow on the back) is worn; real give moves only a worn weapon of the item's slot type
        nr = s.get('give_noroom') or {}
        if it in nr.get('items', []) and any(b in c['eq'] for b in nr.get('blockers', [])):
            return False, ('ERROR: no room for %s in %s\'s inventory (%d already there) item=10x1 slot=0 '
                           'hip:7x1,lim=0,n=1,room=0 back:12x1,lim=0,n=1,room=0 main:6x8,lim=0,n=0,room=0'
                           % (it, c['name'], c['items'].count(it)))
        c['items'] += [it] * n
        return True, '%s got %d/%d %s (now %d)' % (c['name'], n, n, it, c['items'].count(it))
    if cmd in ('pickup', 'give'):
        c = need_char(0)
        if not c:
            return False, 'no character'
        it = item_by_ref(s, a[1]) if len(a) > 1 else ''
        if it and it not in c['items']:
            for o in s['chars'].values():
                if it in o['items'] and it not in o['eq']:
                    o['items'].remove(it); break
            c['items'].append(it)
        if cmd == 'pickup' and ARMOR.search(it) and it not in c['eq']:
            c['eq'].append(it)
        return True, '%s %s %s' % (cmd, c['name'], it)
    if cmd == 'screenshot':
        nm = (a[0] if a else 'shot').replace('\\', '/').split('/')[-1]
        if not nm.lower().endswith('.png'):
            nm += '.png'
        d = os.path.join(dr.KDIR, 'mods', 'AutomationHarness', 'shots')
        os.makedirs(d, exist_ok=True)
        import shutil
        dark = world(s, now)['night'] and os.path.exists(os.path.join(dr.CANNED, 'frame-night.png'))
        shutil.copyfile(os.path.join(dr.CANNED, 'frame-night.png' if dark else 'frame.png'), os.path.join(d, nm))
        dr.jappend('recordings.jsonl', dict(kind='screenshot', t=now, file=nm))
        dr.advance(0.3)
        return True, 'screenshot shots\\%s 1600x900' % nm
    if cmd == 'input_isolation':
        if a and a[0] in ('on', 'off'):
            s['iso'] = 1 if a[0] == 'on' else 0
        return True, 'isolation=%s hooks=user32:8/8 (dryrun)' % ('on' if s.get('iso', 1) else 'off')
    if cmd in ('mouse_inject', 'key_inject') and not s.get('iso', 1):
        return False, 'input isolation is off (input_isolation on first; injected input only feeds the isolated game)'
    if cmd == 'mouse_inject':
        if a and a[0] == 'at':
            s['cursor'] = [int(float(a[1])), int(float(a[2]))] if len(a) >= 3 else s['cursor']
        elif a and a[0] in ('left', 'right', 'middle'):
            b = {'left': 'lmb', 'right': 'rmb', 'middle': 'mmb'}[a[0]]
            mode = a[1] if len(a) > 1 else 'click'
            ms = int(a[2]) if len(a) > 2 else 80
            if mode == 'up':
                release(s, b, now)
            elif b != 'mmb':
                press(s, b, 60000 if mode == 'down' else ms, now)
        return True, 'mouse %s cursor=%d,%d mice=1' % (' '.join(a), s['cursor'][0], s['cursor'][1])
    if cmd == 'key_inject':
        k = a[0].lower() if a else ''
        mode = a[1] if len(a) > 1 else 'tap'
        if k == 'r' and mode in ('tap', 'down'):
            press(s, 'r', 120, now)
        return True, 'key %s %s keyboards=1' % (k, mode)
    if cmd == 'fp_control':
        sub = a[0] if a else 'state'
        if sub == 'take':
            s['fpchar'] = s['selected']
        if sub == 'state':
            c = s['chars'].get(s['fpchar'] or '', {})
            sr, ix = (c.get('id', '#0/0')[1:].split('/') + ['0'])[:2]
            return True, kfpreply.render('ctlstate', direct=1 if s['fpchar'] else 0, controlled='%x' % (0x1000 + int(sr)) if s['fpchar'] else 0,
                                         control_ids='0/0/0/%s/%s' % (sr, ix) if s['fpchar'] else '0/0/0/0/0', take_done=1 if s['fpchar'] else 0)
        return True, 'fp_control %s: char=%s fp=%d' % (sub, s['fpchar'] or '-', 1 if s['fpchar'] else 0)
    if cmd == 'fp_keys':
        sub = a[0] if a else 'state'
        if sub == 'press':
            ms = int(a[2]) if len(a) > 2 and a[2].isdigit() else 80
            return True, press(s, a[1] if len(a) > 1 else '', ms, now)
        if sub == 'release':
            out = [release(s, b, now) for b in ([a[1]] if len(a) > 1 else ['lmb', 'rmb'])]
            return True, '; '.join(out)
        if sub == 'set' and len(a) >= 3:
            s['sets'][a[1]] = a[2]
            st = ' '.join('%s=%s' % kv for kv in s['sets'].items())
            return True, "set %s=%s %s fb_tech='%s' blk_dir=0 blk_org=1" % (a[1], a[2], st, s['sets'].get('blk_allow', 'st'))
        if sub == 'ctl':
            return True, kfpreply.render('ctl', target='none', src='none', last='none', via='none', native_target='none')
        if sub == 'pick' and len(a) > 1 and a[1] == 'show':
            return True, kfpreply.render('pick', n=s.get('picks', 0), result=s.get('pick', 'none'))
        if sub == 'pick':
            s['picks'] = s.get('picks', 0) + 1
            # crosshair = the nearest standing non-squad character within 3 m of the FP character (a pinned row target)
            me = s['chars'].get(s.get('fpchar') or '')
            near = sorted((flat(me, c), k) for k, c in s["chars"].items()
                          if k not in s["squad"] and not c.get("ko") and flat(me, c) <= 30) if me else []
            s['pick_t'] = near[0][1] if near else None
            s['pick'] = uname(s['chars'][s['pick_t']]['name']) if near else 'terrain'
            return True, 'pick requested'
        if sub == 'sneak' and len(a) > 1 and a[1] == 'show':
            t = crosshair(s)
            me = s['chars'].get(s.get('fpchar') or '') or {}
            aw = sneak_aware(s, t, now) if t else -1
            h = is_enemy(s, t) if t else -1
            sk = s.setdefault('sk', {})
            sk['n'] = sk.get('n', 0) + 1
            if t and aw == 1:
                t['seen_once'] = 1
            return True, 'sneak n=%d stealth=%d target=%s target_aware=%d aware_any=%d ko_chance=%.3f hostile=%d enemy_tp=%d ' \
                         'enemy_pt=%d' % (sk['n'], me.get('sneak', 0), uname(t['name']) if t else 'none', aw,
                                          (1 if t.get('seen_once') else 0) if t else -1, (0.0 if aw else 158.0) if t else -1.0,
                                          h, (1 if h == 1 and aw == 1 else 0) if t else -1, h)
        if sub == 'sneak':
            return True, 'sneak probe requested'
        return True, fpkeys_state(s)
    if cmd == 'fp_melee':
        return fp_melee_cmd(s, a, now)
    if cmd == 'fp_mode':
        if not a or a[0].lower() not in ('on', 'off'):
            return False, 'usage: fp_mode on|off'
        want = 1 if a[0].lower() == 'on' else 0
        if want == s.get('fpmode', 0):
            return True, 'FP mode already ON' if want else 'FP mode already OFF'
        s['fpmode'] = want
        return True, 'FP mode toggling ON (next frame; log [input] FP mode toggled)' if want else 'FP mode toggling OFF (next frame)'
    if cmd == 'dialog':   # harness `dialog [close]` (COMMANDS.md): the open conversation window
        d = dlg_open(s, now)
        if a[:1] == ['close']:
            if not d:
                return True, 'no dialogue open'
            d['closed'] = 1
            return True, 'dialogue with %s ended' % d['speaker']
        if not d:
            return True, 'open=0 visible=0 in_dialogue=0 speaker= player= ended=1'
        return True, 'open=1 visible=1 in_dialogue=1 speaker=%s player=%s ended=0' % (d['speaker'], d.get('player', 'Shay'))
    if cmd == 'fp_state':
        if len(a) > 1 and a[0] == 'free':   # Alt free-cursor toggle (fp-playtest PT21/PT01 look mode)
            s['fp_free'] = 1 if a[1] == 'on' else 0
            return True, 'free=%d' % s['fp_free']
        # look mode: FP on + no free cursor = cursor hidden (fp-playtest setup checks cursor_hidden=1)
        dl = dlg_open(s, now)
        return True, kfpreply.render('fpstate', fp_mode=s.get('fpmode', 0), control=1 if s['fpchar'] else 0,
                                     controlled=1 if s['fpchar'] else 0, ui_why='panels' if dl else 'none',
                                     ui_open=1 if dl else 0, panels=('0x%03x' % 0x020) if dl else '0x000', active=s.get('fpmode', 0),
                                     cursor_hidden=1 if s.get('fpmode', 0) and not s.get('fp_free', 0) else 0,
                                     free=s.get('fp_free', 0))
    if cmd == 'detecttime' and len(a) >= 2:   # sneak on, sighting reset, answers when (if) the observer sees him
        me, ob = char(s, a[0]), char(s, a[1])
        if not me or not ob:
            return False, 'no character %s' % (a[0] if not me else a[1])
        if not me.get('sneak'):
            me['sneak'], me['sneak_t'] = 1, now
        seen = sneak_aware(s, ob, now) if me['name'] == s.get('fpchar') else 0
        return True, 'seen=%d seconds_to_seen=%s seconds_to_maybe=-1 max_progress=0.00 dist=15.0 los=%.1f ' \
                     'observer_perception_mult=1.00' % (seen, '0.0' if seen else '-1', 1.0 if seen else 0.0)
    if cmd == 'crime' and a:
        if not char(s, a[0]):
            return False, 'no character %s' % a[0]
        return True, '%s committing_crime=none against=none crime_expiry=-1.0 total_bounty=0 stolen_items=0 hunters=0' % a[0]
    if cmd == 'spawn':   # Commands.cpp spawn <template> <faction> [near <npc> | at x y z] [count n] [dist m] ...
        tpl, fac = a[0], a[1]
        at = list(s['chars'][s['selected']]['pos'])
        if 'near' in a:
            o = char(s, a[a.index('near') + 1])
            if not o:
                return False, 'no character %s' % a[a.index('near') + 1]
            at = list(o['pos'])
        n = int(a[a.index('count') + 1]) if 'count' in a else 1
        d = float(a[a.index('dist') + 1]) if 'dist' in a else 0.0
        made = []
        for _ in range(n):
            sr = 100 + 2 * len([k for k in s['chars'] if '#' in k])
            key = '%s#%d' % (tpl, sr)
            s['chars'][key] = dict(id='#%d/%d' % (sr, sr + 1), fac=fac, pos=[at[0] + d, at[1], at[2]], items=[], eq=[],
                                   ko=0, ranged=None, name=tpl)
            sh = s.get('spawn_hostile', [])
            if '*' in sh or tpl in sh or fac in sh:
                s['chars'][key]['enemy'] = 1
            made.append('%s #%d/%d race=Greenlander' % (tpl, sr, sr + 1))
        return True, 'spawned %d/%d %s: %s' % (n, n, tpl, ', '.join(made))
    if cmd == 'fp_combat' and a:
        r = fp_combat_melee(s, a, now)
        if r is not None:
            return r
    if cmd == 'fp_combat':
        sub = a[0] if a else 'state'
        if sub == 'state':
            rng = fp['drawn'] and not fp['melee']
            # melee-in-hands fixture (rg03 R10/HIT): a melee weapon in the hands = the ranged adapter stands down
            why = 'melee_in_hands' if fp['drawn'] and fp['melee'] and fp.get('weapon') not in (None, 'fists') else 'ok'
            return True, kfpreply.render('combat', enabled=s.get('combat_on', 1), native_ready=1, armed=1 if rng else 0,
                                         aimed=1 if fp['ui_state'] == 'aiming' else 0, anim_ready=1 if rng else 0,
                                         shot_ready=1 if fp['ui_state'] == 'aiming' and fp['loaded'] else 0, ammo=fp['loaded'],
                                         reloading=1 if fp['ui_state'] == 'reloading' else 0, actual_shots=s.get('shots', 0),
                                         auto_reload=s.get('autoreload', 1), why=why, fp_ui_state=fp['ui_state'],
                                         has_ammo=1, loaded=fp['loaded'], loaded_max=1)
        if sub == 'aim':
            return True, 'aim victim=00a1 (target=00a1) dist=12'
        return True, 'fp_combat %s ok' % ' '.join(a)
    if cmd == 'fp_tables':   # KenshiFP live animation tables (pending-fixes/kfp-live-tables.py, kfp_tables.inc reply format)
        sub = a[0] if a else 'state'
        t = s.setdefault('tables', dict(hash='efc48644', file='-', changed=0, loaded=0))
        head = ''
        if sub in ('load', 'reload'):
            f = a[1] if len(a) > 1 else t['file']
            if f == '-':
                return False, 'fp_tables reload: no file (give a path)'
            import zlib
            t.update(file=f, hash=s.get('tables_dumps', {}).get(f) or '%08x' % zlib.crc32(f.encode()), changed=1, loaded=1)
            head = 'tables loaded file=%s lines=1 bad=0 ' % f
        elif sub == 'reset':
            t.update(hash='efc48644', changed=0, last_set={})
            head = 'reset to compiled values '
        elif sub == 'set' and len(a) > 3:
            import zlib
            t.update(hash='%08x' % zlib.crc32((t['hash'] + ' '.join(a)).encode()), changed=t['changed'] + 1)
            t.setdefault('last_set', {})[a[1] + ' ' + a[2]] = ' '.join(a[3:])
            head = 'set %s[0..0] ' % a[1]
        elif sub == 'dump' and len(a) > 1:
            head = 'dump %s rows=189 which=all ' % a[1]
            s.setdefault('tables_dumps', {})[a[1]] = t['hash']   # a later load of this dump restores its hash (dump == state)
            fp = re.sub(r'^([A-Za-z]):/', lambda m: '/mnt/%s/' % m.group(1).lower(), a[1].replace('\\', '/'))
            try:
                with open(fp, 'w') as fo:
                    fo.write('# KenshiFP fp_tables all hash=%s (dryrun stub)\npose.m_ready = 0 0 0\n' % t['hash'])
            except OSError:
                pass
        elif sub == 'get' and len(a) > 1:
            head = '%s[0] %s | ' % (a[1], t.get('last_set', {}).get(a[1] + ' ' + (a[2] if len(a) > 2 else ''), '0'))
        elif sub not in ('state', 'list', 'get'):
            return False, 'usage: fp_tables state|list|reload [file]|load <file>|set <table> <key> <v..>|get <table> [key]|dump <file> [diff|defaults]|reset'
        s['tables'] = t
        return True, head + 'tables hash=%s default=%d changed=%d file=%s loaded=%d lines=%d bad=0' % (
            t['hash'], 0 if t['changed'] else 1, t['changed'], t['file'], t['loaded'], t['loaded'])
    if cmd == 'fp_vm':
        sub = a[0] if a else 'state'
        if sub == 'rec' and len(a) > 1:
            if a[1] == 'on':
                s['rec'] = dict(on=1, t=now, sw0=s.get('vm_swings', 0), k0=s.get('vm_kicks', 0))
            elif a[1] == 'off':
                s['rec']['on'] = 0
            elif a[1] == 'dump' and len(a) > 2:
                n = int((now - s['rec'].get('t', now)) * 60)
                p = os.path.join(dr.KDIR, a[2])
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, 'w') as f:
                    # swings/kicks recorded: the canned lab tools (pyshim) answer per weapon like the real ones
                    f.write('# dryrun canned vm rec frames=%d swings=%d kicks=%d\n' % (
                        n, s.get('vm_swings', 0) - s['rec'].get('sw0', 0), s.get('vm_kicks', 0) - s['rec'].get('k0', 0)))
                    # one ready frame whose weapon point follows the live tables (fp-pose-sweep POSESWEEP-TABLES "pose moved")
                    th = s.get('tables', {}).get('hash', 'efc48644')
                    dy = 0.0 if th == 'efc48644' else 0.1 + int(th[:2], 16) / 255.0
                    f.write('0 0.0 0.0167 ready 0 | 2.4509,%.4f,4.9990 | - | 0,0,0 0,0,0\n' % (-0.2021 - dy))
                dr.jappend('recordings.jsonl', dict(kind='vmrec', t=now, file=a[2], frames=n))
                if n == 0:
                    dr.flag('NOTE', 'fp_vm rec dump %s with 0 frames (rec on never sent?)' % a[2])
                return True, 'rec dump %s frames=%d' % (a[2], n)
            return True, 'rec on=%d frames=%d' % (s['rec']['on'], int((now - s['rec'].get('t', now)) * 60) if s['rec']['on'] else 0)
        if sub == 'fist':   # real kfp_viewmodel.inc `fp_vm fist` format (NA1 fields + kfp-fist-native nat/frz/natL/natR/clamp)
            fs = s.setdefault('fist', dict(force=-1, swings=0, ikfail=0, nat=0))
            on = 1 if fp['drawn'] and fp.get('weapon') == 'fists' else 0
            sw = fp['ui_state'] == 'swinging'
            tn = ['badpunch', 'ma chudan', 'ma 2strike', 'shoteiL'][max(fs['force'], 0) % 4]
            d = 1.5 if sw else 0.0   # native wrist moves during a technique (dm, view space)
            r = "fist ua=1 force=%d on=%d fists=%d wih=%d tech='%s' table=%s fallback=0 u=%.3f swings=%d n=4 w=1.00 zf=0.00 state=%s " % (
                fs['force'], on, on, 0 if fp.get('weapon') in (None, 'fists') else 1,
                tn if sw else '-', tn.split()[0] if sw else 'guard',   # real: tech='-' table=guard between techniques,
                0.9 if sw else 0.0, fs['swings'], fp['ui_state'])
            r += ('tL=-1.60,-1.00,3.80 tR=1.60,-1.00,3.80 wrL=-1.60,%.2f,3.80 wrR=1.60,%.2f,%.2f '
                  'elL=-2.50,-2.50,2.50 elR=2.50,-2.50,2.50 ikfail=%d') % (-1.0 + d * 0.3, -1.0 + d * 0.3, 3.8 + d, fs['ikfail'])
            if fs.get('nat'):
                r += ' nat=1 frz=%d natL=-1.60,%.2f,3.80 natR=1.60,%.2f,%.2f clamp=0' % (1 if sw else 0, -1.0 + d * 0.3, -1.0 + d * 0.3, 3.8 + d)
            return True, r
        if sub == 'set' and len(a) > 2 and a[1] == 'fist_native':   # kfp-fist-native build
            s.setdefault('fist', dict(force=-1, swings=0, ikfail=0))['nat'] = 1 if float(a[2]) else 0
            return True, 'fp_vm set fist_native=%s' % a[2]
        if sub == 'set' and len(a) > 3 and a[1] == 'hand_scale':   # pending-fixes/kfp-hand-scale.py build
            return True, 'hand_scale along=%.3f across=%.3f' % (float(a[2]), float(a[3]))
        if sub == 'set' and len(a) > 2 and a[1] in ('stroke', 'strokes'):   # E6 (kfp_viewmodel.inc vm_set_logged)
            x = int(float(a[2]))
            if a[1] == 'stroke' and -1 <= x < 4:
                s['vm_force'] = x
            elif a[1] == 'strokes' and 0 <= x < 16:
                s['vm_strokes'] = x; s['vm_next'] = 0
            return True, 'fp_vm %s ok' % ' '.join(a)
        if sub == 'set' and len(a) > 2 and a[1] == 'fist_tech':
            s.setdefault('fist', dict(force=-1, swings=0, ikfail=0))['force'] = int(float(a[2]))
            return True, 'fp_vm set fist_tech=%s' % a[2]
        if sub == 'set' and len(a) > 2 and a[1] in ('sw_pose', 'kick_pose'):
            s[a[1]] = float(a[2])
            return True, 'fp_vm %s ok' % ' '.join(a)
        if sub == 'state':
            cls = 'melee' if fp['melee'] or not fp['drawn'] else 'ranged'
            st = fp['vm'] if s.get('sw_pose', -1) < 0 else 'ready'
            if st == 'aiming' and s.get('kick_pose', -1) >= 0.5:
                st = 'aiming-kick'   # frozen kick peak (PT28 fire)
            real = vm_pose(cls, st)
            if real and fp['drawn']:
                # a real KenshiFP reply for this weapon class + state (PT13/14/26/27/28 judge these numbers); live counters
                # (swings, kicks, frames, zoom, fire hold) from the fake game
                for k, v in (('on', s.get('vm_on', 1)), ('state', fp['vm']), ('swings', s.get('vm_swings', 0)),
                             ('kicks', s.get('vm_kicks', 0)), ('frames', int(now * 60) % 100000),
                             ('zoom', '%.2f' % s['cam']['dist']), ('fire', '0.00')):
                    real = re.sub(r' %s=\S*' % k, ' %s=%s' % (k, v), real, count=1)
                return True, real
            return True, kfpreply.render('vm', on=s.get('vm_on', 1), hooked=1, state=fp['vm'], w='1.00' if fp['drawn'] else '0.00',
                                         **{'class': 'melee' if fp['melee'] or not fp['drawn'] else 'ranged'}, melee=fp['melee'],
                                         swings=s.get('vm_swings', 0), kicks=s.get('vm_kicks', 0), frames=int(now * 60) % 100000, zoom='%.2f' % s['cam']['dist'],
                                         wb='12.0')
        return True, 'fp_vm %s ok' % ' '.join(a)
    if cmd == 'fp_camera':
        sub = a[0] if a else 'state'
        if sub in ('distance', 'orbit') and len(a) > 1:
            s['cam']['dist' if sub == 'distance' else 'orbit'] = float(a[1])
        if sub == 'look' and len(a) > 2:
            s['cam']['yaw'], s['cam']['pitch'] = float(a[1]), float(a[2])
        if sub == 'zoommode' and len(a) > 1:
            s['zoom_switch'] = 1 if a[1] == 'switch' else 0
        if sub == 'bandhide' and len(a) > 1:
            s['bandhide'] = int(float(a[1]))
        if sub == 'look' and s['turret']['on']:
            pass
        if sub == 'state':
            me = s['chars'].get(s['fpchar'] or s['selected'], {}).get('pos', [0, 0, 0])
            d = s['cam']['dist']
            return True, kfpreply.render('cam', view_max='40.0', direct=1 if s['fpchar'] else 0, zoom=1 if d > 0 else 0,
                                         target='%.3f' % d, applied='%.3f' % d, actual_distance='%.3f' % d, actual_valid=1, eye=1,
                                         speed_scale='1.000', yaw='%.6f' % s['cam']['yaw'], pitch='%.6f' % s['cam']['pitch'], world_valid=1,
                                         camera_x='%.6f' % me[0], camera_y='%.6f' % (me[1] + 19), camera_z='%.6f' % me[2],
                                         body_yaw='%.6f' % s['cam']['yaw'], body_yaw_valid=1, band_hidden=s['bandhide'] if d > 0 else 0,
                                         zoom_switch=s['zoom_switch'], anchor_x='%.3f' % me[0], anchor_y='%.3f' % (me[1] + 19),
                                         anchor_z='%.3f' % me[2])
        return True, 'fp_camera %s ok' % ' '.join(a)
    tu = s['turret']
    if cmd == 'order' and len(a) > 1 and a[1].upper() == 'USE_TURRET':
        js = os.environ.get('DR_FIXTURE_JSON')
        if js and os.path.exists(js) and json.load(open(js)).get('noseat'):   # fixtures/noseat.json: the order never seats
            return True, 'order %s USE_TURRET ok' % a[0]
        tu['on'] = 1; tu['enters'] += 1
        sched(s, now + 1.0, 'turret', hud_text='loaded' if tu['ammo'] else 'reloading', ui_state='turret', vm='holstered')
        return True, 'order %s USE_TURRET ok' % a[0]
    if cmd == 'power' and len(a) > 1:
        if a[1] in ('off', 'unsupply', 'drain'):
            tu['power'] = 0
            if tu['on']:
                sched(s, now + 0.05, 'turret', hud_text='no power')
        elif a[1] in ('on', 'supply', 'charge'):
            tu['power'] = 1
            if tu['on']:
                sched(s, now + 0.05, 'turret', hud_text='loaded' if tu['ammo'] else 'reloading')
        return True, 'power %s %s has_power=%d' % (a[0], a[1], tu['power'])
    if cmd == 'turret':
        return True, '%s loaded=%d reloading=%d on_turret=%d has_power=%d aim_target=Tassilo aim_err_deg=0.4 fired=%d ranged=YES' % (
            a[0] if a else 'turret', tu['ammo'], 0 if tu['ammo'] else 1, tu['on'], tu['power'], tu['shots'])
    if cmd == 'fp_turret':
        return True, 'on=%d why=- ammo=%d/1 reload_left=0 reload_max=6 rl_state=0 aim_valid=1 aim=1 aim_err_deg=0.4 shots=%d refused=0 enters=%d leaves=%d' % (
            tu['on'], tu['ammo'], tu['shots'], tu['enters'], tu['leaves'])
    if cmd == 'fp_combat' and a and a[0] == 'aim':
        return True, 'aim victim=00a1 (target=00a1) dist=12'
    if cmd == 'fp_move' and a and a[0] not in ('none', 'state') and tu['on']:
        tu['on'] = 0; tu['leaves'] += 1
        sched(s, now + 0.6, 'turret', hud_text='holstered', ui_state='holstered', vm='holstered', drawn=0)
        return True, 'fp_move %s' % a[0]
    if cmd == 'fp_gear':   # kfp fp_gear: worn-item map, one '|' entry per slot ('hands' = the drawn weapon's own entity)
        h = (' | hands type=107 mesh=0000000305beeca0 vis=1 vf=4 ours=0 node=-100.43,660.83,98.16 hand=0.00 parts=3 partsVis=3'
             if fp['drawn'] else '')
        return True, 'app=0000000262c5a290 pc=0000000262c59460 near=1 headHidden=1 ourHid=1' + h +             ' | head type=3 mesh=00000002ad1b38d0 vis=0 vf=0 ours=1 node=-97.62,646.07,93.75 hand=12.64 parts=0 partsVis=0'
    if cmd in ('fp_state', 'fp_melee', 'fp_turret', 'fp_gear', 'fp_mode', 'fp_move', 'fp_combat_probe'):
        return True, '%s fp=%d drawn=%d ui_state=%s' % (cmd, 1 if s['fpchar'] else 0, fp['drawn'], fp['ui_state'])
    if cmd == 'messages':
        return True, 'messages: 0'
    if cmd == 'help':
        return True, ' '.join(sorted(sp))
    if cmd == 'run':
        dr.flag('NOTE', 'scenario file run %s not emulated' % (a[0] if a else ''))
        return True, '== 0 passed, 0 failed (dryrun: scenario not emulated)'
    dr.flag('NOTE', 'command %s answered generically' % cmd)
    return True, '%s ok (dryrun)' % cmd


def main(argv):
    # kah.py options before the command: --dir <harness dir>
    while argv and argv[0].startswith('--'):
        argv = argv[2:] if argv[0] in ('--dir',) else argv[1:]
    if not argv:
        print('kah dryrun stub')
        return 0
    cmd, a = argv[0], argv[1:]
    sp = spec()
    # the call's latency is a virtual WAIT, not a global clock jump: a background call (take_mark's `sync_flash &`) used
    # to push every other process 0.3 s ahead, so the foreground press landed 0.6-0.7 s after its label (ctl-blk claim
    # FAILs, 2026-10-10); concurrent calls overlap like requests answered in the same harness poll
    dr.vwait(LAT)
    with dr.Lock():
        s = load_state()
        now = dr.vnow()
        settle(s, now)
        bad = None
        if sp and cmd not in sp and cmd != 'fp_tables':   # fp_tables: pending kfp-live-tables (stub below) until it is in the base
            bad = 'unknown command "%s" (not in harness COMMANDS.md/src, KenshiFP or Stobe registerCommand)' % cmd
        elif cmd in sp:
            d = sp[cmd]
            if len(a) < d['minargs']:
                bad = '%s: %d argument(s), needs %d (%s)' % (cmd, len(a), d['minargs'], d['usage'][:80])
            elif d['subs'] and a and a[0] not in d['subs']:
                bad = '%s: unknown first argument "%s" (known: %s)' % (cmd, a[0], ','.join(sorted(d['subs'])))
        if not bad and any(x == '' for x in a):
            bad = '%s: empty argument (unset variable?) in: %s' % (cmd, ' '.join(repr(x) for x in a))
        if bad:
            dr.flag('FAIL', bad)
            ok, rep = False, bad
        else:
            try:
                ok, rep = handle(s, cmd, a, now, sp)
            except (IndexError, ValueError) as e:
                dr.flag('FAIL', '%s %s: bad arguments (%s)' % (cmd, ' '.join(a), e))
                ok, rep = False, 'bad arguments'
        settle(s, now)
        save_state(s)
    dr.log('harness', '%s %s -> %s%s' % (cmd, ' '.join(a), '' if ok else 'ERROR ', rep[:120]))
    # the real kah.py prints the harness reply with its trailing \r (harness writes CRLF, kah.py strips only \n):
    # op-b5 fist1 died on "ikfail=0\r" in $(( )); scripts must strip it (tr -d '\r') where they compute with a field
    print(('' if ok else 'ERROR: ') + rep + '\r')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
