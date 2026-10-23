"""Read-only audits and a fresh report for reserve-aware mixed-control evidence."""
import hashlib,json,math,sys
from pathlib import Path
from audit_mixed_avr_500 import audit


def load(p):return json.loads(Path(p).read_text())
def summarize(root,candidate):
    root=Path(root);parent=root/candidate;r=load(parent/'result.json')['data']
    parent_spec=load(parent/'contract.json')
    native=audit(parent);inputs=[load(parent/f'period-{t+1}.json')['data'] for t in range(5)]
    rows=[];coverage={};frozen=True
    resolutions={r['event']:r for resolution_file in sorted(root.glob('resolutions*/summary.json'))
        for r in load(resolution_file)['rows'] if r['accepted'] and load(resolution_file)['candidate']==candidate}
    for journal in sorted(root.glob('scan-'+candidate+'*/summary.json')):
        for row in load(journal)['rows']:
            event=row['event'];resolved=event in resolutions
            if resolved:row=resolutions[event]
            path=Path(row['path'])
            if not path.is_absolute():path=Path.cwd()/path
            checked=audit(path)
            spec=load(path/'contract.json');rr=load(path/'result.json')['data']
            identity=spec['fixed_base'] and spec['events']==[event] and not spec['droop_controls']
            identity &= spec['response']==parent_spec['response'] and spec['s2_emergency']==parent_spec['s2_emergency']
            identity &= spec['factors']==[.9,1.,1.05,1.,.9]
            for t in range(5):
                source=load(path/f'period-{t+1}.json')['data']
                identity &= rr['periods'][t]['states']['base']==r['periods'][t]['states']['base']
                identity &= rr['periods'][t]['tap_settings']['base']==r['periods'][t]['tap_settings']['base']
                identity &= rr['periods'][t]['shunt_settings']['base']==r['periods'][t]['shunt_settings']['base']
                identity &= source['reactive_assignments']==r['periods'][t]['reactive_assignments']
                identity &= rr['periods'][t]['reactive_assignments']==r['periods'][t]['reactive_assignments']
                identity &= not rr['droops'] and not rr['avr_targets'][t]
                for key in ['tap_controls','shunt_controls','control_policy','participation','redispatch_limits']:
                    identity &= source[key]==inputs[t][key]
                # Physical data stay identical; the realized droop is independently
                # encoded in the exact explicit assignments compared above.
                for key in ['network','generators','loads','base_power','base_frequency']:
                    identity &= source['case'][key]==inputs[t]['case'][key]
            if event in coverage:raise ValueError('duplicate scan event '+event)
            valid=bool(row['accepted'] and checked['valid'] and identity)
            coverage[event]=valid;frozen &= identity
            rows.append(dict(event=event,valid=valid,used_separate_recovery=resolved,frozen_identity=bool(identity),path=str(path),
                balance_max_pu=max(x['balance_max_pu'] for x in checked['rows']),
                max_shed_mw=max(x['shed_mw'] for x in checked['rows']),max_dr_mw=max(x['dr_mw'] for x in checked['rows'])))
    catalog=load(root/'catalogue.json');expected={e['contingency']['id'] for e in catalog['entries'] if e['disposition']=='eligible'}
    if set(coverage)-expected:raise ValueError('unexpected scan event')
    counts=[];fractions=[]
    for t,p in enumerate(r['periods']):
        gs=inputs[t]['case']['generators'];pg=p['states']['base']['pg'];modes={a['generator_id']:a['mode'] for a in inputs[t]['reactive_assignments']}
        counts.append(sum(g['available'] and abs(g['p_max']-v)<=1e-6 for g,v in zip(gs,pg)))
        for g,v in zip(gs,pg):
            if not g['available'] or inputs[t]['participation'].get(str(g['id']),0)<=0:continue
            lo,hi=g['p_min'],g['p_max'];m=modes[g['id']]
            if m['type']=='VoltVarDroop':lo=max(lo,m['capability']['p_min']);hi=min(hi,m['capability']['p_max'])
            if g.get('s_rated') is not None:lo=max(lo,-g['s_rated']);hi=min(hi,g['s_rated'])
            if hi>lo:fractions.append((hi-v)/(hi-lo))
    movement=max((abs(r['avr_targets'][t][k]-r['avr_targets'][t-1][k]) for t in range(1,5) for k in r['avr_targets'][t]),default=0.)
    return dict(candidate=candidate,base_and_master_valid=native['valid'],minimum_headroom_fraction=min(fractions),
        pmax_counts_by_period=counts,loss_energy_mwh=r['objective_mwh'],stages=r['stages'],
        avr_targets=r['avr_targets'],max_avr_movement_pu_per_hour=movement,
        catalogue_size=len(expected),scanned=len(coverage),accepted=sum(coverage.values()),
        unresolved=sum(not x for x in coverage.values()),missing=sorted(expected-set(coverage)),
        frozen_identity_valid=bool(frozen),full_security_qualified=bool(native['valid'] and set(coverage)==expected and all(coverage.values()) and frozen),rows=rows)


