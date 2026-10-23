"""Independently replay new fixed-controller connected-outage scans."""
import hashlib
import json
from pathlib import Path
from audit_s2_500bus_loadability import audit_point
from audit_s2_arpae500 import topology

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
OUT = BASE / 'finish_105_multidemand'
EL = BASE / 'emergency_loadability'
load = lambda p: json.loads(Path(p).read_text())


def audit(label, master, stage, factors, zero_shedding=False, output_root=OUT):
    source = load(BASE / 'pilot_study.json')['data']['case']
    islands = {x['branch'] for x in topology(source)['islands']}
    expected = {f"branch_{b['id']}" for b in source['network']['branches'] if b['available'] and b['id'] not in islands}
    expected |= {f"generator_{g['id']}" for g in source['generators'] if g['available']}
    assert len(expected) == 389
    master = BASE / master
    assert audit_point(master, stage)['accepted']
    controls = load(master / f'controller-{stage}.json')['data']['case']['controls']
    references = {r['factor']: r for r in load(master / f'point-{stage}.json')['states'] if r['id'] == 'base'}
    scan = EL / f'coverage/{label}/summary.json'
    saved = load(scan)
    rows, hashes = [], {}
    for group in saved['rows']:
        f = group['factor']; assert f in factors
        entries = []
        for entry in group['rows']:
            folder = EL / entry['path']; s = entry['stage']
            rawpath = folder / f'point-{s}.json'
            if not rawpath.exists():
                assert not entry['accepted']
                entries.append(dict(event=entry['event'], accepted=False, missing=True)); continue
            check = audit_point(folder, s)
            assert load(folder / f'controller-{s}.json')['data']['case']['controls'] == controls
            raw = load(rawpath)['states']
            base = next(r for r in raw if r['id'] == 'base' and r['factor'] == f)
            for field in ('state', 'taps', 'banks', 'dr', 'shed'):
                assert base[field] == references[f][field], field
            state = next(r for r in check['states'] if r['id'] == entry['event'] and r['factor'] == f)
            accepted = entry['accepted'] and check['accepted'] and state['valid']
            if zero_shedding and entry['accepted']:
                assert state['shedding_mw'] == 0.
            assert not entry['accepted'] or accepted
            entries.append(dict(event=entry['event'], accepted=accepted,
                                dr_mw=state['dr_mw'], shedding_mw=state['shedding_mw']))
            for p in (rawpath, folder / f'controller-{s}.json', folder / 'contract.json', folder / 'stages.json'):
                hashes[str(p.resolve().relative_to(ROOT))] = hashlib.sha256(p.read_bytes()).hexdigest()
        ids = {r['event'] for r in entries}; assert len(ids) == len(entries) and ids <= expected
        rows.append(dict(factor=f, qualified=ids == expected and all(r['accepted'] for r in entries),
                         evaluated=len(entries), passed=sum(r['accepted'] for r in entries),
                         unchecked=len(expected - ids), entries=entries))
    qualified = len(rows) == len(factors) and all(r['qualified'] for r in rows)
    assert qualified == saved['accepted']
    result = dict(qualified=qualified, factors=factors, rows=rows, zero_shedding=zero_shedding,
                  common_controller_and_per_demand_preventive_base_verified=True,
                  optimizer_calls=0, source_hashes=hashes, full_n1_accepted=False,
                  master=str(master.relative_to(BASE)), stage=stage)
    (Path(output_root) / f'audit-coverage-{label}.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(dict(qualified=qualified, rows=[{k: v for k, v in r.items() if k != 'entries'} for r in rows])))
    return result


if __name__ == '__main__':
    import sys
    audit(sys.argv[1], sys.argv[2], sys.argv[3],
          [float(f) for f in sys.argv[4].split(',')], sys.argv[5] == 'zero',
          Path(sys.argv[6]) if len(sys.argv) > 6 else OUT)
