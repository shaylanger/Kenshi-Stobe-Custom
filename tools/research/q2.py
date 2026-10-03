import sys; sys.path.insert(0,'/mnt/c/KenshiModding/tools/research')
from fcs_merge import load
db=load()
def show(name,t):
    for r in db.values():
        if r['type']==t and r['name'].strip()==name:
            print('==',t,name); print(' floats',r['floats']); print(' ints',r['ints']); print(' refs',{k:[(db[s]['name'] if s in db else s,a,b,c) for s,a,b,c in v][:6] for k,v in r['refs'].items()}); return
show("Phoenix's Chain Shirt",3); show("The Purge",2); show('Innominate',51); show('Katana',2)
