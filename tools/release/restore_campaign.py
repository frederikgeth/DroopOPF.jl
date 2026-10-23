"""Restore one archived campaign into an empty destination, with per-file checks."""
import argparse,hashlib,json,pathlib,tarfile,tempfile,os,shutil
p=argparse.ArgumentParser();p.add_argument('archive_directory');p.add_argument('campaign');p.add_argument('destination');a=p.parse_args()
base=pathlib.Path(a.archive_directory);dest=pathlib.Path(a.destination).resolve()
if pathlib.PurePosixPath(a.campaign).name!=a.campaign:raise ValueError('campaign must be a single directory name')
index=json.loads((base/'campaigns-files.json').read_text());prefix='artifacts/'+a.campaign+'/'
expected={k:v for k,v in index.items() if k.startswith(prefix)}
if not expected:raise ValueError('unknown campaign')
archive=base/'campaigns.tar.gz';h=hashlib.sha256()
with archive.open('rb') as f:
 for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
assert h.hexdigest()==json.loads((base/'evidence-index.json').read_text())['campaigns']['sha256']
dest.parent.mkdir(parents=True,exist_ok=True)
if dest.exists():raise FileExistsError('destination must not exist')
tmp=pathlib.Path(tempfile.mkdtemp(prefix='restore-',dir=dest.parent));seen=set()
try:
 with tarfile.open(archive,'r:gz') as t:
  for m in t:
   if m.name not in expected:continue
   rel=pathlib.PurePosixPath(m.name[len(prefix):]);assert '..' not in rel.parts and not rel.is_absolute() and m.isfile()
   target=tmp/rel;target.parent.mkdir(parents=True,exist_ok=True);h=hashlib.sha256()
   with t.extractfile(m) as inp,target.open('wb') as out:
    for b in iter(lambda:inp.read(1024*1024),b''):out.write(b);h.update(b)
   assert h.hexdigest()==expected[m.name],m.name
   seen.add(m.name)
 assert seen==set(expected)
 os.rename(tmp,dest)
except BaseException:
 shutil.rmtree(tmp);raise
print(f'Restored and verified {len(seen)} files to {dest}')
