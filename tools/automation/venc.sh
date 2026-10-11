# venc.sh: video encoder args for take recordings (Shay 2026-10-10: cut the 5090's CPU; libx264 on the CPU -> NVENC).
#   . venc.sh;  "$FFX" ... -f gdigrab ... -i "title=..." $(venc_args 18) out.mp4
# venc_args <crf> [x264-preset]  prints the -c:v ... -pix_fmt yuv420p args:
#   h264_nvenc (GPU encoder: 5090 here, 4080 too) -preset p4 -tune hq -rc vbr -cq <crf> -b:v 0 -g 60 -bf 0, same
#   resolution/fps as the input; -bf 0 keeps decode order = display order for the frame checks;
#   else (no NVIDIA encoder, or VENC=x264) libx264 -preset <veryfast> -crf <crf> as before.
# The NVENC probe (a 0.1 s encode with $FFX) runs once per rig and day: ${TMPDIR:-/tmp}/kah-venc.<rig>.
# Works on both rigs (WSL 5090, Git Bash 4080) and in dryrun (fake ffmpeg answers the probe).
venc_args() {
  local crf=${1:-18} x264p=${2:-veryfast} ff=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
  local c="${TMPDIR:-/tmp}/kah-venc.${RIG:-5090}" enc=""
  case "${VENC:-auto}" in
    x264) enc=x264 ;;
    nvenc) enc=nvenc ;;
    *) if [ -f "$c" ] && [ -n "$(find "$c" -mmin -1440 2>/dev/null)" ]; then enc=$(cat "$c")
       else
         if ( cd "${TMPDIR:-/tmp}" && "$ff" -hide_banner -loglevel error -f lavfi -i color=c=gray:s=256x144:r=30:d=0.1 \
                -c:v h264_nvenc -preset p4 -f null - ) </dev/null >/dev/null 2>&1; then enc=nvenc; else enc=x264; fi
         echo "$enc" > "$c" 2>/dev/null
       fi ;;
  esac
  if [ "$enc" = nvenc ]; then echo "-c:v h264_nvenc -preset p4 -tune hq -rc vbr -cq $crf -b:v 0 -g 60 -bf 0 -pix_fmt yuv420p"
  else echo "-c:v libx264 -preset $x264p -crf $crf -pix_fmt yuv420p"; fi
}
