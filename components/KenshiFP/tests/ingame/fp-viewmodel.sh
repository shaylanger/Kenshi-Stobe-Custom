#!/usr/bin/env bash
# fp-viewmodel.sh: KenshiFP Gate 6 viewmodel rows PT13/PT14/PT26-PT30 (COMBAT_TEST_PLAN.md) on a kah-fpxbow copy
# (Axima = crossbow player, Malzin = mate with a melee weapon). Helpers + setup are fp-playtest.sh's (same build).
#  PT13  crossbow: physical R draw -> fp_vm state=ready, hand within VM_TOL deg of the ready target, melee=0, |tilt|<8;
#        RMB held -> state=aiming on the aim target; one injected shot -> state=reloading seen
#  PT14  sword (bow off, sword from the mate): R draw -> ready on target, melee=1, tilt >= 20; RMB held -> blocking on
#        the block target; physical LMB -> a new "[vm] swing" log line with u_end >= 0.5; test pose sw_pose 0 / 1 ->
#        target = the ready target (the swing path starts and ends at the ready pose)
#  PT28  crossbow like Skyrim/KCD, each state zoomed in AND out: ready (low right, forward, top up, whole crossbow
#        above the HUD line: lowest projected body point y/z >= -0.33), aim (seen from behind: grip 2.0..2.9 dm ahead,
#        |x|<=0.5, low (y<=-0.9) = stock up from the bottom centre, top up = limbs horizontal, bolt <=2 deg off the crosshair at AIMD, projected bolt tip
#        within |x|<=0.06, -0.08..0.02 NDC of the centre, off-hand on the fore-stock support point, arm_cov<=0.15 = no
#        forearm blob bottom centre), fire (physical LMB: kicks + "[vm] fire" line; frozen kick_pose 1 = muzzle climb
#        0..0.4 NDC, grip within 0.5 dm of the aim hold), reload (lowered >=10 deg, pointing forward: not in the face)
#  PT27  sword block: blade horizontal across the view (|mf.x|>=0.85, |mf.y|<=0.2) zoomed in and out
#  PT26  sword swing: frozen frame sequence sw_pose 0.1..0.9 (screens + targets) and NSW (3) physical LMB swings:
#        each "[vm] swing" line u_end=1, frames>=8, readable phases from the [vmsw] lines (wind-up 15-50% of the frames,
#        strike mean blade speed >= 2x the wind-up; frame jumps = recorder vmcheck below; ratio only reported),
#        grip rises to elev>=0 (wind-up in view) and crosses to az<=-5 from az>=20, highest frame before the
#        leftmost ([vmsw] per-frame log) = top-right -> bottom-left; plus one LMB swing recorded every frame
#        (fp_vm rec): no frame-to-frame jump on screen (vmcheck swing mode, see PT30)
#  PT30  every-frame smoothness (fp_vm rec, the game's own frames): crossbow draw/aim/fire/reload/ready/aim/holster and
#        sword draw/2 swings/block/swing->block/holster; the embedded vmcheck flags any on-screen frame whose tip step
#        (>0.15 dm) or blade/top rotation (>3 deg) is > 2.5x both neighbours' (dt-scaled; hitch frames dt>0.07 and the
#        fire-kick onset impulse excepted); PASS = 0 flags, weapon within 0.35 dm of the commanded pose, the weapon
#        enters (draw) and leaves (holster) the hand below the view, crossbow reload grip z >= 2.0 (not in the face)
#  PT29  zoom out (fp_camera distance ZO=25) keeps the hold: every captured state's grip within ZO_TOL (0.3) dm and
#        blade within 5 deg of the zoomed-in capture (xbow ready/aim/fire/reload, sword ready/block/swing 0.42)
# Screenshots (vm-*.png, harness shots dir) are listed in a NOTE line: PT17 (overall look) is judged from them.
# Usage: fp-viewmodel.sh [player] [mate] [hostile] [outdir]. Env: ROWS (comma/space list, default all), KFPLOG,
# VM_TOL (4), ZO, ZO_TOL, RATIO_MAX, NSW, SW_US, SLOW_DUR. Example: ROWS=PT26,PT27,PT28,PT29 bash fp-viewmodel.sh
# Needs KenshiFP with the 2026-10-08 viewmodel (fp_vm state mu= field, [vm] fire / swing ratio= log lines).
# Leaves the fixture changed (a shot fired, items moved): reload it after.
SH=${1:-${PLAYER:-Axima}}; MT=${2:-${MATE:-Malzin}}; TG=${3:-${HOSTILE:-Skaera}}; OUT=${4:-/tmp/fp-viewmodel}
KDIR=/mnt/d/Steam/steamapps/common/Kenshi; KFPLOG=${KFPLOG:-$KDIR/KenshiFP.log}
STILL_MAX=${STILL_MAX:-3}; SPIKE_MAX=${SPIKE_MAX:-1.5}; FAR_NPC=${FAR_NPC:-}
ROWS=${ROWS:-"PT13 PT14 PT26 PT27 PT28 PT29 PT30"}; ROWS=${ROWS//,/ }
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
cat > "$OUT/vmcheck.py" <<'VMCHECK'
import sys, math
# vmcheck.py <rec.txt> <xbow|sword|swing>: every-frame viewmodel check of an fp_vm rec dump (PT30). Prints one line:
# ok=0|1 <evidence>. Rendered pose of frame n = measured in record n+1, re-expressed in frame n's camera.
def V(s): return tuple(float(x) for x in s.split(','))
def sub(a,b): return (a[0]-b[0],a[1]-b[1],a[2]-b[2])
def add(a,b): return (a[0]+b[0],a[1]+b[1],a[2]+b[2])
def mul(a,k): return (a[0]*k,a[1]*k,a[2]*k)
def dot(a,b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def ln(a): return math.sqrt(dot(a,a))
def ang(a,b):
    la,lb=ln(a),ln(b)
    if la<1e-6 or lb<1e-6: return 0.0
    return math.degrees(math.acos(max(-1,min(1,dot(a,b)/la/lb))))
F=[]
for line in open(sys.argv[1]):
    if line.startswith('#') or '|' not in line: continue
    pa=line.split('|'); h=pa[0].split(); v=[V(x) for x in pa[1].split()]
    r=dict(t=float(h[1]),dt=float(h[2]),st=h[3],cls=int(h[5]),w=float(h[7]),kick=float(h[11]),op=v[0],mp=v[4],mf=v[5],mu=v[6],
           cam=[V(x) for x in pa[2].split()] if len(pa)>2 else None,ph=0,wih=1)
    if len(pa)>3:
        x=pa[3].split()
        if len(x)>=5: r['ph']=int(x[3]); r['wih']=int(x[4])
    F.append(r)
def remap(c,a,b,pos):
    if a['cam'] is None or b['cam'] is None: return c
    e,rt,up,fw=b['cam']; w=add(add(mul(rt,c[0]),mul(up,c[1])),mul(fw,c[2])); w=add(w,e) if pos else w
    e,rt,up,fw=a['cam']; d=sub(w,e) if pos else w; return (dot(d,rt),dot(d,up),dot(d,fw))
for i in range(len(F)-1):
    a,b=F[i],F[i+1]; a['rp']=remap(b['mp'],a,b,1); a['rf']=remap(b['mf'],a,b,0); a['ru']=remap(b['mu'],a,b,0)
F=F[:-1]; N=len(F)
BL={0:8.0,1:5.85}
def tip(r): return add(add(r['rp'],mul(r['rf'],BL[r['cls']])),mul(r['ru'],0.84 if r['cls']==1 else 0))
def onscr(c): return c[2]>=2.5 and abs(c[1])/c[2]<0.70 and abs(c[0])/c[2]<1.245
for i,r in enumerate(F):
    r['vis']=r['wih']!=0 and (onscr(r['rp']) or onscr(tip(r)))
    p=F[i-1] if i else r
    r['tipd']=ln(sub(tip(r),tip(p))); r['df']=ang(r['rf'],p['rf']); r['du']=ang(r['ru'],p['ru'])
flags=[]; errmax=0.0; rlz=99.0; nvis=0; tipmax=0.0; dfmax=0.0
for i in range(1,N-1):
    a,b,c=F[i-1],F[i],F[i+1]
    if not b['vis']: continue
    nvis+=1
    if b['w']>=0.999 and b['ph']==0: errmax=max(errmax,ln(sub(b['rp'],b['op'])))
    if b['cls']==1 and b['st']=='reloading' and b['kick']==0: rlz=min(rlz,b['rp'][2])
    if not a['vis'] or b['dt']>0.07: continue          # entering the view / game hitch frame (motion is per time)
    if b['kick']>0 and a['kick']==0: continue          # fire kick onset: an impulse by design (sharp kick)
    tipmax=max(tipmax,b['tipd']); dfmax=max(dfmax,b['df'])
    cv=c['vis']
    for k,lim in (('tipd',0.15),('df',3.0),('du',3.0)):   # neighbours scaled to this frame's dt (per-time rates)
        nb=max(a[k]*b['dt']/max(a['dt'],1e-4),(c[k]*b['dt']/max(c['dt'],1e-4)) if cv else 0)
        if b[k]>lim and b[k]>2.5*nb: flags.append('%d:%s=%.2f/%.2f'%(i,k,b[k],nb))
# the weapon enters the hand (draw) and leaves it (holster) below the view, never in sight
inout=[]
for i in range(1,N):
    if F[i]['wih']!=F[i-1]['wih']:
        r=F[i] if F[i]['wih'] else F[i-1]
        inout.append('%s@%d:%s'%('in' if F[i]['wih'] else 'out',i,'vis' if onscr(r['rp']) or onscr(tip(r)) else 'off'))
if sys.argv[2]=='swing': ok=N>=20 and nvis>=15 and not flags and errmax<=0.35 and all(x.endswith('off') for x in inout)
else: ok=N>=200 and nvis>=100 and not flags and errmax<=0.35 and all(x.endswith('off') for x in inout) and len(inout)>=2
if sys.argv[2]=='xbow': ok=ok and rlz>=2.0
fps=1/sorted(r['dt'] for r in F)[N//2]
print("ok=%d frames=%d vis=%d fps=%.0f flags=%d%s errmax=%.2f tipd_max=%.2f df_max=%.1f wih=%s%s" % (ok,N,nvis,fps,len(flags),
      (' ['+' '.join(flags[:6])+']') if flags else '',errmax,tipmax,dfmax,','.join(inout) or 'none',
      (' reload_zmin=%.2f'%rlz) if sys.argv[2]=='xbow' else ''))
VMCHECK
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
note() { echo "$*" >> "$LOG"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cam() { A fp_camera state | fld "$1"; }
ctl() { A fp_control state | fld "$1"; }
fps() { A fp_state | fld "$1"; }
ks() { A fp_keys state | fld "$1"; }
cs() { A fp_combat state | fld "$1"; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr ',' ' '; }
isko() { A where "$1" | grep -qE ' (KO|DEAD)( |$)'; }
notko() { ! isko "$1"; }
d2() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,p," ");split(b,q," ");printf "%.2f", sqrt((q[1]-p[1])^2+(q[3]-p[3])^2)}'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0<b+0)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0>=b+0)}'; }
inc() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && b!="" && b+0>a+0)}'; }     # inc <before> <after>: rose
want() { case " $ROWS " in *" $1 "*) return 0;; esac; return 1; }
waitf() { local end=$((SECONDS+$1)); shift; while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.2; done; return 1; }
uname_() { tr ' =' '__' <<<"$1"; }
kfplines() { tail -n +"$((LN0+1))" "$KFPLOG" 2>/dev/null | tr -d '\r'; }       # KenshiFP.log since the test start
RESULTS=()
# ---- world raids (m53: a Dust Bandits squad attacked Axima/Malzin mid-run: stagger flips in PT01/PT03, PT10 fight=1,
# PT15/PT18 native ranged combat). Raiders within 1500 are knocked out at setup and every 10 s (as stobe-fight-lib.sh
# calm_raiders; the fixture hostile $TG and the PT10 far NPC are kept), and a row during which a non-squad character
# attacked the squad (stobe.log `[EVENT] combat: X -> <squad>`) is `FAIL setup: hostile ... attacking`, never judged.
SLOG=${SLOG:-$KDIR/RE_Kenshi/mods/Stobe/stobe.log}; STOBELIB=${STOBELIB:-/mnt/c/KenshiModding/tests/ingame/stobe/stobe-fight-lib.sh}
[ -r "$STOBELIB" ] && eval "$(grep -E '^RAID_(RE|FILTER)=' "$STOBELIB")"
RAID_RE=${RAID_RE:-Band of Bones|Kral.s Chosen|Dust Bandits|Hungry Bandits|Starving Bandits|Hill Marauders|Black Dragon Ninjas|Berserkers|Cannibals|Fogmen}
RAID_FILTER=${RAID_FILTER:-[band of bones]|[kral|[dust bandits]|[hungry bandits]|[starving bandits]|[hill marauders]|[black dragon ninjas]|[berserkers]|[cannibals]|[fogmen]}
KEEP=""; KEEPN=(); RAIDG=""; SL0=0; SHN=""; MTN=""   # KEEPN: grep -e args for kept attackers ($TG, PT10 far NPC)
sweep() { local lines h n=0
  lines=$(stobe-auto chars 1500 "$RAID_FILTER" 2>/dev/null | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//' \
    | grep -E "\[(${RAID_RE})\]" | grep -v -E ' (KO|DEAD)( |$)' | grep -v -E "^(${SH}|${MT}) #")
  for h in $(grep -oE '#[0-9]+/[0-9]+' <<<"$lines"); do case " $KEEP " in *" $h "*) continue;; esac
    stobe-auto ko "$h" 21600 >/dev/null 2>&1 && n=$((n+1)); done; echo "$n"; }
