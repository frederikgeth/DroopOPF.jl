"""Verify cross-file controller/base identity and exhaustive final coverage."""
import json,sys
from pathlib import Path
from audit_p2_s2_numerics import audit
ROOT=Path(__file__).resolve().parents[1]
load=lambda p:json.loads(Path(p).read_text())
def verify(root,size):
    p=Path(root)/str(size)/'progressive';summary=load(p/'summary.json')
    rounds=summary.get('rounds',[])
    assert rounds,'No completed scan to verify'
    last=rounds[-1];master=ROOT/last['master']['folder']
    mpoint=load(master/'point-solve.json');mstudy=load(master/'controller-solve.json')['data']
    ma=audit(master);assert ma['accepted']
    states={(r['factor'],r['id']):r for r in ma['states']}
    bases={r['factor']:r for r in mpoint['states'] if r['id']=='base'}
    scan=load(p/f"round-{last['round']}"/'scan/scan.json')
    assert scan['complete'] and len(scan['rows'])==(24 if size==14 else 389)
    ids={r['event'] for r in scan['rows']};assert len(ids)==len(scan['rows'])
    # Ranking catalogue is exported from the actual connected-contingency builder.
    catalogue=load(Path(root)/str(size)/'catalogue.json')
    assert ids=={r['id'] for r in catalogue}
    accepted=0
    for row in scan['rows']:
        if not row['accepted']:continue
        if row['path'] is None:
            assert all(any(r['factor']==f and r['id']==row['event'] for r in mpoint['states']) for f in bases)
        else:
            q=ROOT/row['path'];contract=load(q/'contract.json')
            assert contract['fixed_base'] and contract['fixed_controller']
            assert contract['outages']==[row['event']]
            qa=audit(q);assert qa['accepted']
            states.update({(r['factor'],r['id']):r for r in qa['states'] if r['id']==row['event']})
            point=load(q/'point-solve.json');study=load(q/'controller-solve.json')['data']
            assert study['case']['controls']==mstudy['case']['controls']
            for r in point['states']:
                if r['id']=='base':assert all(r[k]==bases[r['factor']][k] for k in ('state','taps','banks'))
        accepted+=1
    result=dict(round=last['round'],outages=len(ids),accepted_outages=accepted,
                common_controller_and_preventive_bases_verified=True,
                exhaustive_accepted=accepted==len(ids),physical_infeasibility_proven=False,
                unique_validated_states=len(states),max_balance_residual_pu=max(r['balance'] for r in states.values()),
                max_response_residual_pu=max(r['coupling'] for r in states.values()),
                max_dr_mw=max(r['dr_mw'] for r in states.values()))
    (Path(root)/str(size)/'final-cross-file-audit.json').write_text(json.dumps(result,indent=2)+'\n')
    return result
if __name__=='__main__':
    print(json.dumps(verify(sys.argv[1],int(sys.argv[2])),indent=2))
