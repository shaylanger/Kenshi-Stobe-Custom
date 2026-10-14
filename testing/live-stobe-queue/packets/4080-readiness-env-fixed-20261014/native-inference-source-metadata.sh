export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
python3 - <<'PY'
from pathlib import Path
import re,json,collections
p=Path('C:/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log')
with p.open('rb') as src:
    src.seek(0,2);size=src.tell();src.seek(max(0,size-20000000));lines=src.read().decode('utf-8','replace').splitlines()
rows=[];counts=collections.Counter()
for line in lines:
    matches=re.findall(r'\b([A-Z][A-Z0-9_]{2,40}):',line)
    kind=next((x for x in matches if any(k in x for k in ('HTTP','CHAT','BIO','PROFILE','BORED','LOAD','AUTONOMY','REACTION','RECHAT'))),None)
    if not kind:continue
    counts[kind]+=1
    if not any(k in line.lower() for k in ('dispatch','request','queued','response','complete','started','finish','error','fail','say id=')):continue
    # Strict time/ID patterns only; no raw log text, utterance, headers, environment or payload.
    stamp=re.search(r'\b(?:20\d{2}-\d{2}-\d{2}[ T])?\d{2}:\d{2}:\d{2}(?:\.\d+)?\b',line)
    ids=re.findall(r'\b(?:req_[0-9a-f]+|k\d{13}_[0-9]+_[0-9]+)\b',line)
    rows.append({'kind':kind,'time':stamp.group(0) if stamp else 'unparsed','ids':ids[:3]})
print(json.dumps({'file_bytes':size,'scanned_bytes':min(size,20000000),'counts':dict(counts),'latest_dispatch_metadata':rows[-24:]},separators=(',',':')))
PY
