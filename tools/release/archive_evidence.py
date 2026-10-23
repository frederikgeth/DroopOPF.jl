"""Archive research evidence losslessly; verify each archived byte before retention changes."""
import argparse,hashlib,json,tarfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('repository');p.add_argument('destination');a=p.parse_args()
r=Path(a.repository).resolve();out=Path(a.destination).resolve();out.mkdir(parents=True,exist_ok=True)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
groups={'campaigns':['artifacts'],'research-docs':['docs/src','README.md','ROADMAP.md','AGENTS.md','RELEASE_NOTES_UNRELEASED.md'],'research-drivers':['examples','test','experiments','src','Project.toml','Manifest.toml','LICENSE']}
index={}
for name,roots in groups.items():
 target=out/(name+'.tar.gz');assert not target.exists(),target
 files=sorted({p for s in roots for p in ([r/s] if (r/s).is_file() else (r/s).rglob('*')) if p.is_file() and '__pycache__' not in p.parts})
 records={str(p.relative_to(r)):sha(p) for p in files}
 with tarfile.open(target,'w:gz',compresslevel=1) as t:
  for p in files:t.add(p,arcname=str(p.relative_to(r)),recursive=False)
 with tarfile.open(target,'r:gz') as t:
  seen=set()
  for m in t:
   assert m.isfile(),m.name
   h=hashlib.sha256();f=t.extractfile(m)
   for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
   assert h.hexdigest()==records[m.name],m.name
   seen.add(m.name)
  assert seen==set(records)
 index[name]={'archive':target.name,'sha256':sha(target),'compressed_bytes':target.stat().st_size,'files':len(records),'verified':True}
 (out/(name+'-files.json')).write_text(json.dumps(records,indent=2)+'\n')
 print(name,index[name],flush=True)
(out/'evidence-index.json').write_text(json.dumps(index,indent=2)+'\n')
