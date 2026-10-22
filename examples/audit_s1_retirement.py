"""Audit the cleaned working tree without interpreting bus IDs as network sizes."""
from pathlib import Path
import json,re,urllib.parse
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/s1_closeout';bad=[];links=[];njson=0
pat=re.compile(r'(?i)(?:ieee[-_ ]*(?:118|300)|(?:case|public|pglib_opf_case)(?:118|300)|\b(?:118|300)[- ]bus|118\s*[,/]\s*300)')
for folder in ('artifacts','docs/src','examples','test/data','outputs'):
 for p in (ROOT/folder).rglob('*'):
  if not p.is_file() or 's1_closeout' in p.parts or p.name==Path(__file__).name:continue
  if re.search(r'(?i)(?:ieee|public|case|network)[_-]?(118|300)',p.name):bad.append(str(p.relative_to(ROOT)))
  if p.suffix in ('.md','.jl','.py','.m') and pat.search(p.read_text(errors='replace')):bad.append(str(p.relative_to(ROOT)))
  if p.suffix=='.json':
   d=json.loads(p.read_text());njson+=1
   if isinstance(d,dict):
    c=d.get('data',{}).get('case',{}) if isinstance(d.get('data'),dict) else {}
    for obj in (d,c,d.get('case',{})):
     if not isinstance(obj,dict):continue
     net=obj.get('network',{})
     if isinstance(net,dict) and isinstance(net.get('buses'),list) and len(net['buses']) in (118,300):bad.append(str(p.relative_to(ROOT)))
     if isinstance(obj.get('bus'),dict) and len(obj['bus']) in (118,300):bad.append(str(p.relative_to(ROOT)))
for p in [*(ROOT/'docs/src').rglob('*.md'),*ROOT.glob('*.md')]:
 for target in re.findall(r'!?\[[^\]]*\]\(([^)\s]+)\)',p.read_text()):
  t=urllib.parse.unquote(target.strip('<>').split('#')[0])
  if not t or ':' in t or t=='@ref':continue
  if not (p.parent/t).exists():links.append(dict(source=str(p.relative_to(ROOT)),target=t))
result=dict(retired_network_files=sorted(set(bad)),broken_doc_links=links,json_files_checked=njson)
(OUT/'cleanup_checks.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));assert not bad and not links
