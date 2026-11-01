"""Check release boundaries without historical campaign data."""
import pathlib,re,sys,fnmatch
root=pathlib.Path(__file__).resolve().parents[2]
errors=[]
private_names = ['ARCHITECTURE*', '*ROADMAP*', 'LLM_DEVELOPMENT.md',
 'TRANSFORMER_SHUNT_PLAN.md', 'VOLT_VAR_AND_TEST_CASE_STUDY.md',
 'RELEASE_NOTES_UNRELEASED.md', 'AGENTS.md', 'research.md', 'agenda.md',
 'discussions.md', 'milestones.md', 'validation_evidence.md',
 'validation_figures.md', 'validation_reports.md', 'validation_tables.md']
private_dirs = {'research','experiments','private','notes','agenda','discussions'}
public_examples = set((root/'tools/release/public_examples.txt').read_text().splitlines())
for name in ['artifacts','outputs']:
 if (root/name).exists():errors.append('unexpected generated tree: '+name)
for p in root.rglob('*'):
 if not p.is_file() or any(x in p.parts for x in ['.git','build','__pycache__']):continue
 relative=p.relative_to(root)
 if relative.parts[0] == 'examples' and relative.as_posix() not in public_examples:
  errors.append('unapproved public example: '+str(relative))
 if any(fnmatch.fnmatch(p.name.lower(), pattern.lower()) for pattern in private_names) or any(part.lower() in private_dirs for part in relative.parts[:-1]) or relative.parts[:4] == ('docs','src','assets','validation'):
  errors.append('private working material in public source: '+str(relative))
 if p.stat().st_size>5_000_000:errors.append('oversized release file: '+str(relative))
for p in [root/'README.md',*(root/'docs/src').glob('*.md')]:
 text=re.sub(r'```.*?```','',p.read_text(),flags=re.S)
 for image in re.findall(r'!\[[^\]]*\]\(([^\s)]+)\)',text):
  if image.startswith(('http:', 'https:')):
   errors.append(f'{p.relative_to(root)}: remote documentation image must be bundled: {image}')
  elif pathlib.Path(image.split('#')[0]).suffix.lower() not in ['.png','.svg','.jpg','.jpeg','.webp','.gif']:
   errors.append(f'{p.relative_to(root)}: image target is not an image: {image}')
 for link in re.findall(r'\]\(([^\s)]+)\)',text):
  if link.startswith(('http:','https:','mailto:','#','@')):continue
  path=link.split('#')[0]
  if not (p.parent/path).exists():errors.append(f'{p.relative_to(root)}: missing {path}')
if errors:print('\n'.join(errors));sys.exit(1)
print('Release boundaries and local documentation links passed')
