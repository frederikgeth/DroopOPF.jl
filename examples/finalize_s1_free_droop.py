"""Package the complete audited extension without overwriting historical results."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/s1_free_droop'
load=lambda p:json.loads(p.read_text())
def save(name,x):(OUT/name).write_text(json.dumps(x,indent=2)+'\n')
summary=load(OUT/'summary.json');parameters=[];witnesses=[];totals=[]
for size in (14,500):
 rows=[load(p) for p in (OUT/str(size)/'attempts').glob('*.json')];byname={r['name']:r for r in rows}
 audit=load(OUT/str(size)/'independent_audit.json')
 assert audit['states_replayed']==sum('state' in r for r in rows) and audit['discrepancies']==0
 for stage in ('design','frozen'):
  rs=[r for r in rows if r['tags']['stage']==stage];assert len(rs)==180
  for family in ('droop','droop_tap','droop_shunt','droop_tap_shunt'):
   for f in (.9,.95,1.,1.05,1.1):
    cell=[r for r in rs if r['tags']['family']==family and r['tags']['factor']==f]
    assert len(cell)==9 and {r['tags']['init'] for r in cell}=={'joint','loss','cost'}
 if size==14:assert sum(r['tags']['stage']=='equipment_baseline' for r in rows)==90
 totals.append(dict(size=size,new_attempts=len(rows),accepted=sum(r['accepted'] for r in rows),physical=sum(r['point_pass'] for r in rows),failed_attempts=sum(not r['accepted'] for r in rows),retries=sum(r['tags']['stage']=='recovery' for r in rows)))
 for selected in load(OUT/str(size)/'selected.json'):
  r=byname[selected['chosen']];c=load(ROOT/r['model_path'])['data']['case'];old=load(ROOT/r['base_model_path'])['data']['case']
  for a in c['attachments']:
   i=a['control_id']-1;d=c['controls'][i];prior=old['controls'][i];q=d['capability'];width=q['q_max']-q['q_min']
   parameters.append(dict(size=size,family=selected['family'],generator=a['generator_id'],control=i+1,slope_percent=100*d['slope']*width,slope_pu_v_per_pu_q=d['slope'],slope_percent_bounds=[2,8],vref=d['schedule']['v_ref'],vref_bounds=[prior['schedule']['v_ref']-.02,prior['schedule']['v_ref']+.02],reference_change_pu=d['schedule']['v_ref']-prior['schedule']['v_ref'],deadband_pu=0,selected_attempt=r['name']))
 for group in summary['groups']:
  if group['size']!=size or group['best'] is None:continue
  r=byname[group['best']];ph=r['point_checks']['physical']
  witnesses.append(dict(size=size,stage=group['stage'],family=group['family'],factor=group['factor'],attempt=r['name'],model_path=r['model_path'],loss_mw=r['loss_mw'],economic_cost=r['economic_cost'],minimum_voltage_lower_margin_pu=ph['voltage_min_margin'],minimum_voltage_upper_margin_pu=ph['voltage_max_margin'],minimum_thermal_margin_mva=ph['branch_thermal_min_margin']*100,maximum_branch_loading_percent=max(max(b['from_mva'],b['to_mva'])/b['rating_mva']*100 for b in r['branches']),generator_limits_and_dispatch=r['generators'],bus_limits_and_voltages=r['buses'],branch_ratings_and_flows=r['branches']))
save('selected_parameters.json',parameters);save('verified_witnesses.json',witnesses);save('totals.json',totals)
# Unified ledger keeps old fixed-curve stress contracts and new design failures distinct.
combined=[]
for r in load(ROOT/'artifacts/s1_arpae500/failed_combinations.json'):
 combined.append(dict(size=500,campaign='Historical '+r['family'],family=r['family'],stage='fixed-droop qualification',factor=r['factor'],solver=r['solver'],failed_attempts=r['failed_attempts'],recovered=r['recovered_same_model_solver_objective'],method=r['method'],recovery=r['recovery_attempt'],changed_equipment_fixes=r['changed_equipment_fix_attempts'],source='artifacts/s1_arpae500/failed_combinations.json'))
for r in summary['failures']:
 combined.append(dict(r,campaign='Historical 14-bus fixed' if r['stage']=='legacy_fixed' else 'New '+r['stage'],source=f"artifacts/s1_free_droop/{r['size']}/failed_combinations.json"))
save('failed_and_recovered_all.json',combined)
ledger=['# Combined failed and recovered ledger','','Covers the selected fixed-droop qualifications, original-limit 500-bus stress contracts, and the new free-droop extension. Earlier superseded 14-bus calibration experiments remain historical. A changed-equipment fix is not a same-model recovery.','','| Buses | Campaign | Family | Demand | Solver | Failed attempts | Same-model recovery | Method |','|---:|---|---|---:|---|---:|---|---|']
for r in combined:ledger.append(f"| {r['size']} | {r['campaign']} | {r['family']} | {r['factor']:.0%} | {r['solver']} | {len(r['failed_attempts'])} | {'Recovered' if r['recovered'] else 'Unresolved'} | {r['method']} |")
(OUT/'FAILED_AND_RECOVERED_ALL.md').write_text('\n'.join(ledger)+'\n')
report=(OUT/'REPORT.md').read_text().split('\nThe combined selected-study ledger is')[0]
report+='\nThe combined selected-study ledger is `FAILED_AND_RECOVERED_ALL.md`, with machine-readable provenance in `failed_and_recovered_all.json`. It also retains historical original-Q failures and distinguishes changed-equipment fixes from same-model recovery.\n'
report+='\n## Interpretation\n\n'
comparisons=load(OUT/'comparisons.json')
for size in (14,500):
 r=next(r for r in comparisons if r['size']==size and r['stage']=='frozen' and r['family']=='droop' and r['factor']==.9)
 report+=f"For {size} buses, the droop-only nominal candidate held fixed at 90% demand changes best-found loss from {r['baseline_loss_mw']:.6f} to {r['new_loss_mw']:.6f} MW ({r['loss_change_percent']:+.2f}%).\n\n"
report+='\nThe original 8% design remains feasible within the free-design bounds, so freeing droop parameters cannot worsen the best attainable objective on the same demand model. Frozen regressions concern the selected solver-returned nominal candidate at another demand, not a smaller feasible set. Nominal loss alone does not select curves for best performance across demand levels. The optimized slope/reference pair is not unique at the nominal point. Preserve the baseline and compare frozen operating performance before adopting a new candidate; a future multi-demand design objective can address this directly. These experiments vary slope and reference together, so improvements cannot be attributed to slope alone.\n'
report+='\n## Independent replay and packaging\n\n'
report+='| Buses | All new attempts | Accepted | Physical witnesses | Recovery attempts | Independent replay discrepancies |\n|---:|---:|---:|---:|---:|---:|\n'
for r in totals:report+=f"| {r['size']} | {r['new_attempts']} | {r['accepted']} | {r['physical']} | {r['retries']} | 0 |\n"
report+='\n`selected_parameters.json` exports every selected generator slope, reference and bounds. `verified_witnesses.json` includes voltages, generator dispatch and limits, branch ratings/flows and margins for each best accepted cell. These are local solutions. Successful native termination and physical feasibility are separate; neither proves global optimality. All pinned source files and previous results remain unchanged.\n'
(OUT/'REPORT.md').write_text(report)
doc=report.replace('# S1 free-droop extension: 14 and 500 buses','# S1 free-droop studies and recovery',1)
doc+='\n## Relation to earlier studies\n\nSee the [14-bus baseline closeout](s1_14bus_closeout.md) and [500-bus fixed-droop qualification](s1_500_results.md). The complete artifact report and per-network failure tables are under `artifacts/s1_free_droop/`. The previous original-Q-limit fixed-equipment failures remain unresolved; this symmetric-Q extension does not change that conclusion.\n'
(ROOT/'docs/src/s1_free_droop_results.md').write_text(doc)

# Preserve the separately scored zero-deadband numerical follow-up.
from s1_zero_deadband_reporting import append_followup
append_followup(OUT/'REPORT.md', doc=False)
append_followup(ROOT/'docs/src/s1_free_droop_results.md', doc=True)

from control_figure_reporting import attach_s1
attach_s1(OUT/'REPORT.md', figures=True)
attach_s1(ROOT/'docs/src/s1_free_droop_results.md', doc=True)

protocol=load(OUT/'protocol.json')
for path,h in protocol['hashes'].items():assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==h,path
paths=list(OUT.rglob('*'))+[ROOT/'examples'/p for p in ('s1_free_droop.jl','s1_free_droop_baselines.jl','s1_free_droop_recovery.jl','audit_s1_free_droop.py','report_s1_free_droop.py','finalize_s1_free_droop.py')]+[ROOT/'docs/src/s1_free_droop_results.md']
save('manifest.json',dict(pinned_input_files_verified=len(protocol['hashes']),hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths) if p.is_file() and p.name!='manifest.json'}))
print(json.dumps(totals));print('Packaged selected parameters, witnesses, documentation and checksums')
