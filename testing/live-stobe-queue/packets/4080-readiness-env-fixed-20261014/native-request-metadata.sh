export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
python3 - <<'PY'
from pathlib import Path
import re,json
p=Path('C:/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log')
with p.open('rb') as src:
    src.seek(0,2);size=src.tell();src.seek(max(0,size-500000));lines=src.read().decode('utf-8','replace').splitlines()
markers=('BORED_EVENT','LOAD_SYNC','TEST_INBOX: say','REACTION_TURN','CHAT_SEND_STAGE','RECHAT: dispatched')
items=[]
for line in lines:
    kind=next((m for m in markers if m in line),None)
    if not kind:continue
    timestamp=re.search(r'\[([^\]\r\n]{1,40})\]',line)
    # Emit event class/time and counters only, no user text, headers or request payload.
    items.append({'kind':kind,'time':timestamp.group(1) if timestamp else 'unparsed'})
print(json.dumps({'file_bytes':size,'recent_event_metadata':items[-12:]},separators=(',',':')))
PY