slog_n() { [ -r "$SLOG" ] && wc -l < "$SLOG" || echo 0; }
# hostile_hit: the last `combat: X -> <player|mate>` since the previous row by anyone outside the squad / KEEP names
hostile_hit() { [ -r "$SLOG" ] && [ -n "$SHN" ] || return 0
  tail -n +"$((SL0+1))" "$SLOG" 2>/dev/null | tr -d '\r' | grep -a -F -e "-> $SHN (" -e "-> $MTN (" | grep -a 'EVENT\] combat: ' \
    | grep -a -v -F -e "combat: $SHN (" -e "combat: $MTN (" "${KEEPN[@]}" | tail -1 | sed 's/.*combat: //' | cut -c1-110; }
row() { local res=$2 ev=$3 hh; hh=$(hostile_hit)
  case "$ev" in setup:*) ;; *) [ -n "$hh" ] && { res=FAIL; ev="setup: hostile attacking the squad during the row ($hh) | $ev"; };; esac
  RESULTS+=("RESULT $1 $res $ev"); echo "RESULT $1 $res $ev" >> "$LOG"; SL0=$(slog_n); }
judge() { if [ "$2" = 1 ]; then row "$1" PASS "$3"; else row "$1" FAIL "$3"; fi; }
finish() { for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done; }
# setup_fail <reason>: every wanted row not yet reported gets `FAIL setup: <reason>`
setup_fail() { local r; for r in $ROWS; do printf '%s\n' "${RESULTS[@]}" | grep -q "^RESULT $r " || row "$r" FAIL "setup: $1"; done; finish; exit 1; }
# rows_fail <reason> <rows...>: the listed wanted rows fail on a setup reason
rows_fail() { local why=$1 r; shift; for r in "$@"; do want "$r" && row "$r" FAIL "setup: $why"; done; }

