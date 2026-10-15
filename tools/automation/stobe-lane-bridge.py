"""4080 lane loopback bridge, no external endpoint: stobe-lane-bridge.py <listen_port> <upstream_port> <state_dir>
Parameterized copy of standalone4080-bridge.py (which hard-codes 18096 -> 18095 and the i3 state dir) so every lane has its
own listener, pid file and log. Forwards /health, /v1/models, /v1/chat/completions to the shared local model via Windows curl."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import subprocess,sys,json,time,threading,os
LISTEN=int(sys.argv[1]);UPSTREAM=int(sys.argv[2]);STATE=sys.argv[3]
class Handler(BaseHTTPRequestHandler):
 def forward(self):
  if self.path not in ('/health','/v1/models','/v1/chat/completions'):
   self.send_error(404);return
  count=int(self.headers.get('Content-Length','0'))
  if count>4000000:self.send_error(413);return
  body=self.rfile.read(count)
  try:stream=self.command=='POST' and json.loads(body).get('stream') is True
  except Exception:stream=False
  if stream:
   self.stream(body);return
  args=['/mnt/c/Windows/System32/curl.exe','-sS','--noproxy','*','--max-time','1200','-w','\n%{http_code}','-X',self.command,'-H','Content-Type: application/json']
  if self.command=='POST':args+=['--data-binary','@-']
  args+=['http://127.0.0.1:%d'%UPSTREAM+self.path]
  try:
   r=subprocess.run(args,input=body,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=1210)
   payload,_,code=r.stdout.rpartition(b'\n');status=int(code) if r.returncode==0 else 502
   if status>=400:print('LOCAL_TRANSPORT rc=%s http=%s stderr=%s'%(r.returncode,code.decode(errors='replace'),r.stderr.decode(errors='replace')[:400]),file=sys.stderr,flush=True)
  except Exception as exc:
   print('LOCAL_TRANSPORT exception=%s'%type(exc).__name__,file=sys.stderr,flush=True)
   payload=b'{"error":"local model transport unavailable"}';status=502
  self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
 do_GET=forward
 do_POST=forward
 def stream(self,body):
  started=time.monotonic()
  args=['/mnt/c/Windows/System32/curl.exe','-sS','--noproxy','*','--no-buffer','--include','--max-time','1200','-X','POST','-H','Content-Type: application/json','--data-binary','@-','http://127.0.0.1:%d/v1/chat/completions'%UPSTREAM]
  proc=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  watchdog=threading.Timer(1210,proc.kill);watchdog.start()
  first=True
  try:
   proc.stdin.write(body);proc.stdin.close()
   headers=[]
   while True:
    line=proc.stdout.readline()
    if not line:raise RuntimeError('no model HTTP header')
    headers.append(line)
    if line in (b'\r\n',b'\n'):
     status=int(headers[0].split()[1])
     if status==100:headers=[];continue
     break
   contenttype='text/event-stream'
   for h in headers:
    if h.lower().startswith(b'content-type:'):contenttype=h.split(b':',1)[1].strip().decode()
   self.send_response(status);self.send_header('Content-Type',contenttype);self.send_header('Connection','close');self.end_headers();self.close_connection=True
   print('STREAM_HEADERS http=%s elapsed=%.3f'%(status,time.monotonic()-started),file=sys.stderr,flush=True)
   while True:
    chunk=proc.stdout.read1(4096)
    if not chunk:break
    if first:
     print('STREAM_FIRST_BYTES elapsed=%.3f'%(time.monotonic()-started),file=sys.stderr,flush=True);first=False
    self.wfile.write(chunk);self.wfile.flush()
   rc=proc.wait(timeout=5)
   print('STREAM_END rc=%s elapsed=%.3f'%(rc,time.monotonic()-started),file=sys.stderr,flush=True)
   if rc:print('STREAM_ERROR '+proc.stderr.read(400).decode(errors='replace'),file=sys.stderr,flush=True)
  except (BrokenPipeError,ConnectionResetError):
   print('STREAM_CLIENT_DISCONNECTED elapsed=%.3f'%(time.monotonic()-started),file=sys.stderr,flush=True)
   proc.kill()
  except Exception as exc:
   print('STREAM_TRANSPORT exception=%s stderr=%s'%(type(exc).__name__,proc.stderr.read(400).decode(errors='replace') if proc.poll() is not None else 'process pending'),file=sys.stderr,flush=True)
   proc.kill()
  finally:
   watchdog.cancel()
   for pipe in (proc.stdout,proc.stderr):pipe.close()
Path(STATE+'/bridge.pid').write_text(str(os.getpid()))
sys.stderr=open(STATE+'/bridge-current.log','a',buffering=1)
ThreadingHTTPServer(('127.0.0.1',LISTEN),Handler).serve_forever()
