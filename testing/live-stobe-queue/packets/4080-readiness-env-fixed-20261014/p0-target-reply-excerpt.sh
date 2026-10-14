export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
python3 - <<'PY'
from pathlib import Path
import json,re
root=Path('C:/KenshiTestRuns/stobe-validation/4080-p0-current-driver-20261014-20261014-114029-951/run')
text=(root/'proposal.native.delta.log').read_text(encoding='utf-8',errors='replace')
speech=[];actions=[];completion=[]
for line in text.splitlines():
    m=re.search(r'NPC_SAY:\s*([^|:]+)\|(\d+):\s*(.*)',line)
    if m and int(m.group(2))==2529907200:
        speech.append({'name':m.group(1),'serial':int(m.group(2)),'text':m.group(3)[:1800]})
    if 'ACTION_EXEC' in line or 'TRAVEL_LOCATION' in line or 'TRAVEL_TICK' in line:
        actions.append(line[:1000])
    if re.search(r'CHAT_THREAD:\s*Queued\s+\d+\s+streamed chat lines',line):completion.append(line[:300])
print(json.dumps({'case':str(root),'target_speech':speech,'native_actions':actions[:12],'response_complete':completion},separators=(',',':')))
PY
