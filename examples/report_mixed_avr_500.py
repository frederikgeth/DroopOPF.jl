"""Cross-file audit and report for the mixed AVR/droop campaign.

No optimization; all successful rows must independently replay and use exactly
one candidate controller and preventive trajectory. Numerical failures remain
unresolved. Rational exclusions apply to frozen dispatch only.
"""
import copy,hashlib,json,math,sys
from collections import Counter
from pathlib import Path
from audit_mixed_avr_500 import audit
from mixed_avr_capacity_screen import screen

SUCCESS={'LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL'}
def load(p):return json.loads(Path(p).read_text())
def result(p):
    d=load(p);return d.get('data',d)
def dump(p,d):Path(p).write_text(json.dumps(d,indent=2,allow_nan=False)+'\n')

def fixed_reference(root):
    folder=root/'fixed-reference';r=result(folder/'result.json');spec=load(folder/'assessment.json')
    valid=r['termination_status']=='COMPOSED_REFERENCE' and not spec['joint_optimizer_converged']
    energy=0.;ramp=0.;previous=None;rows=[]
    common=None
    for t,row in enumerate(spec['rows']):
        source=root/row['source'];sourcefile=source/'result.json'
        valid &= hashlib.sha256(sourcefile.read_bytes()).hexdigest()==row['source_sha256']
        check=audit(source);valid &= check['valid']
        parent=result(sourcefile);period=parent['periods'][0];c=load(folder/f'period-{t+1}.json')['data']['case']
        valid &= r['periods'][t]==period and load(folder/f'period-{t+1}.json')==load(source/'period-1.json')
        signature={k:v for k,v in c.items() if k not in ('id','loads')}
        if common is None:common=signature
        else:valid &= common==signature
        state=period['states']['base'];energy+=c['base_power']*(sum(state['pg'])-sum(l['p'] for l in c['loads']))
        if previous:
            for i,g in enumerate(c['generators']):
                if not g['available']:continue
                cap=.25*(g['p_max']-g['p_min']);delta=state['pg'][i]-previous['pg'][i]
                ramp=max(ramp,abs(delta)-cap)
        previous=state;rows.append(dict(period=t+1,native=parent['termination_status'],valid=check['valid']))
    valid &= ramp<=1e-6 and abs(energy-r['objective_mwh'])<=1e-6 and abs(energy-spec['objective_mwh'])<=1e-6
    return dict(valid=bool(valid),native_joint_optimization_claimed=False,rows=rows,ramp_violation=ramp,objective_mwh=energy)

def expected_case(case,settings):
    c=copy.deepcopy(case)
    for key,s in settings.items():
        d=c['controls'][int(key)-1];d['slope']=s['slope'];d['schedule'].update(v_ref=s['v_ref'],
            v_db_low=s['v_ref']-s['deadband_low'],v_db_high=s['v_ref']+s['deadband_high'])
    return c

