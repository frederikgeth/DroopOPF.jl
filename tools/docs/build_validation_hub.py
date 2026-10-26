"""Build the curated documentation hub and an offline share bundle.

Only catalogued summaries/figures are copied. Private archives, network inputs,
solver logs and live campaign directories are never traversed for bundling.
"""
from pathlib import Path
import argparse
import hashlib
import html
import json
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/src'
ASSETS = DOCS / 'assets/validation'
CATALOG = ASSETS / 'catalog.json'


def esc(value):
    return html.escape(str(value), quote=True)


def anchor(record, kind):
    return f'evidence-{record["id"].lower()}-{kind}'


def md_table(headers, rows):
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join('---' for _ in headers) + ' |'] + ['| ' + ' | '.join(str(c).replace('|', '\\|') for c in row) + ' |' for row in rows])


def markdown(c):
    index = ['# Milestones and validation', '', 'Choose a label to see its report, validation tables or available figures. **M** labels describe library capabilities; **S** labels describe study campaigns; **P** labels describe development priorities. They overlap and are not independent experiments to add together.', '', 'Implementation, numerical acceptance and research closure are separate. Historical results retain their original policies and dates.']
    for prefix, title in [('M', 'Capability milestones'), ('S', 'Study campaigns'), ('P', 'Development priorities')]:
        rows = []
        for r in c['records']:
            if not r['id'].startswith(prefix):
                continue
            links = [f'[Report](@ref {anchor(r,"report")})', f'[Tables](@ref {anchor(r,"tables")})', f'[Figures](@ref {anchor(r,"figures")})' if r['figures'] else '—']
            rows.append([r['id'], r['meaning'], r['status'], *links])
        index += ['', '## ' + title, '', md_table(['ID', 'What it does', 'Status / scope', 'Report', 'Tables', 'Figures'], rows)]
    index += ['', '## Sharing and provenance', '', 'Use the [reports](validation_reports.md), [tables](validation_tables.md) and [figure gallery](validation_figures.md) separately. The [evidence register](validation_evidence.md) records source identities and the portable sharing format. Full research archives remain private; a dash means no figure is bundled for that label. Historical figure sets remain private.']
    reports = ['# Validation reports', '', 'These are curated report summaries, organized by milestone or workstream. Numerical tables and figures live on separate pages; full private historical reports remain in the [research archives](research.md). No historical campaign is rerun by rebuilding these pages.']
    tables = ['# Validation tables', '', 'Recorded outcomes retain their original scope. Historical assertion counts are checkpoint records, not current test results. Solver convergence, physical replay, operating limits, policy and coverage are distinct acceptance gates.']
    for r in c['records']:
        reports += ['', f'## [{r["id"]} — {r["title"]}](@id {anchor(r,"report")})', '', '**Purpose.** ' + r['meaning'], '', '**Status.** ' + r['status'] + '.', '', '**Scope and assumptions.** ' + r['scope'], '', '**Validation.** ' + r['method'], '', '**Boundary.** ' + r['boundary']]
        if r['slices']:
            reports += ['', '**Slices.** ' + '; '.join(f'{s["id"]}: {s["meaning"]}' for s in r['slices']) + '.']
        reports += ['', f'[Validation tables](@ref {anchor(r,"tables")})' + (f' · [Figures](@ref {anchor(r,"figures")})' if r['figures'] else ' · Figures: retained privately / none bundled') + ' · [Source register](validation_evidence.md)', '', 'Model and workflow documentation: ' + ', '.join(f'[{p.removesuffix(".md").replace("_"," ")}]({p})' for p in r['documentation']) + '.']
        tables += ['', f'## [{r["id"]} — {r["title"]}](@id {anchor(r,"tables")})', '', md_table(['Check / comparison', 'Recorded result'], [(f['check'], f['result']) for f in r['findings']]), '', f'[Report](@ref {anchor(r,"report")})' + (f' · [Figures](@ref {anchor(r,"figures")})' if r['figures'] else '')]
    figs = {f['id']: f for f in c['figures']}
    figures = ['# Validation figures', '', 'Selected numerical figures are shown separately from reports and tables. They explain the recorded checks; images alone do not establish acceptance. Figure sets that remain in private archives are not silently treated as published evidence.']
    for r in c['records']:
        if not r['figures']:
            continue
        figures += ['', f'## [{r["id"]} — {r["title"]}](@id {anchor(r,"figures")})', '', f'[Report](@ref {anchor(r,"report")}) · [Tables](@ref {anchor(r,"tables")})']
        for key in r['figures']:
            f = figs[key]
            figures += ['', f'### {f["title"]}', '', f'![{f["title"]}](assets/validation/{f["asset"]})', '', f['caption']]
    figures += ['', '## Reproduction', '', 'The historical tap-sweep image is copied unchanged. The two P2 plots can be regenerated from the bundled compact summary using `python3 tools/release/plot_validation_references.py` with matplotlib. This redraws saved numerical data and does not rerun optimization. See the [compact numerical summary](assets/validation/summary.json) and [source register](validation_evidence.md).']
    provenance = ['# Validation evidence register', '', 'The [milestone index](milestones.md) is the clean entry point. Read [reports](validation_reports.md), [tables](validation_tables.md) or [figures](validation_figures.md) independently.', '', '## What can be shared', '', c['sharing'], '', 'The portable HTML bundle has `index.html`, `reports.html`, `tables.html`, `figures.html`, `provenance.html`, the curated JSON catalogue, three selected figures and a SHA-256 manifest. It works offline. Share the complete ZIP so relative links and images stay together. The full research archives, network inputs, solver logs and unfinished campaign payloads are excluded.', '', 'Build or refresh the documentation and local bundle:', '', '```sh', 'python3 tools/docs/build_validation_hub.py --bundle release/validation-share-20261026', 'python3 tools/docs/build_validation_hub.py --check', '```', '', 'The command creates a local reviewable bundle; it does not upload, email or publish it. Full originals remain available through the [private archive restoration workflow](research.md). Hashes identify originals but do not make those private files publicly reproducible.', '', '## Source identities', '', 'The catalogue is dated ' + c['updated'] + '. [Download the catalogue](assets/validation/catalog.json) for full SHA-256 values and machine-readable definitions, findings and figure captions. [The P2 compact summary](assets/validation/summary.json) also records the selected result, replay and sealed-manifest identities.']
    rows = []
    for r in c['records']:
        for s in r['sources']:
            rows.append([r['id'], '`' + s['path'] + '`', s['availability'], '`' + s['sha256'][:16] + '…`'])
    provenance += ['', md_table(['Label', 'Source locator', 'Availability', 'SHA-256 prefix'], rows), '', '## Maintenance', '', 'Update `docs/src/assets/validation/catalog.json` when evidence changes, retain the source identity and campaign policy, then regenerate these pages. New physical/control policies require a new campaign record. Preserve failed attempts and distinguish an implementation milestone from study closure. Current deadband results remain separate from historical S1/S2 closure until the new campaign is finalized.']
    return {'milestones.md': index, 'validation_reports.md': reports, 'validation_tables.md': tables, 'validation_figures.md': figures, 'validation_evidence.md': provenance}


