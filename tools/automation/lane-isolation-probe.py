#!/usr/bin/env python3
"""lane-isolation-probe.py <registry.json> : WSL-side facts for lane-isolation-check.ps1 (5090). Read-only; prints one JSON object.
Per lane: listeners on its ports (127.0.0.1 only?) with owning pid + cmdline, php/pg/bridge/manager processes whose cmdline names the
lane's private root, env.sh content (key line redacted), activity key sha256[:8], site/log realpath, cross-talk counts
(other lanes' ports / DB names / save names / roots found in this lane's logs)."""
import json, sys, subprocess, re, os, hashlib

reg = json.load(open(sys.argv[1], encoding='utf-8-sig'))

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

def wpath(p):
    m = re.match(r'^([A-Za-z]):[\\/](.*)$', p)
    return '/mnt/%s/%s' % (m.group(1).lower(), m.group(2).replace('\\', '/')) if m else p

ps = []
for line in sh('ps -eo pid=,args=').splitlines():
    m = re.match(r'\s*(\d+)\s+(.*)$', line)
    if m: ps.append((int(m.group(1)), m.group(2)))
ss = {}
for line in sh('ss -ltnpH').splitlines():
    f = line.split()
    if len(f) < 5: continue
    addr = f[3]; port = int(addr.rsplit(':', 1)[1]); host = addr.rsplit(':', 1)[0]
    pm = re.search(r'pid=(\d+)', line)
    ss.setdefault(port, []).append({'host': host, 'pid': int(pm.group(1)) if pm else 0})
cmd_of = dict(ps)

out = {'lanes': {}}
for l in reg['lanes']:
    root = l['wsl_root']; pre = root + '/'
    procs = [{'pid': p, 'cmd': c[:300]} for p, c in ps if pre in c or ('lane-bridge.py %d ' % l['bridge_port']) in c or ('-p %d' % l['pg_port']) in c and 'postgres' in c]
    ports = {}
    for name in ('backend_port', 'bridge_port'):
        port = l[name]
        ports[name] = [{'host': e['host'], 'pid': e['pid'], 'cmd': cmd_of.get(e['pid'], '')[:200]} for e in ss.get(port, [])]
    d = {'procs': procs, 'ports': ports}
    env = ''
    try: env = open(l['env_file']).read()
    except Exception as e: d['env_err'] = str(e)
    d['env'] = re.sub(r'(SECRET=)\S+', r'\1<redacted>', env)
    try: d['key_fp'] = hashlib.sha256(open(l['key_file'], 'rb').read()).hexdigest()[:8]
    except Exception as e: d['key_fp'] = None
    sl = os.path.join(root, 'site', 'log')
    d['site_log_real'] = os.path.realpath(sl) if os.path.exists(sl) else None
    d['site_real'] = os.path.realpath(os.path.join(root, 'site')) if os.path.exists(os.path.join(root, 'site')) else None
    d['root_exists'] = os.path.isdir(root)
    d['pg_socket_exists'] = os.path.exists(os.path.join(root, 'socket'))
    out['lanes'][l['id']] = d

# cross-talk: other lanes' identifiers inside this lane's logs
for l in reg['lanes']:
    logs = [wpath(l['stobe_log']), wpath(l['harness_log']), wpath(l['kfp_log']), l['wsl_root'] + '/php.log', l['wsl_root'] + '/manager.log', l['wsl_root'] + '/site/log/php_error.log']
    hits = {}
    for o in reg['lanes']:
        if o['id'] == l['id']: continue
        pats = ['127.0.0.1:%d' % o['backend_port'], 'localhost:%d' % o['backend_port'], '127.0.0.1:%d' % o['bridge_port'], o['db'], o['save_name'], o['wsl_root'] + '/', o['dir'], wpath(o['dir']) + '/']
        # a lane whose DB/root name is a prefix of ours (stobe_imm26_5090 vs stobe_imm26_5090_i4) would false-hit: match whole tokens
        n = 0; ex = []
        for lg in logs:
            if not os.path.exists(lg): continue
            for pat in pats:
                if pat == o['db']: rx = r'(?<![A-Za-z0-9_])' + re.escape(pat) + r'(?![A-Za-z0-9_])'
                elif pat == o['save_name']: rx = r'(?<![A-Za-z0-9_-])' + re.escape(pat) + r'(?![A-Za-z0-9_-])'
                elif pat.endswith('/'): rx = re.escape(pat)
                else: rx = re.escape(pat) + r'(?![0-9])'
                r = subprocess.run(['grep', '-a', '-c', '-E', '-m', '1', rx, lg], capture_output=True, text=True)
                c = int(r.stdout.strip() or 0)
                if c: n += 1; ex.append('%s in %s' % (pat, os.path.basename(lg)))
        hits[o['id']] = {'count': n, 'examples': ex[:3]}
    out['lanes'][l['id']]['crosstalk'] = hits
print(json.dumps(out))
