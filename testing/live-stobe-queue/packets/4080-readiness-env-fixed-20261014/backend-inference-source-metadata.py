from pathlib import Path
import json,re
root=Path('/tmp/stobe-standalone4080/site').resolve(strict=True)
logdir=root/'log'
assert logdir.resolve(strict=True)==logdir
records=[]
for name in ('audit_request.log','chat_llm_full_capture.log'):
    p=logdir/name
    if not p.is_file() or p.is_symlink():continue
    with p.open('rb') as src:
        src.seek(0,2);size=src.tell();src.seek(max(0,size-2000000));lines=src.read().decode('utf-8','replace').splitlines()
    parsed=[]
    for line in lines:
        pos=line.find('{')
        if pos<0:continue
        try: obj=json.loads(line[pos:])
        except Exception:continue
        if not isinstance(obj,dict):continue
        rid=obj.get('request_id','')
        if not isinstance(rid,str) or not re.fullmatch(r'req_[0-9a-f]+',rid):continue
        kind=obj.get('event_type','unknown')
        if not isinstance(kind,str) or not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}',kind):kind='unknown'
        status=obj.get('status','unknown')
        if status not in ('ok','pending','error','completed','cancelled','success','fail','failed','timeout'):status='unknown'
        npc=obj.get('npc_name','')
        if not isinstance(npc,str) or not re.fullmatch(r"[A-Za-z0-9 .'\[\]_-]{0,100}",npc):npc='unparsed'
        timestamp=re.search(r'20\d{2}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?',line[:pos])
        usage=obj.get('usage',{})
        usage=usage if isinstance(usage,dict) else {}
        counts={key:usage[key] for key in ('prompt_tokens','completion_tokens','cached_tokens') if type(usage.get(key)) is int and usage[key]>=0}
        parsed.append({'request_id':rid,'kind':kind,'status':status,'npc':npc,'time':timestamp.group(0) if timestamp else 'unparsed','counts':counts})
    records.append({'file':name,'file_bytes':size,'latest_metadata':parsed[-10:]})
print(json.dumps({'private_root':str(root),'records':records},separators=(',',':')))
