#!/usr/bin/env python3
"""imm26 compose2: file-level 3-way merge of wp trees onto base -> /root/imm26/compose. usage: compose_merge.py [ORDER...]"""
import os, sys, subprocess, shutil, tempfile
R='/root/imm26'; base=R+'/base'; out=R+'/compose'
order=sys.argv[1:] or ['A','B','D','E','C1','C2']
EXC={'log','__pycache__','soundcache'}
def walk(d):
    for dp,dn,fn in os.walk(d):
        dn[:]=[x for x in dn if x not in EXC]
        for f in fn: yield os.path.relpath(os.path.join(dp,f),d)
def rd(p): return open(p,'rb').read()
if os.path.exists(out): subprocess.run(['rm','-rf',out])
subprocess.run(['rsync','-a','--exclude','log','--exclude','__pycache__','--exclude','soundcache',base+'/',out+'/'],check=True)
conf=[]; merged=[]
for x in order:
    t=f'{R}/wp{x}'
    for rel in walk(t):
        bp=f'{base}/{rel}'; tp=f'{t}/{rel}'; cp=f'{out}/{rel}'
        if os.path.exists(bp) and rd(bp)==rd(tp): continue
        if not os.path.exists(cp):
            os.makedirs(os.path.dirname(cp),exist_ok=True); shutil.copy2(tp,cp); continue
        if not os.path.exists(bp):
            if rd(cp)!=rd(tp): conf.append((x,rel,'new-file-clash'))
            continue
        if rd(cp)==rd(bp): shutil.copy2(tp,cp); continue
        d=tempfile.mkdtemp()
        for n,p in (('cur',cp),('base',bp),('new',tp)):
            open(f'{d}/{n}','wb').write(rd(p).replace(b'\r\n',b'\n'))
        r=subprocess.run(['git','merge-file','-p','--diff3','-L','compose','-L','base','-L','wp'+x,f'{d}/cur',f'{d}/base',f'{d}/new'],capture_output=True)
        data=r.stdout
        if r.returncode>0: conf.append((x,rel,f'{r.returncode} conflict hunks'))
        bb=rd(bp)
        if b'\r\n' in bb and bb.count(b'\n')==bb.count(b'\r\n'): data=data.replace(b'\n',b'\r\n')
        open(cp,'wb').write(data); merged.append((x,rel,r.returncode))
        shutil.rmtree(d)
for x,rel,rc in merged: print('MERGED',x,rel,'conflicts=%d'%rc)
for c in conf: print('CONFLICT',*c)