STYLE = '''body{font:16px/1.6 system-ui,sans-serif;color:#1e293b;max-width:1180px;margin:auto;padding:24px;background:#fff}nav{display:flex;gap:22px;flex-wrap:wrap;border-bottom:1px solid #cbd5e1;padding:12px 0;background:#fff;position:sticky;top:0;z-index:10}a{color:#075985}h1{font-size:2rem;line-height:1.2}h2{margin-top:2.5rem;border-top:1px solid #e2e8f0;padding-top:1rem}table{border-collapse:collapse;width:100%;font-size:.91rem;margin:20px 0}th,td{text-align:left;vertical-align:top;border-bottom:1px solid #e2e8f0;padding:10px}th{background:#f1f5f9}img{max-width:100%;height:auto}section{scroll-margin-top:75px}small{color:#475569}code{overflow-wrap:anywhere}.table-wrap{overflow-x:auto}footer{margin-top:40px;border-top:1px solid #cbd5e1;padding-top:16px}'''


def table(headers, rows):
    return '<div class="table-wrap"><table><thead><tr>' + ''.join('<th>' + esc(h) + '</th>' for h in headers) + '</tr></thead><tbody>' + ''.join('<tr>' + ''.join('<td>' + cell + '</td>' for cell in row) + '</tr>' for row in rows) + '</tbody></table></div>'


