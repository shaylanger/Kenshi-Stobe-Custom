#!/bin/bash
# lane-llm-apply-4080.sh: write the ONE per-rig LLM config (C:\KAH\lane-llm.json) into each isolated lane's private DB
# (core_llm_connector, ALL rows, like config.php did for the 4080 lane i3 and the 5090 lane's rows 1-12).
# Runs inside the rig's WSL distro as root (the lanes' Postgres clusters are in /tmp there). Nothing here touches the live DB
# (/var/www/html/StobeServer, db "stobe"): lanes come only from lane-defs.<rig>.json, each db name must contain "test".
#
#   lane-llm-apply-4080.sh [--check] <lane|all> [--defs <lane-defs.json>] [--llm <lane-llm.json>]
#     apply : UPDATE every core_llm_connector row of the lane (base_url, model, api_key, max_tokens, connector_type,
#             is_default=(id=1), api_badge_id=NULL) + setting HTTP_TIMEOUT; prints one line per lane with the row count.
#     --check: read-only; prints "RESULT lane-llm <lane> PASS|FAIL <why>" and exits 1 if any lane differs from the file.
#   Switch to DeepInfra later (key never printed, never on a command line):
#     1. write C:\KAH\lane-llm.json  {"base_url":"https://api.deepinfra.com/v1/openai","model":"deepseek-ai/DeepSeek-V4.1-Flash",
#        "key_file":"C:\\KAH\\lane-llm.key", ...}   (exact model id/URL as Shay gives them)
#     2. drop the key into key_file (one line)
#     3. run:  lane-llm-apply-4080.sh i3 ; lane-llm-apply-4080.sh i4   (or: all). PHP re-reads connectors per request, no restart.
#   lane-llm.json fields: base_url (may contain {bridge_port} = the lane's local bridge port), model, key_file (optional Windows
#   path; missing/empty = api_key "local-test-no-auth"), connector_type (default openrouterjson), max_tokens (default 1024),
#   http_timeout (seconds, default 600), provider (free text label).
# Wrapper from Windows/5090: tools\automation\lane-llm-apply.ps1 -Rig 4080  (the 5090 lanes use lane-llm-apply.sh with its own registry)
set -eu
mode=apply; lane=; defs=/mnt/c/KenshiTestRuns/lane-i4/lane-defs.4080.json; llm=/mnt/c/KAH/lane-llm.json
while [ $# -gt 0 ]; do case "$1" in
  --check) mode=check;; --defs) defs=$2; shift;; --llm) llm=$2; shift;; *) lane=$1;; esac; shift; done
[ -n "$lane" ] || { sed -n 2,19p "$0"; exit 2; }
[ -f "$defs" ] || { echo "no defs file $defs"; exit 2; }
[ -f "$llm" ] || { echo "no LLM config $llm (write it first, see header)"; exit 2; }

lanes=$lane
[ "$lane" = all ] && lanes=$(python3 -c "import json,sys;print(' '.join(json.load(open(sys.argv[1]))['lanes']))" "$defs")
rc=0
for L in $lanes; do
  # shell vars for the lane + the desired connector values (the key is read inside python, only its sha256 is compared)
  eval "$(python3 - "$defs" "$llm" "$L" <<'PY'
import json,sys,os,hashlib,shlex
defs=json.load(open(sys.argv[1])); cfg=json.load(open(sys.argv[2])); L=sys.argv[3]
lane=defs['lanes'][L]
def win2wsl(p):
    p=p.replace('\\','/')
    return '/mnt/'+p[0].lower()+p[2:] if len(p)>2 and p[1]==':' else p
key='local-test-no-auth'
kf=cfg.get('key_file') or ''
if kf and os.path.isfile(win2wsl(kf)):
    k=open(win2wsl(kf),encoding='utf-8-sig').read().strip()
    if k: key=k
