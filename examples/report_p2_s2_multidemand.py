"""Summarize shared-demand scopes, never independent designs as one controller."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'artifacts/p2_s2_multidemand_20261022'
load=lambda p:json.loads(Path(p).read_text())
rows=[]
for stage in sorted(OUT.glob('stage-*')):
    p=stage/'500/progressive';sp=p/'summary.json'
    summary=load(sp) if sp.exists() else {'status':'running','rounds':[],'accepted':False}
    attempts=[{'record':r} for q in p.rglob('stages.json') for r in load(q)]
    contracts=list(p.glob('round-1/master/*/contract.json'))
    factors=load(contracts[0])['factors'] if contracts else []
    record=dict(stage=stage.name,factors=factors,status=summary['status'],accepted=summary.get('accepted',False),
                completed_rounds=len(summary['rounds']),optimizer_calls=len(attempts),
                build_seconds=sum(a['record']['build_seconds'] for a in attempts),solve_seconds=sum(a['record']['solve_seconds'] for a in attempts))
    cross=stage/'500/final-cross-file-audit.json'
    if cross.exists():record['independent_audit']=load(cross)
    if record['accepted']:
        last=summary['rounds'][-1];master=ROOT/last['master']['folder']
        base_power=load(master/'controller-solve.json')['data']['case']['base_power']
        states={(r['factor'],r['id']):r for r in load(master/'point-solve.json')['states']}
        for row in load(p/f"round-{last['round']}"/'scan/scan.json')['rows']:
            if row['path']:
                for r in load(ROOT/row['path']/'point-solve.json')['states']:
                    if r['id']==row['event']:states[(r['factor'],r['id'])]=r
        record['by_demand']=[dict(factor=f,states=sum(ff==f for ff,sid in states),max_dr_mw=max(sum(r['dr'].values())*base_power for (ff,sid),r in states.items() if ff==f),max_shedding_mw=max(sum(r['shed'].values())*base_power for (ff,sid),r in states.items() if ff==f)) for f in factors]
    rows.append(record)
result=dict(stages=rows,highest_exhaustively_accepted_shared_factors=next((r['factors'] for r in reversed(rows) if r['accepted']),[]),
            s2_reference=dict(shared_master_factors=[.9,.95,1.],exhaustive_independent_factor=1.05,nonexhaustive_expanded_master_factor=1.0625,expanded_witness_uses_shedding=True),
            p2_closed=False,physical_infeasibility_proven=False,s2_resumed=False)
if (OUT/'cross-demand-audit.json').exists():
    result['cross_demand_audit']=load(OUT/'cross-demand-audit.json')
    result['highest_exhaustively_accepted_shared_factors']=result['cross_demand_audit']['accepted_factors']
protocol=load(OUT/'protocol.json')
result['planned_factors']=protocol.get('factors',[])
attempted={f for row in rows for f in row['factors']}
result['not_attempted_factors']=[f for f in result['planned_factors'] if f not in attempted]
(OUT/'SUMMARY.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
