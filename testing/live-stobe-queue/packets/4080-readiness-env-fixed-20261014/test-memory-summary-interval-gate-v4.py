import importlib.util
from pathlib import Path
import tempfile
import json
import subprocess

p=Path(__file__).with_name('memory-summary-interval-gate-v4.py')
spec=importlib.util.spec_from_file_location('gate_v2',p)
g=importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)

assert g.DB_HOST_PIN=='/tmp/stobe-standalone4080/socket'
assert g.DB_PORT_PIN=='15434' and g.DB_USER_PIN=='dwemer'
assert '127.0.0.1:18095' in g.POWERSHELL_PROBE and 'TimeoutSec 2' in g.POWERSHELL_PROBE
assert 'powershell.exe' in g.get_qwen_snapshot.__code__.co_consts[1]
assert 'pg_advisory_xact_lock(937463)' in g.PHP_TRANSACTION
assert "SET LOCAL statement_timeout TO '15000ms'" in g.PHP_TRANSACTION
assert "SET LOCAL statement_timeout TO '3000ms'" in g.PHP_TRANSACTION
assert g.PHP_TRANSACTION.count('pg_advisory_unlock')==1  # status probe only; CAS lock is transaction-scoped
lock_fail=g.PHP_TRANSACTION.index('if($lock===false)')
lock_rollback=g.PHP_TRANSACTION.index('ROLLBACK',lock_fail)
cas_update=g.PHP_TRANSACTION.index('UPDATE public.general_settings',lock_fail)
assert lock_fail < lock_rollback < cas_update
source_text=p.read_text(encoding='utf-8')
assert 'for attempt in range' not in source_text
assert 'timeout=75' in source_text and "'60s'" in source_text
assert 'start_new_session=True' in source_text and 'os.killpg(proc.pid, signal.SIGKILL)' in source_text
assert 'php_timeout_unknown_commit' in source_text and 'run_readonly_status_before_any_retry' in source_text
assert "summary_lock_timeout" in source_text
fixture=(g.POWERSHELL_SLOT_PARSE + r''' $one=Convert-Slots '[{"id":0,"is_processing":false}]'; $many=Convert-Slots '[{"id":0,"is_processing":false},{"id":1,"is_processing":false}]'; $object=Convert-Slots '{"slots":[{"id":0,"is_processing":false}]}'; [ordered]@{one=$one;many=$many;object=$object}|ConvertTo-Json -Compress -Depth 6''')
ps=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',fixture],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=8)
assert ps.returncode==0 and len(ps.stdout)<4096, 'local Windows PowerShell fixture failed'
parsed=json.loads(ps.stdout.strip())
assert parsed['one']['is_array'] is True and len(parsed['one']['records'])==1
assert parsed['one']['records'][0]['id']==0 and parsed['one']['records'][0]['is_processing'] is False
assert parsed['many']['is_array'] is True and len(parsed['many']['records'])==2
assert parsed['object']['is_array'] is False
busy_meta=g.qwen_metadata(200,{'status':'ok'},200,[{'id':0,'is_processing':True}])
assert busy_meta['qwen_idle'] is False and busy_meta['qwen_slot_id']==0
assert busy_meta['qwen_slot_processing'] is True and busy_meta['qwen_health_ok'] is True
unknown_meta=g.qwen_metadata(0,None,0,None)
assert unknown_meta['qwen_slot_count'] is None and unknown_meta['qwen_health_ok'] is False

env_base=("export STOBE_DB_HOST=/tmp/stobe-standalone4080/socket\n"
          "export STOBE_DB_PORT=15434\nexport STOBE_DB_NAME=stobe_standalone4080_test\n"
          "export STOBE_DB_USER=dwemer\nexport STOBE_DB_PASSWORD=opaque-test-value\n")
with tempfile.TemporaryDirectory() as d:
 envp=Path(d)/'env.sh';envp.write_text(env_base,encoding='utf-8')
 child,preserve=g.load_db_env(envp)
 assert preserve=='STOBE_DB_HOST,STOBE_DB_NAME,STOBE_DB_PASSWORD,STOBE_DB_PORT,STOBE_DB_USER'
 for invalid in [env_base.replace('15434','15435'),env_base.replace('/tmp/stobe-standalone4080/socket','/tmp/other/socket'),env_base.replace('dwemer','otheruser')]:
  envp.write_text(invalid,encoding='utf-8')
  try: g.load_db_env(envp)
  except ValueError: pass
  else: raise AssertionError('wrong DB connection tuple accepted')

base={'db_name':g.DB_PIN,'sources_ok':True,'qwen_idle':True,'lock_acquired':True,'mode':'pause','value':'6','updated_at':g.PAUSE_UPDATED_AT}
for name,patch,want in [
 ('pause',{},'cas_ready'),
 ('database_mismatch',{'db_name':'wrong'},'database_pin_mismatch'),
 ('source_mismatch',{'sources_ok':False},'source_pin_mismatch'),
 ('qwen_busy',{'qwen_idle':False},'cas_ready'),
 ('lock_busy',{'lock_acquired':False},'summary_lock_busy'),
 ('stale_row',{'updated_at':'2026-10-12 19:35:06.000000'},'cas_mismatch')]:
 args=dict(base);args.update(patch)
 assert g.gate_decision(**args)==want,(name,g.gate_decision(**args),want)

rollback=dict(base,mode='rollback',value='720',updated_at='2026-10-14 12:00:00.123456',expected_updated_at='2026-10-14 12:00:00.123456')
assert g.gate_decision(**rollback)=='cas_ready'
rollback['updated_at']='2026-10-14 12:00:01.123456'
assert g.gate_decision(**rollback)=='cas_mismatch'

assert g.qwen_slot_is_idle(200,{'status':'ok'},200,[{'id':0,'is_processing':False}])
for bad in [
 (503,{'status':'ok'},200,[{'id':0,'is_processing':False}]),
 (200,{'status':'degraded'},200,[{'id':0,'is_processing':False}]),
 (200,{'status':'ok'},200,[{'id':0,'is_processing':True}]),
 (200,{'status':'ok'},200,[{'id':0,'is_processing':False},{'id':1,'is_processing':False}]),
 (200,{'status':'ok'},200,[]),
 (200,{'status':'ok'},200,{'slots':[{'id':0,'is_processing':False}]}),
 (200,{'status':'ok'},200,[{'id':'0','is_processing':False}]),
 (200,{'status':'ok'},0,None)]:
 assert not g.qwen_slot_is_idle(*bad),bad

def fake_interop_error(*args,**kwargs):
 raise OSError('details must not escape')
assert g.get_qwen_snapshot(fake_interop_error)==(0,None,0,None)
class Timeout:
 def __call__(self,*args,**kwargs): raise __import__('subprocess').TimeoutExpired(args[0],7)
assert g.get_qwen_snapshot(Timeout())==(0,None,0,None)

assert g.hashes_match(g.SOURCE_PINS)
bad_hash=dict(g.SOURCE_PINS);bad_hash['lib/settings.php']='0'*64
assert not g.hashes_match(bad_hash)
print('PASS v4 mocks: PowerShell slot shapes, metadata, pinned DB tuple, one 15s queued CAS lock, bounded timeout, rollback')
