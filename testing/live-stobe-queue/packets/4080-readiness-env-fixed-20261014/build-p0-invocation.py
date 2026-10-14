from pathlib import Path
import base64,hashlib
folder=Path(__file__).resolve().parent
root=folder.parents[3]
driver=(root/'testing/live-stobe-queue/current-build-travel-driver/driver.py').read_bytes()
assert hashlib.sha256(driver).hexdigest().upper()=='46CFEEB2C1763F8E45634C64B1457553B70D55501E0F6C09AEDB3BD188C48C05'
preflight=(root/'testing/live-stobe-queue/4080-final-full-readiness-pass-20261014.receipt.md').read_bytes()+b'\n'+(root/'testing/live-stobe-queue/4080-stored-auth-ready-schema-20261014.receipt.md').read_bytes()
destination=(root/'testing/live-stobe-queue/4080-P0-destination-feasibility-20261014.receipt.md').read_bytes()
row='4080-p0-start-move-20261014-operator01'
unix='/c/KenshiTestRuns/stobe-validation/'+row
win='C:/KenshiTestRuns/stobe-validation/'+row
body="""export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\\KenshiInst\\3\\mods\\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
"""
body+=f"test ! -e '{unix}'\nmkdir -p '{unix}'\n"
body+=f"printf '%s' '{base64.b64encode(preflight).decode()}' | base64 -d > '{unix}/preflight.receipt.md'\n"
body+=f"printf '%s' '{base64.b64encode(destination).decode()}' | base64 -d > '{unix}/destination.receipt.md'\n"
body+=f"export NPC='Cind [Hungry Bandit]' TRAVEL_DESTINATION='The Hub'\nexport OUT='{win}' NATIVE_LOG='C:/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log'\nexport PREFLIGHT_RECEIPT='{win}/preflight.receipt.md' DESTINATION_RECEIPT='{win}/destination.receipt.md'\nexport ROW_ID='P0-TRAVEL-START-MOVE-4080-001'\nexport TRAVEL_DRIVER_BASH='C:/Program Files/Git/bin/bash.exe'\nexport WAIT_SECONDS=300 POLL_SECONDS=5\n"
body+=f"printf '%s' '{base64.b64encode(driver).decode()}' | base64 -d | python3 -\n"
(folder/'p0-start-move-invocation.sh').write_text(body,encoding='utf-8',newline='\n')
print('Packaged exact reviewed driver46CF + actual readiness/feasibility receipts. DO NOT EXECUTE until model owner releases hold and fresh actor/destination readiness refreshed.')
