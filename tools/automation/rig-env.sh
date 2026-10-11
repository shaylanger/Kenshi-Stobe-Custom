# rig-env.sh: rig layer for take/test scripts, so one script runs unchanged on the 5090 (WSL) and the 4080 (Git Bash).
#   . rig-env.sh            (RIG=5090|4080 forced, else detected: WSL = 5090, Git Bash on host DESKTOP-NQQPA73 = 4080)
# Exports (scripts use them as ${VAR:-<5090 value>}, so they still run without this file on the 5090):
#   RIG        5090 | 4080
#   CR         POSIX root of drive C:  /mnt/c (5090) | /c (4080)   -> $CR/KenshiTestRuns, $CR/KenshiModding, $CR/Windows/Fonts
#   KDIR       Kenshi game dir (KenshiFP.log, harness shots, vmrec dumps)
#   FFX        ffmpeg.exe (winget Gyan.FFmpeg 8.0.1, same package path on both rigs); its dir is on PATH (frames.py/takecheck.py
#              call ffmpeg/ffprobe by name)
#   KAH_DIR    harness mod dir (Windows form, read by kah.py); KAH_CLIENT = kah.py dir in the form this rig's python reads
#   KAH_OWNER  game-lock owner for this rig (4080: rig4080) unless already set
#   RES_W RES_H  game render size the takes assume (both rigs: windowed 1600x900, see rig_cfg)
#   WIN_TITLE  game window title for ffmpeg gdigrab
# python3: on the 4080 C:\KAH\bin\python3 (shim to the Windows Python 3.13 with PIL) comes first on PATH. Windows python
# gets POSIX path ARGUMENTS converted by Git Bash; env vars are not converted, hence KAH_CLIENT in C:/ form there.
# Functions:
#   rig_launch <save>   start Kenshi with that save (5090: kenshi-ctl.ps1 launch; 4080: C:\KAH\ctl.ps1 launch, lock rig4080)
#   rig_stop            stop Kenshi (and keep the lock)
#   rig_bg <log> <cmd>  run <cmd> (one bash command line) detached; on the 4080 inside Shay's desktop session, hidden
#                       (C:\KAH\itrun.ps1): ffmpeg gdigrab needs the desktop, an ssh session has none
# 4080 one-time setup + sync of the files takes need: tools/automation/rig4080/setup.sh (run on the 5090).
_rig_detect() {
  if [ -n "$RIG" ]; then echo "$RIG"; return; fi
  if grep -qi microsoft /proc/version 2>/dev/null; then echo 5090; return; fi
  case "$(hostname 2>/dev/null)" in DESKTOP-NQQPA73) echo 4080;; *) echo 5090;; esac
}
export RIG=$(_rig_detect)
export WIN_TITLE="Kenshi 1.0.65 - x64 (Newland)" RES_W=1600 RES_H=900
# gfx-low games render smaller (kenshi-gfx.ps1 low: env KAH_VIDEO_MODE, e.g. lanes 5090b/5090c '800 x 600', else 1280 x 720;
# lane-5090c 2026-10-11: agreerec-i2 FAILed pf_rig "renders at 4096x2160 not 1600x900"): takes and pf_rig judge that size
if [[ "${KAH_VIDEO_MODE:-}" =~ ^([0-9]+)\ x\ ([0-9]+)$ ]]; then export RES_W=${BASH_REMATCH[1]} RES_H=${BASH_REMATCH[2]}
elif [ "${KAH_GFX:-}" = low ]; then export RES_W=1280 RES_H=720; fi
if [ "$RIG" = 4080 ]; then
  export CR=/c
  export KDIR="/c/Program Files (x86)/Steam/steamapps/common/Kenshi"
  export KAH_DIR='C:\Program Files (x86)\Steam\steamapps\common\Kenshi\mods\AutomationHarness'
  # multi-instance lane 4080b: KAH_INSTANCE=n >= 2 = the install copy C:\KenshiInst\<n> (kenshi-instance.ps1: own harness
  # inbox, logs, saves, lock game-<n>.lock); ctl.ps1 gets -Instance. Set unconditionally: itrun sources this file first.
  if [ "${KAH_INSTANCE:-1}" -ge 2 ] 2>/dev/null; then
    export KDIR=/c/KenshiInst/$KAH_INSTANCE KAH_DIR="C:\\KenshiInst\\$KAH_INSTANCE\\mods\\AutomationHarness"
  fi
  export KAH_CLIENT='C:/KenshiModding/Kenshi-Automation-Harness/client'
  export KAH_OWNER=${KAH_OWNER:-rig4080}
  export PATH="/c/KAH/bin:$PATH"
  # animlab catalogs/configs hold WSL game paths; the lab maps them here (visual/ogre.py hostpath)
  export ANIMLAB_PATHMAP='mnt/d/Steam=C:/Program Files (x86)/Steam'   # no leading / (Git Bash would rewrite it for Windows python)
  rig_launch() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KAH\ctl.ps1' launch -Save "$1" -Owner "$KAH_OWNER" -Instance "${KAH_INSTANCE:-1}"; }
  rig_stop() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KAH\ctl.ps1' stop -Owner "$KAH_OWNER" -Instance "${KAH_INSTANCE:-1}"; }
  rig_bg() { local log=$1; shift; powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KAH\itrun.ps1' -Log "$(cygpath -w "$log")" -Cmd "$*"; }
else
  export CR=/mnt/c
  # multi-instance (C:\KenshiTestRuns\multi-instance\PLAN.md): KAH_INSTANCE=n >= 2 = the install copy D:\KenshiInst\<n>
  # (its own harness inbox, logs, saves, lock game-<n>.lock); kenshi-ctl.ps1 gets it through WSLENV. Unset/1 = as before.
  if [ "${KAH_INSTANCE:-1}" -ge 2 ] 2>/dev/null; then
    export KDIR=/mnt/d/KenshiInst/$KAH_INSTANCE KAH_DIR="D:\\KenshiInst\\$KAH_INSTANCE\\mods\\AutomationHarness"
    export WSLENV="${WSLENV:+$WSLENV:}KAH_INSTANCE"
  fi
  export KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}
  export KAH_DIR=${KAH_DIR:-'D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness'}
  export KAH_CLIENT=${KAH_CLIENT:-/mnt/c/KenshiModding/Kenshi-Automation-Harness/client}
  export KAH_OWNER=${KAH_OWNER:-kfp-fixer}
  rig_launch() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1' launch -Save "$1"; }
  rig_stop() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1' stop; }
  rig_bg() { local log=$1; shift; setsid nohup bash -c "$*" > "$log" 2>&1 < /dev/null & }
