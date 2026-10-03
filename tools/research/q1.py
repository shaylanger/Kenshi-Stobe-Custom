import sys; sys.path.insert(0,'/mnt/c/KenshiModding/tools/research')
from fcs_merge import load
db=load()
ch=[r for r in db.values() if r['type']==1]
print(len(ch),'characters')
for r in ch:
    if r['name'] in ('Paladin','High Paladin','Holy Lord Phoenix','Inquisitor','High Inquisitor') or 'Phoenix' in r['name']:
        print('==',r['name'],r['sid']); print(' floats',{k:v for k,v in r['floats'].items()}); print(' ints',r['ints']); print(' refs',{k:[(db[s]['name'] if s in db else s,a,b,c) for s,a,b,c in v] for k,v in r['refs'].items() if k not in ('stats',)})
        break
