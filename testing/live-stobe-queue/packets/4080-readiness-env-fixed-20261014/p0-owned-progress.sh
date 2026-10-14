export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
python3 - <<'PY'
from pathlib import Path
import json,re,time
from urllib.request import urlopen
base=Path('C:/KenshiTestRuns/stobe-validation')
roots=[p for p in base.glob('4080-p0-current-driver-20261014-*') if p.is_dir()]
assert roots
root=max(roots,key=lambda p:p.stat().st_mtime)
run=root/'run'
files=[{'name':p.name,'bytes':p.stat().st_size,'age_s':round(time.time()-p.stat().st_mtime,1)} for p in run.iterdir() if p.is_file()] if run.is_dir() else []
delta=run/'proposal.native.delta.log'
text=delta.read_text(encoding='utf-8',errors='replace') if delta.is_file() else ''
markers={key:len(re.findall(pattern,text)) for key,pattern in {'npc_say':r'NPC_SAY','response_complete':r'CHAT_THREAD: Queued \d+ streamed chat lines','action_exec':r'ACTION_EXEC','http_received':r'CHAT_THREAD:.*(?:HTTP|response)'}.items()}
with urlopen('http://127.0.0.1:18095/slots',timeout=2) as resp:
    slots=json.loads(resp.read(200000))
safe=[{key:s.get(key) for key in ('id','is_processing','n_prompt_tokens') if type(s.get(key)) in (int,bool)} for s in slots if isinstance(s,dict)]
print(json.dumps({'utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'parent':str(root),'run_exists':run.is_dir(),'proposal_handler_receipt_exists':(run/'proposal.send.txt').is_file(),'files':files,'native_marker_counts':markers,'slots':safe},separators=(',',':')))
PY