# ---- physical input (input isolation) ----
mclick() { A mouse_inject "$1" click "${2:-80}" >/dev/null; sleep "$(awk -v m="${2:-80}" 'BEGIN{printf "%.2f", (m+250)/1000}')"; }
mdown() { A mouse_inject "$1" down >/dev/null; }
mup() { A mouse_inject "$1" up >/dev/null; }
rkey() { A key_inject r tap 120 >/dev/null; sleep 0.35; }
altkey() { A key_inject 0xa4 tap 120 >/dev/null; sleep 0.4; }      # Left Alt = KenshiFP free-cursor toggle

# ---- view / control ----
fp_is() { [ "$(fps fp_mode)" = "$1" ]; }
mode() { A fp_mode "$1" >/dev/null; waitf 4 fp_is "$([ "$1" = on ] && echo 1 || echo 0)"; }
ctl_is() { local ids id; ids=$(ctl control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
take() { A select "$1" >/dev/null; A fp_control take >/dev/null; mode on; A fp_control take >/dev/null; waitf 4 ctl_is "$1"; }
cursor_ok() { [ "$(fps cursor_hidden)" = 1 ]; }
look() { A fp_camera look "$1" "${2:-0}" >/dev/null; sleep 0.3; }
SKY=-0.9
sky() { look "$(cam yaw)" "$SKY"; }
# aim_pt <viewer> <x y z> <height dm>: FP camera from the eye at a world point + height; aim_at <viewer> <npc> <height>
aim_pt() { local V=$1 sx sy sz tx ty tz c e YP; read -r sx sy sz <<<"$(pos "$V")"; read -r tx ty tz <<<"$2"
  c=$(A fp_camera state); e=$(fld camera_y <<<"$c"); [ -n "$(fld camera_x <<<"$c")" ] && { sx=$(fld camera_x <<<"$c"); sz=$(fld camera_z <<<"$c"); }
  [ -n "$e" ] || e=$(awk -v y="$sy" 'BEGIN{print y+19}')
  YP=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$ty" -v h="$3" \
     'BEGIN{L=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-(py+h), L)}')
  A fp_camera look $YP >/dev/null; sleep 0.4; }
aim_at() { aim_pt "$1" "$(pos "$2")" "$3"; }
# pick_on <viewer> <npc>: aim until the crosshair pick reports the npc (bounded: heights 13 10 7, 2 tries each)
pick_on() { local H; for H in 13 10 7; do for _ in 1 2; do aim_at "$1" "$2" "$H"; A fp_keys pick >/dev/null; sleep 0.3
  PK=$(A fp_keys pick show); [ "$(fld result <<<"$PK")" = "$(uname_ "$(live_name "$2")")" ] && return 0; done; done; return 1; }
live_name() { local n; n=$(A where "$1" | sed -n 's/^\(.*\) #[0-9][0-9]*\/[0-9][0-9]* .*/\1/p' | head -1); echo "${n:-$1}"; }
menu_close() { [ "$(fps free)" = 1 ] && A fp_state free off >/dev/null; sleep 0.3; }
toggles() { local i; for i in $(seq 1 "$1"); do mode off; sleep 0.5; mode on; sleep 0.5; done; }
in_fight() { A fp_melee state | grep -q 'active=1' && ! A fp_melee state | grep -q 'target_h=#0/'; }
not_fight() { ! in_fight; }
kis() { [ "$(ks "$1")" = "$2" ]; }
kge() { ge "$(ks "$1")" "$2"; }
csis() { [ "$(cs "$1")" = "$2" ]; }
csge() { ge "$(cs "$1")" "$2"; }

# ---- equipment (as fp-controls.sh: the fixture player carries a crossbow only; melee comes from the mate) ----
weapons() { A inv "$SH" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOWN:-@@}"; }
# bow_now: the full bow name (`rangedinfo` prints `bow=<name with spaces> has_ammo=...`; m53: `fld bow` cut it to
# "Oldworld" and every later unequip/pickup/equip by name missed)
bow_now() { local r; r=$(A rangedinfo "$SH"); case "$r" in *" bow=none"*) echo none;; *" bow="*) sed -n 's/.* bow=\(.*\) has_ammo=.*/\1/p' <<<"$r" | head -1;; *) echo none;; esac; }
# href <unequip reply>: the item's `#serial/index` (pickup by handle: exact, any distance)
href() { local i s; i=$(grep -o 'h\.index=[0-9]*' <<<"$1" | head -1 | cut -d= -f2); s=$(grep -o 'h\.serial=[0-9]*' <<<"$1" | head -1 | cut -d= -f2)
  [ -n "$i" ] && [ -n "$s" ] && echo "#$s/$i"; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$SH" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }
GIVEN=""
give_melee() { local w r; [ -n "$(weapons)" ] && return 0
  w=$(A inv "$MT" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | head -1 | sed 's/.*"name":"\([^"]*\)".*/\1/')
  [ -n "$w" ] || { note "SETUP give_melee: $MT has no melee weapon either"; return 1; }
  r=$(A transfer "$MT" "$SH" "$w")
  case "$r" in transferred*) ;; *) r=$(A unequip "$MT" "$w")
    case "$r" in *ground*) r=$(A pickup "$SH" "$w" now);; *) r=$(A transfer "$MT" "$SH" "$w");; esac;; esac
  note "SETUP give_melee $w from $MT: $(cut -c1-120 <<<"$r")"; [ -n "$(weapons)" ] && GIVEN=$w; }
# bow_off: unequip the bow. The fixture player's main inventory holds no long weapon (m53: bow and katana both went
# "-> ground"), and the mate's back slot has her own bow, so a dropped bow stays on the ground next to the player
# (BOW_DROPPED=1, handle BOWREF; harness f4ab9f6+ remembers unequip drops and scans CROSSBOW items for pickup)
BOW_DROPPED=0; BOWREF=""
bow_off() { local r; [ "$(bow_now)" = none ] && return 0; r=$(A unequip "$SH" "$BOWN")
  case "$r" in *"-> ground"*) BOW_DROPPED=1; BOWREF=$(href "$r"); note "SETUP bow on the ground next to $SH ($BOWREF)";; esac
  [ "$(bow_now)" = none ]; }
