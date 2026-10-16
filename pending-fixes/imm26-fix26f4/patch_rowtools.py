"""imm26-fix26f4: inject-propose.sh gets --bypass-availability / --bypass-window / --disarm-all (anchor-asserted, idempotent).
usage: python3 patch_rowtools.py <rowtools dir>"""
import sys
p = sys.argv[1].rstrip('/') + '/inject-propose.sh'
s = open(p, 'rb').read().decode()
crlf = '\r\n' in s
s = s.replace('\r\n', '\n')
if '--disarm-all' in s:
    print('already patched'); sys.exit(0)


def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b)


rep("#   inject-propose.sh <lane|lane-root> --disarm                                                                  remove an unused marker\n",
    "#   inject-propose.sh <lane|lane-root> --disarm                                                                  remove an unused PROPOSE-phase marker (keeps a phase-2 accept marker)\n"
    "#   inject-propose.sh <lane|lane-root> --disarm-all                                                              remove any marker (also the phase-2 accept marker of --bypass-availability)\n"
    "#   arm option --bypass-availability [--bypass-window SEC]  (fix26f4, 26-f) the NPC may be in combat: the seam opens the product availability gate for the PROPOSE turn and for the player's Yes\n"
    "#       (phase-2 marker, default 600 s, 60..1800), lane gate only; logs 'availability bypassed' with the reasons the product gate gave. Without the flag nothing changes.\n")
rep("MODE=arm; ACTOR=\"\"; KIND=\"\"; TARGET=\"\"; ROW=\"\"; TTL=900; QTY=1\n",
    "MODE=arm; ACTOR=\"\"; KIND=\"\"; TARGET=\"\"; ROW=\"\"; TTL=900; QTY=1; BYPASS=0; BWIN=600\n")
rep("  --disarm) MODE=disarm; shift ;;\n", "  --disarm) MODE=disarm; shift ;;\n  --disarm-all) MODE=disarmall; shift ;;\n")
rep("    --quantity) QTY=\"${2:-}\"; shift 2 ;;\n",
    "    --quantity) QTY=\"${2:-}\"; shift 2 ;;\n    --bypass-availability) BYPASS=1; shift ;;\n    --bypass-window) BWIN=\"${2:-}\"; shift 2 ;;\n")
rep("  printf '%s\\n' \"$QTY\" | grep",
    "  printf '%s\\n' \"$BWIN\" | grep -Eq '^[0-9]{2,4}$' && [ \"$BWIN\" -ge 60 ] && [ \"$BWIN\" -le 1800 ] || { echo \"REFUSED --bypass-window 60..1800\"; exit 2; }\n  printf '%s\\n' \"$QTY\" | grep")
rep('''if [ "$MODE" = disarm ]; then
  wbody <<EOF
rm -f "$ROOT/test-inject-activity.json" && echo "DISARMED $LANE_NAME"
EOF
  exit 0
fi
''', '''if [ "$MODE" = disarm ]; then   # only an unused PROPOSE-phase marker; the phase-2 accept marker (bypass) must survive until the Yes
  wbody <<EOF
M="$ROOT/test-inject-activity.json"
if [ -f "\\$M" ] && grep -q '"phase":"accept"' "\\$M"; then echo "KEPT phase-2 accept marker $LANE_NAME (use --disarm-all)"
else rm -f "$ROOT/test-inject-activity.json" && echo "DISARMED $LANE_NAME"; fi
EOF
  exit 0
fi
if [ "$MODE" = disarmall ]; then
  wbody <<EOF
rm -f "$ROOT/test-inject-activity.json" && echo "DISARMED-ALL $LANE_NAME"
EOF
  exit 0
fi
''')
rep('''"row":"%s","expires_at":%s}\\n' \\
  '$KIND' '$ACT_JSON' '$NPC_JSON' '$TARGET' '$QTY' '$ROW' "\\$exp" >''',
    '''"row":"%s","expires_at":%s%s}\\n' \\
  '$KIND' '$ACT_JSON' '$NPC_JSON' '$TARGET' '$QTY' '$ROW' "\\$exp" '$BYPASS_JSON' >''')
rep('ACT_JSON="0"; NPC_JSON=""\n',
    'ACT_JSON="0"; NPC_JSON=""; BYPASS_JSON=""; [ "$BYPASS" = 1 ] && BYPASS_JSON=",\\"bypass_availability\\":true,\\"bypass_window\\":$BWIN"\n')
rep("expires_in=${TTL}s marker", "expires_in=${TTL}s bypass_availability=$BYPASS marker")
if crlf:
    s = s.replace('\n', '\r\n')
open(p, 'wb').write(s.encode())
print('patched', p)
