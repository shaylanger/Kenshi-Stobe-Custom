#!/usr/bin/env bash
# llm-health.sh (PI-15): read-only health/balance check of the chat LLM provider the test lanes use.
# Sends ONE 1-token chat completion and prints exactly one line:
#   LLM-HEALTH OK <ms>
#   LLM-HEALTH FAIL http=<code> <first 120 chars of the body>      (e.g. http=402 {"detail":"You need positive balance ..."}; http=000 = no connection/timeout)
#   LLM-HEALTH SKIP <why>                                          (local/bridge model or no config: nothing to check, exit 0)
# Exit 0 = OK/SKIP, 1 = FAIL. The API key is read inside python from the key file named by the lane LLM config and is never printed
# or put on a command line.
# Config: $KAH_LLM_CONFIG, else C:\KenshiTestRuns\lane-llm.json (the file lane-llm-apply.sh writes into every lane DB), else C:\KAH\lane-llm.json
#   fields used: base_url, model, key_file (Windows or /mnt path).  Works in WSL and Git Bash (python3 required, no curl).
# Options/env: --no-cache (default: an OK result is reused for KAH_LLM_HEALTH_TTL=60 s via $KAH_LLM_CACHE_DIR/llm-health.cache; FAIL is never cached),
#   KAH_LLM_ALLOW_LOCAL=1 (selftest: also check a 127.0.0.1 base_url), KAH_LLM_TIMEOUT=20 (s), KAH_LLM_CACHE_DIR (default C:/KenshiTestRuns or /mnt/c/KenshiTestRuns).
cache=1; [ "${1:-}" = "--no-cache" ] && { cache=0; shift; }
exec python3 - "$cache" <<'PY'
import sys, os, json, time, urllib.request, urllib.error
use_cache = sys.argv[1] == '1'
BS = chr(92)
def p2(p):
    """Return the first existing variant of a Windows/WSL path."""
    if not p: return None
    q = p.replace(BS, '/')
    c = [p, q]
    if len(q) > 2 and q[1] == ':': c += ['/mnt/' + q[0].lower() + q[2:], '/' + q[0].lower() + q[2:]]
    for x in c:
        if os.path.exists(x): return x
    return None
def out(code, line):
    print(line); sys.exit(code)
cands = [os.environ.get('KAH_LLM_CONFIG'), 'C:/KenshiTestRuns/lane-llm.json', 'C:/KAH/lane-llm.json']
cfgp = next((p2(c) for c in cands if c and p2(c)), None)
if not cfgp: out(0, 'LLM-HEALTH SKIP no lane-llm.json found')
try: cfg = json.load(open(cfgp, encoding='utf-8-sig'))
except Exception as e: out(1, 'LLM-HEALTH FAIL http=000 cannot read config %s: %s' % (os.path.basename(cfgp), str(e)[:60]))
base = (cfg.get('base_url') or '').rstrip('/')
is_local = ('127.0.0.1' in base or 'localhost' in base) and not os.environ.get('KAH_LLM_ALLOW_LOCAL')
if not base or is_local or '{bridge_port}' in base or cfg.get('mode') == 'local':
    out(0, 'LLM-HEALTH SKIP local or empty base_url (%s)' % (base[:40] or 'none'))
key = 'local-test-no-auth'
kf = cfg.get('key_file') or ''
if kf:
    kp = p2(kf)
    if not kp: out(1, 'LLM-HEALTH FAIL http=000 key_file not found')
    key = open(kp, encoding='utf-8-sig').read().strip()
    if not key: out(1, 'LLM-HEALTH FAIL http=000 key_file empty')
cdir = p2(os.environ.get('KAH_LLM_CACHE_DIR') or '') or p2('C:/KenshiTestRuns') or '.'
cache = os.path.join(cdir, 'llm-health.cache')
ttl = int(os.environ.get('KAH_LLM_HEALTH_TTL', '60'))
if use_cache:
    try:
        if time.time() - os.path.getmtime(cache) < ttl:
            line = open(cache).read().strip()
            if line.startswith('LLM-HEALTH OK'): out(0, line + ' (cached)')
    except OSError: pass
body = json.dumps({'model': cfg.get('model') or '', 'max_tokens': 1, 'temperature': 0,
                   'messages': [{'role': 'user', 'content': 'hi'}]}).encode()
req = urllib.request.Request(base + '/chat/completions', data=body, method='POST',
      headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key, 'User-Agent': 'kah-llm-health/1'})
t0 = time.time(); code = 0; txt = ''
try:
    r = urllib.request.urlopen(req, timeout=float(os.environ.get('KAH_LLM_TIMEOUT', '20')))
    code = r.getcode(); txt = r.read(2000).decode('utf-8', 'replace')
except urllib.error.HTTPError as e:
    code = e.code
    try: txt = e.read(2000).decode('utf-8', 'replace')
    except Exception: txt = ''
except Exception as e:
    code = 0; txt = str(e)
ms = int((time.time() - t0) * 1000)
txt = txt.replace(key, '***') if key and len(key) > 8 else txt
if 200 <= code < 300:
    line = 'LLM-HEALTH OK %d' % ms
    try: open(cache, 'w').write(line + '\n')
    except OSError: pass
    out(0, line)
out(1, 'LLM-HEALTH FAIL http=%03d %s' % (code, ' '.join(txt.split())[:120]))
PY
