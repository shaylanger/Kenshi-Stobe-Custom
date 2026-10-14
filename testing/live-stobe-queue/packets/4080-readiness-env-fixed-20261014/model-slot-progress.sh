export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
python3 - <<'PY'
import json,time
from urllib.request import urlopen
for sample in range(3):
    with urlopen('http://127.0.0.1:18095/slots',timeout=2) as response:
        obj=json.loads(response.read(200000))
    assert isinstance(obj,list)
    out=[]
    for slot in obj:
        rec={key:slot.get(key) for key in ('id','is_processing','n_prompt_tokens','n_decoded','n_tokens','task_id') if type(slot.get(key)) in (int,bool)}
        timings=slot.get('timings',{})
        if isinstance(timings,dict):
            rec['timings']={key:timings.get(key) for key in ('prompt_n','predicted_n','prompt_ms','predicted_ms') if type(timings.get(key)) in (int,float)}
        out.append(rec)
    print(json.dumps({'utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'sample':sample,'slots':out},separators=(',',':')),flush=True)
    if sample<2:time.sleep(10)
PY
