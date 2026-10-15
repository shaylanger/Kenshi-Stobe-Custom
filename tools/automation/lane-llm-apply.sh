#!/usr/bin/env bash
# lane-llm-apply.sh [--check] <lane|all>     (WSL root; 5090 imm26 lanes; the 4080 uses lane-llm-apply.ps1 -Rig 4080)
# ONE per-rig LLM file C:\KenshiTestRuns\lane-llm.json drives every lane DB:
#   { "mode":"local|deepinfra", "base_url":"http://127.0.0.1:{bridge_port}/v1", "model":"qwen4b", "key_file":"",
#     "connector_type":"", "max_tokens":1024, "local_api_key":"local-test-no-auth" }
#   {bridge_port} is replaced per lane (registry C:\KenshiTestRuns\lanes\lanes-5090.json). mode=local: api_key = local_api_key;
#   mode=deepinfra: api_key is read from key_file (a Windows or /mnt path; the file content is never printed, only a 6-char sha256 fingerprint).
#   connector_type "" keeps the row's type (local = openrouterjson); for DeepInfra set the type the server expects (openaijson, base_url https://api.deepinfra.com/v1/openai).
# Rewrites EVERY row of core_llm_connector in the lane DB (the lane DB has ids 1-12), api_badge_id=NULL, is_default only id 1.
# Switching later = put the key in key_file, edit lane-llm.json (mode/base_url/model/connector_type), run this per lane.
# --check: no write; prints per-lane MATCH/MISMATCH, exit 1 on a mismatch.
set -euo pipefail
args=(); for a in "$@"; do [ -n "$a" ] && args+=("$a"); done; set -- "${args[@]+"${args[@]}"}"
chk=0; [ "${1:-}" = "--check" ] && { chk=1; shift; }
lane=${1:-all}
exec python3 - "$chk" "$lane" <<'PY'
import json, sys, subprocess, hashlib, re
chk = sys.argv[1] == '1'; want = sys.argv[2]
reg = json.load(open('/mnt/c/KenshiTestRuns/lanes/lanes-5090.json', encoding='utf-8-sig'))
cfg = json.load(open('/mnt/c/KenshiTestRuns/lane-llm.json', encoding='utf-8-sig'))
def wsl_path(p):
    m = re.match(r'^([A-Za-z]):[\\/](.*)$', p)
    return '/mnt/%s/%s' % (m.group(1).lower(), m.group(2).replace('\\', '/')) if m else p
mode = cfg.get('mode', 'local')
if mode == 'local':
    key = cfg.get('local_api_key', 'local-test-no-auth')
else:
    kf = cfg.get('key_file', '')
    if not kf: print('FAIL mode=%s but key_file is empty' % mode); sys.exit(2)
    key = open(wsl_path(kf)).read().strip()
    if not key: print('FAIL key_file empty'); sys.exit(2)
fp = hashlib.sha256(key.encode()).hexdigest()[:6]
q = lambda s: "'" + str(s).replace("'", "''") + "'"
bad = 0
for l in reg['lanes']:
    if want != 'all' and l['id'] != want: continue
    url = cfg['base_url'].replace('{bridge_port}', str(l['bridge_port']))
    psql = ['runuser', '-u', 'postgres', '--', 'psql', '-h', l['wsl_root'] + '/socket', '-p', str(l['pg_port']), '-d', l['db'], '-At', '-v', 'ON_ERROR_STOP=1']
    def run(sql):
        r = subprocess.run(psql, input=sql, capture_output=True, text=True)
        if r.returncode: print('FAIL lane %s psql: %s' % (l['id'], r.stderr.strip()[:200])); sys.exit(2)
        return r.stdout.strip()
    ct = cfg.get('connector_type', '')
    if chk:
        out = run("select count(*), count(*) filter (where base_url=%s and model=%s and api_key=%s and api_badge_id is null%s) from core_llm_connector;" %
                  (q(url), q(cfg['model']), q(key), (' and connector_type=%s' % q(ct)) if ct else ''))
        n, ok = [int(x) for x in out.split('|')]
        good = n > 0 and n == ok
        bad += 0 if good else 1
        print('lane %s %s rows=%d matching=%d mode=%s url=%s model=%s key_fp=%s' % (l['id'], 'MATCH' if good else 'MISMATCH', n, ok, mode, url, cfg['model'], fp))
    else:
        sql = ("UPDATE core_llm_connector SET base_url=%s, model=%s, api_key=%s, max_tokens=%d, api_badge_id=NULL, is_default=(id=1)%s;"
               % (q(url), q(cfg['model']), q(key), int(cfg.get('max_tokens', 1024)), (', connector_type=%s' % q(ct)) if ct else ''))
        run(sql)
        n = run("select count(*) from core_llm_connector;")
        print('lane %s APPLIED rows=%s mode=%s url=%s model=%s key_fp=%s' % (l['id'], n, mode, url, cfg['model'], fp))
sys.exit(1 if bad else 0)
PY
