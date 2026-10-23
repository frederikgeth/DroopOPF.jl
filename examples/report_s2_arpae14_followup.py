"""Render frozen-controller demand qualification and conditional G5-trip coverage."""
from pathlib import Path
import json,hashlib,shutil,os
os.environ.setdefault('MPLCONFIGDIR','/tmp/s2-arpae14-matplotlib')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from control_figure_reporting import attach
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'artifacts/s2_scopf/ieee14_native';OUT=BASE/'followup'
load=lambda p:json.loads(p.read_text())
s=load(OUT/'summary.json');audit=load(OUT/'independent_audit.json')
assert len(s['attempts'])==15 and audit['discrepancies']==0
rows={(r['solver'],r['factor']):r for r in s['attempts']};factors=[.9,.95,1.,1.05,1.1];solvers=['ipopt','madnlp','ccopt']
checks={x['name']:x['checks'] for x in audit['connected']}
accepted=sum(r['accepted_with_trip_assumption'] for r in rows.values());direct=sum(r['primary']['accepted'] for r in rows.values())
retry_count=sum(r['primary']['name']!=r['final']['name'] for r in rows.values())
assert accepted==9 and direct==9 and retry_count==6
colors={'ipopt':'#2563eb','madnlp':'#d97706','ccopt':'#059669'}
plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
fig,axes=plt.subplots(1,3,figsize=(16,5.5),gridspec_kw={'width_ratios':[1,1.05,1]})
m=np.array([[int(rows[(solver,f)]['accepted_with_trip_assumption']) for f in factors] for solver in solvers])
from matplotlib.colors import ListedColormap
axes[0].imshow(m,cmap=ListedColormap(['#fee2e2','#dcfce7']),vmin=0,vmax=1,aspect='auto')
for i in range(3):
 for j in range(5):axes[0].text(j,i,'PASS' if m[i,j] else 'NOT\nQUALIFIED',ha='center',va='center',fontsize=7.7,color='#166534' if m[i,j] else '#991b1b')
axes[0].set_xticks(range(5),[f'{f:.0%}' for f in factors]);axes[0].set_yticks(range(3),['Ipopt','MadNLP','CCOpt'])
axes[0].set(title='Full outage-set qualification',xlabel='Sampled demand')
for solver in solvers:
 losses=[rows[(solver,f)]['final'].get('base_loss_mw',np.nan) if rows[(solver,f)]['accepted_with_trip_assumption'] else np.nan for f in factors]
 axes[1].plot(np.array(factors)*100,losses,'o-',color=colors[solver],label={'ipopt':'Ipopt','madnlp':'MadNLP','ccopt':'CCOpt'}[solver])
 ratios=[]
 for f in factors:
  cs=checks[rows[(solver,f)]['final']['name']]
  ratios.append(max(max(x['power_balance_max_pu']/1e-6,x['exact_droop_max_pu']/1e-5) for x in cs))
 axes[2].plot(np.array(factors)*100,ratios,'o-',color=colors[solver],label={'ipopt':'Ipopt','madnlp':'MadNLP','ccopt':'CCOpt'}[solver])
