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
    f = fixture(save)
    s = dict(save=save, chars=f['chars'], squad=f['squad'], hour=f['hour'], hour_vt=dr.vnow(), speed=1.0, paused=0,
             selected=f['squad'][0], fpchar=None, chatter='on', cursor=[800, 450], cam=dict(dist=0, orbit=0, yaw=0, pitch=0),
             fp=dict(drawn=0, melee=0, loaded=1, ui_state='holstered', hud_text='holstered', vm='holstered'),
             tl=[], hist=[], rec=dict(on=0, t=0), keys={}, sets={}, zoom_switch=1, bandhide=1,
             turret=dict(on=0, ammo=1, power=1, shots=0, enters=0, leaves=0), fight=int(f.get('fight', 0)),
             iso=0 if os.environ.get('RIG') == '4080' or os.environ.get('DRYRUN_ISO') == 'off' else 1)
    # iso: 5090 kenshi-ctl launch turns input isolation on; the 4080 C:\KAH\ctl.ps1 launch does not (b4080c setup FAIL)
    t = dr.vnow()
    for k, v in s['fp'].items():
        s['hist'].append([t - 3600, k, v])
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
        s['hour'] = (s['hour'] + (now - s['hour_vt']) * s['speed'] / 120.0) % 24
    s['hour_vt'] = now


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


def world(s, now=None):
    """what a camera would show right now (bug-replay fixtures: dryrun/fixtures/*.json): game hour + night, hostile NPCs
    (not squad, not Nameless, not KO) within 30 m of the FP / selected character, the popup a fight near the spot puts on
    screen ("<name> is attacking!", fixture "fight": 1). Read by fakeexe (recordings), pyshim (sampler, frames.py)."""
    h = s.get('hour', 11.0)
    if now is not None and s.get('speed', 1) >= 2 and not s.get('paused'):
        h = (h + (now - s.get('hour_vt', now)) * s['speed'] / 120.0) % 24
    me = s['chars'].get(s.get('fpchar') or s.get('selected'), {}).get('pos')
    host, near = [], []
    for n, c in s['chars'].items():
        if me is None or n in s['squad'] or c.get('fac') == 'Nameless' or c.get('ko'):
            continue
        d = sum((c['pos'][i] - me[i]) ** 2 for i in range(3)) ** 0.5
        if d < 3000:
            host.append(n)
        if d < 2000:
            near.append(n)
    return dict(hour=round(h, 2), night=h < 6.5 or h >= 18.5, hostiles=host, near=near,
                popup=('%s is attacking!' % host[0]) if host and s.get('fight') else None)


