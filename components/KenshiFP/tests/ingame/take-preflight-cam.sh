# take-preflight-cam.sh: zoomed-out camera-line check for takes (source AFTER take-preflight.sh; uses PF_A + pf_fail).
# Setup-miss class "obstruction between the orbit camera and the character" (SETUP_MISSES.md VMQUICK op-b6 2026-10-10:
# z25 swing frames partly hidden by thin dead trees between camera and char; vmq_spot's 13 horizontal rays at the body
# miss the orbit camera line, and the camera's own pull-back mask 0x88204 passes through trees).
#   pf_camclear [label] [orbit]  call with the camera at its filming zoom/orbit, right before recording; pass the orbit
#     (radians) the take set with `fp_camera orbit`. Zoom 0: skipped.
#     `fp_camera probe` casts the pull-back ray from the eye anchor backwards along the LOOK yaw (it ignores the orbit;
#     the real camera sits at yaw+orbit, kfp_view.inc), so for orbit != 0 the check sets orbit 0 + look yaw+orbit, probes,
#     and restores look + orbit. Per collision mask (cam = 0x88204,
#     all = every group but bit 0, mesh = visual-mesh refine <= 20); any hit between PF_CAM_MIN (2.0, the own head) and
#     actual_distance - PF_CAM_SLACK (1.0) = something solid between camera and character -> RESULT <row> FAIL setup.
#     PF_CAMCLEAR=0 turns it off; a probe that is unavailable (no anchor/raycast) is reported, not failed.
# Dry run: fixture camblock (dryrun/fixtures/camblock.json, stub answers the probe with a hit), selftest bug-camblock /
# ctl-camclear (replay-take.sh mode camz25).
pf_camclear(){ local lb=${1:-camera} o=${2:-0} st d p hit="" k v y pt
  [ "${PF_CAMCLEAR:-1}" = 1 ] || { echo "pf_camclear off (PF_CAMCLEAR=0)"; return 0; }
  st=$(PF_A fp_camera state); d=$(grep -o 'actual_distance=[-0-9.]*' <<<"$st" | head -1 | cut -d= -f2)
  awk -v d="${d:-0}" 'BEGIN{exit !(d > 2.5)}' || { echo "pf_camclear skip: $lb zoom in (actual_distance=${d:-?})"; return 0; }
  y=$(grep -o ' yaw=[-0-9.]*' <<<"$st" | head -1 | cut -d= -f2); pt=$(grep -o ' pitch=[-0-9.]*' <<<"$st" | head -1 | cut -d= -f2)
  if awk -v o="$o" 'BEGIN{exit !(o != 0)}' && [ -n "$y" ] && [ -n "$pt" ]; then   # aim the probe down the orbit camera line
    PF_A fp_camera orbit 0 >/dev/null; PF_A fp_camera look "$(awk -v y="$y" -v o="$o" 'BEGIN{printf "%.6f", y+o}')" "$pt" >/dev/null; sleep 0.3
    p=$(PF_A fp_camera probe | tr -d "\r" | head -1)
    PF_A fp_camera look "$y" "$pt" >/dev/null; PF_A fp_camera orbit "$o" >/dev/null; sleep 0.5
  else p=$(PF_A fp_camera probe | tr -d "\r" | head -1); fi
  case "$p" in probe\ from=*) ;; *) echo "pf_camclear: probe unavailable for $lb (${p:0:80}), not judged"; return 0;; esac
  for k in cam all mesh; do v=$(grep -o " $k=[-0-9.]*" <<<"$p" | head -1 | cut -d= -f2)
    awk -v v="${v:--1}" -v d="$d" -v m="${PF_CAM_MIN:-2.0}" -v s="${PF_CAM_SLACK:-1.0}" 'BEGIN{exit !(v >= m && v < d - s)}' && hit="$hit $k=$v"; done
  [ -z "$hit" ] || pf_fail "camera line blocked ($lb, orbit $o): hit$hit of camera distance $d (tree/wall/body between the zoomed-out camera and the character)"
  echo "pf_camclear ok: $lb (orbit $o) camera line clear over $d (${p#probe })" | cut -c1-200; }
