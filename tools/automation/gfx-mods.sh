#!/usr/bin/env bash
# gfx-mods.sh <off|on|status> [--hdtex]: graphics-only mods off for automated runs (RAM rule, CLAUDE.md), back on for Shay.
#   off: Dust plugin (mods/Dust/RE_Kenshi.json -> .gfxoff: RE_Kenshi skips Dust.dll, which loads its effect DLLs,
#        DLSS and FidelityFX; Dust.mod data stays listed) + ReShade (dxgi.dll -> dxgi.dll.gfxoff).
#   --hdtex: also take "detail textures.mod" out of data/mods.cfg (original line order kept in mods.cfg.gfxbak).
#        Only used if mem-ab shows it saves real memory. Compressed Textures Project and all data mods stay.
#   on:  restores everything above (Shay before playing: bash .../gfx-mods.sh on).
# Kenshi must be closed. Works from WSL (/mnt/d) or Git Bash (/d).
set -u
K=/mnt/d/Steam/steamapps/common/Kenshi; [ -d "$K" ] || K=/d/Steam/steamapps/common/Kenshi
act=${1:?off|on|status}; hd=0; [ "${2:-}" = --hdtex ] && hd=1
CFG="$K/data/mods.cfg"; HD="detail textures.mod"
running() { if command -v tasklist.exe >/dev/null; then tasklist.exe </dev/null 2>/dev/null | grep -qi kenshi_x64; else tasklist </dev/null 2>/dev/null | grep -qi kenshi_x64; fi; }
mvq() { [ -e "$1" ] && mv -f "$1" "$2"; return 0; }
case $act in
  off)
    running && { echo "GFX REFUSED: Kenshi is running"; exit 2; }
    mvq "$K/mods/Dust/RE_Kenshi.json" "$K/mods/Dust/RE_Kenshi.json.gfxoff"
    mvq "$K/dxgi.dll" "$K/dxgi.dll.gfxoff"
    if [ $hd = 1 ] && grep -qxF "$HD" <(tr -d '\r' < "$CFG"); then cp -f "$CFG" "$CFG.gfxbak"; grep -vxF "$HD" <(tr -d '\r' < "$CFG") | sed 's/$/\r/' > "$CFG.tmp" && mv -f "$CFG.tmp" "$CFG"; fi ;;
  on)
    running && { echo "GFX REFUSED: Kenshi is running"; exit 2; }
    mvq "$K/mods/Dust/RE_Kenshi.json.gfxoff" "$K/mods/Dust/RE_Kenshi.json"
    mvq "$K/dxgi.dll.gfxoff" "$K/dxgi.dll"
    [ -e "$CFG.gfxbak" ] && mv -f "$CFG.gfxbak" "$CFG"
    # kenshi.cfg back to Shay's full-screen values (test launches set it windowed: kenshi-ctl.ps1 cfg)
    powershell.exe -NoProfile -File C:/KenshiModding/tools/automation/kenshi-ctl.ps1 cfg play </dev/null ;;
  status) ;;
  *) echo "usage: gfx-mods.sh off|on|status [--hdtex]"; exit 1 ;;
esac
powershell.exe -NoProfile -File C:/KenshiModding/tools/automation/kenshi-ctl.ps1 cfg status </dev/null
d=on; [ -e "$K/mods/Dust/RE_Kenshi.json.gfxoff" ] && d=off
r=on; [ -e "$K/dxgi.dll.gfxoff" ] && r=off
h=on; grep -qxF "$HD" <(tr -d '\r' < "$CFG") || h=off
echo "GFX dust=$d reshade=$r hdtex=$h"
