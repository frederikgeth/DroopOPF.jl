"""Verify curated sources and every offline evidence link/hash."""
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
from urllib.parse import unquote, urlsplit
import zipfile

ROOT=Path(__file__).resolve().parents[2]
DOCS=ROOT/'docs/src'

class Page(HTMLParser):
    def __init__(self,text):
        super().__init__();self.ids=set();self.links=[];self.images=[];self.feed(text)
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:
            assert a['id'] not in self.ids, 'Duplicate HTML anchor'
            self.ids.add(a['id'])
        if tag=='a' and 'href' in a:self.links.append(a['href'])
        if tag=='img':
            assert a.get('alt'), 'Image needs a descriptive alt'
            self.images.append(a['src'])

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('bundle',type=Path);args=ap.parse_args()
    folder=args.bundle.resolve();catalog=json.loads((DOCS/'assets/validation/catalog.json').read_text())
    checked=0;verified=0;unavailable=0
    archived=ROOT/'release/research-v0.10.0-rc1/research-docs-files.json'
    archive=json.loads(archived.read_text()) if archived.exists() else None
    for r in catalog['records']:
        for doc in r['documentation']:assert (DOCS/doc).is_file(), doc
        for s in r['sources']:
            if s['availability']=='repository':
                assert hashlib.sha256((ROOT/s['path']).read_bytes()).hexdigest()==s['sha256'], 'Source hash drift: '+s['path']
                verified+=1
            elif s['availability']=='private archive':
                if archive is not None:
                    assert archive[s['path']]==s['sha256'], 'Archive source hash mismatch'
                    verified+=1
                else:unavailable+=1
            elif s['availability'] in ('private campaign','private package'):
                local=ROOT/s['path']
                if local.exists():
                    assert hashlib.sha256(local.read_bytes()).hexdigest()==s['sha256'], 'Private source hash drift'
                    verified+=1
                else:unavailable+=1
            else:raise ValueError('Unknown source availability')
            checked+=1
    manifest=json.loads((folder/'MANIFEST.json').read_text())
    expected={'index.html','reports.html','tables.html','figures.html','provenance.html','catalog.json','summary.json',*['assets/'+f['asset'] for f in catalog['figures']]}
    assert set(manifest['files'])==expected, 'Unexpected files in sharing manifest'
    actual={str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file()}
    assert actual==expected|{'MANIFEST.json'}, 'Unexpected files in sharing directory'
    for name,digest in manifest['files'].items():
        assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest, 'Bundle hash drift: '+name
    pages={name:Page((folder/name).read_text()) for name in expected if name.endswith('.html')}
    links=0
    for name,page in pages.items():
        for href in page.links+page.images:
            u=urlsplit(href)
            assert not u.scheme and not u.netloc, 'Bundle must work offline: '+href
            dest=(folder/Path(name).parent/unquote(u.path)).resolve() if u.path else folder/name
            assert dest.is_relative_to(folder), 'Link escapes sharing directory'
            assert dest.is_file(), 'Missing link: '+href
            if u.fragment:assert unquote(u.fragment) in pages[str(dest.relative_to(folder))].ids, 'Missing anchor: '+href
            links+=1
    for r in catalog['records']:
        for p in ('reports.html','tables.html','provenance.html'):assert r['id'].lower() in pages[p].ids
    with zipfile.ZipFile(folder.with_suffix('.zip')) as z:
        names={str(Path(p).relative_to(folder.name)) for p in z.namelist()}
        assert names==actual, 'ZIP scope differs from reviewed directory'
        for member in z.namelist():
            local=folder/Path(member).relative_to(folder.name)
            assert z.read(member)==local.read_bytes(), 'ZIP content drift'
    print(json.dumps(dict(labels=len(catalog['records']),source_identities=checked,verified_source_identities=verified,unavailable_private_identities=unavailable,offline_links_checked=links,bundled_files=len(actual),private_archive_payloads=0,all_passed=True)))

if __name__=='__main__':main()