axes[1].set(title='Accepted base-state losses only',xlabel='Demand (%)',ylabel='Active loss (MW)',xticks=[90,95,100,105,110]);axes[1].legend(fontsize=8);axes[1].grid(alpha=.2)
axes[2].axhline(1,color='#b91c1c',ls='--',label='Acceptance threshold');axes[2].set_yscale('log')
axes[2].set(title='Worst final AC / exact-droop residual',xlabel='Demand (%)',ylabel='Residual divided by its tolerance',xticks=[90,95,100,105,110]);axes[2].grid(alpha=.2);axes[2].legend(fontsize=8)
fig.suptitle('14-bus S2 · nominal Ipopt-designed curves frozen across demand',fontsize=15)
fig.text(.5,.025,'Corrective taps and continuous bank remain free. PASS requires all 24 connected outages plus the line 7–8 / G5-trip retained-network check.\nUnqualified points remain failed after one bounded retry; local failures do not prove global infeasibility. No curve was redesigned.',ha='center',fontsize=9)
fig.subplots_adjust(top=.82,bottom=.23,wspace=.35)
for ext in ['png','svg']:fig.savefig(OUT/f'demand_qualification.{ext}',dpi=180,bbox_inches='tight')
plt.close(fig)
lines=['# S2 14-bus frozen-controller demand and G5-trip follow-up','','**Outcome: 9/15 solver–demand combinations qualified; 100%, 105% and 110% demand passed on all three solvers. The 90% and 95% points remain unqualified after bounded retries.** The controller is therefore not qualified over the full sampled 90–110% envelope.','','## Confirmed scope','','The user explicitly confirmed all three transformer taps corrective within source-relative ±5%, bank 3 corrective and continuous within 0–0.4 pu, and no additional movement budgets. Generator P/Q, source voltage/angle and Rate-A thermal limits remain enforced in every state. Automatic active response uses the original surviving-generator Pmax weights. Curves from the nominal `full-designed-ipopt` study are frozen exactly at all five demands and for every backend; slopes/references are not redesigned. Base dispatch and corrective equipment may optimize separately at each demand.','','A primary receives 600 iterations/20 native solver seconds; each failed lane receives one retry with 3,000 iterations/120 seconds. CCOpt uses initial barrier 1e-6 on primaries and 1e-8 on retries, with bound push/fraction 1e-8; physical tolerances and constraints are unchanged. All optimization ran serially. Primary failures are retained and are not replaced by retries.','','## Islanding contract and retained-network proof','','Line 11 (7–8) separates unloaded bus 8 and G5. Under the **user-confirmed G5-trip assumption**, bus 8 is disconnected, G5 produces zero, and the 13-bus main network must retain all declared load. There is no declared active or reactive load, fixed shunt or bank on bus 8; its only available connection is the uncharged 7–8 line. No generator protection, frequency or transient behavior is certified.','','In the existing G5-outage state, that unloaded leaf has zero line flow and the same voltage phasor as bus 7. Removing bus 8, line 11 and G5 therefore gives a retained-network witness without changing surviving voltages, dispatch, taps or bank B. The surviving active-response weights are the same. This is a physical projection and independent replay, not a new optimization or an added constraint in the connected master. The projection is checked separately for AC balance, exact droop, generator/voltage/thermal/angle limits, equipment bounds and response coupling. All six original nominal full-master witnesses pass it.','','Conditional steady-state coverage now accounts for all 25 catalog events at the qualified demand points: 24 connected outages plus this line-11/G5-trip response. The original catalog and exclusion records remain unchanged. This does not establish unrestricted islanding, protection operation or dynamic N-1 security.','','## Demand results','','| Demand | Ipopt | MadNLP | CCOpt | Accepted solver combinations |','|---:|---|---|---|---:|']
for f in factors:
 statuses=['PASS' if rows[(solver,f)]['accepted_with_trip_assumption'] else 'Unqualified' for solver in solvers]
 lines.append(f"| {f:.0%} | {' | '.join(statuses)} | {sum(rows[(solver,f)]['accepted_with_trip_assumption'] for solver in solvers)}/3 |")
lines+=['','![Frozen-controller demand qualification](demand_qualification.png)','','[SVG](demand_qualification.svg)','','## Retained solver attempts','','| Solver | Demand | Primary status | Final status | Retry | Accepted base loss MW | Conditional island projection |','|---|---:|---|---|---|---:|---|']
def native(row):
 result=load(BASE/row['name']/'result.json')['data']
 return result['termination_status']+(' (postprocessing error retained)' if row.get('error') else '')
for solver in solvers:
 for f in factors:
  row=rows[(solver,f)];final=row['final'];loss=f"{final['base_loss_mw']:.9f}" if row['accepted_with_trip_assumption'] else '—'
  lines.append(f"| {solver} | {f:.0%} | {native(row['primary'])} | {native(final)} | {'Yes' if final['name']!=row['primary']['name'] else 'No'} | {loss} | {'Pass' if row['island_valid'] else 'Fail'} |")
