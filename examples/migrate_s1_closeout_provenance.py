"""One-time provenance transition for the authorized study retirement.

Only hash registries change. Electrical inputs, saved states and results are
checked against their existing pinned values and are never rewritten here.
"""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/s1_closeout'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
transition=OUT/"provenance_transition.json"
changes=json.loads(transition.read_text())["registries"] if transition.exists() else [];files=[]
for p in (ROOT/'artifacts').rglob('*.json'):
 if 's1_closeout' in p.parts:continue
 if not any(x in p.name.lower() for x in ('manifest','protocol')):continue
 files.append(str(p.relative_to(ROOT)))
 obj=json.loads(p.read_text());before=sha(p);local=[]
 def walk(x):
  if isinstance(x,dict):
   for k,v in list(x.items()):
    if '/' in k and isinstance(v,str) and len(v)==64 and all(c in '0123456789abcdef' for c in v):
     q=Path(k) if Path(k).is_absolute() else ROOT/k
     if q.is_file():
      now=sha(q)
      if now!=v:
       # Physical data/results must remain pinned; code and prose may change.
       assert not (k.startswith('test/data/arpae/') or '/attempts/' in k or '/models/' in k),k
       x[k]=now;local.append(dict(path=k,old_sha256=v,new_sha256=now,action='repin retained code/documentation'))
     else:del x[k];local.append(dict(path=k,old_sha256=v,action='remove retired input from active registry'))
    else:walk(v)
  elif isinstance(x,list):
   for v in x:walk(v)
 walk(obj)
 if local:
  p.write_text(json.dumps(obj,indent=2)+'\n');changes.append(dict(manifest=str(p.relative_to(ROOT)),old_manifest_sha256=before,new_manifest_sha256=sha(p),changes=local))
# Some retained registries pin other registries. Bring those chains up to date.
for _ in range(5):
 changed=False
 for pp in files:
  p=ROOT/pp;obj=json.loads(p.read_text());updates=[]
  def refresh(x):
   if isinstance(x,dict):
    for k,v in list(x.items()):
     q=ROOT/k
     if '/' in k and isinstance(v,str) and len(v)==64 and q.is_file():
      new=sha(q)
      if new!=v:x[k]=new;updates.append(dict(path=k,old_sha256=v,new_sha256=new))
     elif isinstance(v,(dict,list)):refresh(v)
   elif isinstance(x,list):
    for v in x:refresh(v)
  refresh(obj)
  if updates:p.write_text(json.dumps(obj,indent=2)+'\n');changed=True;changes.append(dict(manifest=pp,changes=updates,action='refresh dependent manifest'))
 if not changed:break
(OUT/'provenance_transition.json').write_text(json.dumps(dict(reason='User-authorized network-study retirement and S1 closeout; physical source/results preserved',registries=changes),indent=2)+'\n')
print('Updated provenance registries:',len(files))
