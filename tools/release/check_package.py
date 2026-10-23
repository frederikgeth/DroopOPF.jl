"""Check release boundaries without historical campaign data."""
import pathlib,re,sys
root=pathlib.Path(__file__).resolve().parents[2]
errors=[]
for name in ['artifacts','outputs']:
 if (root/name).exists():errors.append('unexpected generated tree: '+name)
for p in root.rglob('*'):
 if not p.is_file() or any(x in p.parts for x in ['.git','build','__pycache__']):continue
 if p.stat().st_size>5_000_000:errors.append('oversized release file: '+str(p.relative_to(root)))
for p in [root/'README.md',*(root/'docs/src').glob('*.md')]:
 text=re.sub(r'```.*?```','',p.read_text(),flags=re.S)
 for link in re.findall(r'\]\(([^\s)]+)\)',text):
  if link.startswith(('http:','https:','mailto:','#','@')):continue
  path=link.split('#')[0]
  if not (p.parent/path).exists():errors.append(f'{p.relative_to(root)}: missing {path}')
if errors:print('\n'.join(errors));sys.exit(1)
print('Release boundaries and local documentation links passed')
