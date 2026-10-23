"""Review the declared 14-bus S2 scope; never close a failed convergence gate."""
from pathlib import Path
import json,hashlib
from control_figure_reporting import attach
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'artifacts/s2_scopf/ieee14_native'
MULTI=BASE/'multidemand';COMPARE=MULTI/'solver_design_comparison';RECOVER=COMPARE/'ccopt_recovery'
OUT=BASE/'14bus_review';OUT.mkdir(exist_ok=True)
load=lambda p:json.loads(p.read_text())
original=load(MULTI/'evaluation_summary.json')['attempts']
solver=load(COMPARE/'summary.json');recovery=load(RECOVER/'summary.json')
audit=load(RECOVER/'independent_audit.json')
gates=dict(ipopt_nine_sampled_demands=all(r['accepted_with_trip_assumption'] for r in original if r['solver']=='ipopt') and len([r for r in original if r['solver']=='ipopt'])==9,
    madnlp_free_training_design='madnlp' in solver['selected'],
    madnlp_four_held_out_checks=len([r for r in solver['heldout'] if r['solver']=='madnlp'])==4 and all(r['accepted'] for r in solver['heldout'] if r['solver']=='madnlp'),
    ccopt_free_training_design=recovery['selected'] is not None,
    ccopt_four_held_out_checks=len(recovery['heldout'])==4 and all(r['accepted'] for r in recovery['heldout']),
    independent_recovery_audit=audit['classification_discrepancies']==0 and audit['source_hashes_verified'],
    s1_remains_closed=load(ROOT/'artifacts/s1_closeout/STATUS.json')['status']=='closed')
closed=all(gates.values());status='closed_declared_14bus_scope' if closed else 'open_ccopt_convergence_item'
record=dict(status=status,gates=gates,scope='14-bus S1 Pmin0/symmetric-Q case; shared zero-deadband droop; five training and four held-out demand points; 24 connected outages plus conditional G5-trip projection; corrective continuous equipment',
    broader_s2_closed=False,general_full_n1_claim=False,continuous_demand_envelope_claim=False,
    original_limit_requalification=False,protection_or_dynamic_validation=False,
    new_500bus_optimisation_started=False,release_published=False)
(OUT/'STATUS.json').write_text(json.dumps(record,indent=2)+'\n')
table='\n'.join(f"| {key.replace('_',' ')} | {'Pass' if value else 'Open'} |" for key,value in gates.items())
decision='The declared sampled 14-bus scope is closed.' if closed else 'The 14-bus review remains open on the CCOpt convergence/held-out items. Ipopt and MadNLP qualifications remain accepted.'
text=f'''# S2 14-bus qualification review

**{decision}** This decision concerns the declared sampled steady-state sub-study. Broader S2 remains open.

| Review item | Result |
|---|---|
{table}

The contract retains the S1 Pmin=0/symmetric-Q case, 2–8% full-Q-span droop and calibration ±0.02 pu references, zero deadband, all 24 connected outages, source voltage/angle/Rate-A limits, within-demand Pmax-weighted response, and corrective taps/continuous bank within confirmed bounds with no additional movement budget. Nine demand points are sampled; no continuous-envelope claim is made.

Line 7–8 coverage remains conditional on G5 trip and unloaded bus8 disconnection, with a verified retained-network witness. Original-limit compatibility, protection/dynamics and general islanding N-1 security remain outside this closeout. Native local convergence and independently replayed physics are both required for accepted designs.

The [CCOpt recovery](s2_14bus_ccopt_recovery.md) retains its starts, strategies, failed attempts, native residuals and independent audits. The [initial multi-demand study](s2_14bus_multidemand.md) and [solver-design comparison](s2_14bus_solver_designs.md) remain historical records. S1 remains closed and its numerical scores are unchanged. No release was published.

'''
if closed:
    source=ROOT/'artifacts/s1_arpae500/calibrated-study.json'
    assert source.exists()
    case=load(source)['data']['case']
    taps=[b['id'] for b in case['network']['branches'] if b['available'] and b['kind']=='transformer']
    banks=[b['id'] for b in case['network']['banks'] if b['available']]
    draft=dict(status='draft_requires_new_campaign_confirmation',source=str(source.relative_to(ROOT)),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        buses=len(case['network']['buses']),online_generators=sum(g['available'] for g in case['generators']),online_branches=sum(b['available'] for b in case['network']['branches']),
        proposed_tap_ids=taps,proposed_bank_ids=banks,proposed_timing='corrective per scenario',proposed_additional_movement_budget=None,
        proposed_shunt_representation='continuous susceptance',control_bounds_and_solver_budgets='To declare and confirm with the 500-bus campaign protocol',
        confirmation_reused_from_14bus=False,numerical_runs_started=False)
    prep=BASE.parent/'ieee500_preparation';prep.mkdir(exist_ok=True)
    (prep/'scope.json').write_text(json.dumps(draft,indent=2)+'\n')
    text+=f'''## 500-bus preparation

A read-only scope draft is prepared from the saved S1 calibrated case: {draft['buses']} buses, {draft['online_generators']} online generators and {draft['online_branches']} online branches. Candidate transformer/bank IDs are retained in `artifacts/s2_scopf/ieee500_preparation/scope.json`. No 500-bus solve has started. The 14-bus confirmation is not reused; exact equipment bounds, timing, movement limits, catalogue treatment and numerical budgets must be declared and confirmed for that new campaign.
'''
else:
    text+='''## Remaining work

Review the recovery stationarity evidence before choosing another numerical strategy. The confirmed bounded recovery has ended; no extra optimisation attempts or 500-bus campaign were started. The 500-bus preparation step remains deferred until this review gate is resolved.
'''
(OUT/'REPORT.md').write_text(text.replace('(s2_14bus_ccopt_recovery.md)','(../multidemand/solver_design_comparison/ccopt_recovery/REPORT.md)').replace('(s2_14bus_multidemand.md)','(../multidemand/REPORT.md)').replace('(s2_14bus_solver_designs.md)','(../multidemand/solver_design_comparison/REPORT.md)'))
(ROOT/'docs/src/s2_14bus_review.md').write_text(text)
note=f'''## 14-bus S2 review decision

{decision} See the [14-bus review](s2_14bus_review.md). Broader S2 remains open; S1 remains closed.'''
for page in ['s2_14bus.md','s2_14bus_multidemand.md','s2_14bus_solver_designs.md','s2_14bus_ccopt_recovery.md','milestones.md','future_work.md']:
    attach(ROOT/'docs/src'/page,'S2_14BUS_REVIEW',note)
for page in ['README.md','RELEASE_NOTES_UNRELEASED.md','CHANGELOG.md']:
    attach(ROOT/page,'S2_14BUS_REVIEW',note.replace('(s2_14bus_review.md)','(docs/src/s2_14bus_review.md)'))
top=load(BASE/'STATUS.json');top['declared_14bus_review']=record;(BASE/'STATUS.json').write_text(json.dumps(top,indent=2)+'\n')
print(status)
