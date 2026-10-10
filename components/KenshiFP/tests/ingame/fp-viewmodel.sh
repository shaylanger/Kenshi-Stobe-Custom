#!/usr/bin/env bash
# fp-viewmodel.sh: KenshiFP Gate 6 viewmodel rows PT13/PT14/PT26-PT30 (COMBAT_TEST_PLAN.md) on a kah-fpxbow copy
# (Axima = crossbow player, Malzin = mate with a melee weapon). Helpers + setup are fp-playtest.sh's (same build).
#  PT13  crossbow: physical R draw -> fp_vm state=ready, hand within VM_TOL deg of the ready target, melee=0, tilt -27..-6 (PT28 low carry);
#        RMB held -> state=aiming on the aim target; one injected shot -> state=reloading seen
#  PT14  sword (bow off, sword from the mate): R draw -> ready on target, melee=1, tilt >= 20; RMB held -> blocking on
#        the block target; physical LMB -> a new "[vm] swing" log line with u_end >= 0.5; test pose sw_pose 0 / 1 ->
#        target = the ready target (the swing path starts and ends at the ready pose)
#  PT28  crossbow like Chivalry 2 (reference photos/crossbow aiming.PNG), each state zoomed in AND out: ready (low
#        carry right: grip >=4 dm ahead, az>=15, nose 6..27 deg down, top up, low carry mostly behind the bottom bar (Shay
#        2026-10-10 spec-videos: keep r_ready_py -4.0): lowest projected body point y/z >= -0.70, bolt tip y >= -0.80 NDC,
#        limb line below the centre, right wrist in front of the near clip rwz>=3.3),
#        aim (grip at the eye plane |z|<=1, |x|<=0.3, low (y<=-1.4): nothing of the hands drawn (wrists behind the near
#        clip: rwz<=2.6, lwz<=2.8, arm_cov<=0.02), bolt <=2 deg off the crosshair at AIMD, projected bolt tip within
#        |x|<=0.06 NDC and 0.05..0.25 below the centre, limb line y/z -0.30..-0.10 (lower third) with half span x/z >=0.6,
#        off-hand on the support point), fire (physical LMB: kicks + "[vm] fire" line; frozen kick_pose 1 = muzzle climb
#        tip -0.1..0.4 NDC, grip within 0.3 dm of the aim hold), reload (grip >=4 dm ahead, nose down >=14 deg, top
#        rolled toward the eye uz<=-0.3, limb line above the HUD line, right wrist in front of the near clip)
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
#        enters (draw) and leaves (holster) the hand below the view, crossbow reload grip z >= 2.0 (not in the face),
#        and no near-plane cut (PT17): cut=0, no rendered frame where the 3 dm near clip slices an arm tube (upper arm,
#        forearm r 0.45, hand r 0.35, from the recorded joints) at a point inside the screen (hollow / cut-off limb);
#        sword wrist (PT17 wrist fold): forearm (elbow->wrist) vs hand bone X <= WB_MAX (30) deg on every on-screen
#        viewmodel frame (wb_max=..@frame:state; wb_xbow = crossbow value, reported only)
#  PT29  zoom out (fp_camera distance ZO=25): the native third-person animations take over (zf<=0.05) and look natural:
#        per recorded zoomed frame head >= 2.5 dm from the grip (not aiming), torso >= 1.0, blade visible length >= 0.06
#        (not hidden by head/torso), wrist <= 30 deg, elbow not above the shoulder (+0.5, swing prog < 0.5 excepted);
#        FAIL if > 3% of the frames are bad (uses VMQUICK's zoom-25 segments when VMQUICK ran first)
#  VMQUICK (run first on every viewmodel build, ~3 min): each weapon at zoom 0 AND ZO: draw/ready/walk/aim-fire-reload
#        (crossbow) or ready/walk/block/wind-up/strike/follow-through/swing/swing->block (sword)/holster, recorded per
#        segment (zoom 0 = PT30 vmcheck incl. the wrist check, zoom 25 = the PT29 checks) + one labelled sheet
#        (vmquick-sheet.jpg, final-<weapon>-zoom<0|25>.jpg via vm-sheet.py); VMQ_BEFORE=1 = wfix 0 zfade 0 (0750f26a
#        behaviour), VMQ_FRAMES=1 = every frame of one zoom-0 swing (swing-frames.jpg)
# Screenshots (vm-*.png, harness shots dir) are listed in a NOTE line: PT17 (overall look) is judged from them.
# Usage: fp-viewmodel.sh [player] [mate] [hostile] [outdir]. Env: ROWS (comma/space list, default all), KFPLOG,
# KDIR (Kenshi dir; Git Bash rig: "/c/Program Files (x86)/Steam/steamapps/common/Kenshi"), PY (python, default python3), VM_TOL (4), WB_MAX (30), VMQ_BEFORE, VMQ_FRAMES, ZO, ZO_TOL, RATIO_MAX, NSW, SW_US, SLOW_DUR. Example: ROWS=PT26,PT27,PT28,PT29 bash fp-viewmodel.sh
# Needs KenshiFP with the 2026-10-08 viewmodel (fp_vm state mu= field, [vm] fire / swing ratio= log lines).
# Leaves the fixture changed (a shot fired, items moved): reload it after.
SH=${1:-${PLAYER:-Axima}}; MT=${2:-${MATE:-Malzin}}; TG=${3:-${HOSTILE:-Skaera}}; OUT=${4:-/tmp/fp-viewmodel}
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}; PY=${PY:-python3}; KFPLOG=${KFPLOG:-$KDIR/KenshiFP.log}
STILL_MAX=${STILL_MAX:-3}; SPIKE_MAX=${SPIKE_MAX:-1.5}; FAR_NPC=${FAR_NPC:-}
ROWS=${ROWS:-"PT13 PT14 PT26 PT27 PT28 PT29 PT30"}; ROWS=${ROWS//,/ }
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"; rm -f "$LOG.sweepc"
cat > "$OUT/vmcheck.py" <<'VMCHECK'
import sys, math, os
# vmcheck.py <rec.txt> <xbow|sword|seg|swing|zo>: every-frame viewmodel check of an fp_vm rec dump (PT30); seg = sword without the draw+holster pair (VMQUICK splits around the frozen poses). Prints one line:
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
    r=dict(t=float(h[1]),dt=float(h[2]),st=h[3],ti=int(h[4]),cls=int(h[5]),w=float(h[7]),kick=float(h[11]),fire=float(h[12]),op=v[0],mp=v[4],mf=v[5],mu=v[6],
           cam=[V(x) for x in pa[2].split()] if len(pa)>2 else None,ph=0,wih=1,j=v[7:13] if len(v)>=13 else None)
    if len(pa)>3:
        x=pa[3].split()
        if len(x)>=5: r['ph']=int(x[3]); r['wih']=int(x[4])
    r['zoom']=float(h[16]); r['sw']=int(h[8]); r['prog']=float(h[10]); r['wb']=None
    if len(pa)>4:   # KenshiFP PT17 wrist build: wb mh mfx [zf head neck spine]
        x=pa[4].split(); r['wb']=float(x[0]); r['mh']=V(x[1])
        if len(x)>=7: r['zf']=float(x[3]); r['hd']=V(x[4]); r['nk']=V(x[5]); r['sp']=V(x[6])
    F.append(r)
WBM=float(os.environ.get('WB_MAX','30'))
# Shay 2026-10-10: frames that play the NATIVE animation (viewmodel weight w*zf <= 0.05 = the game's own pose, or an NA1
# native-retarget frame, rec field na=1) are exempt from the wrist-bend limit; it holds for solver-posed frames only.
def native(r): return r['w']*r.get('zf',1.0)<=0.05 or r.get('na')==1
# ---- zo: the zoomed-out view (PT29, fp_camera distance >= ZO_MIN) must show a person holding the weapon (native third-
# person animation, viewmodel faded out). Per frame, from the recorded bones (camera numbers, unzoomed eye) and the
# zoomed camera (eye - fw*zoom): zf<=0.05 (viewmodel off); right wrist + grip >= HD_MIN (2.0 dm; the bug was 1.0, the native
# crossbow reload reaches 2.37) from the head centre (head bone + 0.9 dm along neck->head; not while aiming: a crossbow
# stock at the cheek is the natural aim); both
# wrists >= TOR_MIN (1.0 dm) from the spine->neck axis (no hand inside the torso); weapon visible: projected length of
# the grip->tip line not hidden behind the head (r 1.3) / torso (r 1.7) capsule >= VIS_MIN (0.06 tan units, ~4% of the
# screen height); with the viewmodel off (zf<=0.05, the game's own third-person animation) instead >= 5 of the 21
# grip->tip points on screen: seen from behind, a weapon held/aimed in front of the body is naturally end-on or behind
# the torso/head, and the reported bug (weapon in the head) is caught by the head distance; sword wrist bend <= WB_MAX
# (the crossbow wrist is not limited at zoom 0 either); right elbow at most 0.5 dm above the right shoulder (world up) except the first
# half of a swing (wind-up). A check fails when more than 3% of the zoomed-out frames break it (draw/holster blends).
if sys.argv[2]=='zo':
    ZMIN=float(os.environ.get('ZO_MIN','15')); HDM=float(os.environ.get('HD_MIN','2.0')); TORM=float(os.environ.get('TOR_MIN','1.0'))
    VISM=float(os.environ.get('VIS_MIN','0.06')); BLZ={0:8.0,1:5.85}
    def nz(a): l=ln(a); return mul(a,1/l) if l>1e-6 else a
    def segd(P,A,B):
        d=sub(B,A); L=dot(d,d); t=0 if L<1e-9 else max(0,min(1,dot(sub(P,A),d)/L)); return ln(sub(P,add(A,mul(d,t))))
    def prj(P,C):
        q=sub(P,C); return (q[0]/q[2],q[1]/q[2],q[2]) if q[2]>0.1 else None
    def d2seg(s,a,b):
        dx,dy=b[0]-a[0],b[1]-a[1]; L=dx*dx+dy*dy; t=0 if L<1e-12 else max(0,min(1,((s[0]-a[0])*dx+(s[1]-a[1])*dy)/L))
        return math.hypot(s[0]-a[0]-t*dx,s[1]-a[1]-t*dy), a[2]+t*(b[2]-a[2])
    Z=[r for r in F if r['zoom']>=ZMIN and r['wih'] and 'hd' in r and r['j']]
    bad={}; mn=dict(hd=99.0,tor=99.0,vis=99.0,npt=99); mx=dict(zf=0.0,wb=0.0,elb=-99.0)
    for i,r in enumerate(Z):
        cam=r['cam']; upw=nz((cam[1][1],cam[2][1],cam[3][1])) if cam else (0,1,0); C=(0,0,-r['zoom'])
        J=r['j']; Lwr,Rsh,Rel,Rwr=J[2],J[3],J[4],J[5]
        hc=add(r['hd'],mul(nz(sub(r['hd'],r['nk'])),0.9))
        hd=min(ln(sub(Rwr,hc)),ln(sub(r['mp'],hc))); tor=min(segd(Rwr,r['sp'],r['nk']),segd(Lwr,r['sp'],r['nk']))
        ph,ps_,pn=prj(hc,C),prj(r['sp'],C),prj(r['nk'],C); vis=0.0; prev=None; npt=0
        for k in range(21):
            s_=prj(add(r['mp'],mul(r['mf'],BLZ[r['cls']]*k/20)),C); ok_=False
            if s_ and abs(s_[0])<1.245 and abs(s_[1])<0.70:
                ok_=True
                if ph and math.hypot(s_[0]-ph[0],s_[1]-ph[1])<1.3/ph[2] and s_[2]>ph[2] and r['zf']>0.05: ok_=False
                if ps_ and pn:
                    dd,dep=d2seg(s_,ps_,pn)
                    if dd<1.7/max(dep,0.1) and s_[2]>dep and r['zf']>0.05: ok_=False
            npt+=ok_
            if ok_ and prev: vis+=math.hypot(s_[0]-prev[0],s_[1]-prev[1])
            prev=s_ if ok_ else None
        elb=dot(sub(Rel,Rsh),upw); wind=r['st']=='swinging' and r['prog']<0.5
        mn['hd']=min(mn['hd'],hd) if r['st']!='aiming' else mn['hd']; mn['tor']=min(mn['tor'],tor); mn['vis']=min(mn['vis'],vis); mn['npt']=min(mn['npt'],npt)
        mx['zf']=max(mx['zf'],r['zf']); mx['wb']=max(mx['wb'],(r['wb'] or 0) if not native(r) else 0); mx['elb']=max(mx['elb'],elb if not wind else -99)
        for k,c in (('zf',r['zf']>0.05),('head',hd<HDM and r['st']!='aiming'),('torso',tor<TORM),('vis',vis<VISM if r['zf']>0.05 else npt<5),
                    ('wrist',r['cls']==0 and (r['wb'] or 0)>WBM and not native(r)),('elbow',elb>0.5 and not wind)):
            if c: bad.setdefault(k,[]).append('%d:%s'%(i,r['st']))
    N=len(Z); fails={k:v for k,v in bad.items() if len(v)>0.03*N}
    ok=N>=30 and not fails
    # sword arm motion (m78, Shay: at zoom 25 block / swings showed no animation, right arm hanging at the hip: wrist-minus-
    # shoulder stayed at one value through the block, each swing lasted 2 frames): per block run (st blocking) and per swing
    # run (swing flag), the max displacement of the right wrist relative to the right shoulder from the mean of the last 5
    # ready frames before it; every segment must reach ARM_MIN (1.0 dm), the RESULT prints the per-segment values
    AMIN=float(os.environ.get('ARM_MIN','1.0')); arm=[]; ready=[]; seg=None
    def rel(r): return sub(r['j'][5],r['j'][3])
    for r in Z+[None]:
        k=None if r is None or r['cls']!=0 else ('blk' if r['st']=='blocking' else 'sw' if r['sw'] else None)
        if seg and k!=seg[0]:
            ref=seg[2]; arm.append((seg[0],max(ln(sub(x,ref)) for x in seg[1]),len(seg[1]))); seg=None
        if r is None: break
        if k and seg is None and ready:
            R=ready[-5:]; seg=(k,[],mul((sum(x[0] for x in R),sum(x[1] for x in R),sum(x[2] for x in R)),1.0/len(R)))
        if k and seg: seg[1].append(rel(r))
        if r['cls']==0 and r['st']=='ready' and not r['sw']: ready.append(rel(r))
    if any(r['cls']==0 for r in Z):
        if not arm or any(a[1]<AMIN for a in arm): ok=False
    atxt=(' arm=%s(min %.1f)'%(','.join('%s%.2f/%df'%(a[0],a[1],a[2]) for a in arm) or 'none',AMIN)) if any(r['cls']==0 for r in Z) else ''
    print("ok=%d zo_frames=%d zf_max=%.2f head_min=%.2f torso_min=%.2f vis_min=%.3f pts_min=%d wb_max=%.1f elb_max=%.2f bad=%s%s" % (ok,N,mx['zf'],mn['hd'],
          mn['tor'],mn["vis"],mn["npt"],mx["wb"],mx['elb'],','.join('%s:%d/%d@%s'%(k,len(v),N,v[0]) for k,v in sorted(bad.items())) or 'none',atxt))
    sys.exit(0)
F=[r for r in F if r['zoom']<0.5]   # zoom-0 checks: the viewmodel frames only
def remap(c,a,b,pos):
    if a['cam'] is None or b['cam'] is None: return c
    e,rt,up,fw=b['cam']; w=add(add(mul(rt,c[0]),mul(up,c[1])),mul(fw,c[2])); w=add(w,e) if pos else w
    e,rt,up,fw=a['cam']; d=sub(w,e) if pos else w; return (dot(d,rt),dot(d,up),dot(d,fw))
# near-plane cut (PT17): the 3 dm near clip slices an arm tube (joints shoulder-elbow-wrist r 0.45, hand wrist->grip
# x1.4 r 0.35; cross-section along z slant-corrected) at a point inside the screen = a hollow / cut-off limb in view.
# The plane is the game's: 3 dm, 1.5 dm while the ranged viewmodel is shown (X2, KenshiFP g_vm_nc; env VM_NC_R).
RF,RH=0.45,0.35; ZCS={0:3.0,1:float(os.environ.get('VM_NC_R','1.5'))}
def cutseg(P,Q,r,ZC=3.0):
    d=sub(Q,P); L=ln(d)
    if L<1e-4: return False
    dz=abs(d[2])/L; rz=r*math.sqrt(max(0.0,1-dz*dz))+0.02; pp=P
    for k in range(41):
        p=add(P,mul(d,k/40.0))
        if (abs(p[2]-ZC)<rz or (k and (p[2]-ZC)*(pp[2]-ZC)<0)) and min(1.245-abs(p[0]/ZC),0.70-abs(p[1]/ZC))>0.02: return True
        pp=p
    return False
cuts=[]
for i in range(len(F)-1):
    a,b=F[i],F[i+1]; a['rp']=remap(b['mp'],a,b,1); a['rf']=remap(b['mf'],a,b,0); a['ru']=remap(b['mu'],a,b,0)
    if a['w']>=0.01 and b['j']:
        J=[remap(x,a,b,1) for x in b['j']]; W=J[5]
        segs=((J[3],J[4],RF),(J[4],W,RF),(W,add(W,mul(sub(a['rp'],W),1.4)),RH),(J[0],J[1],RF),(J[1],J[2],RF))
        if any(cutseg(P,Q,r,ZCS.get(a['cls'],3.0)) for P,Q,r in segs): cuts.append('%d:%s'%(i,a['st']))
F=F[:-1]; N=len(F)
DTH=max(0.045,3.0*sorted(r["dt"] for r in F)[len(F)//2]) if F else 0.07   # hitch: > 3x the median frame time (0.055 s frames at ~70 fps under load also jump; was a fixed 0.07)
BL={0:8.0,1:5.85}
def tip(r): return add(add(r['rp'],mul(r['rf'],BL[r['cls']])),mul(r['ru'],0.84 if r['cls']==1 else 0))
def onscr(c): return c[2]>=2.5 and abs(c[1])/c[2]<0.70 and abs(c[0])/c[2]<1.245
for i,r in enumerate(F):
    r['vis']=r['wih']!=0 and (onscr(r['rp']) or onscr(tip(r)))
    p=F[i-1] if i else r
    r['tipd']=ln(sub(tip(r),tip(p))); r['df']=ang(r['rf'],p['rf']); r['du']=ang(r['ru'],p['ru'])
    tl=r['t'] if (r['st']!='reloading' or r['op'][2]<1.0 or r['fire']>0 or r['kick']>0 or i==0) else tl; r['rlt']=r['t']-tl   # s since the post-shot aim hold ended (reload blend-in excluded)
flags=[]; errmax=0.0; errat="-"; t2=-9.0; rlz=99.0; nvis=0; tipmax=0.0; dfmax=0.0
for i in range(1,N-1):
    a,b,c=F[i-1],F[i],F[i+1]
    if not b['vis']: continue
    nvis+=1
    if b["st"]=="reloading" and b["ti"]==2: t2=b["t"]
    if b["w"]>=0.999 and b["ph"]==0 and b["t"]-t2>0.25:   # X3 native reload (ti 2 + its 0.2 s rlblend fade-out): hand = native crank
                                                       # (C4c clamps), not op; checked by cut/reload_zmin/moves instead
        e=ln(sub(b["rp"],b["op"]))
        if e>errmax: errmax=e; errat="%d:%s"%(i,b["st"])
    if b['cls']==1 and b['st']=='reloading' and b['ti']==2 and b['rlt']>=0.4: rlz=min(rlz,b['rp'][2])
    # C4d: rlt also restarts while a reload from ready holds the AIM pose (op z<1, at the eye) for the native raise
    if not a['vis'] or max(a['dt'],b['dt'],c['dt'])>DTH: continue   # entering the view / game hitch frame or next to one (motion is
                                                       # per time; a hitch neighbour's step averages over a peak, PT17 m77 f228)
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
else: ok=N>=200 and nvis>=100 and not flags and errmax<=0.35 and all(x.endswith('off') for x in inout) and len(inout)>=(1 if sys.argv[2]=='seg' else 2)
if sys.argv[2]=='xbow': ok=ok and rlz>=2.0
ok=ok and not cuts
# C1 (Shay 2026-10-09: the crossbow aim stayed in the ready pose and the row still passed): every state that should move
# the weapon must VISIBLY differ from ready (viewmodel up, w>=0.99): grip (mp) displacement >= MOVE_DM (1.0 dm) or blade/stock
# angle >= MOVE_DEG (15 deg) from the median ready pose; held states (aiming, blocking) by their median pose, paths (swing,
# reloading) by their largest frame. Required states: xbow aiming + reloading, sword/seg blocking + swing. A required state
# that never shows or does not move fails the row (moves=... lists state:dm/deg, MISSING or STILL).
MOVE_DM,MOVE_DEG=1.0,15.0
def _med(xs): xs=sorted(xs); return xs[len(xs)//2]
def _mpose(rs): return (tuple(_med([r['mp'][k] for r in rs]) for k in range(3)),tuple(_med([r['mf'][k] for r in rs]) for k in range(3)))
_up=[r for r in F if r['w']>=0.99 and r['wih'] and r['mp'] is not None]
_rd=[r for r in _up if r['st']=='ready' and not r['sw']]
_req={'xbow':('aiming','reloading'),'sword':('blocking','swing'),'seg':('blocking','swing')}.get(sys.argv[2],())
moves=[]
if _req and _rd:
    rp_,rf_=_mpose(_rd)
    for k in _req:
        rs=[r for r in _up if (r['sw'] if k=='swing' else r['st']==k and not r['sw'])]
        if not rs: moves.append(k+':MISSING'); ok=False; continue
        if k in ('aiming','blocking'): pp,ff=_mpose(rs); d,g=ln(sub(pp,rp_)),ang(ff,rf_)
        else: d=max(ln(sub(r['mp'],rp_)) for r in rs); g=max(ang(r['mf'],rf_) for r in rs)
        still=d<MOVE_DM and g<MOVE_DEG; ok=ok and not still
        moves.append('%s:%.1fdm/%.0fdeg%s'%(k,d,g,':STILL' if still else ''))
elif _req: moves.append('ready:MISSING'); ok=False
# wrist (PT17): angle between the weapon forearm (elbow->wrist) and the hand bone X axis on every on-screen sword frame of
# the viewmodel (w>=0.99) <= WB_MAX (30 deg: a neutral grip wrist; 0750f26a folded it to ~100 deg in the strike)
W0=[(r['wb'],i,r['st']) for i,r in enumerate(F) if r['wb'] is not None and r['vis'] and r['w']>=0.99 and r['wih'] and not native(r)]
WS=[x for x in W0 if F[x[1]]['cls']==0]; WX=[x for x in W0 if F[x[1]]['cls']==1]
wbm=max(WS) if WS else None; wbsw=max([x[0] for x in WS if F[x[1]]['sw']] or [-1]); wbx=max(WX)[0] if WX else -1
if wbm and wbm[0]>WBM: ok=False
wtxt=(' wb_max=%.1f@%d:%s wb_swing=%.1f wb_xbow=%.1f wb_lim=%.0f'%(wbm[0],wbm[1],wbm[2],wbsw,wbx,WBM)) if wbm else (' wb_xbow=%.1f'%wbx if WX else ' wb=na')
fps=1/sorted(r['dt'] for r in F)[N//2]
print("ok=%d frames=%d vis=%d fps=%.0f cut=%d%s flags=%d%s errmax=%.2f@%s tipd_max=%.2f df_max=%.1f wih=%s%s" % (ok,N,nvis,fps,
      len(cuts),(' ['+' '.join(cuts[:6])+']') if cuts else '',len(flags),
      (' ['+' '.join(flags[:6])+']') if flags else '',errmax,errat,tipmax,dfmax,','.join(inout) or 'none',
      (' reload_zmin=%.2f'%rlz) if sys.argv[2]=='xbow' else '')+wtxt+(' moves='+','.join(moves) if moves else ''))
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
# raiders_near [x z r]: live (not KO/dead) raider lines; with x z r only those within r of (x,z), else within 1500 of the
# player (`chars` measures from the first squad member, Shay at the base, so a far capture spot gets x z r: m78 f7b a
# Dust Bandit outside the 1500 circle around Shay attacked Axima at the VMQUICK spot)
raiders_near() { local cr=1500; [ -n "$3" ] && cr=4000
  stobe-auto chars "$cr" "$RAID_FILTER|!ko|!dead" 2>/dev/null | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//' \
    | grep -E "\[(${RAID_RE})\]" | grep -v -E ' (KO|DEAD)( |$)' | grep -v -E "^(${SH}|${MT}) #" \
    | { if [ -n "$3" ]; then awk -v x="$1" -v z="$2" -v r="$3" '{ if (match($0,/pos=[-0-9.]+,[-0-9.]+,[-0-9.]+/)) {
          split(substr($0,RSTART+4,RLENGTH-4),p,","); d=sqrt((p[1]-x)^2+(p[3]-z)^2); if (d<r) printf "%s sd=%.0f\n", $0, d } }'; else cat; fi; }; }
# sweep: knock out raiders near the player, or (file $LOG.sweepc = "x z r", written by vmq_spot) near the capture spot
sweep() { local lines h n=0 cx="" cz="" cr=""
  [ -r "$LOG.sweepc" ] && read -r cx cz cr < "$LOG.sweepc"
  lines=$(raiders_near $cx $cz $cr)
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
# sword swings go through kfp_controls (fp_keys press lmb, as FS01 in fp-controls.sh): a mouse_inject click never reaches
# it (lmb_clicks=0, no native free-swing anim, so the zoomed-out swing showed the ready pose)
lswing() { A fp_keys press lmb "${1:-100}" >/dev/null; sleep "$(awk -v m="${1:-100}" 'BEGIN{printf "%.2f", (m+250)/1000}')"; }
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
weapons() { A inv "$SH" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | awk -v b="${BOWN:-@@}" 'tolower($0)!=tolower(b)'; }
# (not grep -v -i -x -F: the 4080's Git Bash grep dropped every line with it, "no melee weapon equips", 2026-10-09)
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
trap 'A fp_vm set sw_pose -1 >/dev/null; A fp_vm set kick_pose -1 >/dev/null; A fp_vm set rlamp 1.0 >/dev/null; A fp_vm replay off >/dev/null; [ "${VMQ_BEFORE:-0}" = 1 ] && { A fp_vm set wfix 1 >/dev/null; A fp_vm set zfade 1 >/dev/null; }; cleanup' EXIT
vfld() { A fp_vm state | fld "$1"; }
# vm_on <state>: vm in that state with the hand within VM_TOL deg of its target
vm_on() { local V; V=$(A fp_vm state); [ -z "$1" ] || [ "$(fld state <<<"$V")" = "$1" ] || return 1
  awk -v t="$(fld target <<<"$V")" -v e="$(fld elev <<<"$V")" -v a="$(fld az <<<"$V")" -v k="$VM_TOL" -v P="$(fld mp <<<"$V")" \
    'BEGIN{split(t,x,","); if(e==""||t=="") exit 1; r=3.14159265/180; c=sin(e*r)*sin(x[1]*r)+cos(e*r)*cos(x[1]*r)*cos((a-x[2])*r); if(c>1)c=1
      g=atan2(sqrt(1-c*c),c); split(P,p,","); d=sqrt(p[1]^2+p[2]^2+p[3]^2); exit !(g/r<=k || (P!="" && d*g<=0.15))}'; }
# angle between hand and target directions (az is meaningless near the poles: PT28 aim hold elev -87), or within 0.15 dm
# of it: the crossbow aim grip sits ~1.8 dm from the eye, where 0.1 dm of spring settling is 3-4 deg (PT13 FAIL 2026-10-09)
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
  waitf 10 csis loaded 1 || note "SETUP PT13: bow not loaded before the aim (reloading=$(cs reloading))"   # fresh load: auto-reload after the draw
  look "$(cam yaw)" 0.05; mdown right; waitf 4 vm_on aiming; R2=$(vm_on aiming && echo 1 || echo 0); E2=$(vev); shot xbow-aim; mup right; sleep 0.4
  # m54: the controller arms only after one idle input frame (an aim already held never arms), so idle first
  EN0=$(cs enabled); A fp_combat on >/dev/null   # m55: why=off, the controller was never enabled here (fp-playtest enables it itself)
  A fp_combat input 0 0 0 >/dev/null; waitf 4 csis armed 1 || note "SETUP PT13 not armed after idle input (why=$(cs why))"
  A fp_combat input 1 0 0 >/dev/null; waitf 8 csis aimed 1; RL=0
  if waitf 20 csis shot_ready 1; then S=$(cs actual_shots); A fp_combat input 1 1 0 >/dev/null; waitf 3 csge actual_shots $((S+1))
    A fp_combat input 1 0 0 >/dev/null; waitf 8 vm_is reloading && { RL=1; sleep 0.5; shot xbow-reload; }; fi
  A fp_combat input 0 0 0 >/dev/null; A fp_combat physical >/dev/null
  ev="ready: $E1| aim: $E2| reload_seen=$RL"
  # tilt band = the PT28 ready spec (low carry, nose 6..27 deg down; was |tilt|<8 for the pre-Chivalry level carry)
  ok=1; [ "$R1" = 1 ] && [ "$M1" = 0 ] && awk -v t="$T1" 'BEGIN{exit !(t!="" && t<=-6 && t>=-27)}' && [ "$R2" = 1 ] && [ $RL = 1 ] || ok=0
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
# capst <tag> <state> [max_s]: capture while the weapon is in <state>; repeats until the grip settles (< 0.05 dm since the
# previous capture) or the state ends, keeping the last capture taken inside <state> (a fixed settle missed the short
# 5090 reload: captured in aiming, m71)
capst() { local t=$1 st=$2 end=$((SECONDS+${3:-6})) pv="" pl="" pp="" pf="" pu="" ps="" d
  while [ $SECONDS -lt $end ]; do
    cap "$t"; if [ "${VST[$t]}" != "$st" ]; then [ -n "$ps" ] && { VSL[$t]=$pl; VST[$t]=$ps; VMP[$t]=$pp; VMF[$t]=$pf; VMU[$t]=$pu; }; break; fi
    if [ -n "$pp" ]; then d=$(awk -v a="$pp" -v b="${VMP[$t]}" 'BEGIN{split(a,p,",");split(b,q,",");print sqrt((p[1]-q[1])^2+(p[2]-q[2])^2+(p[3]-q[3])^2)<0.05}'); [ "$d" = 1 ] && break; fi
    pl=${VSL[$t]}; ps=${VST[$t]}; pp=${VMP[$t]}; pf=${VMF[$t]}; pu=${VMU[$t]}; sleep 0.15; done; }
# cap2 <tag>: cap zoomed in, then (PT29 wanted) at distance $ZO as <tag>-zo, back to 0
cap2() { cap "$1"; }   # (zoomed out: PT29 zo segments, the viewmodel fades to the native animation there)
# vq "<awk condition>" <tag>: condition over px py pz fx fy fz ux uy uz, el/az (grip elevation/azimuth, deg)
vq() { awk -v P="${VMP[$2]}" -v F="${VMF[$2]}" -v U="${VMU[$2]}" "BEGIN{if(P==\"\"||F==\"\"||U==\"\")exit 1
  split(P,p,\",\");split(F,f,\",\");split(U,u,\",\");px=p[1];py=p[2];pz=p[3];fx=f[1];fy=f[2];fz=f[3];ux=u[1];uy=u[2];uz=u[3]
  el=atan2(py,pz)*57.2958; az=atan2(px,pz)*57.2958; exit !($1)}"; }
pev() { echo "$1:${VST[$1]} mp=${VMP[$1]} mf=${VMF[$1]} mu=${VMU[$1]}"; }
# xbgeo <tag>: crossbow (Oldworld Bow MkI, repeating) screen geometry from the captured state line. Body model in grip
# axes (f = bolt, u = top, s = f x u, dm), MEASURED on the 4080 2026-10-08 from 3 grip depths: bolt tip 5.85f+1.0u,
# limb ends 3.87f+1.0u+-3.2s, fore-stock 3.0f+0.5u, grip handle 0..0.3f-0.45u, magazine 0.3f+1.3u, stock 0..-3.9f at
# +0.3u. Screen: 1920x1080, half-FOV tan 0.70 (v) / 1.245 (h), HUD line y/z=-0.33, near clip 3 world units (points
# closer than NEAR=2.5 dm are not drawn).
# Prints "tx ty bmin cov omode oerr ly lhs rwz lwz": bolt tip NDC, lowest on-screen body point y/z, arm_cov = upper arm
# + forearm area (radius 0.5 dm) inside the bottom-centre zone |x/z|<=0.436, -0.45<=y/z<=-0.05 / zone area (Lsh..Rwr
# joints), limb centre y/z, limb half span x/z, right / left wrist camera z (dm; < 3.0 = behind the near clip).
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
   n=0; pt(5.85,1.0,0); pt(3.87,1.0,3.2); pt(3.87,1.0,-3.2); pt(3.87,1.0,0); pt(3.87,1.0,1.6); pt(3.87,1.0,-1.6); pt(3.0,0.5,0)
   pt(0,-0.45,0); pt(0.3,-0.45,0); pt(0.3,1.3,0); for(t=0;t>=-3.9;t-=0.3) pt(t,0.3,0)
   tx=X[1]/Z[1]/1.245; ty=Y[1]/Z[1]/0.7; miny=9; ly=Z[4]>0.05?Y[4]/Z[4]:-9
   lhs=(Z[2]>0.05&&Z[3]>0.05)?(X[2]/Z[2]-X[3]/Z[3])/2:0; if(lhs<0)lhs=-lhs
   split(g("Rwr"),RW,","); split(g("Lwr"),LW,","); rwz=RW[3]==""?"x":RW[3]; lwz=LW[3]==""?"x":LW[3]
   for(i=1;i<=n;i++){ if(Z[i]<NEAR) continue; xs=X[i]/Z[i]; ys=Y[i]/Z[i]; if(xs<-1.245||xs>1.245||ys<-0.7) continue; if(ys<miny) miny=ys }
   area=0; cov="x"; for(si=1;si<=2;si++){ sd=si==1?"L":"R"; split(g(sd "sh"),S,","); split(g(sd "el"),E,","); split(g(sd "wr"),W,",")
     if(S[3]==""||E[3]==""||W[3]=="") { area=-1; break } seg(S,E); seg(E,W) }
   if(area>=0) cov=sprintf("%.3f", area/(0.872/0.7*0.4/0.7))
   om=g("omode"); oe=g("oerr"); printf "%.3f %.3f %.3f %s %s %s %.3f %.3f %s %s\n", tx, ty, miny, cov, om==""?"x":om, oe==""?"x":oe, ly, lhs, rwz, lwz }'; }
# xq "<awk condition>" <tag>: condition over tx ty bmin cov om oe ly lhs rwz lwz (xbgeo numbers)
xq() { local G; G=$(xbgeo "$2"); awk -v G="$G" "BEGIN{split(G,v,\" \"); for(i=1;i<=10;i++) if(v[i]==\"x\") exit 1
  tx=v[1]+0;ty=v[2]+0;bmin=v[3]+0;cov=v[4]+0;om=v[5]+0;oe=v[6]+0;ly=v[7]+0;lhs=v[8]+0;rwz=v[9]+0;lwz=v[10]+0; exit !($1)}"; }
kfpn() { kfplines | grep -c "$1"; }
# vmrec <name> <xbow|sword|swing>: dump the fp_vm recording to $KDIR/vmrec-<name>.txt (copied to $OUT) and print
# vmcheck's one-line verdict (ok=0|1 frames vis fps flags errmax tipd_max df_max wih in/out [reload_zmin])
vmrec() { local f="$KDIR/vmrec-$1.txt"; rm -f "$f"; A fp_vm rec dump "vmrec-$1.txt" >/dev/null; waitf 5 test -s "$f"
  [ -s "$f" ] || { echo "ok=0 no dump $f"; return; }; cp "$f" "$OUT/" 2>/dev/null; "$PY" "$OUT/vmcheck.py" "$f" "$2" 2>&1 | tail -1; }

# ---- VMQUICK (run first on every viewmodel build, <= ~4 min, one launch): every animation state of both weapons at zoom 0
# AND zoom $ZO, one labelled contact sheet (rows: sword zoom 0 / sword zoom $ZO / crossbow zoom 0 / crossbow zoom $ZO) +
# one sheet per weapon per zoom (final-<weapon>-zoom<z>.jpg in $OUT), and the numeric checks on the fp_vm recordings of
# each segment: zoom 0 = vmcheck xbow/sword (cut=0, no jump, wrist bend <= WB_MAX, in/out of the hand below the view),
# zoom $ZO = vmcheck zo (PT29 geometry: viewmodel faded out, hand away from the head, weapon visible, wrist, elbow, torso).
# Swing phases: zoom 0 = frozen path sw_pose 0.20/0.42/0.58 (wind-up/strike/follow-through) + one live swing in the
# recording; zoom $ZO = live swing at game speed 0.5 with 3 shots. VMQ_BEFORE=1: the 0750f26a behaviour (fp_vm set wfix 0,
# zfade 0) for before/after sheets. VMQ_FRAMES=1: plus every recorded frame of one zoom-0 swing replayed (fp_vm replay)
# and shot -> $OUT/swing-frames.jpg. Needs PIL in $PY (the 5090 WSL python3 has it).
SHOTD=${SHOTD:-$KDIR/mods/AutomationHarness/shots}; SHEETPY=${SHEETPY:-$(dirname "$0")/vm-sheet.py}; MAN="$OUT/vmq-manifest.tsv"
snap() { local p; p=$(A screenshot "vmq-$2" | grep -oE '[^ ]*\.png' | head -1); printf '%s\t%s\t%s\n' "$1" "$3" "$SHOTD/vmq-$2.png" >> "$MAN"; }
moving() { A fp_move w "${1:-1500}" >/dev/null; }
# every segment starts on one open-ground spot of the FP-crossbow fixture outside the walled base, facing yaw 0 (+z) with
# a level look (Shay 2026-10-09: every sheet so far had the char next to a wall, the blade hidden; the walk drifts by
# run), then a clearance check: 13 horizontal rays (-90..90 deg around the facing, 15 deg steps) at 1.6 m above the
# ground must not hit anything within VMQ_CLEAR game units (100 = 10 m; ground rises ~16 m ahead) or the row
# setup_fails (VMQ_SPOT=0: off; VMQ_SPOT_P="x y z" another spot)
vmq_spot() { [ "${VMQ_SPOT:-1}" = 1 ] || return 0; local p r x y z a d bad="" fy=${1:-0}
  p=${VMQ_SPOT_P:-"-54100 669.2 7300"}; read -r x y z <<<"$p"
  r=$(A teleport "$SH" $p); grep -q 'moved=1' <<<"$r" || setup_fail "VMQUICK teleport $SH $p: $(cut -c1-120 <<<"$r")"; sleep 1; look "$(awk -v d="$fy" 'BEGIN{printf "%.4f", d*3.14159265/180}')" 0.05
  # the spot is outside the base walls: roaming raiders came in during the m78 f7/f7b runs (Hungry/Dust Bandit -> Axima).
  # An attack on the squad since the last segment fails the row (the first segment: since setup, before the spot sweep,
  # ignored); raiders within VMQ_SWEEP_R (1500) of the spot are knocked out (also by the 10 s background sweep from now
  # on), then any live raider within VMQ_HOSTILE_R (1000 = 100 m) of the spot is a setup_fail
  if [ -n "$VQSPOT1" ]; then r=$(hostile_hit); [ -z "$r" ] || setup_fail "hostile attacked the squad during the previous VMQUICK segment ($r)"; fi
  VQSPOT1=1; echo "$x $z ${VMQ_SWEEP_R:-1500}" > "$LOG.sweepc"
  r=$(sweep); [ "${r:-0}" -gt 0 ] 2>/dev/null && { note "SETUP VMQUICK spot raid sweep: knocked out $r"; sleep 2; r=$(sweep); }
  r=$(raiders_near "$x" "$z" "${VMQ_HOSTILE_R:-1000}" | cut -c1-70 | tr '\n' ';')
  [ -z "$r" ] || setup_fail "VMQUICK spot $p: live raiders within ${VMQ_HOSTILE_R:-1000} after the sweep: $r"
  SL0=$(slog_n)
  for a in -90 -75 -60 -45 -30 -15 0 15 30 45 60 75 90; do
    d=$(A fp_camera ray "$x" "$(awk -v y="$y" 'BEGIN{print y+16}')" "$z" $(awk -v a="$a" -v fy="$fy" 'BEGIN{t=(a+fy)*3.14159265/180; printf "%.4f 0 %.4f", sin(t), cos(t)}') "${VMQ_CLEAR:-100}" | grep -o 'd=[0-9.]*' | cut -d= -f2)
    [ -n "$d" ] && bad+=" ${a}deg:$d"; done
  [ -z "$bad" ] || setup_fail "VMQUICK spot $p not clear within ${VMQ_CLEAR:-100} (hits$bad)"; note "VMQUICK spot $p clear (13 rays, ${VMQ_CLEAR:-100})"; }
vmq_seg() { local W=$1 Z=$2 row="$1 zoom $2" t="$1-z$2" r
  # zoomed out: the body faces the base (yaw 180) so the camera orbited round to its front looks out over open ground
  # (m78 f8: facing +z the zoom-25 frames had the base wall in the background)
  vmq_spot "$([ "$Z" = 0 ] && echo 0 || echo "${VMQ_ZO_YAW:-180}")"
  zoom "$Z" || note "SETUP VMQUICK zoom $Z failed (actual_distance=$(cam actual_distance))"
  # zoomed out: camera yawed round to the side/front (fp_camera orbit, the body keeps facing +z): seen from behind the
  # arm and weapon motion is hidden by the body
  [ "$Z" = 0 ] || A fp_camera orbit "${VMQ_ORBIT:-2.36}" >/dev/null
  draw_to 0; sleep 0.6; look "$(cam yaw)" 0.05; A fp_vm rec on >/dev/null; sleep 0.3
  rkey; sleep 0.15; snap "$row" "$t-draw" draw
  if [ "$W" = crossbow ]; then waitf 6 vm_is ready; sleep 0.8; snap "$row" "$t-ready" ready
    moving 1600; sleep 0.7; snap "$row" "$t-walk" walk; sleep 1; A fp_move none >/dev/null; sleep 0.4
    # a fresh fixture bow is unloaded (m78 f7: ammo=0, the RMB ran the reload, every aim/fire/reload tile was wrong):
    # prime it with one RMB reload first, the aim/fire/reload tiles need a loaded bow
    waitf 10 csis loaded 1 || { note "SETUP VMQUICK $t bow not loaded (ammo=$(cs ammo)): priming reload"; mdown right; waitf 15 csis loaded 1; mup right
      waitf 6 vm_is ready; sleep 0.8; csis loaded 1 || setup_fail "VMQUICK $t crossbow would not load (ammo=$(cs ammo) reloading=$(cs reloading))"; }
    mdown right; waitf 5 vm_is aiming; sleep 0.8; snap "$row" "$t-aim" aim
    mclick left 60; snap "$row" "$t-fire" fire; waitf 4 vm_is reloading; sleep 1.2; snap "$row" "$t-reload" reload
    sleep 2; snap "$row" "$t-reload2" "reload 2"; waitf 10 vm_is aiming; mup right; sleep 0.8
  else waitf 6 vm_is ready; sleep 0.8; snap "$row" "$t-ready" ready
    moving 1600; sleep 0.7; snap "$row" "$t-walk" walk; sleep 1; A fp_move none >/dev/null; sleep 0.4
    FSQ0=$(ks free_swings); mdown right; waitf 4 vm_is blocking; sleep 0.6; snap "$row" "$t-block" block; mup right; sleep 0.6
    # the frozen poses jump by design (sw_pose set/unset): kept out of the recording (part a checked here, rec on restarts it)
    if [ "$Z" = 0 ]; then A fp_vm rec off >/dev/null; r=$(vmrec "q-$t-a" seg); VQR+=" $t-a: $r;"; case "$r" in ok=1*) ;; *) VQOK=0;; esac
      for u in 0.20:wind-up 0.42:strike 0.58:follow-through; do A fp_vm set sw_pose "${u%%:*}" >/dev/null; sleep 0.5
        snap "$row" "$t-sw${u%%:*}" "${u#*:} (u ${u%%:*})"; done; A fp_vm set sw_pose -1 >/dev/null; sleep 0.6; A fp_vm rec on >/dev/null
      waitf 3 vm_is ready; SWQ0=$(kfpn '\[vm\] swing #[0-9]* [0-9.]*s u_end='); lswing; waitf 4 eval '[ "$(kfpn "\[vm\] swing #[0-9]* [0-9.]*s u_end=")" -gt "${SWQ0:-0}" ]'
    else A speed 0.5 >/dev/null; waitf 3 vm_is ready; lswing; sleep 0.1; snap "$row" "$t-sw1" "swing 1"; snap "$row" "$t-sw2" "swing 2"
      snap "$row" "$t-sw3" "swing 3"; sleep 1; A speed 1 hold >/dev/null; sleep 0.6; fi
    waitf 3 vm_is ready; lswing 60; sleep 0.15; mdown right; sleep 0.35; snap "$row" "$t-swblock" "swing->block"; sleep 0.8; mup right; sleep 0.6
    FSQ1=$(ks free_swings); [ "${FSQ1:-0}" -ge "$(( ${FSQ0:-0} + 2 ))" ] || { VQOK=0; VQR+=" $t: native free swings ${FSQ0}->${FSQ1} (want +2: swing + swing->block);"; }
  fi
  rkey; sleep 0.12; snap "$row" "$t-holster" holster; sleep 2.2
  A fp_vm rec off >/dev/null; r=$(vmrec "q-$t" "$([ "$Z" = 0 ] && { [ "$W" = crossbow ] && echo xbow || echo seg; } || echo zo)")
  VQR+=" $t: $r;"; case "$r" in ok=1*) ;; *) VQOK=0;; esac
  [ "$Z" = 0 ] || { A fp_camera orbit 0 >/dev/null; [ "$W" = crossbow ] && P29X=$r || P29S=$r; }; }
P29X=""; P29S=""
# animlab gate before every VMQUICK (components/KenshiFP/animlab/gate.sh: every lab check on the whole evidence corpus +
# E6 pool + mutation tests + flips vs the baseline, offline): uses the cached result for the current /root/KenshiFP source
# + lab + corpus (run `gate.sh` right after the build, ~2 min), else runs it here. A FAIL fails VMQUICK before filming.
# VMQ_GATE=0 skips (lab-only debugging; never for a build review).
vmq_gate() { [ "${VMQ_GATE:-1}" = 1 ] || return 0; local G=/mnt/c/KenshiModding/components/KenshiFP/animlab/gate.sh h f l
  h=$(bash "$G" hash); f=/root/animlab-gate/result-$h.txt
  [ -s "$f" ] || { note "VMQUICK: animlab gate for source $h not run yet: running it now (offline)"; bash "$G" >/dev/null 2>&1; }
  l=$(head -1 "$f" 2>/dev/null); l=${l:-RESULT ANIMLAB-REGRESS FAIL no gate result for $h}
  RESULTS+=("$l"); echo "$l" >> "$LOG"
  case "$l" in "RESULT ANIMLAB-REGRESS PASS"*) return 0;; esac
  row VMQUICK FAIL "animlab gate FAIL, fix the lab FAIL / the returned miss before filming (${l#RESULT ANIMLAB-REGRESS })"; return 1; }
if want VMQUICK && vmq_gate; then VQOK=1; VQR=""; : > "$MAN"; T0=$SECONDS
  [ "${VMQ_BEFORE:-0}" = 1 ] && { A fp_vm set wfix 0 >/dev/null; A fp_vm set zfade 0 >/dev/null; }
  A fp_vm state | grep -q ' wb=' || setup_fail "fp_vm state has no wb= (needs the PT17 wrist build)"
  A fp_combat physical >/dev/null; [ -z "$EN0" ] && EN0=$(cs enabled); A fp_combat on >/dev/null; A fp_combat input 0 0 0 >/dev/null
  waitf 4 csis armed 1 || note "SETUP VMQUICK not armed after idle input (why=$(cs why))"; A fp_combat physical >/dev/null
  if [ $BOWOK = 1 ] && [ "$(bow_now)" != none ]; then vmq_seg crossbow 0; vmq_seg crossbow "$ZO"; zoom 0; else VQOK=0; VQR+=" crossbow: setup no crossbow;"; fi
  draw_to 0; give_melee || note "SETUP: could not give $SH a melee weapon"; bow_off || note "SETUP: bow would not unequip ($(bow_now))"
  if arm_melee; then vmq_seg sword 0
    L=$(kfplines | grep '\[vm\] swing #[0-9]* [0-9.]*s u_end=' | tail -1); UE=$(grep -o 'u_end=[0-9.]*' <<<"$L" | cut -d= -f2)
    [ "$(kfpn '\[vm\] swing #[0-9]* [0-9.]*s u_end=')" -gt "${SWQ0:-0}" ] && ge "$UE" 1 || { VQOK=0; VQR+=" live swing: no full [vm] swing line ($L);"; }
    vmq_seg sword "$ZO"; zoom 0
    if [ "${VMQ_FRAMES:-0}" = 1 ]; then draw_to 1; waitf 6 vm_is ready; sleep 0.6; A fp_vm rec on >/dev/null; sleep 0.2; lswing; sleep 1.2
      A fp_vm rec off >/dev/null; A fp_vm rec dump vmrec-q-frames.txt >/dev/null; FR="$KDIR/vmrec-q-frames.txt"; waitf 5 test -s "$FR"; cp "$FR" "$OUT/" 2>/dev/null
      FM="$OUT/frames-manifest.tsv"; : > "$FM"
      for n in $(awk '!/^#/ && $9==1 {print $1}' "$FR"); do A fp_vm replay "$n" >/dev/null; sleep 0.12
        p=$(A screenshot "vmq-fr$n" | grep -oE '[^ ]*\.png' | head -1); u=$(awk -v n="$n" '$1==n{print $10}' "$FR")
        printf 'swing frames\tf%s u%s wb%s\t%s\n' "$n" "$u" "$(awk -v n="$n" '$1==n{split($0,a,"|"); split(a[5],b," "); print b[1]}' "$FR")" "$SHOTD/vmq-fr$n.png" >> "$FM"; done
      A fp_vm replay off >/dev/null; "$PY" "$SHEETPY" "$OUT/swing-frames.jpg" "$FM" --cols 8 >/dev/null 2>&1 || note "frames sheet failed"; draw_to 0; fi
  else VQOK=0; VQR+=" sword: setup no melee weapon ($(weapons | tr '\n' ';'));"; fi
  [ "${VMQ_BEFORE:-0}" = 1 ] && { A fp_vm set wfix 1 >/dev/null; A fp_vm set zfade 1 >/dev/null; }
  "$PY" "$SHEETPY" "$OUT/vmquick-sheet.jpg" "$MAN" --split "$OUT" >/dev/null 2>&1 || { VQOK=0; VQR+=" sheet failed;"; }
  judge VMQUICK $VQOK "$((SECONDS-T0))s sheet=$OUT/vmquick-sheet.jpg$( [ -s "$OUT/swing-frames.jpg" ] && echo " frames=$OUT/swing-frames.jpg") |$VQR"; fi

# ---- PT28: crossbow held like Skyrim/KCD (ready / aim / fire / reload, each zoomed in AND out for PT29) ----
if want PT28 || want PT29; then if [ $BOWOK = 0 ] || [ "$(bow_now)" = none ]; then rows_fail "no crossbow on $SH" PT28
else
  A fp_combat physical >/dev/null; A fp_vm set kick_pose -1 >/dev/null; A fp_vm set rlamp 0 >/dev/null; zoom 0
  # m76: run without PT13 the controller stayed off (why=off) and the live click never fired; enable it here too
  # (arm with one injected idle frame like PT13, then back to the physical mouse: `input` overrides it, aimed stayed 0)
  [ -z "$EN0" ] && EN0=$(cs enabled); A fp_combat on >/dev/null; A fp_combat input 0 0 0 >/dev/null
  waitf 4 csis armed 1 || note "SETUP PT28 not armed after idle input (why=$(cs why))"; A fp_combat physical >/dev/null
  draw_to 1 || note "SETUP PT28: R did not draw (drawn=$(ks drawn))"
  waitf 20 vm_on ready || note "SETUP PT28: not ready on target after draw ($(vev))"
  look "$(cam yaw)" 0.05; cap2 xbow-ready
  mdown right; waitf 20 vm_on aiming; cap2 xbow-aim
  A fp_vm set kick_pose 1 >/dev/null; sleep 0.5; cap2 xbow-fire; A fp_vm set kick_pose -1 >/dev/null; sleep 0.5
  # live shot zoomed in: kick + "[vm] fire" line, then the reload pose
  waitf 10 csis loaded 1 || note "SETUP PT28: bow not loaded before the live shot (reloading=$(cs reloading) reload_left=$(cs reload_left))"   # PT13's reload may still run
  K0=$(vfld kicks); F0=$(kfpn '\[vm\] fire'); mclick left
  # capture first: a harness call takes ~1.3 s here and the reload lasts ~6 s; kicks/fire lines are read afterwards
  waitf 4 vm_is reloading || note "SETUP PT28: no reload after the shot ($(vev))"; waitf 2 fire_done; capst xbow-reload reloading
  K1=$(vfld kicks); F1=$(kfpn '\[vm\] fire'); shot xbow-reload-live   # screenshot after the capture (~4.5 s in the background)
  # live shot zoomed out (PT29 reload pair: same delay after the shot)
  if want PT29 && [ -z "$P29X" ]; then mup right; sleep 0.4; draw_to 0; vmq_seg crossbow "$ZO"; zoom 0; fi
  mup right; sleep 0.4; A fp_vm set rlamp 1.0 >/dev/null
  ok=1; why=""
  # ready: low carry right (grip >=4 dm ahead, az>=15), nose 6..27 deg down, top up, mostly behind the bottom bar (Shay
  # 2026-10-10 spec-videos keeps the low carry r_ready_py -4.0: accepted bmin -0.55, tip y -0.61; was bmin>=-0.33 "whole
  # crossbow above the HUD"): lowest body point y/z >= -0.70, bolt tip y >= -0.80, limb line below the centre, right wrist
  # in front of the near clip (no cut glove)
  { [ "${VST[xbow-ready]}" = ready ] && vq "fz>=0.85 && fy<=-0.1 && fy>=-0.45 && uy>=0.9 && az>=15 && pz>=4.0" xbow-ready && xq "bmin>=-0.70 && ty>=-0.80 && ly<=-0.05 && rwz>=3.3" xbow-ready; } || { ok=0; why+=" ready"; }
  # aim (zoomed in and out), Chivalry 2 hold: grip at the eye plane (|z|<=1, |x|<=0.3, y<=-1.4) so NO hand is drawn (both
  # wrists behind the near clip rwz<=2.6 lwz<=2.8, arm_cov<=0.02), limbs horizontal (top up) in the lower third (limb line
  # y/z -0.30..-0.10, half span x/z >=0.6), bolt on the crosshair (<=2 deg at AIMD), bolt tip projected |x|<=0.06 NDC and
  # 0.05..0.25 below the centre, off-hand on the support point (omode=1, oerr<=0.5 dm)
  for t in xbow-aim; do
    { [ "${VST[$t]}" = aiming ] && vq "fz>=0.99 && uy>=0.95 && px*px<=0.09 && pz>=-1.0 && pz<=1.0 && py<=-1.4 &&       (-fx*px - fy*py + fz*($AIMD-pz)) / sqrt(px*px+py*py+($AIMD-pz)^2) >= 0.99939" $t &&       xq "tx<=0.06 && tx>=-0.06 && ty>=-0.25 && ty<=-0.05 && ly>=-0.30 && ly<=-0.10 && lhs>=0.6 && om==1 && oe<=0.5 && cov<=0.02 && rwz<=2.6 && lwz<=2.8" $t; } || { ok=0; why+=" $t"; }; done
  # fire (frozen kick_pose 1 = kick peak): muzzle climbs (fy>=0.1, tip -0.1..0.4 NDC, |x|<=0.1), the grip stays within
  # 0.3 dm of the aim hold (not in the face); live LMB: kicks + "[vm] fire" line
  AZ=$(awk -v P="${VMP[xbow-aim]}" 'BEGIN{split(P,p,",");print p[3]-0.3}')
  { vq "fy>=0.1 && pz>=$AZ" xbow-fire && xq "tx<=0.1 && tx>=-0.1 && ty>=-0.1 && ty<=0.4" xbow-fire && [ "$K1" -gt "$K0" ] && [ "$F1" -gt "$F0" ]; } || { ok=0; why+=" fire(kicks $K0->$K1 lines $F0->$F1)"; }
  # reload: lowered (grip >=4 dm ahead, nose down >=14 deg, forward), top rolled toward the eye (uz<=-0.3: the spanning
  # motion is readable), limb line above the HUD line, right wrist in front of the near clip (hand visible, no cut glove)
  { [ "${VST[xbow-reload]}" = reloading ] && vq "pz>=4.0 && fy<=-0.25 && fz>=0.7 && uz<=-0.3" xbow-reload && xq "ly>=-0.33 && rwz>=3.3" xbow-reload; } || { ok=0; why+=" reload"; }
  GEO="geo(tx ty bmin cov om oe ly lhs rwz lwz) ready=[$(xbgeo xbow-ready)] aim=[$(xbgeo xbow-aim)] fire=[$(xbgeo xbow-fire)] reload=[$(xbgeo xbow-reload)]"
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
    SW0=$(kfpn '\[vm\] swing #[0-9]* [0-9.]*s u_end='); lswing; waitf 4 eval '[ "$(kfpn "\[vm\] swing #[0-9]* [0-9.]*s u_end=")" -gt "$SW0" ]'
    SWL=$(kfplines | grep '\[vm\] swing #[0-9]* [0-9.]*s u_end=' | tail -1); [ "$(kfpn '\[vm\] swing #[0-9]* [0-9.]*s u_end=')" -gt "$SW0" ] || SWL=""
    UE=$(grep -o 'u_end=[0-9.]*' <<<"$SWL" | cut -d= -f2)
    RT=$(fld target <<<"$E1"); waitf 3 vm_is ready
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
      ok=1; for t in sword-block; do [ -n "${VMP[$t]}" ] || continue
        { [ "${VST[$t]}" = blocking ] && vq "fx*fx>=0.72 && fy*fy<=0.04" "$t"; } || ok=0; done
      want PT27 && judge PT27 $ok "$(pev sword-block)"; fi

# ---- PT26: smooth full swing top-right -> bottom-left: frozen frame sequence + real swings (per-frame [vmsw] log) ----
    if want PT26 || want PT29; then
      SEQ=""; for u in ${SW_US:-0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90}; do A fp_vm set sw_pose "$u" >/dev/null; sleep 0.5
        cap "sword-sw$u"; SEQ+=" $u:$(vfld target)"; done
      A fp_vm set sw_pose 0.42 >/dev/null; sleep 0.5; cap sword-sw0.42; A fp_vm set sw_pose -1 >/dev/null; sleep 0.6
      ok=1; ev=""; NSW=${NSW:-3}
      for i in $(seq 1 "$NSW"); do waitf 3 vm_is ready
        S0=$(kfpn '\[vm\] swing #[0-9]* [0-9.]*s u_end='); lswing; waitf 4 eval '[ "$(kfpn "\[vm\] swing #[0-9]* [0-9.]*s u_end=")" -gt "$S0" ]'
        L=$(kfplines | grep '\[vm\] swing #[0-9]* [0-9.]*s u_end=' | tail -1); [ "$(kfpn '\[vm\] swing #[0-9]* [0-9.]*s u_end=')" -gt "$S0" ] || { ok=0; ev+=" swing$i: no [vm] swing line;"; continue; }
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
      waitf 3 vm_is ready; A fp_vm rec on >/dev/null; sleep 0.3; lswing; sleep 1.2; A fp_vm rec off >/dev/null
      LIVE=$(vmrec pt26 swing); case "$LIVE" in ok=1*) ;; *) ok=0;; esac; ev+=" every-frame: $LIVE;"
      want PT26 && judge PT26 $ok "$ev frozen u:target(elev,az)$SEQ"; fi
    if want PT30; then draw_to 0; sleep 1; look "$(cam yaw)" 0.05; A fp_vm rec on >/dev/null; sleep 0.5
      rkey; sleep 2.2; lswing; sleep 1.2; lswing; sleep 1.2; mdown right; sleep 1.2; mup right; sleep 1
      lswing 60; sleep 0.15; mdown right; sleep 1; mup right; sleep 1
      rkey; sleep 2.2; A fp_vm rec off >/dev/null; P30S=$(vmrec pt30-sword sword); fi
    if want PT29 && [ -z "$P29S" ]; then draw_to 0; vmq_seg sword "$ZO"; zoom 0; fi
    draw_to 0; fi; fi

if want PT30; then ok=1; case "$P30X" in ok=1*) ;; *) ok=0;; esac; case "$P30S" in ok=1*) ;; *) ok=0;; esac
  judge PT30 $ok "xbow: ${P30X:-not run} | sword: ${P30S:-not run}"; fi

# ---- PT29: zoomed out (fp_camera distance $ZO) every state of both weapons reads as a person holding/swinging it: the
# recorded zo segments (VMQUICK's when it ran, else run here) pass vmcheck zo (see vmcheck.py) ----
if want PT29; then ok=1; case "$P29X" in ok=1*) ;; *) ok=0;; esac; case "$P29S" in ok=1*) ;; *) ok=0;; esac
  judge PT29 $ok "zoom $ZO crossbow: ${P29X:-not run} | sword: ${P29S:-not run}"; fi

echo "NOTE PT17 viewmodel screenshots (harness shots dir):$SHOTS" >> "$LOG"
finish; echo "NOTE PT17 screenshots:$SHOTS"
