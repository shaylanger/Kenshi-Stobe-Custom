#!/usr/bin/env bash
# llm-health-selftest.sh: offline selftest for llm-health.sh (PI-15). Fake local HTTP server (402 / 200 / hang), temp config + key file.
# Prints PASS/FAIL per case and `RESULT llm-health-selftest PASS|FAIL n/m`. Never calls the real provider.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); command -v cygpath >/dev/null 2>&1 && T=$(cygpath -m "$T")  # Windows python needs a C:/ path
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
cat > "$T/srv.py" <<'PY'
import http.server, sys, time
mode = {'v': 200}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); self.rfile.read(n)
        auth = self.headers.get('Authorization', '')
        m = open(sys.argv[2]).read().strip()
        if m == 'hang': time.sleep(5); return
        if m == '402' or auth != 'Bearer FAKEKEY-123456789':
            code, b = (402 if m == '402' else 401), b'{"detail":"You need positive balance to run this model"}'
        else: code, b = 200, b'{"choices":[{"message":{"content":"h"}}]}'
        self.send_response(code); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
PORT=$((20000 + RANDOM % 20000))
echo 200 > "$T/mode"; python3 "$T/srv.py" $PORT "$T/mode" & SRV=$!
for i in 1 2 3 4 5 6 7 8 9 10; do python3 -c "import socket;socket.create_connection(('127.0.0.1',$PORT),1)" 2>/dev/null && break; sleep 0.5; done
printf 'FAKEKEY-123456789' > "$T/key"
mkcfg() { printf '{"base_url":"%s","model":"m","key_file":"%s"}' "$1" "$2" > "$T/cfg.json"; }
pass=0; tot=0
chk() {  # chk <name> <want-rc> <want-regex> <got-rc> <got-out>
  tot=$((tot+1)); if [ "$4" = "$2" ] && echo "$5" | grep -Eq "$3"; then pass=$((pass+1)); echo "PASS $1: $5"; else echo "FAIL $1: rc=$4 out=$5"; fi; }
run() { KAH_LLM_ALLOW_LOCAL=${ALLOW-1} KAH_LLM_CONFIG="$T/cfg.json" KAH_LLM_CACHE_DIR="$T" KAH_LLM_TIMEOUT=${TMO:-3} bash "$HERE/llm-health.sh" "$@" 2>&1; }
URL="http://127.0.0.1:$PORT/v1"
mkcfg "$URL" "$T/key"
o=$(run --no-cache); chk ok-200 0 '^LLM-HEALTH OK [0-9]+$' $? "$o"
echo 402 > "$T/mode"; o=$(run); chk ok-cached-within-ttl 0 '^LLM-HEALTH OK [0-9]+ \(cached\)$' $? "$o"
o=$(run --no-cache); chk fail-402 1 '^LLM-HEALTH FAIL http=402 .*positive balance' $? "$o"
rm -f "$T/llm-health.cache"; o=$(run); chk fail-402-nocache-file 1 '^LLM-HEALTH FAIL http=402' $? "$o"
echo 200 > "$T/mode"; printf 'WRONGKEY' > "$T/key2"; mkcfg "$URL" "$T/key2"; o=$(run --no-cache); chk fail-401-wrong-key 1 '^LLM-HEALTH FAIL http=401' $? "$o"
case "$o" in *WRONGKEY*|*FAKEKEY*) tot=$((tot+1)); echo "FAIL key-leak: $o";; *) tot=$((tot+1)); pass=$((pass+1)); echo "PASS no-key-in-output";; esac
mkcfg "$URL" "$T/key"; run --no-cache >/dev/null; o=$(run); chk cache-reuse 0 '^LLM-HEALTH OK [0-9]+ \(cached\)$' $? "$o"
echo hang > "$T/mode"; rm -f "$T/llm-health.cache"; TMO=1 o=$(TMO=1 run --no-cache); chk fail-timeout 1 '^LLM-HEALTH FAIL http=000' $? "$o"
mkcfg "http://127.0.0.1:1/v1" "$T/key"; o=$(ALLOW= run --no-cache); chk skip-local-base 0 '^LLM-HEALTH SKIP local' $? "$o"
mkcfg "http://example.invalid/v1" "$T/nokey"; o=$(run --no-cache); chk fail-missing-keyfile 1 '^LLM-HEALTH FAIL http=000 key_file not found' $? "$o"
[ "$pass" = "$tot" ] && echo "RESULT llm-health-selftest PASS $pass/$tot" || echo "RESULT llm-health-selftest FAIL $pass/$tot"
[ "$pass" = "$tot" ]
