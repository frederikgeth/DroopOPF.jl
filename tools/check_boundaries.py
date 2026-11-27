"""Enforce the static-library dependency direction and source ownership."""
from pathlib import Path
import re,sys,tomllib

def check(root):
 root=Path(root);errors=[];p=tomllib.loads((root/'Project.toml').read_text())
 if p.get('name')!='DroopOPF' or p.get('uuid')!='e6b4e7b0-8d6a-4d22-9b7c-3c4d6c4e4d2a':errors.append('DroopOPF package identity changed')
 forbidden={'DroopDesign','PowerSimulationsDynamics','PowerDynamics','ANDES'}
 for section in ['deps','weakdeps','extras']:
  if forbidden & set(p.get(section,{})):errors.append('research/dynamic backend dependency in core')
 for d in ['h1','h23','h123','h45','h_tools','h_ieee','q','mhq']:
  if (root/'tools'/d).exists():errors.append('research implementation in core: tools/'+d)
 for folder in ['src','ext']:
  for f in (root/folder).rglob('*.jl'):
   if re.search(r'\b(?:using|import)\s+(?:DroopDesign|PowerSimulationsDynamics|PowerDynamics|ANDES)\b',f.read_text()):errors.append('research import in '+str(f.relative_to(root)))
 return errors
if __name__=='__main__':
 errors=check(Path(__file__).resolve().parents[1]);print('\n'.join(errors) if errors else 'Static-library dependency and ownership checks passed');sys.exit(bool(errors))
