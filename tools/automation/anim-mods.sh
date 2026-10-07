#!/usr/bin/env bash
# anim-mods.sh <status|set <loadout>|restore>: combat animation mod loadouts for KenshiFP M09 (COMBAT_TEST_PLAN.md:
# "vanilla first, individual MCA/DodgeStrafe/Great Anims, then full loadout"). Edits only the lines of these mods in
# data/mods.cfg (the game reads it at launch, so a loadout change needs a restart). Kenshi must be closed.
#   groups:   mca     = More Combat Animation.mod + UWE - MCA Compatibility Patch.mod (the patch needs MCA)
#             dodge   = DodgeStrafe.mod
#             gam     = Great Anims Mod.mod + UWE - GAM Compatibility Patch.mod (the patch needs GAM)
#             standup = Faster Stand-Up Animation.mod (KO stand-up animation)
#   loadouts: vanilla (all four off) | mca | dodge | gam (that group only, the other three off) | full (all on = Shay's list)
#   restore:  full + drop the reference copy (one-command restore before Shay plays; also `set full`).
# Every other line (data mods the fixtures depend on, non-combat/idle animation mods, UWE itself) is never touched.
# The first change saves data/mods.cfg.animref (the original order); re-enabled lines go back right after their
# original predecessor, so it composes with gfx-mods.sh --hdtex (restore order: anim-mods.sh restore, then gfx-mods.sh on).
# Both rigs: K = $KENSHI_DIR, else the 5090 path (WSL /mnt/d or Git Bash /d), else the 4080 Steam path (Git Bash).
# Output: one line `ANIM loadout=<name|custom> mca=on|off|partial dodge=.. gam=.. standup=..`; `loaded` adds what
# kenshi_info.log says the last launch really loaded (`[Mods] Loaded mod: <name>`).
set -u
K=${KENSHI_DIR:-}
for d in /mnt/d/Steam/steamapps/common/Kenshi /d/Steam/steamapps/common/Kenshi "/c/Program Files (x86)/Steam/steamapps/common/Kenshi"; do
  [ -z "$K" ] && [ -f "$d/data/mods.cfg" ] && K=$d; done
[ -n "$K" ] && [ -f "$K/data/mods.cfg" ] || { echo "ANIM ERROR: Kenshi data/mods.cfg not found (set KENSHI_DIR)"; exit 1; }
CFG="$K/data/mods.cfg"; REF="$CFG.animref"
AGROUPS="mca dodge gam standup"
lines() { case $1 in
  mca) printf '%s\n' "More Combat Animation.mod" "UWE - MCA Compatibility Patch.mod" ;;
  dodge) printf '%s\n' "DodgeStrafe.mod" ;;
  gam) printf '%s\n' "Great Anims Mod.mod" "UWE - GAM Compatibility Patch.mod" ;;
  standup) printf '%s\n' "Faster Stand-Up Animation.mod" ;; esac; }
running() { [ -n "${ANIM_SKIP_RUNCHECK:-}" ] && return 1; if command -v tasklist.exe >/dev/null; then tasklist.exe </dev/null 2>/dev/null | grep -qi kenshi_x64; else tasklist </dev/null 2>/dev/null | grep -qi kenshi_x64; fi; }
cur() { tr -d '\r' < "$CFG"; }
gstate() { local n=0 on=0 l; while IFS= read -r l; do n=$((n+1)); cur | grep -qxF "$l" && on=$((on+1)); done < <(lines "$1")
  [ $on = $n ] && echo on || { [ $on = 0 ] && echo off || echo partial; }; }
status() { local g s lo="" st=""; for g in $AGROUPS; do s=$(gstate $g); st+=" $g=$s"; done
  case "$st" in " mca=off dodge=off gam=off standup=off") lo=vanilla ;; " mca=on dodge=on gam=on standup=on") lo=full ;;
    " mca=on dodge=off gam=off standup=off") lo=mca ;; " mca=off dodge=on gam=off standup=off") lo=dodge ;;
    " mca=off dodge=off gam=on standup=off") lo=gam ;; *) lo=custom ;; esac
  echo "ANIM loadout=$lo$st ref=$([ -f "$REF" ] && echo saved || echo none)"; }
loaded() { local f="$K/kenshi_info.log" g l s out=""; [ -f "$f" ] || { echo "loaded=unknown(no kenshi_info.log)"; return; }
  for g in $AGROUPS; do s=""; while IFS= read -r l; do grep -qF "Loaded mod: ${l%.mod}" <(tr -d '\r' < "$f") && s+=1 || s+=0; done < <(lines $g)
    case $s in *0*1*|*1*0*) s=partial ;; *1*) s=on ;; *) s=off ;; esac; out+=" $g=$s"; done
  echo "loaded:$out"; }
# apply <enabled groups...>: rebuild mods.cfg = current non-managed lines + enabled managed lines at their ref spots
apply() { local en="" g l
  [ -f "$REF" ] || cp -f "$CFG" "$REF"
  for g in "$@"; do en+="$(lines $g)"$'\n'; done
  local all=""; for g in $AGROUPS; do all+="$(lines $g)"$'\n'; done
  while IFS= read -r l; do [ -z "$l" ] || tr -d '\r' < "$REF" | grep -qxF "$l" || { echo "ANIM ERROR: '$l' is not in the original mods.cfg (not installed/enabled on this rig?)"; exit 1; }; done <<<"$en"
  awk -v en="$en" -v all="$all" -v ref="$REF" '
    BEGIN { n=split(all,a,"\n"); for(i=1;i<=n;i++) if(a[i]!="") M[a[i]]=1; n=split(en,e,"\n"); for(i=1;i<=n;i++) if(e[i]!="") E[e[i]]=1
            while ((getline r < ref) > 0) { sub(/\r$/,"",r); R[++nr]=r } }
    { sub(/\r$/,""); if (!($0 in M)) O[++no]=$0 }
    END {
      for (i=1;i<=nr;i++) { if (!(R[i] in E)) continue
        pos=0; for (j=i-1;j>=1 && !pos;j--) for (k=1;k<=no;k++) if (O[k]==R[j]) { pos=k; break }
        for (k=no;k>pos;k--) O[k+1]=O[k]; O[pos+1]=R[i]; no++ }
      for (k=1;k<=no;k++) printf "%s\r\n", O[k] }' "$CFG" > "$CFG.animtmp" && mv -f "$CFG.animtmp" "$CFG"; }
case ${1:-status} in
  status) status; [ "${2:-}" = loaded ] && loaded ;;
  loaded) status; loaded ;;
  set) running && { echo "ANIM REFUSED: Kenshi is running"; exit 2; }
    case ${2:-} in vanilla) apply ;; mca|dodge|gam) apply "$2" ;; full) apply $AGROUPS ;;
      *) echo "usage: anim-mods.sh set vanilla|mca|dodge|gam|full"; exit 1 ;; esac; status ;;
  restore) running && { echo "ANIM REFUSED: Kenshi is running"; exit 2; }
    [ -f "$REF" ] && { apply $AGROUPS; rm -f "$REF"; }; status ;;
  *) echo "usage: anim-mods.sh status [loaded] | loaded | set vanilla|mca|dodge|gam|full | restore"; exit 1 ;;
esac
