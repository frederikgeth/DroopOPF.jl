"""Reuse better native witnesses only with identical controller and base.

No optimizer runs; preserve the raw separator ledger, including its poor local
resource allocations. Never combine states from different designs or bases.
"""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'targeted_demand_diagnostics'
EL=BASE/'emergency_loadability'
load=lambda p:json.loads(p.read_text())


def select(factor):
    summary=load(OUT/f'summary-emergency-{round(factor*10000)}.json');assert summary['qualified']
    group=next(r for r in summary['rounds'] if r['coverage'] and r['coverage']['accepted'])
    folder=BASE/group['selected_path'];stage=group['selected_stage']
    controller=load(folder/f'controller-{stage}.json')['data']['case']['controls']
    states=load(folder/f'point-{stage}.json')['states'];reference=next(r for r in states if r['id']=='base')
    master=load(folder/f'audit-{stage}.json');assert master['accepted']
    scan=load(EL/f"coverage/targeted-emergency-{round(factor*10000)}-round-{group['round']}/summary.json")
    replacements=[];entries=[]
    for original in scan['rows'][0]['rows']:
        entry=dict(original);source=EL/entry['path'];s=entry['stage']
        assert load(source/f'controller-{s}.json')['data']['case']['controls']==controller
        raw=load(source/f'point-{s}.json')['states'];base=next(r for r in raw if r['id']=='base')
        for key in ('state','taps','banks','dr','shed'):assert base[key]==reference[key]
        audit=load(source/f'audit-{s}.json');assert audit['accepted']
        old=next(r for r in audit['states'] if r['id']==entry['event'])
        candidate=next((r for r in master['states'] if r['id']==entry['event']),None)
        if candidate and (candidate['shedding_mw'],candidate['dr_mw'])<(old['shedding_mw']-1e-10,old['dr_mw']):
            entry.update(path='../'+group['selected_path'],stage=stage,reused_master_state=True,
                         selection_reason='Lower shedding at exactly identical controller and preventive base')
            replacements.append(dict(event=entry['event'],separator_shedding_mw=old['shedding_mw'],
                                     selected_shedding_mw=candidate['shedding_mw']))
        entries.append(entry)
    payload=dict(factor=factor,round=group['round'],entries=entries,replacements=replacements,
                 native_witnesses_only=True,optimizer_calls=0,common_controller_and_base_verified=True,
                 original_scan_sha256=hashlib.sha256((EL/f"coverage/targeted-emergency-{round(factor*10000)}-round-{group['round']}/summary.json").read_bytes()).hexdigest())
    (OUT/f'selected-operating-witnesses-{round(factor*10000)}.json').write_text(json.dumps(payload,indent=2)+'\n')
    print(json.dumps(dict(factor=factor,replacements=replacements,optimizer_calls=0)))


def compose_zero_shedding(factor):
    coverage_path=OUT/f'audit-emergency-{round(factor*10000)}-coverage.json'
    coverage=load(coverage_path);assert coverage['qualified']
    priority=load(OUT/'relief_priority_witness.json');assert priority['zero_shedding_constructed']
    derived_folder=BASE/priority['folder'];derived=load(derived_folder/'point-derived.json')
    validation=load(derived_folder/'network-audit-derived.json')
    assert validation['original_full_network_valid'] and validation['reduction_valid'] and not validation['native_success']
    controller=load(derived_folder/'controller-derived.json')['data']['case']['controls']
    summary=load(OUT/f'summary-emergency-{round(factor*10000)}.json')
    master=BASE/summary['selected_path'];stage=summary['selected_stage']
    assert controller==load(master/f'controller-{stage}.json')['data']['case']['controls']
    original=load(master/f'point-{stage}.json');base=next(r for r in original['states'] if r['id']=='base')
    assert next(r for r in derived['states'] if r['id']=='base')==base
    changed=[];events=coverage['rounds'][-1]['events'];assert len(events)==389
    for entry in events:
        assert entry['accepted']
        if entry['shedding_mw']>0:
            before=next(r for r in original['states'] if r['id']==entry['event'])
            after=next(r for r in derived['states'] if r['id']==entry['event'])
            for key in ('state','taps','banks','delta','artificial_max_pu'):assert before[key]==after[key]
            assert sum(after['shed'].values())==0.
            for key in before['dr']:
                assert abs(before['dr'][key]+before['shed'][key]-after['dr'][key]-after['shed'][key])<1e-12
            changed.append(entry['event'])
    result=dict(factor=factor,connected_outages=389,zero_shedding_feasible=True,
                derived_allocation_outages=changed,unchanged_native_zero_shedding_outages=389-len(changed),
                original_network_validation=True,controller_and_preventive_base_unchanged=True,
                optimizer_calls=0,native_optimization_result=False,minimum_dr_or_loss_established=False,
                canonical_coverage_audit_sha256=hashlib.sha256(coverage_path.read_bytes()).hexdigest(),
                derived_point_sha256=hashlib.sha256((derived_folder/'point-derived.json').read_bytes()).hexdigest(),
                derived_full_network_audit_sha256=hashlib.sha256((derived_folder/'network-audit-derived.json').read_bytes()).hexdigest())
    (OUT/'dr-first-connected-witness.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':
    import sys
    select(float(sys.argv[1]))