bow_back() { [ "$(bow_now)" != none ]; }
# bow_on: pickup by handle (`now` = giveItem: the game puts it on the free back slot = equipped), else equip by name
bow_on() { bow_back && return 0; [ -n "$BOWN" ] || return 1
  if [ "$BOW_DROPPED" = 1 ]; then note "SETUP bow pickup: $(A pickup "$SH" "${BOWREF:-$BOWN}" now | cut -c1-140)"
    waitf 15 bow_back && { BOW_DROPPED=0; return 0; }; fi
  A equip "$SH" "$BOWN" | grep -q '^equipped' && BOW_DROPPED=0; bow_back; }
draw_to() { kis drawn "$1" && return 0; rkey; waitf 4 kis drawn "$1"; }

# ---- restore on exit ----
FP0=""; DIST0=""; AR0=""; EN0=""; PASSIVE0=""; PINNED=""; WEP=""; BOWN=""; ISO_SET=0; LN0=0
cleanup() { A mouse_inject right up >/dev/null; A mouse_inject left up >/dev/null; A fp_move none >/dev/null
  A fp_keys reset >/dev/null; A fp_keys swallow on >/dev/null
  A fp_combat input 0 0 0 >/dev/null; A fp_combat physical >/dev/null; [ -n "$AR0" ] && A fp_combat autoreload "$AR0" >/dev/null; [ "$EN0" = 0 ] && A fp_combat off >/dev/null
  [ "$(fps free)" = 1 ] && A fp_state free off >/dev/null
  for c in $PINNED; do A pin "$c" off >/dev/null; done
  [ -n "$PASSIVE0" ] && A combatmode "$SH" passive "$([ "$PASSIVE0" = 1 ] && echo on || echo off)" >/dev/null
  [ -n "$RAIDG" ] && kill "$RAIDG" 2>/dev/null
  # the melee weapon goes back to the mate (an unequip with no room drops it: she picks it up by handle)
  local wr=""; [ -n "$WEP" ] && wr=$(A unequip "$SH" "$WEP"); [ -n "$BOWN" ] && bow_on >/dev/null
  if [ -n "$GIVEN" ]; then case "$wr" in *"-> ground"*) A pickup "$MT" "$(href "$wr")" now >/dev/null;; *) A transfer "$SH" "$MT" "$GIVEN" >/dev/null;; esac
  else case "$wr" in *"-> ground"*) A pickup "$SH" "$(href "$wr")" now >/dev/null;; esac; fi  # own weapon: back on the hip
  for c in "$SH" "$MT"; do A protect "$c" off >/dev/null; done
  A select "$SH" >/dev/null; A fp_control take >/dev/null
  A fp_camera distance "${DIST0:-0}" >/dev/null; A speed 1 >/dev/null
  [ -n "$FP0" ] && A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null
  [ "$ISO_SET" = 1 ] && A input_isolation off >/dev/null; }
trap cleanup EXIT

# ---- setup (bounded checks) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$MT"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ -r "$KFPLOG" ] || setup_fail "KenshiFP.log not readable at $KFPLOG (set KFPLOG=)"
LN0=$(wc -l < "$KFPLOG")
K=$(A fp_keys state)
grep -q 'speed_now=' <<<"$K" && grep -q 'mmb_self=' <<<"$K" || setup_fail "KenshiFP fp_keys state has no Gate 6 fields (needs 74b3408+): $(cut -c1-80 <<<"$K")"
grep -q '\bhook=1\b' <<<"$K" || setup_fail "fp_keys hook=0 (playerControl hook not installed)"
A fp_keys ctl | grep -q '^ctl shown=' || setup_fail "fp_keys ctl missing (needs 968a5f6+)"
A fp_combat state | grep -q 'spread_n=' || setup_fail "fp_combat state has no spread_n (needs 095837f+)"
if ! A input_isolation status | grep -q 'isolation=on'; then A input_isolation on >/dev/null; ISO_SET=1
  A input_isolation status | grep -q 'isolation=on' || setup_fail "input isolation would not turn on (mouse_inject/key_inject need it)"; fi