def report(root,candidate,checks=None):
    root=Path(root);d=summarize(root,candidate) if checks is None else checks
    assert d['candidate']==candidate
    (root/'reserve-aggregate-checks.json').write_text(json.dumps(d,indent=2)+'\n')
    targets=d['avr_targets']
    avr_table='\n'.join('| '+str(g)+' | '+' | '.join(f"{float(t[str(g)]):.8f}" for t in targets)+' |' for g in sorted(map(int,targets[0])))
    validation_path=root/'final-source-test-verification.json'
    validation=load(validation_path) if validation_path.exists() else {}
    attempts=[]
    for folder in sorted(root.iterdir()):
        if folder.is_dir() and (folder/'summary.json').exists() and (folder/'result.json').exists():
            summary=load(folder/'summary.json')
            if 'status' in summary:attempts.append(f"| `{folder.name}` | {summary['status']} | {summary['accepted']} |")
    attempt_table='\n'.join(attempts)
    text=f'''# Reserve-aware 500-bus mixed AVR/droop continuation

Candidate: `{candidate}`. Full five-period connected-outage qualification: **{'PASSED' if d['full_security_qualified'] else 'OPEN'}**.

The new objective prioritizes minimum shedding, then DR, then maximizes the
minimum participating effective-active-range upward-headroom fraction.
The `reserve_loss` variant additionally minimizes loss while retaining that
reserve optimum; `reserve` stops after reserve optimization. Generator fuel
costs were not invented. These are local nonlinear optimization results.

| Result | Value |
|---|---:|
| Native + independent base/master replay | {d['base_and_master_valid']} |
| Minimum upward-headroom fraction | {100*d['minimum_headroom_fraction']:.6f}% |
| Generators at Pmax, periods 1–5 (1e-6 pu tolerance) | {d['pmax_counts_by_period']} |
| Five-hour base loss energy | {d['loss_energy_mwh']:.8f} MWh |
| Maximum preventive AVR change | {d['max_avr_movement_pu_per_hour']:.8f} pu/hour |
| Eligible connected outages | {d['catalogue_size']} |
| Outages scanned at all five periods | {d['scanned']} |
| Accepted outage trajectories | {d['accepted']} |
| Numerically unresolved trajectories | {d['unresolved']} |
| Unscanned trajectories | {len(d['missing'])} |

## Controls and limits

15 largest online units have AVR; 36 have reactive droop. Apparent ratings are
explicit assumptions S=Pmax/0.95; existing Q boxes and P–Q circles remain enforced.
GFL/GFM dynamics are deferred. Five one-hour demands: 90/100/105/100/90%, with
25%-of-active-range/hour preventive dispatch ramps.

There are 131 settled corrective tap controls and 11 continuous shunt-bank
susceptance controls within the unchanged S2 absolute bounds, without added
movement caps. Continuous equipment results do not qualify discrete switching
or physical response delays. S2 proportional equality response is retained.
Normal full-load base limits and original S2 emergency limits/relief allowances
remain unchanged. The 15 AVR targets may vary preventively by period within
original nominal +/-0.02 pu, clipped to normal bus voltage bounds, with at most
0.01 pu/hour movement; targets are frozen across outages within each period.

The native master includes a bounded outage subset. Full catalogue scans freeze
the same preventive dispatch, equipment, shared curves and period-specific AVR
schedule. The independent audit checks these identities, not just separate
scenario feasibility. Omitted contingencies do not contribute to the subset
master's resource objective; full-catalogue resource optimality is not claimed.
Numerical failures are not physical infeasibility. Structural island exclusions
remain outside the 389 connected-outage scope. Earlier sealed evidence is unchanged.

## Preventive AVR schedule

Targets below are pu voltage, shared across all outages within each period.
The bounds, inter-period movement and exact outage use are independently checked.

| Generator | Period 1 | Period 2 | Period 3 | Period 4 | Period 5 |
|---|---:|---:|---:|---:|---:|
{avr_table}

## Executed master attempts

| Attempt | Native termination | Native + Julia/Python accepted |
|---|---|---|
{attempt_table}

The reserve-aware base initialization passes at 85.66745328 MWh; the previous
loss-only base design was 82.54935643 MWh and failed security qualification.
The selected security master reports its actual loss energy above; it did not
converge a final loss-polishing stage. These objective values do not establish
an economic optimum or a unique droop design.

## Remaining corridor qualification

The exhaustive fixed-candidate assessment retains numerical failures as unresolved.
Line 36 connects buses 246–332; transformer 562 connects buses 247–246. They share
a corridor. Failed starts, period-by-period attempts, joint corridor masters,
backend comparisons and restoration preparations remain separate artifacts.
Small power-balance error is insufficient: the closest joint attempts also have
larger AVR projection/capability residuals in the 105% period. No network-wide
infeasibility proof is claimed. Artificial-injection preparations are not security
witnesses and are never substituted for a native original-model solve.

## Software validation

Final source/test hash verification: {validation.get('valid',False)}.
Final Julia checks: {validation.get('julia_checks','pending')}. Independent
Python contract/corruption checks: 19 passed. Documentation build and normal
package import/precompilation passed. A duplicate equivalent DroopControl JSON
serializer was removed to restore normal precompilation; result schema is unchanged.

The final current-source replay passes all 388 selected result files (3,880 state instances including repeated base states). Full security qualification remains open for the two corridor outages. The evidence seal records that distinction. Historical
source snapshots and rejected numerical attempts remain available. No monolithic
389-outage model was repeated. Model allocations recorded in individual attempt
summaries are cumulative allocations, not measured RAM usage.

Detailed stages, targets, event coverage and independent replay are saved in
`reserve-aggregate-checks.json`. Failed/time-limited attempts remain in separate
folders and are not accepted witnesses.
'''
    (root/'REPORT.md').write_text(text)
    print(json.dumps({k:v for k,v in d.items() if k not in ['rows','avr_targets','missing','stages']},indent=2))
    return d

if __name__=='__main__':report(sys.argv[1],sys.argv[2],load(Path(sys.argv[1])/'reserve-aggregate-checks.json') if '--reuse' in sys.argv[3:] else None)
