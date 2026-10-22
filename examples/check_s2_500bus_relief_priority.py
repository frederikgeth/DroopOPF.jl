"""Construct and audit a DR-first allocation; never label it a native solve."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
from audit_s2_500bus_network_reduction import audit,BASE

load=lambda p:json.loads(Path(p).read_text())
save=lambda p,d:Path(p).write_text(json.dumps(d,indent=2)+'\n')


def check(root=None,selected=None):
    root=BASE/'free_droop_continuation' if root is None else Path(root).resolve()
    if selected is None:
        for file in ('selected-joint.json','selected-single-demand.json'):
            if (root/file).exists():selected=load(root/file);break
    if selected is None:return
    source=root/selected['name'];stage=selected['stage']
    assert load(source/f'network-audit-{stage}.json')['accepted']
    point=load(source/f'point-{stage}.json');controller=load(source/f'controller-{stage}.json')
    case=controller['data']['case'];loads={str(l['id']):l for l in case['loads']}
    derived=copy.deepcopy(point);rows=[]
    for old,new in zip(point['states'],derived['states']):
        replaced=0.
        for lid,l in loads.items():
            if old['id']=='base' or l['p']<=0:continue
            cap=.01*l['p']*old['factor']
            delta=max(0.,min(old['shed'][lid],cap-old['dr'][lid]))
            new['dr'][lid]+=delta;new['shed'][lid]-=delta;replaced+=delta
            assert abs((new['dr'][lid]+new['shed'][lid])-(old['dr'][lid]+old['shed'][lid]))<1e-12
        for key in ('state','taps','banks','delta','artificial_max_pu'):assert new[key]==old[key]
        scale=case['base_power']
        rows.append(dict(factor=old['factor'],outage=old['id'],
            original_dr_mw=sum(old['dr'].values())*scale,derived_dr_mw=sum(new['dr'].values())*scale,
            original_shedding_mw=sum(old['shed'].values())*scale,
            derived_shedding_mw=sum(new['shed'].values())*scale,replaced_shedding_mw=replaced*scale))
    folder=root/'relief_priority_witness'/f"{selected['name']}-{stage}";folder.mkdir(parents=True,exist_ok=True)
    record=dict(stage='derived',status='DERIVED_RELIEF_PRIORITY_WITNESS',native_success=False,
        elapsed_seconds=0.,optimizer_calls=0,
        objective=sum(sum(s['shed'].values()) for s in derived['states']),
        objective_label='sum_shedding_pu',parent_name=selected['name'],parent_native_stage=stage)
    derived['record']=record
    contract=load(source/'contract.json');contract['name']=str(folder.relative_to(BASE))
    contract['derived_witness_only']=True
    save(folder/'contract.json',contract);save(folder/'stages.json',[record])
    save(folder/'point-derived.json',derived);save(folder/'controller-derived.json',controller)
    shutil.copyfile(source/'network_reduction_maps.json',folder/'network_reduction_maps.json')
    ck=audit(folder,'derived')
    assert ck['original_full_network_valid'] and ck['reduction_valid']
    assert not ck['accepted'] and not ck['native_success'] and not ck['diagnostic_accepted']
    result=dict(selected=selected,folder=str(folder.relative_to(BASE)),optimizer_calls=0,
        original_electrical_states_and_controller_unchanged=True,
        original_full_network_valid=True,reconstruction_valid=True,
        native_solver_acceptance=False,minimum_shedding_established=False,rows=rows,
        zero_shedding_constructed=all(r['derived_shedding_mw']<=1e-12 for r in rows),
        parent_point_sha256=hashlib.sha256((source/f'point-{stage}.json').read_bytes()).hexdigest())
    save(root/'relief_priority_witness.json',result)
    print(json.dumps(result,indent=2))
    return result


if __name__=='__main__':check()