def scan_audit(root,lane,candidate,require_complete=True):
    journal=load(root/f'scan-{lane}/summary.json');c=result(root/candidate/'result.json')
    entries=load(root/'catalogue.json')['entries'];events={e['contingency']['id'] for e in entries if e['disposition']=='eligible'}
    seen=[r['event'] for r in journal['rows']]
    valid=len(seen)==len(set(seen)) and set(seen)<=events
    complete=journal['complete'] and set(seen)==events
    if require_complete:valid &= complete
    # Recompute every rational certificate from the actual saved candidate.
    certificates=screen(root,candidate);certmap={(r['period'],r['event']):r for r in certificates['rows']}
    retryfile=root/'scan-retries/summary.json'
    retries={(r['lane'],r['event']):r for r in load(retryfile)['rows']} if retryfile.exists() else {}
    rows=[];accepted=excluded=unresolved=recovered=0;maxbalance=0.;maxdr=maxshed=0.;mincircle=math.inf
    for row in journal['rows']:
        event=row['event'];proofs=[certmap[(t,event)] for t in range(1,6)]
        if row['certified_periods']==5:
            certified=all(p['certified_infeasible'] for p in proofs);valid &= certified
            excluded+=1;rows.append(dict(event=event,status='fixed_dispatch_capacity_excluded',periods=5,
                minimum_deficit_mw=min(p['gap_pu'] for p in proofs)*100.,maximum_deficit_mw=max(p['gap_pu'] for p in proofs)*100.));continue
        path=Path(row['path']);replayed=False;used_retry=False
        retry=retries.get((lane,event))
        if retry and retry['accepted']:path=Path(retry['path']);used_retry=True
        summary=load(path/'summary.json')
        if summary['accepted']:
            check=audit(path);valid &= check['valid'];replayed=check['valid']
            r=result(path/'result.json');contract=load(path/'contract.json')
            identity=contract['fixed_base'] and contract['events']==[event] and contract['factors']==[.9,1.,1.05,1.,.9]
            for t,p in enumerate(r['periods']):
                identity &= p['states']['base']==c['periods'][t]['states']['base']
                identity &= p['tap_settings']['base']==c['periods'][t]['tap_settings']['base']
                identity &= p['shunt_settings']['base']==c['periods'][t]['shunt_settings']['base']
                identity &= p['reactive_assignments']==c['periods'][t]['reactive_assignments']
                inputcase=load(path/f'period-{t+1}.json')['data']['case']
                reference=load(root/candidate/f'period-{t+1}.json')['data']['case']
                identity &= inputcase==expected_case(reference,c['droops'])
            valid &= identity
            replayed &= identity
            if replayed:
                accepted+=1;recovered+=used_retry
                for state in check['rows']:
                    maxbalance=max(maxbalance,state['balance_max_pu']);maxdr=max(maxdr,state['dr_mw']);maxshed=max(maxshed,state['shed_mw']);mincircle=min(mincircle,state['circle_margin_pu'])
        if not replayed:unresolved+=1
        rows.append(dict(event=event,status='native_and_independent_pass' if replayed else 'numerically_unresolved',
            used_retry=used_retry,path=str(path),native_status=summary['status']))
    return dict(valid=bool(valid),complete=complete,candidate=candidate,connected_outages=len(events),processed=len(rows),
        native_accepted=accepted,fixed_dispatch_excluded=excluded,numerically_unresolved=unresolved,
        recovered_by_retry=recovered,accepted_period_outage_pairs=5*accepted,excluded_period_outage_pairs=5*excluded,
        unresolved_period_outage_pairs=5*unresolved,security_passed=complete and accepted==len(events),
        maximum_accepted_balance_pu=maxbalance,minimum_accepted_circle_margin_pu=None if mincircle==math.inf else mincircle,
        maximum_observed_dr_mw=maxdr,maximum_observed_shed_mw=maxshed,
        relief_scope='observed in feasible witnesses; not a minimum required-relief result',rows=rows)

def assessment(root,require_complete=True):
    root=Path(root);ref=fixed_reference(root)
    design=audit(root/'multi-design-hot')
    scans={lane:scan_audit(root,lane,candidate,require_complete) for lane,candidate in [('fixed','fixed-reference'),('designed','multi-design-hot')]}
    smallbase=audit(root/'14-bus/base-designed');smallsecurity=audit(root/'14-bus/security-joint')
    original=load(root/'generator-assignment.json');eligible=[r for r in original['rows'] if r['available']]
    share=sum(r['p_max_mw'] for r in eligible if r['mode']=='AVR')/sum(r['p_max_mw'] for r in eligible)
    energy=design['objective_recomputed_mwh'];difference=ref['objective_mwh']-energy
    return dict(valid=ref['valid'] and design['valid'] and all(s['valid'] for s in scans.values()) and smallbase['valid'] and smallsecurity['valid'],
        reference=ref,designed_base=design,scans=scans,small_14_base=smallbase,small_14_security=smallsecurity,
        avr_count=original['avr_count'],droop_count=original['droop_count'],avr_active_capacity_share=share,
        energy_difference_mwh=difference,energy_difference_percent=100*difference/ref['objective_mwh'],
        physical_network_infeasibility_proven=False,original_s2_resumed=False,p2_closed=False)