lines+=['','A valid isolated-event projection does not rescue an invalid full connected-outage master. At 95%, the G5-trip projection passes but G1’s outage remains invalid. Losses at rejected points are not used as feasible cost benchmarks. One failed MadNLP 95% primary also triggered the strict bank-susceptance domain check during result processing; its raw result is retained and independently audited.','','## Failure diagnosis','','At 95% demand all three final lanes fail on G1’s outage. Ipopt and MadNLP leave about 0.0061802 pu (0.61802 MVAr on 100 MVA base) reactive imbalance at bus 1 while matching the exact droop equations. CCOpt instead balances AC physics but leaves about 0.0129016 pu (1.29016 MVAr) exact-droop mismatch at G4/bus 6. These are different invalid iterates, not alternative accepted solutions.','','At 90%, the retained failures involve the 6–11 line outage (branch 8), G1 outage and G5 outage. The G5-trip retained-network projection also fails at that demand. All these failed states remain visible in the independent audit. No global infeasibility certificate is claimed. The supported conclusion is failure to qualify the frozen nominal controller at these two sampled demands under the declared policy.','','## Independent verification and next step','',f"Independent Python replay checked **{audit['connected_states']} connected-state records** across {audit['connected_attempts']} primary/retry runs and **{audit['island_projections']} retained-network projections**, including six original nominal projections. It found **zero classification discrepancies**. Of the 21 projections, 18 are physically valid; valid projections at an otherwise failed demand are not counted as full qualification. All source/runtime hashes and frozen-curve identities were verified. Physical acceptance tolerances remain AC/limits/response coupling 1e-6 pu, exact droop 1e-5 pu and unavailable generation 1e-8 pu.",'','This result motivated the subsequent [shared multi-demand controller study](s2_14bus_multidemand.md), which performs a separately confirmed redesign and held-out checks. The frozen nominal-controller results on this page remain unchanged; they do not substitute the later redesigned curves.','','## Evidence and reproduction','','`protocol.json` records the user confirmation and policy. `summary.json` preserves primary and final outcomes, island validity and the conditional combined acceptance. Each run directory retains inputs, starts, raw results, validation and evaluation plots. `island-*.json` records reduced cases, witness projections, discarded zero load and coupling checks. `independent_audit.json` retains every replayed state, bus-balance residual and per-generator exact-droop residual.','','```sh','julia --project=. examples/s2_arpae14_followup.jl "Explicit confirmation of this follow-up scope"','python3 examples/audit_s2_arpae14_followup.py','python examples/report_s2_arpae14_followup.py','```','','No 500-bus campaign was run. S1 remains closed for its earlier base-case study; this frozen S2 controller result does not change S1’s saved qualifications.','']
text='\n'.join(lines);(OUT/'REPORT.md').write_text(text)
assets=ROOT/'docs/src/assets/s2_14bus_followup';assets.mkdir(exist_ok=True)
for ext in ['png','svg']:shutil.copyfile(OUT/f'demand_qualification.{ext}',assets/f'demand_qualification.{ext}')
doc=text.replace('(demand_qualification.png)','(assets/s2_14bus_followup/demand_qualification.png)').replace('(demand_qualification.svg)','(assets/s2_14bus_followup/demand_qualification.svg)')
(ROOT/'docs/src/s2_14bus_followup.md').write_text(doc)
status=dict(status='partially_qualified_frozen_demand_envelope',primary_combinations=15,primary_accepted=direct,
 accepted_after_retries=accepted,bounded_retries=retry_count,qualified_demand_factors=[1.,1.05,1.1],unqualified_demand_factors=[.9,.95],
 connected_outages=24,conditional_islanding_events=1,conditional_response='Line 11 removed, G5 tripped, bus8 disconnected with zero declared load',
 general_full_n1_claim=False,nominal_island_projections=6,nominal_island_projection_passes=6,
 connected_state_checks=audit['connected_states'],island_projection_checks=audit['island_projections'],independent_discrepancies=0)
(OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
body='''## Frozen-controller demand and conditional island follow-up

The [follow-up](s2_14bus_followup.md) retains the nominal Ipopt curves at five
demands. All three solvers qualify 100/105/110%; 90/95% remain unqualified after
bounded retries (9/15 combinations pass). Line 7–8 is additionally accounted for
under the explicit G5-trip/unloaded-bus8-disconnection assumption, validated on
the retained 13-bus network. This is conditional steady-state coverage, not
protection/dynamic certification or a qualified continuous demand envelope.
'''
attach(ROOT/'docs/src/s2_14bus.md','S2_FROZEN_DEMAND_FOLLOWUP',body)
attach(BASE/'REPORT.md','S2_FROZEN_DEMAND_FOLLOWUP',body.replace('(s2_14bus_followup.md)','(followup/REPORT.md)'))
print('Follow-up report: direct 9/15; after six retries 9/15; all six original nominal island projections passed.')

from control_figure_reporting import attach_s2_multidemand
attach_s2_multidemand(ROOT/'docs/src/s2_14bus_followup.md',doc=True)
attach_s2_multidemand(ROOT/'docs/src/s2_14bus.md',doc=True)
attach_s2_multidemand(BASE/'REPORT.md')
