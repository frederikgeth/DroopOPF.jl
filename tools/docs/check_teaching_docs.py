"""Check built internal links, anchors and teaching-figure accessibility.

Run after docs/make.jl. This checks rendered output; executed Julia assertions
are provided by Documenter's @example blocks.
"""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit,unquote
import argparse,json,re,xml.etree.ElementTree as ET
class Page(HTMLParser):
 def __init__(self,path):
  super().__init__();self.ids=set();self.links=[];self.images=[];self.text=[];self.feed(path.read_text())
 def handle_data(self,data):self.text.append(data)
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if 'id' in a:self.ids.add(a['id'])
  if tag=='a' and 'href' in a:self.links.append(a['href'])
  if tag=='img':self.images.append(a)
def check(build):
 build=Path(build).resolve();pages={p:Page(p) for p in build.rglob('*.html')};errors=[];links=0;figures=0
 if not pages:errors.append('No rendered HTML pages')
 for published in build.rglob('*'):
  if published.is_file() and any(re.fullmatch(r'(?:roadmap|architecture|research|agenda|milestones?)(?:\.[^.]+)?',part,re.I) for part in published.relative_to(build).parts):
   errors.append(f'excluded planning/history file published: {published.relative_to(build)}')
 excluded={'milestones.html','research.html','validation_reports.html','validation_tables.html','validation_figures.html','validation_evidence.html'}
 forbidden=re.compile(r'\b(?:M[0-9]+(?:\.[0-9]+)?|S[0-9]+|P[0-9]+)\b|\b(?:roadmap|architecture|research|milestone|agenda)s?\b',re.I)
 # Internal compatibility identifiers such as s2_emergency are API names, not labels.
 for path,page in pages.items():
  if path.name in excluded or (path.name=='index.html' and path.parent.name+'.html' in excluded):errors.append(f'excluded page published: {path.name}')
  visible=' '.join(page.text)
  matches=sorted(set(m.group(0) for m in forbidden.finditer(visible)))
  if matches:errors.append(f'{path.name}: internal labels/planning terms visible: {matches}')
  for href in page.links:
   u=urlsplit(href)
   if u.scheme or u.netloc:continue
   target=(path.parent/unquote(u.path)).resolve() if u.path else path
   if target.is_dir():target=target/'index.html'
   if not target.is_relative_to(build):continue
   links+=1
   if not target.exists():errors.append(f'{path.name}: missing {href}')
   elif u.fragment and target in pages and unquote(u.fragment) not in pages[target].ids:errors.append(f'{path.name}: missing anchor {href}')
  for img in page.images:
   if 'assets/teaching/' in img.get('src',''):
    figures+=1
    if not img.get('alt','').strip():errors.append(f'{path.name}: teaching image missing alternative text')
    target=(path.parent/img['src']).resolve()
    if not target.is_file():errors.append(f'{path.name}: missing image {img["src"]}')
 if (build/'assets/validation').exists():errors.append('Internal evidence assets copied to public build')
 for index in build.rglob('search_index.js'):
  matches=sorted(set(m.group(0) for m in forbidden.finditer(index.read_text())))
  if matches:errors.append(f'{index.name}: internal labels/planning terms indexed: {matches}')
 for path in (build/'assets/teaching').glob('*.svg'):
  root=ET.parse(path).getroot();ns={'s':'http://www.w3.org/2000/svg'}
  if root.find('s:title',ns) is None or not root.get('viewBox'):errors.append(f'{path.name}: missing SVG title/viewBox')
 result={'pages':len(pages),'local_links':links,'teaching_figure_uses':figures,'errors':errors,'valid':not errors}
 print(json.dumps(result,indent=2));return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('build',nargs='?',default='docs/build');a=p.parse_args()
 raise SystemExit(0 if check(a.build)['valid'] else 1)