def sched(s, t, tag, **kv):
    for k, v in kv.items():
        s['tl'].append([t, k, v, tag])


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
    rng = [w for w in c['eq'] if RANGED.search(w)]
    mel = [w for w in c['eq'] if not RANGED.search(w) and not re.search(r'(?i)hat|armour|shirt|boots|pants', w)]
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
            sched(s, now + 0.8, 'r', drawn=1, melee=melee, ui_state='ready', hud_text='ready', vm='ready', weapon=w)
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
            sched(s, now + 0.1, 'rmb', ui_state='blocking', vm='block', hud_text='block')
            sched(s, end + 0.15, 'rmb', ui_state='ready', vm='ready', hud_text='ready')
            if busy:
                kfplog(now + 0.1, "E4 free swing cut by block")
            kfplog(now + 0.1, "free block start tech=0 anim='st' live=1")
        else:
            t = now + 0.1
            if not fp['loaded']:
                sched(s, t, 'rmb', ui_state='reloading', hud_text='reloading', vm='reload')
                t += 2.0
                sched(s, t, 'rmb', loaded=1, hud_text='loaded')
            if t < end:
                sched(s, t + 0.05, 'rmb', ui_state='aiming', vm='aim', hud_text='aiming')
            sched(s, max(end, t) + 0.1, 'rmb', ui_state='ready', vm='ready', hud_text='ready')
    elif btn == 'lmb':
        if fp['melee'] and fp.get('weapon') == 'fists':
            fs = s.setdefault('fist', dict(force=-1, swings=0, ikfail=0))
            fs['swings'] += 1
            tn = ['badpunch', 'ma chudan', 'ma 2strike', 'shoteiL'][max(fs['force'], 0) % 4]
            kfplog(now + 0.05, "[vm] fist swing tech='%s' table=%s fallback=0" % (tn, tn.split()[0]))
        if fp['melee']:
            sched(s, now + 0.05, 'lmb', ui_state='swinging', vm='swing')
            sched(s, now + 1.1, 'lmb', ui_state='ready', vm='ready')
            kfplog(now + 0.05, "free swing start live=1")
            # KenshiFP: native free swing counted (fp_keys free_swings) + viewmodel swing lines (kfp_viewmodel.inc)
            s['free_swings'] = s.get('free_swings', 0) + 1
            n = s['vm_swings'] = s.get('vm_swings', 0) + 1
            kfplog(now + 0.05, '[vm] swing #%d stroke 0 (mask 0x1 force -1)' % n)
            kfplog(now + 1.1, '[vm] swing #%d 1.05s u_end=1.00 prog=1.00 frames=63 maxstep=4.0 rate_max=300 rate_med=150 '
                              'ratio=2.00 elev=-10.0..20.0 az=-30.0..40.0' % n)
        elif fp['ui_state'] == 'aiming' and fp['loaded']:
            sched(s, now + 0.05, 'lmb', loaded=0, hud_text='reload')
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
    return ' '.join('%s=%s' % (k, v.get(k, '-' if k.endswith(('_why', '_path', '_target', '_result', '_where', '_hist', 'last_select', 'last_target')) else 0))
                    for k in FPKEYS_FIELDS)


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
        h = s['hour']
        return True, 'day=12 time=%02d:%02d speed=%g' % (int(h), int((h % 1) * 60), s['speed'])
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
        if cmd == 'pin' and 'at' in a:
            i = a.index('at')
            xyz = a[i + 1:i + 4]
            if len(xyz) == 3 and all(re.match(r'^-?[\d.]+$', v) for v in xyz):
                c['pos'] = [float(v) for v in xyz]
        if cmd == 'ko':
            c['ko'] = 1
        if cmd == 'wake':
            c['ko'] = 0
        if cmd == 'kill':
            c['ko'] = 2
        return True, '%s %s ok' % (cmd, c['name'])
    if cmd == 'sync_flash':   # harness d2a9ff2: full-frame marker for label sync (take-sample.sh take_mark)
        ms = int(a[0]) if a and a[0].isdigit() else 120
        n = int(a[1]) if len(a) > 1 and a[1].isdigit() else 0
        dr.log('sync', 'flash n=%d ms=%d' % (n, ms))
        return True, 'sync_flash n=%d ms=%d view=1600x900' % (n, ms)
    if cmd == 'rangedinfo':
        c = need_char(0)
        if not c:
            return False, 'no character %s' % (a[0] if a else '')
        bows = [w for w in c['eq'] if RANGED.search(w)]
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
            if not re.search(r'(?i)hat|helmet|armour|shirt|boots|pants|coat', i):
                d['weapon_model'] = i.lower().replace(' ', '_')
            its.append(d)
        return True, '%s items=%d %s' % (line(c), len(its), json.dumps(its, separators=(',', ':')))
    if cmd in ('equip', 'unequip', 'iteminfo'):
        c = need_char(0)
        if not c or len(a) < 2:
            return False, 'no character'
        it = item_name(' '.join(a[1:]))
        if it not in c['items']:
            return False, 'no item %s on %s' % (it, c['name'])
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
            return True, 'unequipped (%s -> main) %s' % ('back' if RANGED.search(it) else 'hip', desc_item(s, it))
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
        if cmd == 'pickup' and re.search(r'(?i)hat|helmet|armour|shirt|boots', it) and it not in c['eq']:
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
            return True, 'pick requested'
        return True, fpkeys_state(s)
    if cmd == 'fp_combat':
        sub = a[0] if a else 'state'
        if sub == 'state':
            rng = fp['drawn'] and not fp['melee']
            return True, kfpreply.render('combat', enabled=s.get('combat_on', 1), native_ready=1, armed=1 if rng else 0,
                                         aimed=1 if fp['ui_state'] == 'aiming' else 0, anim_ready=1 if rng else 0,
                                         shot_ready=1 if fp['ui_state'] == 'aiming' and fp['loaded'] else 0, ammo=1,
                                         reloading=1 if fp['ui_state'] == 'reloading' else 0, actual_shots=s.get('shots', 0),
                                         auto_reload=s.get('autoreload', 1), why='ok', fp_ui_state=fp['ui_state'],
                                         has_ammo=1, loaded=fp['loaded'], loaded_max=1)
        if sub == 'aim':
            return True, 'aim victim=00a1 (target=00a1) dist=12'
        return True, 'fp_combat %s ok' % ' '.join(a)
    if cmd == 'fp_vm':
        sub = a[0] if a else 'state'
        if sub == 'rec' and len(a) > 1:
            if a[1] == 'on':
                s['rec'] = dict(on=1, t=now)
            elif a[1] == 'off':
                s['rec']['on'] = 0
            elif a[1] == 'dump' and len(a) > 2:
                n = int((now - s['rec'].get('t', now)) * 60)
                p = os.path.join(dr.KDIR, a[2])
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, 'w') as f:
                    f.write('# dryrun canned vm rec frames=%d\n' % n)
                dr.jappend('recordings.jsonl', dict(kind='vmrec', t=now, file=a[2], frames=n))
                if n == 0:
                    dr.flag('NOTE', 'fp_vm rec dump %s with 0 frames (rec on never sent?)' % a[2])
                return True, 'rec dump %s frames=%d' % (a[2], n)
            return True, 'rec on=%d frames=%d' % (s['rec']['on'], int((now - s['rec'].get('t', now)) * 60) if s['rec']['on'] else 0)
        if sub == 'fist':   # NA1 fists build (pending-fixes/kfp-fists-na1.py)
            fs = s.setdefault('fist', dict(force=-1, swings=0, ikfail=0))
            on = 1 if fp['drawn'] and fp.get('weapon') == 'fists' else 0
            return True, 'fist ua=1 on=%d fists=%d wih=%d force=%d tech=%d swings=%d ikfail=%d u=%.2f' % (
                on, on, 0 if fp.get('weapon') in (None, 'fists') else 1, fs['force'], max(fs['force'], 0), fs['swings'],
                fs['ikfail'], 0.9 if fp['ui_state'] == 'swinging' else 0.0)
        if sub == 'set' and len(a) > 3 and a[1] == 'hand_scale':   # pending-fixes/kfp-hand-scale.py build
            return True, 'hand_scale along=%.3f across=%.3f' % (float(a[2]), float(a[3]))
        if sub == 'set' and len(a) > 2 and a[1] == 'fist_tech':
            s.setdefault('fist', dict(force=-1, swings=0, ikfail=0))['force'] = int(float(a[2]))
            return True, 'fp_vm set fist_tech=%s' % a[2]
        if sub == 'state':
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
    dr.advance(LAT)
    with dr.Lock():
        s = load_state()
        now = dr.vnow()
        settle(s, now)
        bad = None
        if sp and cmd not in sp:
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
