"""Summarize checked S1 outcomes; never infer infeasibility from solver status."""
from pathlib import Path
import json
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/s1_arpae14_gated"

def report():
    path = OUT / "primary_matrix_summary.json"
    rows = json.loads((path if path.exists() else OUT / "matrix_summary.json").read_text())
    assert len({r['name'] for r in rows}) == len(rows)
    groups = []
    families = ['fixed', 'droop', 'tap', 'shunt', 'tap_shunt', 'tap_droop', 'shunt_droop', 'joint']
    for variant in ['no_deadband', 'with_deadband']:
        for family in families:
            cells = [r for r in rows if r['tags']['variant'] == variant and r['tags']['family'] == family]
            groups.append(dict(variant=variant, family=family, attempts=len(cells),
                verified_points=sum(r.get('point_pass',False) for r in cells),
                solver_success=sum(r['solver_success'] for r in cells),
                calibration_pass=sum(r['calibration_pass'] for r in cells),
                qualified_points=sum(r.get('replacement_qualified',False) and r.get('point_pass',False) for r in cells),
                unresolved=sum(r['gate_status']=='unresolved' for r in cells),
                attempts_without_verified_point=sum(not r.get('point_pass',False) for r in cells),
                certified_infeasible=sum(r['gate_status']=='certified_infeasible' for r in cells),
                by_solver={s:dict(attempts=sum(r['solver']==s for r in cells),
                    verified_points=sum(r['solver']==s and r.get('point_pass',False) for r in cells))
                    for s in ['ipopt','madnlp','ccopt']},
                by_demand={str(f):dict(attempts=sum(r['tags']['factor']==f for r in cells),
                    verified_points=sum(r['tags']['factor']==f and r.get('point_pass',False) for r in cells)) for f in [.9,1.,1.1]}))
    passed = [r for r in rows if r.get('point_pass',False)]
    residuals = {}
    for key in ['power_balance_max','droop_residual_max','voltage_min_margin','voltage_max_margin',
                'branch_thermal_min_margin','generator_p_min_margin','generator_p_max_margin',
                'generator_q_min_margin','generator_q_max_margin']:
        vals=[(r['point_checks']['physical'].get(key),r['name']) for r in passed]
        vals=[(v,n) for v,n in vals if isinstance(v,(float,int))]
        if vals:
            value,name = max(vals) if key.endswith('_max') else min(vals)
            residuals[key]={'value':value,'case':name}
    payload=dict(completed=len(rows),planned=459,verified_points=len(passed),groups=groups,
        total_stress_attempts_including_uncoupled_diagnostics=675,
        qualified_droop_points=sum(r.get('replacement_qualified',False) and r.get('point_pass',False) for r in rows),
        solver_summary={solver:{variant:sum(r.get('point_pass',False) for r in rows if r['solver']==solver and r['tags']['variant']==variant) for variant in ['source','no_deadband','with_deadband']} for solver in ['ipopt','madnlp','ccopt']},
        source_verified=sum(r.get('point_pass',False) for r in rows if r['tags']['variant']=='source'),
        errors={r['name']:r['error'] for r in rows if 'error' in r},
        solver_statuses=dict(Counter(r.get('solver_status','error') for r in rows)),
        verified_point_extremes=residuals,
        interpretation='Verified operating points are distinct from qualification of frozen curves across all demand conditions. Unresolved is not infeasible.')
    (OUT/'scorecard.json').write_text(json.dumps(payload,indent=2)+'\n')
    print(f"Completed {len(rows)}/459; source verified {payload['source_verified']}/27; errors {len(payload['errors'])}")
    print('| Controls | No deadband: verified / attempted | With deadband: verified / attempted |')
    print('|---|---:|---:|')
    for family in families:
        counts=[next(f"{g['verified_points']}/{g['attempts']}" for g in groups if g['variant']==v and g['family']==family) for v in ['no_deadband','with_deadband']]
        print(f'| {family} | {counts[0]} | {counts[1]} |')
    return payload

if __name__ == '__main__':
    report()
