export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
python3 - <<'PY'
import json
from urllib.request import urlopen
out=[]
for path in ('/health','/slots'):
    try:
        with urlopen('http://127.0.0.1:18095'+path,timeout=2) as response:
            obj=json.loads(response.read(200000));code=response.status
        records=obj if isinstance(obj,list) else obj.get('slots',[]) if isinstance(obj,dict) else []
        out.append({'route':'WINDOWS_LOOPBACK_18095','path':path,'http':code,'top_type':type(obj).__name__,'status':obj.get('status') if path=='/health' and isinstance(obj,dict) else None,'slots':[{'id':r.get('id'),'id_type':type(r.get('id')).__name__,'is_processing':r.get('is_processing')} for r in records if isinstance(r,dict)]})
    except Exception:
        out.append({'route':'WINDOWS_LOOPBACK_18095','path':path,'http':0,'result':'unavailable'})
print(json.dumps(out,separators=(',',':')))
PY
MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 - <<'PY'
import json
from urllib.request import urlopen
out=[]
for port in (18095,18096):
    try:
        with urlopen('http://127.0.0.1:'+str(port)+'/slots',timeout=2) as response:
            obj=json.loads(response.read(200000));code=response.status
        records=obj if isinstance(obj,list) else obj.get('slots',[]) if isinstance(obj,dict) else []
        out.append({'route':'WSL_LOOPBACK_'+str(port),'http':code,'top_type':type(obj).__name__,'slots':[{'id':r.get('id'),'id_type':type(r.get('id')).__name__,'is_processing':r.get('is_processing')} for r in records if isinstance(r,dict)]})
    except Exception:
        out.append({'route':'WSL_LOOPBACK_'+str(port),'http':0,'result':'unavailable'})
print(json.dumps(out,separators=(',',':')))
PY
