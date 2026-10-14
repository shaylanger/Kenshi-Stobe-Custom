export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
MSYS2_ENV_CONV_EXCL='KENSHI_DIR;KDIR' python3 - <<'PY'
import os,json
print(json.dumps({key:os.environ.get(key) for key in ('RIG','KAH_INSTANCE','KENSHI_DIR','KDIR','KAH_DIR')},separators=(',',':')))
assert os.environ.get('KENSHI_DIR')=='/c/KenshiInst/3'
assert os.environ.get('KAH_DIR')==r'C:\KenshiInst\3\mods\AutomationHarness'
print('RESULT MSYS-ROUTE-ENV PASS isolated_route_preserved_in_windows_python')
PY
