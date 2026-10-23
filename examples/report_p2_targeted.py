"""Independent original-policy identity and full-catalogue diagnostic report."""
import json,sys
from pathlib import Path
from report_mixed_avr_reserve import summarize

def load(p):return json.loads(Path(p).read_text())
def policy_identity(before,after,oldspec,newspec):
    keys=['case','mode','participation','redispatch_limits','tap_controls','shunt_controls','control_policy','reactive_assignments']
    same=len(before)==len(after) and all(a[k]==b[k] for a,b in zip(before,after) for k in keys)
    contract=['factors','duration_hours','ramps','angles','response','s2_emergency','avr_bounds','avr_movement_per_hour','reserve_generator_outages','reserve_margin_pu']
    same &= all(oldspec[k]==newspec[k] for k in contract)
    same &= {c['control_id']:c['bounds'] for c in oldspec['droop_controls']}=={c['control_id']:c['bounds'] for c in newspec['droop_controls']}
    return bool(same)

def report(root,candidate="joint-five"):
    root=Path(root);repo=Path(__file__).resolve().parents[1];parent=root/candidate;old=repo/'artifacts/p2_mixed_limit_aware_20261023/p2-base'
    d=summarize(root,candidate)
    previous=[load(old/f'period-{t}.json')['data'] for t in range(1,6)]
    current=[load(parent/f'period-{t}.json')['data'] for t in range(1,6)]
    same=policy_identity(previous,current,load(old/'contract.json'),load(parent/'contract.json'))
    if not same:raise ValueError('original P2 physical/control policy identity failed')
    original=load(old/'result.json')['data'];result=load(parent/'result.json')['data']
    gs=current[2]['case']['generators'];base_mva=current[2]['case']['base_power']
    old_peak=sum(g['p_max']-original['periods'][2]['states']['base']['pg'][i] for i,g in enumerate(gs) if g['available'])*base_mva
    new_peak=sum(g['p_max']-result['periods'][2]['states']['base']['pg'][i] for i,g in enumerate(gs) if g['available'])*base_mva
    changes=[]
    for t,(a,b) in enumerate(zip(original['periods'],result['periods'])):
        gs=current[t]['case']['generators'];delta=[(b['states']['base']['pg'][i]-a['states']['base']['pg'][i])*current[t]['case']['base_power'] for i in range(len(gs))]
        i=max(range(len(gs)),key=lambda i:abs(delta[i]))
        changes.append(dict(period=t+1,largest_pg_change_mw=delta[i],generator=gs[i]['id'],total_absolute_pg_change_mw=sum(map(abs,delta)),
            largest_avr_target_change_pu=max(abs(result['avr_targets'][t][k]-original['avr_targets'][t][k]) for k in result['avr_targets'][t])))
    proof=dict(valid=same,physical_relaxations_used=[],original_policy_unchanged=True,
        change='Preventive dispatch, shared droop settings and AVR schedule reoptimized; feasibility objective instead of reserve maximization',changes=changes,
        reserve_note='Previous reserve-aware solution was a warm start; maintaining its 21.58% minimum headroom was not required. No claim that higher reserve is infeasible.')
    (root/'original-policy-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
    (root/'reserve-aggregate-checks.json').write_text(json.dumps(d,indent=2)+'\n')
    failed=', '.join(r['event'] for r in d['rows'] if not r['valid']) or 'none'
    avr='\n'.join('| '+str(g)+' | '+' | '.join(f"{float(t[str(g)]):.8f}" for t in d['avr_targets'])+' |' for g in sorted(map(int,d['avr_targets'][0])))
    attempts=[]
    for path in sorted(root.iterdir()):
        if path.is_dir() and (path/'summary.json').exists() and (path/'result.json').exists():
            z=load(path/'summary.json')
            if 'status' in z:attempts.append(f"| `{path.name}` | {z['states']} | {z['status']} | {z['accepted']} |")
    attempt_table='\n'.join(attempts)
    text=f'''# P2 targeted recovery under original limits

Selected candidate: `{candidate}`.

**No physical-limit relaxation was needed to satisfy outages 21, 36 and 562 jointly.**
Individual base-plus-outage models first passed at 105% demand. One common peak
model then passed, followed by a common five-period model with 20 validated states.
The native five-period model uses shared droop settings and a preventive AVR
schedule with the original inter-period movement and generator ramp limits.

The successful recovery objective was feasibility. The earlier reserve-aware
candidate supplied initialization, but its dispatch, curves and AVR targets were
reopened for optimization. No constraint requiring 21.58% minimum headroom was
added. The result does not establish that higher reserve is infeasible, or prove
that the earlier solver failures had a single physical cause.

The minimum per-unit headroom metric is not aggregate reserve. At 105% demand,
summed Pmax minus Pg is **{new_peak:.3f} MW**, compared with **{old_peak:.3f} MW**
for the prior candidate. This static headroom does not itself certify deliverability;
the contingency assessments enforce network and response constraints.

## Configuration and relaxations

| Item | Result |
|---|---|
| Branch / transformer ratings | Unchanged, original Rate A |
| Voltage bounds | Unchanged, original normal bounds |
| Generator P/Q and apparent ratings | Unchanged, including assumed S=Pmax/0.95 |
| Load service | Full load, no DR or shedding |
| Active response | Unchanged limit-aware participation and capability-range weights |
| Tap controls | Same 131; absolute +/-5%, corrective movement <=2.5% supplied ratio |
| Shunts | Same 11 continuous banks; same legal envelope and two-section budget |
| Timing | Same assumed 120-second settled sensitivity |
| Droop | Same 36 shared curves and design bounds; settings reoptimized |
| AVR | Same 15 units and +/-0.02 pu design envelope, <=0.01 pu/hour; schedule reoptimized |
| Physical / control policy identity | {same} |

The proposed larger tap budgets and rating/voltage sensitivities were not needed
after the unchanged-bound models passed. Candidate device rankings from failed
iterates are retained as diagnostic observations, not recommendations for uprating.
Zero physical relaxation is attained for the targeted joint model; no global
optimality claim is made for the resulting dispatch or controller settings.

## Complete frozen-candidate assessment

Every outage assessment freezes the same preventive dispatch, base equipment,
shared curves and period-specific AVR schedule. Corrective actions obey the
original budgets. All 389 eligible connected outages are required for complete
qualification; structural island exclusions retain their separate scope.

| Result | Value |
|---|---:|
| Native + independent joint model valid | {d['base_and_master_valid']} |
| Connected outages assessed | {d['scanned']} / {d['catalogue_size']} |
| Accepted five-period outage trajectories | {d['accepted']} |
| Numerically unresolved | {d['unresolved']} |
| Minimum base upward headroom | {100*d['minimum_headroom_fraction']:.6f}% |
| Generators at Pmax by period | {d['pmax_counts_by_period']} |
| Five-hour base loss energy | {d['loss_energy_mwh']:.8f} MWh |
| Maximum hourly AVR movement | {d['max_avr_movement_pu_per_hour']:.8f} pu |
| Cross-file frozen-policy identity | {d['frozen_identity_valid']} |
| Full connected-outage qualification | {d['full_security_qualified']} |

Unresolved outages: {failed}.
Unassessed outages: {', '.join(d['missing']) or 'none'}.

## Native diagnostic attempts

| Attempt | States | Native termination | Accepted |
|---|---:|---|---|
{attempt_table}

Expanded generator-outage models are separate diagnostics unless they are the
selected candidate above. A time-limited point is not accepted merely because
its physical residuals are small. Longer frozen-candidate numerical retries retain
all original bounds and are checked independently before replacing failed scans.

## Preventive AVR schedule

| Generator | Period 1 | Period 2 | Period 3 | Period 4 | Period 5 |
|---|---:|---:|---:|---:|---:|
{avr}

All accepted outputs require native convergence, Julia replay and independent
complex-current physics/controller/capability/response/equipment checks.
Qualification is steady-state, continuous equipment, and scoped to the connected
catalogue. Discrete switching, manufacturer delays, dynamics, GFL/GFM behavior,
full-catalogue resource/loss optimality and broader P2 closure remain separate.
Original S2 remains paused; previous sealed evidence remains historical and unchanged.
'''
    (root/'REPORT.md').write_text(text)
    print(json.dumps({k:d[k] for k in ['scanned','accepted','unresolved','full_security_qualified']}))
if __name__=='__main__':report(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else 'joint-five')
