"""Report accepted designs and independently proved negative P2 control groups."""
import csv, json, sys
from pathlib import Path

def read(path):return json.loads(path.read_text())
def main(root):
    root=Path(root);audit=read(root/'independent_audit.json')
    if not audit['pass']:raise RuntimeError('Independent audit must pass before reporting')
    summary=read(root/'summary.json');decisions=[]
    for row in summary:
        case=root/row['name'];cuts=read(case/'cut_certificates.json')
        obstructions=[x for x in cuts if x['certified_obstruction'] and x['device_kind'] in ('line','transformer')]
        if row['training_accepted']:
            status='accepted_training_and_heldout' if all(h['accepted'] for h in row['heldout']) else 'accepted_training_only'
        elif obstructions:
            status='certified_infeasible_declared_training_scope'
        else:status='unresolved'
        decisions.append(dict(case=row['name'],lane=row['lane'],decision=status,
            training_accepted=row['training_accepted'],heldout=row['heldout'],
            proof_outages=sorted({x['outage'] for x in obstructions})))
    rounded=read(root/'bank_fixture/rounded_candidate/summary.json')
    fixed=read(root/'bank_fixture/fixed/primary/summary.json')
    free=read(root/'bank_fixture/droop/primary/summary.json')
    preventive=read(root/'bank_fixture/preventive/primary/summary.json')
    nominal=lambda s:next(r['loss_mw'] for r in s['training'] if r['factor']==1.)
    baseline=nominal(fixed);stage2=nominal(free);stage3=nominal(preventive)
    rounded_loss=next(r['loss_mw'] for r in rounded if r['factor']==1.)
    status=dict(scope='finite staged configuration comparison; not P2 closure',
        planned_groups=len(summary),classified_groups=sum(x['decision']!='unresolved' for x in decisions),
        feasible_groups=sum(x['training_accepted'] for x in decisions),
        certified_negative_groups=sum(x['decision']=='certified_infeasible_declared_training_scope' for x in decisions),
        all_feasible_gate=all(x['training_accepted'] and x['heldout'] is not None and all(h['accepted'] for h in x['heldout']) for x in summary),P2_closed=False,independent_audit_pass=audit['pass'],decisions=decisions,
        rounded_fixture_accepted=all(r['valid'] for r in rounded),rounded_demands=len(rounded),
        nominal_fixture_loss_reduction_percent=100*(baseline-stage3)/baseline,
        scope_complete=all(x['decision']!='unresolved' for x in decisions))
    (root/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
    loss_rows=[('Fixed supplied controls',baseline,'5/5','4/4'),('Shared droop design',stage2,'5/5','4/4'),
        ('Shared droop + preventive equipment',stage3,'5/5','4/4'),('Supplied tap + legal 3-section bank',rounded_loss,'5/5','4/4')]
    body='''# P2 staged preventive-control comparison

Date: 21 October 2026. **The finite comparison is classified; P2 remains open.**
Three planned fixture configurations are accepted. Six planned public-case
configuration groups are independently proved infeasible for the declared
training requirement. The original all-feasible gate remains failed.

## What changed

- Active response remains limit-aware with effective-capability-range fallback
  weights. Generation capability and operating limits are unchanged.
- Lane 1 fixes supplied droop parameters, taps and shunts.
- Lane 2 designs slopes and references once, shared across every training demand
  and outage; equipment remains supplied and fixed.
- Lane 3 additionally selects preventive transformer ratios and existing simple
  bank susceptances, shared across all training demands and outages.
- **Post-outage equipment movement remains zero.** Preventive pre-positioning may
  differ from supplied settings. Curves and equipment freeze for held-out tests.
- Each demand may optimize its own preventive base dispatch in all three lanes.
  Thus this is a matched design comparison, not the historical fixed-base P2
  assessment. The common objective is mean base schedule deviation, not economic
  cost or loss minimization. Losses are reported separately.

Training demands are 90/95/100/105/110%; held-out demands are
92.5/97.5/102.5/107.5%. Slopes have 0.5–2x supplied bounds; references have +/-0.02
pu bounds. Deadbands, Q references and capabilities stay fixed. Selected taps
have supplied-ratio +/-5% **assumed sensitivity bounds**, not verified manufacturer
capabilities. Existing bank bounds come from supplied legal-count envelopes;
optimization is continuous. Source branch-angle bounds are enforced and replayed.

## Fixture results

The 3-bus fixture covers every eligible branch and generator outage: five
outages plus the base at each demand. All three designs pass all five training
and four held-out demand levels. These are local solutions at finite points.

| Configuration | Nominal base loss MW | Training | Held out |
|---|---:|---:|---:|
'''
    body+=''.join(f'| {n} | {loss:.9f} | {train} | {hold} |\n' for n,loss,train,hold in loss_rows)
    body+=f'''
The preventive design reduces nominal losses by **{status['nominal_fixture_loss_reduction_percent']:.2f}%** relative
to the matched fixed-control solution. Its mean schedule-deviation objective is
{preventive['objective']:.12g}, versus {fixed['objective']:.12g} for fixed controls.
This is an observed local comparison, not a global-optimality or general savings
claim.

The continuous solution selects tap 11 = 1.0009967353 and bank 201 B =
0.0599974781 pu, compared with supplied 1.0 and 0.02 pu. The bank's legal envelope
is 0–3 sections, B = 0–0.06 pu. A separate deterministic recovery restores the
supplied tap ratio 1.0 and picks the nearest legal bank state, three sections
(B=0.06). It passes all nine demands and all five outages without retuning the
curves. This is fixture-level discrete recovery, not general tap/bank switching
or dynamic qualification.

## Public-case qualification boundaries

Public comparisons cover connected branch outages: 19 on the 14-bus case and
35 on the 39-bus case. Islanding branches remain explicit exclusions. Generator
outages receive separate necessary supply/cut checks. No public held-out designs
are accepted because their full training requirements are infeasible.

- **14-bus, branch 1 outage:** the load-side area has at most 59 MW generation
  and 128 MW incoming apparent-power capacity. Demand is 233.1 MW even at 90%.
  The exact verified cut gap, including validation allowances, is 46.0982 MW at
  that point and remains positive at every training factor. Droop, taps, shunts
  and corrective redistribution cannot remove this active-transfer deficit
  while the supplied generation/thermal bounds and constant-power demand hold.
- **39-bus, branch 35 outage at 110%:** the identified area needs 6607.403 MW,
  has 5060 MW local active capability and at most 1500 MW boundary capacity.
  The verified gap after allowances is 47.3987 MW.
- Additional generator-outage supply and network-cut obstructions are retained
  in the per-case certificate files. Failed native statuses alone were not used
  as infeasibility proof.

The certificates enlarge the candidate set: they ignore reactive restrictions,
AC losses and prescribed response laws. Passivity gives nonnegative active losses, and
apparent-power ratings bound active imports. A strictly positive rational cut
contradiction therefore excludes every AC solution within the declared limits
and tolerances, even with more equipment/control freedom. Verification does not
trust max-flow discovery or a solver infeasibility status.

Native attempts and rejected states are preserved. Remaining public solver
budgets were interrupted once the obstructions were established; interruptions
are diagnostic outcomes, not certificates. The fixed source ratings and
capabilities were not relaxed to manufacture acceptance.

## Verification

'''
    body+=f'''Independent Python scalar replay checked **{audit['record_count']} result records / {audit['state_count']:,} scenario states**,
with zero native-plus-physical or physical-only classification discrepancies.
This includes rejected iterates; their sharing/limit violations remain visible.
All {audit['cut_verification']['count']} saved cut witnesses verify with exact rational arithmetic. Deliberately
corrupted dispatches, response signals and proof gaps are rejected. Accepted
equipment and curves are independently checked for cross-demand sharing and
held-out freezing. The rounded fixture additionally checks source tap ratios
and legal bank counts.

The prior 3,147-assertion library regression remains applicable to unchanged
production source. This campaign adds numerical example-level evidence; it does
not expand remote CI, dynamic stability, continuous demand-envelope or public
security qualification. No speedup benchmark was performed.

## Remaining restrictions worth investigating

1. **Capacity-consistent study scope comes first.** Identify demand ranges and
   contingency catalogs supported by actual generation reserve and transfer
   capability, or define explicit hardware upgrades / emergency service policies.
   Keep the present failed requirement and certificates. Do not simply loosen
   physical ratings or generator bounds.
2. **Demand-specific preventive equipment:** one setting across every demand is
   conservative. A separate study could schedule settings for known demand
   before an outage while still allowing zero post-outage movement. It cannot
   repair the proven cuts above.
3. **Controller limits:** the fixture solutions approach lower slope and upper
   reference bounds. Test deadband design and justified controller-bound
   sensitivities; do not infer dynamic acceptability from steady-state benefit.
4. **Adjustable public shunts require device data.** The 14-bus source has a fixed
   shunt, and neither public input supplies adjustable-bank metadata. Those
   shunts remain fixed; adding bank control would require explicit hardware and
   legal-state assumptions.
5. **Corrective equipment remains deferred.** Introduce it only with declared
   devices, steps, delays and movement budgets, and assess the immediate state
   separately. No corrective actions were silently enabled here.
6. **Other physical assumptions remain:** actual governor/AGC weights and reserve
   response times, discrete tap data, all-island service and transient behavior
   are not established by this study.

## Evidence and reproduction

`protocol.json`, `summary.json`, `STATUS.json`, per-attempt inputs/results,
`independent_audit.json`, per-case cut certificates, `control_plan.csv`, rounded
recovery records, logs and a manifest retain the evidence. Current configuration
instructions are in the repository `AGENTS.md`.

From the repository root, rerun independent replay with:

```sh
python3 examples/audit_p2_preventive_controls.py artifacts/p2_preventive_controls_20261021
python3 examples/report_p2_preventive_controls.py artifacts/p2_preventive_controls_20261021
```

Use fresh directories for numerical reproduction. The Julia campaign runner is
`examples/p2_preventive_controls.jl`; fixture-only reproduction takes
`fresh-output bank_fixture`. Public all-demand masters are already excluded by
the retained cut proofs; check these before spending further solver budgets.
The legal-state check uses `examples/p2_preventive_discrete_check.jl`.
'''
    (root/'REPORT.md').write_text(body)
    rows=[]
    for inp in root.glob('*/inputs.json'):
        source=read(inp.parent/'source.json')['data']['case']
        for lane in ('fixed','droop','preventive'):
            plan=read(inp.parent/lane/'primary/protocol.json')
            accepted=next(x['training_accepted'] for x in decisions if x['case']==inp.parent.name and x['lane']==lane)
            for ctl in plan['controls']:
                ref=source['controls'][ctl['control_id']-1]
                for field,supplied in [('slope',ref['slope']),('v_ref',ref['schedule']['v_ref'])]:
                    bounds=ctl['bounds'][field]
                    rows.append([inp.parent.name,lane,'droop',ctl['control_id'],field,supplied,*bounds,'shared_all_demands_outages','offline_design_then_frozen',0,accepted])
            for ctl in plan['taps']:
                b=next(x for x in source['network']['branches'] if x['id']==ctl['branch_id'])
                rows.append([inp.parent.name,lane,'tap',b['id'],'ratio',b['tap_ratio'],ctl['lower'],ctl['upper'],'shared_all_demands_outages','preventive',0,accepted])
            for ctl in plan['shunts']:
                b=next(x for x in source['network']['banks'] if x['id']==ctl['bank_id'])
                values=[x[0]*b['step_susceptances'][0] for x in b['legal_states']]
                supplied=b['state'][0]*b['step_susceptances'][0]
                rows.append([inp.parent.name,lane,'bank',b['id'],'B_pu',supplied,min(values),max(values),'shared_all_demands_outages','preventive',0,accepted])
    with (root/'control_plan.csv').open('w',newline='') as f:
        writer=csv.writer(f);writer.writerow(['case','lane','type','id','parameter','supplied','lower','upper','sharing','timing','post_outage_movement','training_accepted']);writer.writerows(rows)
    print(json.dumps({k:status[k] for k in ('planned_groups','classified_groups','feasible_groups','certified_negative_groups','all_feasible_gate','P2_closed')}))
if __name__=='__main__':main(Path(sys.argv[1]))