def report(root,checks):
    root=Path(root);s=checks['scans'];ref=checks['reference']['objective_mwh'];design=checks['designed_base']['objective_recomputed_mwh']
    table='\n'.join(f"| {lane.title()} | {d['native_accepted']} | {d['fixed_dispatch_excluded']} | {d['numerically_unresolved']} |" for lane,d in s.items())
    scope=load(root/'generator-assignment.json');avr=[r['generator_id'] for r in scope['rows'] if r['mode']=='AVR']
    verification=''
    proof_file=root/'verification/results.json'
    if proof_file.exists():
        proof=load(proof_file)
        verification=f"""## Verification

The final source passed **{proof['julia_checks_passed']:,} Julia checks** and
**{proof['python_checks_passed']} independent Python corruption/contract checks**.
Current-source Julia replay passed on **{proof['julia_replay_result_files']} accepted
result files** ({proof['replayed_state_instances']} state instances including repeated
frozen bases). The documentation build passed. Source/test hashes match the
final regression run. Prior sealed evidence rehashed unchanged ({proof['prior_sealed_files_verified']:,} files).

"""
    text=f'''# Mixed AVR / droop campaign — 14 and 500 buses

The capability and control implementation is tested. The 14-bus connected security
study passes. The 500-bus base trajectory passes, but its loss-optimized preventive
candidate is **not N−1 secure under the exact S2 proportional response**. This is
not a proof that the network cannot be secured by preventive redispatch/design.

## Configuration actually used

- 500 buses: 90 generator records, 51 online positive-Pmax units. The largest 30%
  by count, rounded half upward, selects **15 AVR** and **36 droop** units; 39 remain
  offline. AVR IDs: {', '.join(map(str,avr))}. AVR units hold {100*checks['avr_active_capacity_share']:.4f}% of online Pmax.
- AVR targets use nominal saved S2 generator-bus voltages, fixed across time and
  automatic outage response in the main comparison. AVR Q changes automatically
  and releases voltage regulation at its current capability limit.
- Every online unit has the explicit exploratory rating **S=Pmax/0.95**, in
  system-base pu. These are study assumptions, not manufacturer nameplates or
  imported PSS/E machine bases. Existing P/Q bounds remain unchanged.
- Delivered reactive power clips to the intersection of Q bounds and
  `[-sqrt(S²−P²), sqrt(S²−P²)]`; independent replay checks `P²+Q²≤S²` in every state.
  Algebraically implied circle rows are omitted for clipped controls to avoid
  duplicate active constraints; other units retain explicit inequalities.
- One shared curve per droop unit, with calibrated 2–8% full-Q-span slopes,
  reference ±0.02 pu and fixed zero deadband: **72 shared parameters** in the 500-bus
  design. Droop technology remains unspecified; GFL/GFM models are deferred to P3.
- Five one-hour periods at **90/100/105/100/90%**, scaling both P and Q at each load.
  Preventive dispatch ramps assume 25% of active capability range per hour,
  with no initial or terminal boundary. These are assumed rates.
- Same exact S2 selection: **131 corrective taps and 11 continuous banks**, original
  absolute bounds, no additional movement cap. Settled recourse is assumed;
  device delays, discrete switching and trajectories are not certified.
- Exact stored S2 Pmax-proportional equality response is used for this benchmark.
  The production library default remains limit-aware saturation/redistribution.
- Bases retain normal limits and full demand. Outages retain S2 voltage extension
  ±0.05 pu, branch ratings ×1.1, DR ≤1% per positive load, shedding ≤10 MW per
  outage, combined relief ≤10% per load, and proportional reactive relief.

## Accepted base-operation comparison

| Lane | Five-hour loss energy | Qualification |
|---|---:|---|
| Fixed curves | {ref:.8f} MWh | Independently optimized periods assembled into a physically replayed trajectory; all temporal ramps pass |
| Shared designed curves | {design:.8f} MWh | Native joint multi-period LOCALLY_SOLVED; Julia/Python replay |

The difference is **{checks['energy_difference_mwh']*1000:.3f} kWh ({checks['energy_difference_percent']:.6f}%)**.
There is no material observed loss benefit. Do not interpret parameter changes as
unique or globally optimal designs. The fixed-lane coupled optimizer did not
converge in its bounded retries; its composed feasible reference is explicitly
identified and is not presented as a converged coupled solve.

At nominal demand, fixed and designed curves both yield approximately
17.58572 MW loss. Some droop units reach their reactive capability; all droop
units run at or near Pmax in the accepted base profile. Free equipment and weakly
identified curve settings must be considered when interpreting the tiny difference.

## Connected-outage assessment

Every lane uses the same frozen controller and preventive trajectory throughout
its catalogue scan. Eligible scope is **389 outages × 5 periods = 1,945 pairs per
lane**. The 644-entry catalogue also contains 255 structural islanding exclusions;
those are not qualified by this connected campaign.

| Lane | Native + independent AC pass, all 5 periods | Fixed-dispatch capacity exclusions, all 5 periods | Numerically unresolved |
|---|---:|---:|---:|
{table}

Capacity exclusions use exact rational active-balance bounds in a conservative
outer relaxation that drops reactive controls, apparent circles and attached P
bounds while retaining actual response support. They never predict a safe outage.
These exclusions apply to this frozen dispatch and S2 participation law, even with
maximum allowed relief. They do not prove network-wide physical infeasibility.
The constrained signal is limited by participating units already at Pmax; surplus
headroom at other units cannot redistribute under the S2 equality law.

All remaining accepted outcomes have a native success status and independent
complex-current AC, exact-control, circle, response, relief, equipment, angle,
ramp and objective replay. Time/iteration/numerical failures remain unresolved.
Longer retries are retained alongside original failures. Relief in feasibility
witnesses is observed usage, **not minimum necessary relief** and not a full-load
security guarantee. Full coupled resource/loss priorities are not closed.

## Additional stages attempted

- **14 buses:** largest 30% of 5 generators rounds to 2 AVR and 3 droop units.
  Five periods span 90–110%. With 3 corrective taps, 1 continuous bank, original
  normal bounds and no DR/shedding, the complete 24-connected-outage joint study
  passes: **125 native LOCALLY_SOLVED states**, Julia and Python replay. Its
  security-constrained loss is 4.27023073 MWh, versus 2.84738747 MWh before outages.
- **500-bus preventive AVR scheduling:** implemented with per-period targets,
  reference ±0.02 pu within bus bounds and movement ≤0.01 pu/hour. Common regulated
  locations share one exact target. Nominal and peak single-period sensitivities
  pass, but five-period scheduling retries do not qualify; their time limits and
  local infeasibility statuses are not physical infeasibility proofs.
- **500-bus joint recovery:** a bounded 15-state pilot includes loss of generator
  60 and heavily loaded branch 299. Joint preventive/controller recovery times
  out and fails physical acceptance. No monolithic 1,950-state model was repeated.
- Detailed inverter, frequency and dynamic controls remain deferred. The frozen
  global/rational feasibility gate and legacy voltage-only droop predictor reject
  rated cases until their P-dependent graphs are extended; native AC replay works.

## Evidence and remaining work

`aggregate-checks.json` contains cross-file identity and independently replayed
coverage. Individual folders retain input cases, contracts, returned states,
Julia/Python audits, summaries and native solver logs. `verification/` records
regressions, corruption checks, documentation build and source identities.
Original S2 inputs are byte/hash verified; current library source drift is expected
for this new model and is declared. Original S2 remains paused and prior sealed
evidence is retained. Allocated-byte counters are cumulative allocations, not RAM.
Native CPU caps apply per optimization stage; wall times also include compilation,
construction and successive stages. Supplied bus-specific normal voltage bounds
apply; some permit 1.10 pu. The catalogue uses the accepted fixed-AVR trajectories
listed above; unqualified scheduling/recovery iterates are not substituted.

Remaining qualification is a successful security-constrained preventive
redispatch/shared design for the 500-bus case, resolution of numerical leftovers,
and a qualified five-period AVR schedule. **P2 is not closed.**

{verification}## Figures

Accepted base-operation states only; no failed iterate is plotted as a design.

![Capability use](figures/capability_use.png)

![Shared droop examples](figures/shared_droop_curves.png)

![Voltage envelope](figures/voltage_envelope.png)
'''
    (root/'REPORT.md').write_text(text)

if __name__=='__main__':
    root=Path(sys.argv[1]);checks=assessment(root,require_complete='--partial' not in sys.argv)
    dump(root/'aggregate-checks.json',checks);report(root,checks)
    print(json.dumps(dict(valid=checks['valid'],scans={k:{kk:vv for kk,vv in v.items() if kk!='rows'} for k,v in checks['scans'].items()})))
    if '--partial' not in sys.argv:assert checks['valid']