def portable(c):
    index = '<h1>DroopOPF validation and study evidence</h1><p>Choose a capability milestone (M), study campaign (S) or development priority (P). Each label links separately to its report, validation tables and available figures.</p><p><small>Curated snapshot: ' + esc(c['updated']) + '. Historical contracts are retained; overlapping labels are not independent experiments.</small></p>'
    reports = '<h1>Validation reports</h1><p>Curated summaries. Full historical reports remain private.</p>'
    tables = '<h1>Validation tables</h1><p>Native convergence, independent physical replay, policy and coverage are separate gates. Historical checkpoint counts are not fresh test runs.</p>'
    figures = '<h1>Validation figures</h1><p>Selected saved numerical evidence. A figure alone does not establish acceptance.</p>'
    provenance = '<h1>Evidence and sharing</h1><p>' + esc(c['sharing']) + '</p><p>Share the complete ZIP; open index.html after extraction. All links and figures work offline. MANIFEST.json records SHA-256 values for bundled files. The catalogue records full source identities and figure captions.</p><p><a href="catalog.json">Machine-readable catalogue</a> · <a href="summary.json">Compact numerical summary</a> · <a href="MANIFEST.json">Bundle manifest</a></p>'
    figs = {f['id']: f for f in c['figures']}
    for prefix, title in [('M', 'Capability milestones'), ('S', 'Study campaigns'), ('P', 'Development priorities')]:
        rows = []
        for r in c['records']:
            if r['id'].startswith(prefix):
                key = r['id'].lower()
                rows.append([esc(r['id']), esc(r['meaning']), esc(r['status']), f'<a href="reports.html#{key}">Report</a>', f'<a href="tables.html#{key}">Tables</a>', f'<a href="figures.html#{key}">Figures</a>' if r['figures'] else '—'])
        index += '<h2>' + title + '</h2>' + table(['ID', 'What it does', 'Status / scope', 'Report', 'Tables', 'Figures'], rows)
    index += '<p><a href="provenance.html">Sharing instructions and source identities</a>. A dash means no figure is bundled for that label. Full research archives, network inputs and solver logs are excluded. The new deadband study is still in progress and does not replace historical S1/S2 outcomes.</p>'
    for r in c['records']:
        key = r['id'].lower();head = '<section id="' + key + '"><h2>' + esc(r['id'] + ' — ' + r['title']) + '</h2>'
        reports += head
        for label, field in [('Purpose','meaning'),('Status','status'),('Scope and assumptions','scope'),('Validation','method'),('Boundary','boundary')]:
            reports += '<p><strong>' + label + '.</strong> ' + esc(r[field]) + '</p>'
        if r['slices']:
            reports += '<p><strong>Slices.</strong> ' + esc('; '.join(s['id'] + ': ' + s['meaning'] for s in r['slices'])) + '.</p>'
        reports += '<p>Repository documentation: ' + ', '.join('<code>docs/src/' + esc(p) + '</code>' for p in r['documentation']) + '.</p><p><a href="tables.html#' + key + '">Tables</a>' + (' · <a href="figures.html#' + key + '">Figures</a>' if r['figures'] else ' · Figures retained privately / none bundled') + ' · <a href="provenance.html#' + key + '">Sources</a></p></section>'
        tables += head + table(['Check / comparison','Recorded result'], [[esc(f['check']),esc(f['result'])] for f in r['findings']]) + '<a href="reports.html#' + key + '">Report</a>' + (' · <a href="figures.html#' + key + '">Figures</a>' if r['figures'] else '') + '</section>'
        provenance += head + table(['Source locator','Availability','SHA-256'], [[esc(s['path']),esc(s['availability']),'<code>' + esc(s['sha256']) + '</code>'] for s in r['sources']]) + '</section>'
        if r['figures']:
            figures += head
            for name in r['figures']:
                f = figs[name]
                figures += '<h3>' + esc(f['title']) + '</h3><img src="assets/' + esc(f['asset']) + '" alt="' + esc(f['title']) + '"><p>' + esc(f['caption']) + '</p>'
            figures += '<p><a href="reports.html#' + key + '">Report</a> · <a href="tables.html#' + key + '">Tables</a></p></section>'
    body = {'index.html':index,'reports.html':reports,'tables.html':tables,'figures.html':figures,'provenance.html':provenance}
    pages = {}
    for name, content in body.items():
        nav = '<nav>' + ' '.join('<a href="' + n + '">' + label + '</a>' for n,label in [('index.html','Index'),('reports.html','Reports'),('tables.html','Tables'),('figures.html','Figures'),('provenance.html','Evidence & sharing')]) + '</nav>'
        pages[name] = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DroopOPF validation — ' + esc(name.removesuffix('.html')) + '</title><style>' + STYLE + '</style></head><body>' + nav + '<main>' + content + '</main><footer><small>Curated validation evidence. No new campaign is run by generating this bundle.</small></footer></body></html>\n'
    return pages