out={
 'ROOT':lane['backend_root'],'PGPORT_':str(lane['pg_port']),'DB':lane['db'],
 'URL':cfg['base_url'].replace('{bridge_port}',str(lane['bridge_port'])),
 'MODEL':cfg['model'],'CTYPE':cfg.get('connector_type','openrouterjson'),
 'MAXTOK':str(int(cfg.get('max_tokens',1024))),'HTTPTO':str(int(cfg.get('http_timeout',600))),
 'KEYSHA':hashlib.sha256(key.encode()).hexdigest(),'HASKEY':'1' if key!='local-test-no-auth' else '0',
}
for k2,v in out.items(): print('%s=%s'%(k2,shlex.quote(v)))
open('/tmp/.lane-llm-key.%s'%L,'w').write(key)  # mode fixed below; deleted right after use
os.chmod('/tmp/.lane-llm-key.%s'%L,0o600)
PY
)"
  trap 'rm -f /tmp/.lane-llm-key.'"$L" EXIT
  case "$DB" in *test*) ;; *) echo "RESULT lane-llm $L FAIL refusing db '$DB' (not a test db)"; rc=1; continue;; esac
  [ "$DB" != stobe ] || { echo "refusing live db"; exit 3; }
  P="runuser -u postgres -- psql -h $ROOT/socket -p $PGPORT_ -d $DB -At -v ON_ERROR_STOP=1"
  if [ "$mode" = check ]; then
    rows=$($P -c "select count(*) from core_llm_connector" 2>&1) || { echo "RESULT lane-llm $L FAIL db unreachable: $(echo "$rows"|head -1)"; rc=1; continue; }
    bad=$($P -c "select count(*) from core_llm_connector where base_url<>'$URL' or model<>'$MODEL' or connector_type<>'$CTYPE' or max_tokens<>$MAXTOK or encode(sha256(convert_to(api_key,'UTF8')),'hex')<>'$KEYSHA'")
    dflt=$($P -c "select string_agg(id::text,',') from core_llm_connector where is_default")
    if [ "$bad" = 0 ] && [ "$dflt" = 1 ]; then echo "RESULT lane-llm $L PASS rows=$rows base_url=$URL model=$MODEL key=$([ $HASKEY = 1 ] && echo set || echo local-no-auth)"
    else echo "RESULT lane-llm $L FAIL rows=$rows differing=$bad default_ids=$dflt want base_url=$URL model=$MODEL"; rc=1; fi
  else
    # SQL (with the key) goes over stdin only; never on a command line
    {
      python3 - "$URL" "$MODEL" "$CTYPE" "$MAXTOK" "$L" <<'PY'
import sys
url,model,ctype,maxtok,L=sys.argv[1:6]
q=lambda s:"'"+s.replace("'","''")+"'"
key=open('/tmp/.lane-llm-key.%s'%L).read()
print("UPDATE core_llm_connector SET base_url=%s,model=%s,api_key=%s,api_badge_id=NULL,max_tokens=%s,connector_type=%s,is_default=(id=1);"%(q(url),q(model),q(key),maxtok,q(ctype)))
PY
    } | $P -f - >/dev/null
    rm -f /tmp/.lane-llm-key.$L
    # HTTP_TIMEOUT lives in the lane's settings table via the app's own setter (same call config.php used)
    ( set +x; . "$ROOT/env.sh"; php -r "require '$ROOT/site/lib/bootstrap.php'; setSetting('HTTP_TIMEOUT','$HTTPTO','general','lane-llm-apply');" ) >/dev/null 2>&1 \
      && to=ok || to="FAILED(setSetting)"
    n=$($P -c "select count(*) from core_llm_connector")
    echo "lane-llm $L: $n connector rows -> base_url=$URL model=$MODEL key=$([ $HASKEY = 1 ] && echo set || echo local-no-auth) http_timeout=$HTTPTO($to)"
  fi
  rm -f /tmp/.lane-llm-key.$L
done
exit $rc
