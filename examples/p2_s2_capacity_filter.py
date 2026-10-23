"""Necessary active-balance certificate for the isolated S2 proportional policy.

Exact rational arithmetic on serialized binary64 data. No positive feasibility
claim: nonpositive gaps and unsupported data always route to native AC solves.
Corrective taps and continuous banks cannot remove a total active-power deficit
when every series resistance and shunt conductance is nonnegative.
"""
from fractions import Fraction as F
import math

def capacity_certificate(study, base, event, factor=1., tolerance=1e-6, active_response=None):
    case=study['case']; net=case['network']
    uncertain=lambda reason:dict(certified_infeasible=False,reason=reason,route='exact')
    if active_response!='s2_proportional_v1':return uncertain('unsupported_response_policy')
    if study.get('mode','preventive')!='preventive':return uncertain('unsupported_dispatch_policy')
    if study.get('reactive_assignments') is not None:return uncertain('explicit_reactive_policy_unsupported')
    if any(a.get('priority','unit')!='unit' for a in case['attachments']):return uncertain('attachment_policy_unsupported')
    if len(base['state']['pg'])!=len(case['generators']):return uncertain('base_dimension')
    if not math.isfinite(factor) or factor<0:return uncertain('invalid_demand_factor')
    if not math.isfinite(tolerance) or tolerance<0:return uncertain('invalid_tolerance')
    tol=F(tolerance)
    if any(not math.isfinite(w) for w in study['participation'].values()):return uncertain('nonfinite_participation')
    physical=[case['base_power']]+[l['p'] for l in case['loads']]
    physical += [g[k] for g in case['generators'] for k in ('p_min','p_max')]
    physical += [b['resistance'] for b in net['branches'] if b['available']]
    physical += [s['conductance'] for s in net['shunts'] if s['available']]
    physical += [g for b in net['banks'] if b['available'] for g in b['step_conductances']]
    physical += [cap['capability'][k] for cap in case['controls'] for k in ('p_min','p_max')]
    if not all(math.isfinite(v) for v in physical) or case['base_power']<=0:return uncertain('invalid_physical_data')
    if any(not math.isfinite(v) or v<0 for v in study['redispatch_limits'].values()):return uncertain('invalid_movement_limit')
    if any(not math.isfinite(v) for v in base['state']['pg']):return uncertain('nonfinite_base')
    if any(b['resistance']<0 for b in net['branches'] if b['available']):return uncertain('nonpassive_branch')
    if any(s['conductance']<0 for s in net['shunts'] if s['available']):return uncertain('nonpassive_shunt')
    if any(any(g<0 for g in b['step_conductances']) for b in net['banks'] if b['available']):return uncertain('nonpassive_bank')
    lost=set(event.get('generator_ids',[])); surviving=[(i,g) for i,g in enumerate(case['generators']) if g['available'] and g['id'] not in lost]
    total=sum((F(study['participation'].get(str(g['id']),0.)) for _,g in surviving),F(0))
    if total<=0:return uncertain('no_surviving_participant')
    controls={a['generator_id']:case['controls'][a['control_id']-1] for a in case['attachments']}
    lower=None;upper=None;fixed_total=F(0)
    for i,g in surviving:
        pg=F(base['state']['pg'][i]);fixed_total+=pg
        lo=F(g['p_min'])-tol;hi=F(g['p_max'])+tol
        if g['id'] in controls:
            cap=controls[g['id']]['capability'];lo=max(lo,F(cap['p_min'])-tol);hi=min(hi,F(cap['p_max'])+tol)
        limit=study['redispatch_limits'].get(str(g['id']))
        if limit is not None:lo=max(lo,pg-F(limit)-tol);hi=min(hi,pg+F(limit)+tol)
        alpha=F(study['participation'].get(str(g['id']),0.))/total
        if alpha<0:return uncertain('negative_participation')
        if alpha==0:
            if not lo<=pg<=hi:return uncertain('nonresponding_base_outside_bounds')
            continue
        # Allow the same per-generator response residual as the physical auditor.
        a=(lo-pg-tol)/alpha;b=(hi-pg+tol)/alpha
        lower=a if lower is None else max(lower,a);upper=b if upper is None else min(upper,b)
    if upper is None:return uncertain('unbounded_signal')
    load=sum((F(l['p'])*F(factor) for l in case['loads']),F(0))
    dr=sum((F(.01)*F(l['p'])*F(factor)+tol for l in case['loads'] if l['p']>0),F(0))
    shedding=F(10)/F(case['base_power'])+tol
    # Sum of bus balance tolerances and response residuals makes the exclusion
    # robust to the existing independent validator, rather than exact equalities only.
    residual_allowance=(len(net['buses'])+len(surviving))*tol
    maximum_generation=fixed_total+upper+len(surviving)*tol
    minimum_demand=load-dr-shedding-residual_allowance
    gap=minimum_demand-maximum_generation
    return dict(certified_infeasible=gap>0,reason='passive_active_balance_deficit' if gap>0 else 'inconclusive',
                route='certified_infeasible' if gap>0 else 'exact',gap_pu=float(gap),exact_gap=str(gap),
                max_generation_pu=float(maximum_generation),minimum_served_demand_pu=float(minimum_demand),
                response='s2_proportional_v1',corrective_equipment='unchanged absolute bounds; passive loss lower bound zero',
                feasible_prediction=False)