FP0=$(fps fp_mode); DIST0=$(cam target); AR0=$(cs auto_reload)
BOWN=$(A rangedinfo "$SH" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//'); [ "$BOWN" = none ] && BOWN=""
A speed 1 hold >/dev/null; A fp_move none >/dev/null; A fp_keys reset >/dev/null; A fp_keys swallow on >/dev/null
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done
PASSIVE0=$(A combatmode "$SH" | fld passive); A combatmode "$SH" passive on >/dev/null
TGH=""; if A where "$TG" | grep -q 'pos='; then TGH=$(A where "$TG" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  A pin "$TGH" at "$SH" dist 600 >/dev/null && PINNED+=" $TGH"; KEEP+=" $TGH"; KEEPN+=(-e "combat: $(live_name "$TGH") ("); fi
RK=$(sweep); note "SETUP raid sweep: knocked out $RK raiders within 1500 (kept:$KEEP)"; [ "$RK" -gt 0 ] 2>/dev/null && sleep 3
take "$SH" || setup_fail "could not take $SH ($(A fp_control state | cut -c1-160))"
A fp_camera distance 0 >/dev/null
H0=$(ctl controlled); HOME=$(pos "$SH"); MTN=$(live_name "$MT"); SHN=$(live_name "$SH")
note "SETUP sh=$SH($SHN) mt=$MT($MTN) tg=$TG$TGH bow='$BOWN' auto_reload=$AR0 home=$HOME controlled=$H0 iso_set=$ISO_SET kfplog_from=$LN0"
( while sleep 10; do kill -0 $$ 2>/dev/null || exit 0; n=$(sweep); [ "$n" = 0 ] || echo "RAID sweep $(date +%H:%M:%S): knocked out $n" >> "$LOG"; done ) </dev/null >/dev/null 2>&1 &
RAIDG=$!; SL0=$(slog_n)

# ---- viewmodel ----
VM_TOL=${VM_TOL:-4}; SHOTS=""
A fp_vm state | grep -q 'hooked=1' || setup_fail "fp_vm hooked=0 or missing (needs KenshiFP e515843+): $(A fp_vm state | cut -c1-100)"
A fp_vm state | grep -q ' mu=' || setup_fail "fp_vm state has no mu= field (needs the 2026-10-08 viewmodel build)"
A fp_vm on >/dev/null
trap 'A fp_vm set sw_pose -1 >/dev/null; A fp_vm set kick_pose -1 >/dev/null; A fp_vm set rlamp 1.6 >/dev/null; cleanup' EXIT
vfld() { A fp_vm state | fld "$1"; }
# vm_on <state>: vm in that state with the hand within VM_TOL deg of its target
vm_on() { local V; V=$(A fp_vm state); [ -z "$1" ] || [ "$(fld state <<<"$V")" = "$1" ] || return 1
  awk -v t="$(fld target <<<"$V")" -v e="$(fld elev <<<"$V")" -v a="$(fld az <<<"$V")" -v k="$VM_TOL" \
    'BEGIN{split(t,x,","); de=e-x[1]; da=a-x[2]; if(de<0)de=-de; if(da<0)da=-da; exit !(e!="" && t!="" && de<=k && da<=k)}'; }
vm_is() { [ "$(vfld state)" = "$1" ]; }
vev() { A fp_vm state | grep -oE '\b(state|elev|az|target|melee|tilt|swing|swu|swings)=[^ ]*' | tr '\n' ' '; }
shot() { local p; p=$(A screenshot "vm-$1" | grep -oE '[^ ]*\.png' | head -1); SHOTS+=" ${p##*[\/]}"; }
tilt_ge() { ge "$(vfld tilt)" "$1"; }
fire_done() { awk -v f="$(vfld fire)" 'BEGIN{exit !(f!="" && f+0<=0)}'; }   # the shot's aim hold (fire_hold) is over

# ---- PT13: crossbow ready / aim / reload ----
BOWOK=0; [ -n "$BOWN" ] && [ "$(bow_now)" != none ] && BOWOK=1
if want PT13; then if [ $BOWOK = 0 ]; then row PT13 FAIL "setup: no crossbow on $SH"; else
  draw_to 1 || note "SETUP PT13: R did not draw (drawn=$(ks drawn))"
  waitf 5 vm_on ready; R1=$(vm_on ready && echo 1 || echo 0); E1=$(vev); shot xbow-ready
  T1=$(vfld tilt); M1=$(vfld melee)
  look "$(cam yaw)" 0.05; mdown right; waitf 4 vm_on aiming; R2=$(vm_on aiming && echo 1 || echo 0); E2=$(vev); shot xbow-aim; mup right; sleep 0.4
  # m54: the controller arms only after one idle input frame (an aim already held never arms), so idle first
  EN0=$(cs enabled); A fp_combat on >/dev/null   # m55: why=off, the controller was never enabled here (fp-playtest enables it itself)
  A fp_combat input 0 0 0 >/dev/null; waitf 4 csis armed 1 || note "SETUP PT13 not armed after idle input (why=$(cs why))"
  A fp_combat input 1 0 0 >/dev/null; waitf 8 csis aimed 1; RL=0
  if waitf 20 csis shot_ready 1; then S=$(cs actual_shots); A fp_combat input 1 1 0 >/dev/null; waitf 3 csge actual_shots $((S+1))
    A fp_combat input 1 0 0 >/dev/null; waitf 8 vm_is reloading && { RL=1; sleep 0.5; shot xbow-reload; }; fi
  A fp_combat input 0 0 0 >/dev/null; A fp_combat physical >/dev/null
  ev="ready: $E1| aim: $E2| reload_seen=$RL"
  ok=1; [ "$R1" = 1 ] && [ "$M1" = 0 ] && awk -v t="$T1" 'BEGIN{exit !(t!="" && t<8 && t>-8)}' && [ "$R2" = 1 ] && [ $RL = 1 ] || ok=0
  judge PT13 $ok "$ev"; draw_to 0; fi; fi

# ---- PT26-PT29 helpers: measured weapon pose in camera numbers (x right, y up, z forward, dm from the UNZOOMED eye):
# mp = grip, mf = blade/bolt direction, mu = edge / crossbow top (fp_vm state, KenshiFP viewmodel 2026-10-08+) ----
declare -A VMP VMF VMU VST VSL
ZO=${ZO:-25}; ZO_TOL=${ZO_TOL:-0.3}; RATIO_MAX=${RATIO_MAX:-3.0}; AIMD=${AIMD:-400}; ZTAGS=""; ZW=0
zd_ok() { awk -v d="$(cam actual_distance)" -v w="$ZW" 'BEGIN{exit !(d!="" && (w==0 ? d<1 : d>=w*0.6))}'; }
# zoom <dist>: fp_camera distance, wait until the camera really sits there (collision may shorten it: >= 60%)
zoom() { local r; ZW=$1; A fp_camera distance "$1" >/dev/null; waitf 4 zd_ok; r=$?; sleep 0.6; return $r; }
# cap <tag>: record state/mp/mf/mu + screenshot vm-<tag>.png
cap() { local V; V=$(A fp_vm state); VSL[$1]=$V; VST[$1]=$(fld state <<<"$V"); VMP[$1]=$(fld mp <<<"$V"); VMF[$1]=$(fld mf <<<"$V"); VMU[$1]=$(fld mu <<<"$V")
  shot "$1"; case "$1" in *-zo) sleep 0.7; shot "$1-b";; esac  # zoomed out: a 2nd shot (4080: intermittent black screen-space boxes)
  note "CAP $1 $(grep -oE '\b(state|mp|mf|mu|elev|az|target|fire|kicks)=[^ ]*' <<<"$V" | tr '\n' ' ')"; }
# cap2 <tag>: cap zoomed in, then (PT29 wanted) at distance $ZO as <tag>-zo, back to 0
cap2() { cap "$1"; want PT29 || return 0
  if zoom "$ZO"; then cap "$1-zo"; ZTAGS+=" $1"; else note "SETUP zoom $ZO for $1 failed (actual_distance=$(cam actual_distance))"; fi; zoom 0; }
# vq "<awk condition>" <tag>: condition over px py pz fx fy fz ux uy uz, el/az (grip elevation/azimuth, deg)
vq() { awk -v P="${VMP[$2]}" -v F="${VMF[$2]}" -v U="${VMU[$2]}" "BEGIN{if(P==\"\"||F==\"\"||U==\"\")exit 1
  split(P,p,\",\");split(F,f,\",\");split(U,u,\",\");px=p[1];py=p[2];pz=p[3];fx=f[1];fy=f[2];fz=f[3];ux=u[1];uy=u[2];uz=u[3]
  el=atan2(py,pz)*57.2958; az=atan2(px,pz)*57.2958; exit !($1)}"; }
pev() { echo "$1:${VST[$1]} mp=${VMP[$1]} mf=${VMF[$1]} mu=${VMU[$1]}"; }
# xbgeo <tag>: crossbow (Oldworld Bow MkI, repeating) screen geometry from the captured state line. Body model in grip
# axes (f = bolt, u = top, s = f x u, dm): bolt tip 5.85f+0.84u, limb ends 5.0f+0.84u+-1.7s, fore-stock 4.8f, grip
# handle 0..0.3f-0.45u, magazine 0.3f+1.3u, stock 0..-3.9f at +0.3u. Screen: 1920x1080, half-FOV tan 0.70 (v) /
# 1.245 (h), HUD line y/z=-0.33, near clip 3 world units (points closer than NEAR=2.5 dm are not drawn).
# Prints "tx ty bmin cov omode oerr": bolt tip NDC, lowest on-screen body point y/z, arm_cov = upper arm + forearm
# area (radius 0.5 dm) inside the bottom-centre zone |x/z|<=0.436, -0.45<=y/z<=-0.05 / zone area (Lsh..Rwr joints).
xbgeo() { awk -v L="${VSL[$1]}" -v NEAR=2.5 -v R=0.5 '
  function g(k,  m){ if(match(" " L, " " k "=[^ ]*")){ m=substr(" " L,RSTART+1,RLENGTH-1); sub(/^[^=]*=/,"",m); return m } return "" }
  function pt(a,b,c){ n++; X[n]=p[1]+a*f[1]+b*u[1]+c*s[1]; Y[n]=p[2]+a*f[2]+b*u[2]+c*s[2]; Z[n]=p[3]+a*f[3]+b*u[3]+c*s[3] }
  function seg(a,b,  i,t,x,y,z,xs,ys,in_,px,py,pin){ pin=0; for(i=0;i<=40;i++){ t=i/40
     x=a[1]+(b[1]-a[1])*t; y=a[2]+(b[2]-a[2])*t; z=a[3]+(b[3]-a[3])*t; in_=0
     if(z>=NEAR){ xs=x/z; ys=y/z; in_=(xs>=-0.436&&xs<=0.436&&ys>=-0.45&&ys<=-0.05) }
     if(in_&&pin) area+=sqrt((xs-px)^2+(ys-py)^2)/0.7 * 2*R/z/0.7
     pin=in_; px=xs; py=ys } }
  BEGIN{ if(g("mp")==""||g("mf")==""||g("mu")=="") { print "x x x x x x"; exit }
   split(g("mp"),p,","); split(g("mf"),f,","); split(g("mu"),u,",")
   s[1]=f[2]*u[3]-f[3]*u[2]; s[2]=f[3]*u[1]-f[1]*u[3]; s[3]=f[1]*u[2]-f[2]*u[1]
   n=0; pt(5.85,0.84,0); pt(5.0,0.84,1.7); pt(5.0,0.84,-1.7); pt(4.8,0,0); pt(0,-0.45,0); pt(0.3,-0.45,0); pt(0.3,1.3,0)
   for(t=0;t>=-3.9;t-=0.3) pt(t,0.3,0)
   tx=X[1]/Z[1]/1.245; ty=Y[1]/Z[1]/0.7; miny=9
   for(i=1;i<=n;i++){ if(Z[i]<NEAR) continue; xs=X[i]/Z[i]; ys=Y[i]/Z[i]; if(xs<-1.245||xs>1.245||ys<-0.7) continue; if(ys<miny) miny=ys }
   area=0; cov="x"; for(si=1;si<=2;si++){ sd=si==1?"L":"R"; split(g(sd "sh"),S,","); split(g(sd "el"),E,","); split(g(sd "wr"),W,",")
     if(S[3]==""||E[3]==""||W[3]=="") { area=-1; break } seg(S,E); seg(E,W) }
   if(area>=0) cov=sprintf("%.3f", area/(0.872/0.7*0.4/0.7))
   om=g("omode"); oe=g("oerr"); printf "%.3f %.3f %.3f %s %s %s\n", tx, ty, miny, cov, om==""?"x":om, oe==""?"x":oe }'; }
# xq "<awk condition>" <tag>: condition over tx ty bmin cov om oe (xbgeo numbers)
xq() { local G; G=$(xbgeo "$2"); awk -v G="$G" "BEGIN{split(G,v,\" \"); for(i=1;i<=6;i++) if(v[i]==\"x\") exit 1
  tx=v[1]+0;ty=v[2]+0;bmin=v[3]+0;cov=v[4]+0;om=v[5]+0;oe=v[6]+0; exit !($1)}"; }
kfpn() { kfplines | grep -c "$1"; }
# vmrec <name> <xbow|sword|swing>: dump the fp_vm recording to $KDIR/vmrec-<name>.txt (copied to $OUT) and print
# vmcheck's one-line verdict (ok=0|1 frames vis fps flags errmax tipd_max df_max wih in/out [reload_zmin])
vmrec() { local f="$KDIR/vmrec-$1.txt"; rm -f "$f"; A fp_vm rec dump "vmrec-$1.txt" >/dev/null; waitf 5 test -s "$f"
  [ -s "$f" ] || { echo "ok=0 no dump $f"; return; }; cp "$f" "$OUT/" 2>/dev/null; python3 "$OUT/vmcheck.py" "$f" "$2" 2>&1 | tail -1; }

# ---- PT28: crossbow held like Skyrim/KCD (ready / aim / fire / reload, each zoomed in AND out for PT29) ----
if want PT28 || want PT29; then if [ $BOWOK = 0 ] || [ "$(bow_now)" = none ]; then rows_fail "no crossbow on $SH" PT28
else
  A fp_combat physical >/dev/null; A fp_vm set kick_pose -1 >/dev/null; A fp_vm set rlamp 0 >/dev/null; zoom 0
  draw_to 1 || note "SETUP PT28: R did not draw (drawn=$(ks drawn))"
  waitf 20 vm_on ready || note "SETUP PT28: not ready on target after draw ($(vev))"
  look "$(cam yaw)" 0.05; cap2 xbow-ready
  mdown right; waitf 20 vm_on aiming; cap2 xbow-aim
  A fp_vm set kick_pose 1 >/dev/null; sleep 0.5; cap2 xbow-fire; A fp_vm set kick_pose -1 >/dev/null; sleep 0.5
  # live shot zoomed in: kick + "[vm] fire" line, then the reload pose
  K0=$(vfld kicks); F0=$(kfpn '\[vm\] fire'); mclick left; waitf 3 eval '[ "$(vfld kicks)" -gt "$K0" ]'
  K1=$(vfld kicks); F1=$(kfpn '\[vm\] fire'); shot xbow-fire-live
  waitf 4 vm_is reloading || note "SETUP PT28: no reload after the shot ($(vev))"; waitf 2 fire_done; sleep 0.6; cap xbow-reload
  # live shot zoomed out (PT29 reload pair: same delay after the shot)
  if want PT29; then waitf 25 vm_is aiming || note "SETUP PT28: not aiming again after reload ($(vev))"
    if zoom "$ZO"; then K2=$(vfld kicks); mclick left; waitf 3 eval '[ "$(vfld kicks)" -gt "$K2" ]'; shot xbow-fire-live-zo
      waitf 4 vm_is reloading || note "SETUP PT29: no reload after the shot ($(vev))"; waitf 2 fire_done; sleep 0.6; cap xbow-reload-zo; ZTAGS+=" xbow-reload"; fi; zoom 0; fi
  mup right; sleep 0.4; A fp_vm set rlamp 1.6 >/dev/null
  ok=1; why=""
  # ready: low right, forward, top up, the whole crossbow above the HUD line (lowest on-screen body point y/z >= -0.33)
  { [ "${VST[xbow-ready]}" = ready ] && vq "fz>=0.9 && uy>=0.9 && az>=10" xbow-ready && xq "bmin>=-0.33" xbow-ready; } || { ok=0; why+=" ready"; }
  # aim (zoomed in and out): seen from behind, stock up from the bottom centre (grip low, 2-2.9 dm ahead), limbs horizontal (top up), bolt on the
  # crosshair (<=2 deg at AIMD), bolt tip projected within a few % of the screen centre (sight just below it), off-hand
  # on the support point under the fore-stock (omode=1, oerr<=0.5 dm), no forearm/sleeve blob bottom centre (arm_cov<=0.15)
  for t in xbow-aim xbow-aim-zo; do [ "$t" = xbow-aim ] || [ -n "${VSL[$t]}" ] || continue
    { [ "${VST[$t]}" = aiming ] && vq "fz>=0.99 && uy>=0.95 && px*px<=0.25 && pz>=2.0 && pz<=2.9 && py<=-0.9 &&       (-fx*px - fy*py + fz*($AIMD-pz)) / sqrt(px*px+py*py+($AIMD-pz)^2) >= 0.99939" $t &&       xq "tx<=0.06 && tx>=-0.06 && ty>=-0.08 && ty<=0.02 && om==1 && oe<=0.5 && cov<=0.15" $t; } || { ok=0; why+=" $t"; }; done
  # fire (frozen kick_pose 1 = kick peak): muzzle climbs (fy>=0.05, tip 0..0.4 above centre, |x|<=0.1), the grip stays
  # within 0.5 dm of the aim hold (not in the face); live LMB: kicks + "[vm] fire" line
  AZ=$(awk -v P="${VMP[xbow-aim]}" 'BEGIN{split(P,p,",");print p[3]-0.5}')
  { vq "fy>=0.05 && pz>=$AZ" xbow-fire && xq "tx<=0.1 && tx>=-0.1 && ty>=0 && ty<=0.4" xbow-fire && [ "$K1" -gt "$K0" ] && [ "$F1" -gt "$F0" ]; } || { ok=0; why+=" fire(kicks $K0->$K1 lines $F0->$F1)"; }
  # reload: lowered and pointing forward (not raised into the face)
  { [ "${VST[xbow-reload]}" = reloading ] && vq "el<=-10 && fz>=0.8 && pz>=2.0" xbow-reload; } || { ok=0; why+=" reload"; }
  GEO="geo(tx ty bmin cov om oe) ready=[$(xbgeo xbow-ready)] aim=[$(xbgeo xbow-aim)] aim-zo=[$(xbgeo xbow-aim-zo)] fire=[$(xbgeo xbow-fire)]"
  judge PT28 $ok "$(pev xbow-ready) | $(pev xbow-aim) | $(pev xbow-fire) kicks=$K0->$K1 | $(pev xbow-reload) | $GEO${why:+ | bad:$why}"
  draw_to 0; fi; fi
# ---- PT30 crossbow part: every frame of draw, aim, fire, reload, ready, aim, holster (fp_vm rec) ----
if want PT30; then if [ $BOWOK = 0 ] || [ "$(bow_now)" = none ]; then P30X="ok=0 setup: no crossbow on $SH"
  else A fp_combat physical >/dev/null; zoom 0; draw_to 0; sleep 1; look "$(cam yaw)" 0.05; A fp_vm rec on >/dev/null; sleep 0.5
    rkey; sleep 2.2; mdown right; sleep 2; mclick left; sleep 9; mup right; sleep 1.5; mdown right; sleep 0.8; mup right; sleep 1.5
    rkey; sleep 2.2; A fp_vm rec off >/dev/null; P30X=$(vmrec pt30-xbow xbow); fi; fi

# ---- PT14: sword ready / block / swing / arc ----
if want PT14; then draw_to 0
  give_melee || note "SETUP: could not give $SH a melee weapon"; bow_off || note "SETUP: bow would not unequip ($(bow_now))"
  if ! arm_melee; then row PT14 FAIL "setup: no melee weapon equips on $SH (inv: $(weapons | tr '\n' ';'))"; else
    draw_to 1 || note "SETUP PT14: R did not draw (drawn=$(ks drawn))"
    waitf 5 vm_on ready; waitf 3 tilt_ge 20; R1=$(vm_on ready && echo 1 || echo 0); E1=$(vev); M1=$(vfld melee); T1=$(vfld tilt); shot sword-ready
    look "$(cam yaw)" 0.05; mdown right; waitf 4 vm_on blocking; R2=$(vm_on blocking && echo 1 || echo 0); E2=$(vev); shot sword-block; mup right; sleep 0.5
    SW0=$(kfplines | grep -c '\[vm\] swing'); mclick left; waitf 4 eval '[ "$(kfplines | grep -c "\[vm\] swing")" -gt "$SW0" ]'
    SWL=$(kfplines | grep '\[vm\] swing' | tail -1); [ "$(kfplines | grep -c '\[vm\] swing')" -gt "$SW0" ] || SWL=""
    UE=$(grep -o 'u_end=[0-9.]*' <<<"$SWL" | cut -d= -f2)
    RT=$(fld target <<<"$E1")
    A fp_vm set sw_pose 0 >/dev/null; sleep 1; P0=$(vm_on "" && echo 1 || echo 0); T0=$(vfld target); shot sword-swing0
    A fp_vm set sw_pose 0.5 >/dev/null; sleep 1; shot sword-swing05
    A fp_vm set sw_pose 1 >/dev/null; sleep 1; P1=$(vm_on "" && echo 1 || echo 0); TE=$(vfld target); shot sword-swing1
    A fp_vm set sw_pose -1 >/dev/null
    ev="ready: $E1| block: $E2| swing_line='$(cut -c1-80 <<<"$SWL")' | pose0 on=$P0 target=$T0 pose1 on=$P1 target=$TE"
    ok=1; [ "$R1" = 1 ] && [ "$M1" = 1 ] && ge "$T1" 20 && [ "$R2" = 1 ] && [ -n "$SWL" ] && ge "$UE" 0.5 || ok=0
    [ "$P0" = 1 ] && [ "$T0" = "$RT" ] && [ "$P1" = 1 ] && [ "$TE" = "$RT" ] || ok=0
    judge PT14 $ok "$ev"; draw_to 0; fi; fi

# ---- PT27: block = blade horizontal across the view (zoomed in and out) ----
if want PT27 || want PT26 || want PT29 || want PT30; then
  if ! { [ -n "$WEP" ] || { draw_to 0; give_melee; bow_off; arm_melee; }; }; then rows_fail "no melee weapon equips on $SH" PT26 PT27; P30S="ok=0 setup: no melee weapon"
  else zoom 0; draw_to 1 || note "SETUP PT26/27: R did not draw (drawn=$(ks drawn))"; waitf 5 vm_on ready
    look "$(cam yaw)" 0.05; cap2 sword-ready
    if want PT27 || want PT29; then mdown right; waitf 4 vm_on blocking; cap2 sword-block; mup right; sleep 0.5
      ok=1; for t in sword-block sword-block-zo; do [ -n "${VMP[$t]}" ] || continue
        { [ "${VST[$t]}" = blocking ] && vq "fx*fx>=0.72 && fy*fy<=0.04" "$t"; } || ok=0; done
      want PT27 && judge PT27 $ok "$(pev sword-block) | $(pev sword-block-zo)"; fi

# ---- PT26: smooth full swing top-right -> bottom-left: frozen frame sequence + real swings (per-frame [vmsw] log) ----
    if want PT26 || want PT29; then
      SEQ=""; for u in ${SW_US:-0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90}; do A fp_vm set sw_pose "$u" >/dev/null; sleep 0.5
        cap "sword-sw$u"; SEQ+=" $u:$(vfld target)"; done
      A fp_vm set sw_pose 0.42 >/dev/null; sleep 0.5; cap2 sword-sw0.42; A fp_vm set sw_pose -1 >/dev/null; sleep 0.6
      ok=1; ev=""; NSW=${NSW:-3}
      for i in $(seq 1 "$NSW"); do waitf 3 vm_is ready
        S0=$(kfpn '\[vm\] swing #'); mclick left; waitf 4 eval '[ "$(kfpn "\[vm\] swing #")" -gt "$S0" ]'
        L=$(kfplines | grep '\[vm\] swing #' | tail -1); [ "$(kfpn '\[vm\] swing #')" -gt "$S0" ] || { ok=0; ev+=" swing$i: no [vm] swing line;"; continue; }
        n=$(grep -oE 'swing #[0-9]+' <<<"$L" | grep -oE '[0-9]+')
        # order: the highest grip frame (wind-up, top) comes before the leftmost one (follow-through)
        ORD=$(kfplines | grep "\[vmsw\] #$n " | sed 's/.*meas=\([^ ]*\).*/\1/' | awk -F, '{e=atan2($2,$3); a=atan2($1,$3)
          if(NR==1||e>me){me=e;ie=NR} if(NR==1||a<ma){ma=a;ia=NR}} END{print (ie<ia)?"top->left":"BAD(top@" ie ",left@" ia ")"}')
        # phases: blade deg/s per frame (measured mf of line k = the frame of line k-1: divided by that dt)
        PH=$(kfplines | grep "\[vmsw\] #$n " | awk 'function g(s,k){match(s,k"=[^ ]*");return substr(s,RSTART+length(k)+1,RLENGTH-length(k)-1)}
          {n++; split(g($0,"mf"),f,","); split(g($0,"meas"),m,","); e=atan2(m[2],m[3]); a=atan2(m[1],m[3])
           if(n==1||e>me){me=e;ie=n} if(n==1||a<ma){ma=a;ia=n}
           if(n>1){d=f[1]*p[1]+f[2]*p[2]+f[3]*p[3]; l=sqrt((f[1]^2+f[2]^2+f[3]^2)*(p[1]^2+p[2]^2+p[3]^2)); c=l>0?d/l:1; c=c>1?1:(c<-1?-1:c)
             r[n]=atan2(sqrt(1-c*c),c)*57.29578/(pd>1e-4?pd:1e-4)} pd=g($0,"dt")+0; p[1]=f[1];p[2]=f[2];p[3]=f[3]}
          END{w=0;wn=0;for(i=2;i<=ie;i++){w+=r[i];wn++} s=0;sn=0;for(i=ie+1;i<=ia;i++){s+=r[i];sn++}
            w=wn?w/wn:0; s=sn?s/sn:0; fr=n?ie/n:0; ok=(n>=8 && fr>=0.15 && fr<=0.5 && s>=2*w && s>0)
            printf "%s wind=%.0f strike=%.0f windup=%.0f%%\n", ok?"phases":"BADPHASES", w, s, fr*100}')
        if ! awk -v l="$L" -v rm="$RATIO_MAX" 'BEGIN{
            if(!match(l,/u_end=[0-9.]+/))exit 1; u=substr(l,RSTART+6,RLENGTH-6)+0
            match(l,/frames=[0-9]+/); fr=substr(l,RSTART+7,RLENGTH-7)+0; match(l,/ratio=[0-9.]+/); r=substr(l,RSTART+6,RLENGTH-6)
            match(l,/elev=[-0-9.]+\.\.[-0-9.]+/); split(substr(l,RSTART+5,RLENGTH-5),e,/[.][.]/)
            match(l,/az=[-0-9.]+\.\.[-0-9.]+/); split(substr(l,RSTART+3,RLENGTH-3),a,/[.][.]/)
            exit !(u>=1 && fr>=8 && e[2]>=0 && a[1]<=-5 && a[2]>=20)}' || [ "$ORD" != top-\>left ] || [ "${PH%% *}" != phases ]; then ok=0; fi
        ev+=" swing$i: $(grep -oE '(swing #[0-9]+ [0-9.]+s|frames|ratio|maxstep|elev|az)=?[^ ]*' <<<"$L" | tr '\n' ' ')$ORD $PH;"
      done
      # live proof in screenshots: one physical LMB swing slowed to SLOW_DUR s (same live path, only the clock
      # is stretched), screenshot + swing progress u every step: u must rise monotonically over >= 5 shots
      waitf 3 vm_is ready; A fp_vm rec on >/dev/null; sleep 0.3; mclick left; sleep 1.2; A fp_vm rec off >/dev/null
      LIVE=$(vmrec pt26 swing); case "$LIVE" in ok=1*) ;; *) ok=0;; esac; ev+=" every-frame: $LIVE;"
      want PT26 && judge PT26 $ok "$ev frozen u:target(elev,az)$SEQ"; fi
    if want PT30; then draw_to 0; sleep 1; look "$(cam yaw)" 0.05; A fp_vm rec on >/dev/null; sleep 0.5
      rkey; sleep 2.2; mclick left; sleep 1.2; mclick left; sleep 1.2; mdown right; sleep 1.2; mup right; sleep 1
      A mouse_inject left click 60 >/dev/null; sleep 0.15; mdown right; sleep 1; mup right; sleep 1
      rkey; sleep 2.2; A fp_vm rec off >/dev/null; P30S=$(vmrec pt30-sword sword); fi
    draw_to 0; fi; fi

if want PT30; then ok=1; case "$P30X" in ok=1*) ;; *) ok=0;; esac; case "$P30S" in ok=1*) ;; *) ok=0;; esac
  judge PT30 $ok "xbow: ${P30X:-not run} | sword: ${P30S:-not run}"; fi