fi
export FFX="$CR/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe"
case ":$PATH:" in *":${FFX%/*}:"*) ;; *) export PATH="$PATH:${FFX%/*}";; esac
# Capture mode (capture-fix 2026-10-11): KAH_CAPTURE=wgc|gdigrab, else line 1 of C:\KenshiTestRuns\capture.default, else
# gdigrab. wgc: FFX = ffx-cap.sh, which turns every `-f gdigrab -i title=..` into Windows Graphics Capture of the window
# (wgccap.exe: works while other windows cover the game) and passes every other ffmpeg call through to FFX_REAL.
export FFX_REAL="$FFX"
kah_capture_mode(){ local m=${KAH_CAPTURE:-}; [ -z "$m" ] && [ -f "$CR/KenshiTestRuns/capture.default" ] && m=$(head -1 "$CR/KenshiTestRuns/capture.default" | tr -d '\r '); echo "${m:-gdigrab}"; }
[ "$(kah_capture_mode)" = wgc ] && export FFX="$CR/KenshiModding/tools/automation/ffx-cap.sh"
# venc_args <crf> [x264-preset]: take recorder encoder args (h264_nvenc on both rigs, libx264 fallback; venc.sh header)
. "$(dirname "${BASH_SOURCE[0]}")/venc.sh"
# rig_preflight <row>: capture preflight, run before any recording (rec.sh calls it). 4080: Shay's desktop session must be
# Active in quser (a disconnected/locked session records black). Both rigs: a 1-frame gdigrab of $WIN_TITLE averaged to
# one gray pixel must have luma >= ${PF_MIN_LUMA:-8}. Failure prints `RESULT <row> FAIL setup: ...` and returns 1.
rig_preflight() {
  local row=${1:-take} q luma
  if [ "$RIG" = 4080 ]; then
    q=$(/c/Windows/System32/quser.exe 2>/dev/null | grep -i shay)
    if ! echo "$q" | grep -q ' Active '; then
      echo "RESULT $row FAIL setup: 4080 session not active (quser: $(echo $q | tr -s ' '))"; return 1
    fi
    # C:\KAH\display-check.ps1 (4080-display agent): virtual display + desktop grab in the session; must say LIVE
    # (needs Shay's keep-display-on.bat run in his RDP session)
    q=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KAH\display-check.ps1' 2>&1 | tr -d '\r' | grep 'gdigrab frame')
    if ! echo "$q" | grep -q '=> LIVE'; then
      echo "RESULT $row FAIL setup: 4080 session not active (display-check: ${q#--- })"; return 1
    fi
  fi
  luma=$("$FFX" -hide_banner -loglevel error -f gdigrab -draw_mouse 0 -i "title=$WIN_TITLE" -frames:v 1 \
    -vf "scale=1:1:flags=area,format=gray" -f rawvideo - 2>/dev/null | od -An -tu1 | tr -d ' \n')
  if [ -z "$luma" ] || [ "$luma" -lt "${PF_MIN_LUMA:-8}" ]; then
    if [ "$RIG" = 4080 ]; then echo "RESULT $row FAIL setup: 4080 session not active (test grab luma=${luma:-none})"
    else echo "RESULT $row FAIL setup: capture black (test grab luma=${luma:-none})"; fi
    return 1
  fi
  return 0
}
