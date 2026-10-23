"""Replay each independent emergency design's connected-outage coverage."""
import hashlib
import json
from pathlib import Path
from audit_s2_500bus_loadability import audit_point
from audit_s2_arpae500 import topology

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'targeted_demand_diagnostics'
EL=BASE/'emergency_loadability'


def audit(factor):
    load=lambda p:json.loads(p.read_text())
    source=load(BASE/'pilot_study.json')['data']['case']
    islands={x['branch'] for x in topology(source)['islands']}
    expected={f"branch_{b['id']}" for b in source['network']['branches'] if b['available'] and b['id'] not in islands}
    expected|={f"generator_{g['id']}" for g in source['generators'] if g['available']}
    assert len(expected)==389
    label=f'emergency-{round(factor*10000)}';summary=load(OUT/f'summary-{label}.json')
    rounds=[];hashes={}
    for group in summary['rounds']:
        if group['coverage'] is None:continue
        master=BASE/group['selected_path'];stage=group['selected_stage']
        controller=load(master/f'controller-{stage}.json')['data']['case']['controls']
        reference=next(x for x in load(master/f'point-{stage}.json')['states'] if x['id']=='base' and x['factor']==factor)
        scan=EL/f"coverage/targeted-{label}-round-{group['round']}/summary.json"
        saved=load(scan);assert len(saved['rows'])==1 and saved['rows'][0]['factor']==factor
        entries=[]
        witness_path=OUT/f'selected-operating-witnesses-{round(factor*10000)}.json'
        ledger=load(witness_path) if witness_path.exists() else None
        candidates=ledger['entries'] if ledger and ledger['round']==group['round'] else saved['rows'][0]['rows']
        if ledger:assert ledger['original_scan_sha256']==hashlib.sha256(scan.read_bytes()).hexdigest()
        for entry in candidates:
            folder=EL/entry['path'];s=entry['stage']
            rawpath=folder/f'point-{s}.json'
            if not rawpath.exists():
                assert not entry['accepted'];entries.append(dict(event=entry['event'],accepted=False,missing=True));continue
            check=audit_point(folder,s)
            assert load(folder/f'controller-{s}.json')['data']['case']['controls']==controller
            raw=load(rawpath)['states'];base=next(x for x in raw if x['id']=='base' and x['factor']==factor)
            for field in ('state','taps','banks','dr','shed'):assert base[field]==reference[field],field
            state=next(x for x in check['states'] if x['id']==entry['event'] and x['factor']==factor)
            accepted=entry['accepted'] and check['accepted'] and state['valid']
            assert not entry['accepted'] or accepted
            entries.append(dict(event=entry['event'],accepted=accepted,dr_mw=state['dr_mw'],
                                shedding_mw=state['shedding_mw'],max_normal_loading_ratio=state['max_normal_loading_ratio'],
                                normal_voltage_departures=state['normal_voltage_departures'],
                                normal_thermal_departures=state['normal_thermal_departures']))
            for p in (rawpath,folder/f'controller-{s}.json',folder/'contract.json',folder/'stages.json'):
                hashes[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
        ids={x['event'] for x in entries};assert len(ids)==len(entries) and ids<=expected
        qualified=ids==expected and all(x['accepted'] for x in entries)
        assert qualified==saved['accepted']
        rounds.append(dict(round=group['round'],qualified=qualified,evaluated=len(entries),
                           passed=sum(x['accepted'] for x in entries),unchecked=len(expected-ids),events=entries))
    qualified=any(x['qualified'] for x in rounds)
    assert qualified==summary['qualified']
    result=dict(factor=factor,qualified=qualified,rounds=rounds,optimizer_calls=0,
                common_controller_and_preventive_base_verified=True,source_hashes=hashes,
                scope='Independent single-demand design; 389 connected outages; islanding remains separate')
    (OUT/f'audit-{label}-coverage.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(factor=factor,qualified=qualified,rounds=[{k:v for k,v in r.items() if k!='events'} for r in rounds])))
    return result


if __name__=='__main__':
    import sys
    audit(float(sys.argv[1]))