def build_bundle(c, destination):
    destination = destination.resolve()
    if destination.exists() and not (destination/'MANIFEST.json').is_file():
        raise ValueError('Refusing to overwrite a directory without a generated bundle manifest')
    destination.mkdir(parents=True, exist_ok=True)
    files = []
    for name, content in portable(c).items():
        (destination/name).write_text(content, encoding='utf-8');files.append(name)
    for filename in ['catalog.json','summary.json']:
        shutil.copyfile(ASSETS/filename,destination/filename);files.append(filename)
    for f in c['figures']:
        source=ASSETS/f['asset']
        assert hashlib.sha256(source.read_bytes()).hexdigest()==f['sha256'], 'Curated figure hash drift'
        target=destination/'assets'/f['asset'];target.parent.mkdir(exist_ok=True)
        shutil.copyfile(source,target);files.append('assets/'+f['asset'])
    manifest=dict(schema_version=1,updated=c['updated'],scope=c['sharing'],files={name:hashlib.sha256((destination/name).read_bytes()).hexdigest() for name in sorted(files)})
    (destination/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n');files.append('MANIFEST.json')
    bundle=destination.with_suffix('.zip')
    with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
        for name in sorted(files):z.write(destination/name,arcname=destination.name+'/'+name)
    print(str(bundle.relative_to(ROOT)) if bundle.is_relative_to(ROOT) else str(bundle))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--check',action='store_true',help='Fail if generated documentation differs; do not write')
    p.add_argument('--bundle',type=Path,help='Create an offline curated HTML directory and ZIP')
    args=p.parse_args();c=json.loads(CATALOG.read_text());changed=[]
    ids=[r['id'] for r in c['records']]
    assert len(ids)==len(set(ids)), 'Duplicate milestone label'
    assert all(re.fullmatch(r'[MSP]\d+',key) for key in ids), 'Invalid milestone label'
    assert {*[f'M{i}' for i in range(1,11)],'S1','S2',*[f'P{i}' for i in range(4)]}.issubset(ids), 'Required milestone missing'
    for name,lines in markdown(c).items():
        content='\n'.join(lines)+'\n';target=DOCS/name
        if args.check:
            if not target.exists() or target.read_text()!=content:changed.append(name)
        else:target.write_text(content,encoding='utf-8')
    if changed:raise SystemExit('Generated pages differ: '+', '.join(changed))
    if args.bundle:build_bundle(c,args.bundle)
    print(f'{len(ids)} labels; reports/tables/figures navigation generated' if not args.check else 'Generated documentation is current')


if __name__=='__main__':main()
