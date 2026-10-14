import importlib.util
from pathlib import Path
p=Path(__file__).with_name('memory-summary-interval-gate.py')
spec=importlib.util.spec_from_file_location('gate',p)
g=importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
base={'db_name':g.DB_PIN,'sources_ok':True,'qwen_idle':True,'lock_acquired':True,'mode':'pause','value':'6','updated_at':g.PAUSE_UPDATED_AT}
checks=[
 ('normal_pause',{},'cas_ready'),
 ('database_pin',{'db_name':'wrong'},'database_pin_mismatch'),
 ('source_hash',{'sources_ok':False},'source_pin_mismatch'),
 ('qwen_slot_busy',{'qwen_idle':False},'qwen_not_idle'),
 ('advisory_lock_busy',{'lock_acquired':False},'summary_lock_busy'),
 ('stale_config_row',{'updated_at':'2026-10-12 19:35:06.000000'},'cas_mismatch'),
]
assert g.hashes_match(g.SOURCE_PINS)
altered=dict(g.SOURCE_PINS);altered['lib/settings.php']='0'*64
assert not g.hashes_match(altered)
for name,patch,want in checks:
 args=dict(base);args.update(patch);got=g.gate_decision(**args)
 assert got==want,(name,got,want)
rollback=dict(base,mode='rollback',value='720',updated_at='2026-10-14 12:00:00.123456',expected_updated_at='2026-10-14 12:00:00.123456')
assert g.gate_decision(**rollback)=='cas_ready'
rollback['updated_at']='2026-10-14 12:00:01.123456'
assert g.gate_decision(**rollback)=='cas_mismatch'
assert g.qwen_slot_is_idle(200,{'status':'ok'},200,{'slots':[{'id':0,'is_processing':False}]})
for bad in [
 (503,{'status':'ok'},200,{'slots':[{'id':0,'is_processing':False}]}),
 (200,{'status':'degraded'},200,{'slots':[{'id':0,'is_processing':False}]}),
 (200,{'status':'ok'},200,{'slots':[{'id':0,'is_processing':True}]}),
 (200,{'status':'ok'},200,{'slots':[{'id':0,'is_processing':False},{'id':1,'is_processing':False}]}),
 (200,{'status':'ok'},200,{'slots':[]}),
]: assert not g.qwen_slot_is_idle(*bad)
print('PASS 16 local mocks: DB/source pins, health/slot gate, lock busy, CAS mismatch, pause, rollback timestamp')
