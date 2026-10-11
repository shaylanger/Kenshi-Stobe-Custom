#!/bin/bash
# selftest.sh   (WSL, root; ~2 min)   self-test of tools/automation/dryrun.sh
# Replays the take bugs seen on 2026-10-10 against the fake game and checks dryrun.sh still FAILs each one for the right
# reason, and that the clean controls (current take scripts, also in the bad worlds) PASS. Run it after every change to
# dryrun.sh / dryrun/ / take-preflight.sh. Prints one line per case and a last line
#   RESULT DRYRUN-SELFTEST PASS|FAIL cases=<n> bad=<names>
# (bug-shellop / ctl-quoted: run-batch.sh row_split, rows are not run by a shell)
# Cases: <name> | <fixture or -> | <rig> | <expect: PASS or FAIL:<regex the DRYRUN line must match>> | <batch row>
set -u
H=/mnt/c/KenshiModding/tools/automation; RP=$H/dryrun/fixtures/replay-take.sh
KT=/mnt/c/KenshiModding/components/KenshiFP/tests/ingame
OUT=/mnt/c/KenshiTestRuns/dryrun/selftest-$(date +%m%d-%H%M%S)
CASES=$(cat <<EOF
ctl-clean      | -      | 5090 | PASS                                           | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp clean
ctl-blk        | -      | 5090 | PASS                                           | blk | - | Axima | Malzin | 900 | $KT/fp-block-guard.sh {OUT}/blk blkH
ctl-blk-night  | night  | 5090 | PASS                                           | blk | - | Axima | Malzin | 900 | $KT/fp-block-guard.sh {OUT}/blk blkH
ctl-blk-combat | combat | 5090 | PASS                                           | blk | - | Axima | Malzin | 900 | $KT/fp-block-guard.sh {OUT}/blk blkH
ctl-clean-4080 | combat | 4080 | PASS                                           | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp clean
ctl-studio     | -      | 5090 | PASS                                           | studio | - | Axima | Malzin | 900 | $KT/fp-studio-fixture.sh {OUT}/studio
ctl-swa-ko     | swing-ko | 5090 | PASS                                         | swa | - | Malzin | Shay | 900 | $KT/fp-swing-hits-all.sh Malzin Skaera Shay {OUT}/swa
ctl-swa-nomelee | no-melee | 5090 | PASS                                        | swa | - | Malzin | Shay | 900 | $KT/fp-swing-hits-all.sh Malzin Skaera Shay {OUT}/swa
ctl-xbmesh-empty | xbow-empty | 5090 | PASS                                    | xbmesh | kah-fpxbow | Axima | Malzin | 600 | $KT/fp-xbow-mesh.sh Axima Skaera {OUT}/xbmesh
ctl-2h-noroom  | studio-noroom | 4080 | PASS                                   | wm | kah-fpxbow | Axima | Malzin | 900 | RIG=4080 bash $KT/fp-weapon-sweep.sh {OUT}/wm /mnt/c/KenshiModding/components/KenshiFP/animlab/weapons/sweep-2h-b.list wm
bug-night      | night  | 5090 | FAIL:filmed at night                           | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp bare
bug-combat     | combat | 5090 | FAIL:hostiles within 30 m.*popup               | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp bare
bug-popup      | combat | 5090 | FAIL:setup: foreign overlay                    | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp popup
bug-noresult   | -      | 5090 | FAIL:no RESULT line                            | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp noresult
bug-lag        | -      | 5090 | FAIL:REPLAY-lag FAIL takecheck                 | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp lag
bug-early      | -      | 5090 | FAIL:REPLAY-early FAIL takecheck.*claim        | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp early
bug-noiso      | -      | 4080 | FAIL:REPLAY-noiso FAIL takecheck.*claim        | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp noiso
bug-stall      | stall  | 5090 | FAIL:REPLAY-clean FAIL takecheck.*cover        | rp | - | Axima | Malzin | 120 | $RP {OUT}/rp clean
bug-fistcand  | -      | 5090 | FAIL:setup: lab candidate .* missing           | fist0 | - | Axima | Malzin | 900 | FIST_NATIVE=0 $KT/fp-fists.sh {OUT}/fists 0 3 /tmp/no-fists-cand
ctl-quoted     | -      | 5090 | PASS                                           | rp | - | Axima | Malzin | 120 | DRQ="a b c" $RP {OUT}/rp clean
ctl-quoted-4080 | -     | 4080 | PASS                                           | rp | - | Axima | Malzin | 120 | RIG=4080 DRQ="a b c" $RP {OUT}/rp clean
ctl-dialog     | dialog | 5090 | PASS                                           | dlg | kah-fpxbow | Axima | Malzin | 120 | DRYRUN_NOREC=1 $RP {OUT}/rp dialog
bug-dialog     | dialog | 5090 | FAIL:stalled: ui_open=1                        | dlg | kah-fpxbow | Axima | Malzin | 120 | DRYRUN_NOREC=1 DIALOG_GUARD=0 $RP {OUT}/rp dialog
ctl-actor      | raider-on-mate | 5090 | PASS                                   | act | kah-fpxbow | Malzin | Axima | 120 | DRYRUN_NOREC=1 $RP {OUT}/rp actor
bug-actor      | raider-on-mate | 5090 | FAIL:ai_refused rose.*own fight        | act | kah-fpxbow | Malzin | Axima | 120 | DRYRUN_NOREC=1 $RP {OUT}/rp actor-bare
ctl-stealth    | spawn-hostile | 5090 | PASS                                  | st | kah-fpxbow | Axima | Malzin | 1200 | DRYRUN_NOREC=1 bash $KT/fp-stealth.sh Axima Malzin {OUT}/ST
bug-stealth-hostile | spawn-hostile-all | 5090 | FAIL:setup no neutral target   | st | kah-fpxbow | Axima | Malzin | 1200 | DRYRUN_NOREC=1 ROWS=ST03 bash $KT/fp-stealth.sh Axima Malzin {OUT}/ST
bug-shellop    | -    | 5090 | FAIL:list: shell operator                      | rp | - | Axima | Malzin | 120 | stobe-auto speed 1; $RP {OUT}/rp clean
EOF
)
mkdir -p "$OUT"; n=0; bad=""
while IFS='|' read -r name fix rig exp row; do
  t(){ local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; printf '%s' "${v%"${v##*[![:space:]]}"}"; }
  name=$(t "$name"); fix=$(t "$fix"); rig=$(t "$rig"); exp=$(t "$exp")
  [ -n "$name" ] || continue
  n=$((n + 1))
  args=(--rig "$rig" --out "$OUT/$name"); [ "$fix" != - ] && args+=(--fixture "$fix")
  v=$(bash $H/dryrun.sh "${args[@]}" --row "$row" 2>/dev/null </dev/null | grep '^DRYRUN ' | head -1)
  ok=0; vw=$(cut -d' ' -f3 <<<"$v")   # the verdict word only ("... FAIL ... guard PASS" is a FAIL)
  case "$exp" in
    PASS) [ "$vw" = PASS ] && ok=1 ;;
    FAIL:*) [ "$vw" = FAIL ] && echo "$v" | grep -qE "${exp#FAIL:}" && ok=1 ;;
  esac
  [ $ok = 1 ] && st=ok || { st=WRONG; bad="$bad $name"; }
  echo "SELFTEST $name $st expect=$exp got: ${v:0:260}"
done <<<"$CASES"
echo "RESULT DRYRUN-SELFTEST $([ -z "$bad" ] && echo PASS || echo FAIL) cases=$n bad=[${bad# }] out=$OUT"
[ -z "$bad" ] && rm -rf "$OUT"
[ -z "$bad" ]