# ---- PT29: zooming out keeps the same hold (grip within ZO_TOL dm, blade within 5 deg, same state) ----
if want PT29; then ok=1; ev=""; [ -n "$ZTAGS" ] || ok=0
  for t in $ZTAGS; do z="$t-zo"
    d=$(awk -v a="${VMP[$t]}" -v b="${VMP[$z]}" 'BEGIN{split(a,p,",");split(b,q,",");printf "%.2f", sqrt((p[1]-q[1])^2+(p[2]-q[2])^2+(p[3]-q[3])^2)}')
    g=$(awk -v a="${VMF[$t]}" -v b="${VMF[$z]}" 'BEGIN{split(a,p,",");split(b,q,",");c=p[1]*q[1]+p[2]*q[2]+p[3]*q[3];if(c>1)c=1;if(c<-1)c=-1;printf "%.1f", atan2(sqrt(1-c*c),c)*57.2958}')
    s="ok"; { [ -n "${VMP[$t]}" ] && [ -n "${VMP[$z]}" ] && [ "${VST[$t]}" = "${VST[$z]}" ] && awk -v d="$d" -v g="$g" -v k="$ZO_TOL" 'BEGIN{exit !(d<=k && g<=5)}'; } || { s="BAD"; ok=0; }
    ev+=" $t:${VST[$t]}/${VST[$z]} dp=$d df=${g}deg $s;"; done
  judge PT29 $ok "zoom $ZO vs 0:$ev"; fi

echo "NOTE PT17 viewmodel screenshots (harness shots dir):$SHOTS" >> "$LOG"
finish; echo "NOTE PT17 screenshots:$SHOTS"
