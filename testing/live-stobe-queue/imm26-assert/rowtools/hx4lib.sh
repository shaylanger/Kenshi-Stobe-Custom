#!/usr/bin/env bash
# hx4lib.sh (imm26-fix15bx05cx3, 2026-10-16): shared helpers of the cx4 / v4 row tools (hxrun_cx4.sh, unblockdefs_c_v4.sh).  NEW file; source it AFTER lane.sh (lt_h).
# Why: `stobe-auto load <missing save>` does not fail: the hx rows silently ran in whatever world was already loaded (5090-i3 has no kah-imm26-5090-hxA; op23).
#   hx4_save_check <save> : rc 0 when the save folder exists in the lane's game folder ($KDIR/save/<name>, KDIR from rig-env.sh = the lane's install); rc 3 + HX4_WHY otherwise.
#   If the lane has no $KDIR/save folder at all (a layout this check does not know) the answer is "SAVE-UNKNOWN": rc 0, a warning in HX4_WHY (never a silent pass of a KNOWN-missing save).
#   Dry runs (KAH_ROW_DRY) skip it.   hx4_lane_save <lane> : a save that EXISTS for the lane's hx rows (override: --save).
hx4_lane_save() {
  case "${1:-${LT_LANE:-}}" in
    5090-i3) echo kah-imm26-5090-ready;;     # /d/KenshiInst/3/save (the trip rows' ready save: Shay + Cind + Malzin); hxA never existed on i3
    5090-i4) echo kah-imm26-i4-hx0;;
    5090-i5) echo kah-imm26-i5;;
    4080-i4) echo kah-imm26-4080-i4h;;
  esac
}
hx4_save_check() {
  local sv="$1" o; HX4_WHY=""
  [ -n "${KAH_ROW_DRY:-}" ] && return 0
  [ -n "$sv" ] || { HX4_WHY="no base save known for lane ${LT_LANE:-?} (use --save S)"; return 3; }
  o=$(printf 'if [ -d "$KDIR/save/%s" ]; then echo SAVE-OK; elif [ -d "$KDIR/save" ]; then echo "SAVE-MISSING $KDIR/save/%s"; else echo "SAVE-UNKNOWN no save folder under $KDIR"; fi\n' "$sv" "$sv" | lt_h 2>&1 | grep -E '^SAVE-(OK|MISSING|UNKNOWN)' | tail -1)
  case "$o" in
    SAVE-OK*) return 0;;
    SAVE-UNKNOWN*) HX4_WHY="warning: cannot verify save '$sv' ($o)"; return 0;;
    SAVE-MISSING*) HX4_WHY="base save '$sv' does not exist ($o); a load would silently keep the world already loaded. Use --save <existing save> (lane default: $(hx4_lane_save))"; return 3;;
    *) HX4_WHY="save check for '$sv' got no answer from lane ${LT_LANE:-?} ($(printf '%s' "$o" | cut -c1-120))"; return 3;;
  esac
}
