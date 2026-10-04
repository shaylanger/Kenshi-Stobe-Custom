#!/usr/bin/env bash
# run-as.sh <scenario.txt> [player] [mate] [--real-power] [--keep-supply <name>] [--drop <regex>] [--after <regex> <line>] [--csv out.csv]
# Runs a STOBE `.txt` scenario (written with Shay/Malzin) for another squad: every whole-word "Shay" becomes
# <player>, every "Malzin" becomes <mate> (lines and regexes alike), and `select <player>` is put after the first
# `speed 0` (stobe_say speaks as the selected character).
#   --real-power        drop the harness `power "..." supply` cheat lines, so the fixture's own power is tested
#   --keep-supply <b>   ...but keep the supply line of building <b> (e.g. one the scenario builds: outside the grid)
#   --drop <regex>      drop every line matching <regex> (repeatable; e.g. a `build` the fixture doesn't need)
#   --after <regex> <line>  insert <line> after every line matching <regex> (repeatable, in order; matched and
#                       inserted after the Shay/Malzin renaming; e.g. a fixture-specific setup step after a `ko`)
# The rewritten file is kept next to the CSV (<csv>.scenario.txt) or in /tmp, for the run log.
set -u
src="${1:?usage: run-as.sh <scenario.txt> [player] [mate] [options]}"; shift
player="Shay"; mate="Malzin"
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then player="$1"; shift; fi
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then mate="$1"; shift; fi
export RA_REAL=0 RA_KEEP="" RA_DROP="" RA_AFTER=""
csv=""
while [ $# -gt 0 ]; do
  case "$1" in
    --real-power) RA_REAL=1; shift;;
    --keep-supply) RA_KEEP="${RA_KEEP}${2}"$'\x1f'; shift 2;;
    --drop) RA_DROP="${RA_DROP}${2}"$'\x1f'; shift 2;;
    --after) RA_AFTER="${RA_AFTER}${2}"$'\x1e'"${3}"$'\x1f'; shift 3;;
    --csv) csv="$2"; shift 2;;
    *) echo "run-as: unknown option $1" >&2; exit 2;;
  esac
done
out="/tmp/run-as-$(basename "$src")"; [ -n "$csv" ] && out="${csv%.csv}.scenario.txt"
python3 - "$src" "$out" "$player" "$mate" <<'PY'
import os, re, sys
src, out, player, mate = sys.argv[1:5]
real = os.environ.get('RA_REAL') == '1'
keep = [k for k in os.environ.get('RA_KEEP', '').split('\x1f') if k]
drops = [d for d in os.environ.get('RA_DROP', '').split('\x1f') if d]
afters = [a.split('\x1e', 1) for a in os.environ.get('RA_AFTER', '').split('\x1f') if a]
ren = lambda l: re.sub(r'\bMalzin\b', mate, re.sub(r'\bShay\b', player, l))
res, selected = [], False
for l in open(src, encoding='utf-8').read().splitlines():
    if any(re.search(d, l) for d in drops):
        res.append('# (run-as --drop) ' + l); continue
    if real and re.match(r'\s*power\s+"[^"]+"\s+supply\b', l) and not any(k in l for k in keep):
        res.append('# (run-as --real-power) ' + l); continue
    l = ren(l)
    res.append(l)
    res.extend(ren(ins) for rx, ins in afters if re.search(rx, l))
    if not selected and l.strip() == 'speed 0':
        res.append('select ' + player); selected = True
open(out, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('run-as: %s -> %s (player=%s mate=%s real_power=%s keep=%s drop=%s after=%d)' % (src, out, player, mate, real, keep, drops, len(afters)))
PY
if [ -n "$csv" ]; then stobe-auto run "$out" --csv "$csv"; else stobe-auto run "$out"; fi
