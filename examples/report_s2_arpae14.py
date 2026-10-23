"""Report the confirmed native 14-bus S2 scope; no solves and no source rewrites."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s2_scopf/ieee14_native'
load=lambda p:json.loads(p.read_text())
summary=load(OUT/'summary.json');audit=load(OUT/'independent_audit.json');catalog=load(OUT/'catalog.json')['data']
rows=summary['attempts'];by_name={r['name']:r for r in rows}
assert audit['lanes_replayed']==len(rows) and audit['discrepancies']==0
frozen=by_name['full-frozen-ipopt'];design=by_name['full-designed-ipopt']
gain=frozen['base_loss_mw']-design['base_loss_mw'];percent=100*gain/frozen['base_loss_mw']
excluded=[e for e in catalog['entries'] if e['disposition']=='excluded']
lines=['# Native 14-bus S2 qualification', '',
       f"**Connected-outage study: {sum(r['accepted'] for r in rows)}/{len(rows)} solver runs accepted; {summary['eligible']} eligible outages plus the base state in each full master.** Independent Python audit: {audit['states_replayed']} saved states, zero classification discrepancies. One islanding outage remains excluded; **complete N-1 security is not established**.", '',
       '## Declared contract', '',
       'ARPA-E Challenge 1 Network Model 01 Scenario 01, nominal demand, S1 Pmin-zero/symmetric-Q case and calibrated zero-deadband curves. The study has 14 buses, five online generators, 20 online branches including three designated transformers, and one available continuous bank. Source generator limits and imported OPF/SCOPF references remain separate. Original P/Q-limit requalification is outside this campaign.', '',
       'The user confirmed this campaign and its bounded retries on 2026-10-15: all three eligible transformer taps free within source-relative ±5%, bank 3 continuously adjustable within its bank-specific bounds, corrective independent settings per scenario, and no additional movement budget. Absolute equipment bounds still apply. Continuous B optimization does not establish discrete switching feasibility.', '',
       'Active-power policy is preventive base dispatch plus Pmax-weighted automatic balancing, renormalized over surviving online generators. Every state enforces its surviving generator P/Q capability box. Droop slopes/references are shared across all states; “frozen droop” means fixed curve settings, while confirmed tap and bank controls remain corrective in both arms.', '',
       'Objective: minimize base-state active loss, sum(Pg)−sum(Pd); outage states impose feasibility constraints and carry no added objective weight. The native solver is used rather than the imported upstream recourse model. Source Rate-A ratings apply in every state, conservatively relative to source contingency Rate-C ratings. Source voltage and branch-angle bounds are enforced and independently checked in every state.', '',
       'Frozen curves retain the S1 8% full-Q-span slope and calibrated reference. Shared design selects each slope independently within 2–8% full-Q span and each reference within ±0.02 pu of calibration; both deadband widths and Q at reference remain zero. This is one nominal-demand security design, not a qualification across S1’s five demands.', '',
       '## Results', '',
       '| Run | States | Native status | Independent acceptance | Base loss MW | Wall time s including build/extraction |',
       '|---|---:|---|---|---:|---:|']
for r in rows:
    lines.append(f"| {r['name']} | {r['scenario_count']} | {r.get('solver_status',r.get('error'))} | {'Pass' if r['accepted'] else 'Fail'} | {r.get('base_loss_mw',float('nan')):.9f} | {r.get('elapsed_seconds',float('nan')):.3f} |")
lines+=['',f"Full enumeration reduces base loss by **{gain*1000:.3f} kW ({percent:.3f}%)** when shared slope/reference design is allowed: {frozen['base_loss_mw']:.9f} → {design['base_loss_mw']:.9f} MW with Ipopt. MadNLP reproduces the same comparison within approximately 2.5e-7 MW. CCOpt then solves the exact-complementarity full master with each chosen curve set frozen; both pass exact physical checks. Its tiny objective differences are within numerical tolerance, not evidence of a better global optimum.", '',
          'The source-two subset contains line 6–12 (branch 9) and generator 3 at bus 3. Those runs are bring-up checks, not the security claim. The full master includes all connected eligible line, transformer and generator outages without screening or contingency omission. Primary budgets are 600 iterations/20 native solver seconds; one 3,000-iteration/120-second retry per lane was authorized but **none was needed**. The first solve of each backend/model path may include compilation; these wall times are not a controlled solver speed ranking.', '',
          '## Independently replayed full-master margins', '',
          '| Full run | Max AC residual pu | Max exact-droop residual pu | Min thermal margin MVA | Min voltage margin pu | Min generator P margin MW | Min generator Q margin MVAr |',
          '|---|---:|---:|---:|---:|---:|---:|']
for lane in audit['checks']:
    if len(lane['scenarios'])!=25:continue
    ss=lane['scenarios']
    lines.append(f"| {lane['name']} | {max(s['power_balance_max_pu'] for s in ss):.3g} | {max(s['exact_droop_max_pu'] for s in ss):.3g} | {min(s['thermal_min_margin_mva'] for s in ss):.3g} | {min(s['voltage_min_margin_pu'] for s in ss):.3g} | {min(s['generator_p_min_margin_mw'] for s in ss):.3g} | {min(s['generator_q_min_margin_mvar'] for s in ss):.3g} |")
lines+=['', 'Near-zero or slightly negative margins within tolerance are binding limits, not operating headroom. Acceptance tolerances are AC balance/limits/angle/response coupling 1e-6 pu or radians as applicable, exact droop 1e-5 pu, and unavailable generation 1e-8 pu. The independent Python audit recomputes complex AC flows, balance, source ratings, generator/voltage limits, saturated exact curves, shared design bounds, active-response coupling and equipment bounds directly from saved JSON. Objective replay is checked separately.', '',
          '## Shared design parameters', '',
          '| Generator | Bus | Full-Q-span droop % | Reference voltage pu |', '|---:|---:|---:|---:|']
case=load(OUT/'full-designed-ipopt/optimized_input.json')['data']['case']
for attachment in case['attachments']:
    d=case['controls'][attachment['control_id']-1];cap=d['capability']
    lines.append(f"| {attachment['generator_id']} | {attachment['location']['bus_id']} | {100*d['slope']*(cap['q_max']-cap['q_min']):.6f} | {d['schedule']['v_ref']:.9f} |")
lines+=['', '## Explicit coverage gap', '']
for e in excluded:
    branch=next(b for b in case['network']['branches'] if b['id']==e['device_id'])
    lines.append(f"`{e['contingency']['id']}`: {e['device_kind']} {e['device_id']} ({branch['from_bus']}–{branch['to_bus']}) is excluded as `{e['reason']}`. Its outage separates bus 8 and generator 5 from the main component. Bus 8 has no declared load, but this study does not balance both resulting islands, test the separated generator/protection response, or certify that event as safe. The catalog retains the excluded event explicitly.")
lines+=['', 'The original nominal-only study left islanding-response and demand testing as follow-up work. The subsequent frozen-demand study, shared multi-demand designs and scheduled CCOpt recovery retain their separate evidence. The current accepted-results section above consolidates the completed sampled 14-bus qualification and its conditional G5-trip coverage. No original-limit, dynamic, discrete-equipment or global-optimality claim follows from these results. A later campaign needs its own equipment-policy confirmation under `AGENTS.md`.', '',
          '## Evidence and reproduction', '',
          'Each run directory under `artifacts/s2_scopf/ieee14_native/` contains the complete input/optimized studies, starts, solver result, contracts, native and independent physical checks, and an evaluation report with device-level inputs, outputs, flow/voltage/dispatch plots and operating margins. `catalog.json` lists all 25 candidates; `protocol.json` records user confirmation, policies, budgets and source hashes. `independent_audit.json` retains all 157 state checks. Imported references under `artifacts/s2_scopf/ieee14/` remain intact.', '',
          '```sh', 'julia --project=. examples/s2_arpae14_campaign.jl',
          'python3 examples/audit_s2_arpae14.py', 'python3 examples/report_s2_arpae14.py', '```', '',
          'S1 remains closed for its declared base-case study; this S2 qualification is separate. Release notes are staged in `RELEASE_NOTES_UNRELEASED.md`; no release or tag was published.', '']
text='\n'.join(lines)
(OUT/'REPORT.md').write_text(text)
(ROOT/'docs/src/s2_14bus.md').write_text(text)
(OUT/'STATUS.json').write_text(json.dumps(dict(status='qualified_connected_outages',eligible_outages=summary['eligible'],
    excluded_outages=[e['contingency']['id'] for e in excluded],full_n1_accepted=False,solver_attempts=len(rows),
    accepted_attempts=sum(r['accepted'] for r in rows),independent_states=audit['states_replayed'],discrepancies=0,
    base_loss_improvement_kw=gain*1000,scope='Nominal demand; Pmin0 symmetric Q; corrective continuous equipment; all connected eligible outages'),indent=2)+'\n')
print('Native S2 report generated:',sum(r['accepted'] for r in rows),'/',len(rows),'accepted;',audit['states_replayed'],'states; full N-1 not claimed')

from control_figure_reporting import attach_s2
attach_s2(OUT/'REPORT.md')
attach_s2(ROOT/'docs/src/s2_14bus.md', doc=True)

# Preserve the separately scored, explicitly confirmed frozen-demand follow-up.
followup_doc=ROOT/'docs/src/s2_14bus_followup.md'
if followup_doc.exists():
    from control_figure_reporting import attach
    note="""## Frozen-controller demand and conditional island follow-up

The [follow-up](s2_14bus_followup.md) retains the nominal Ipopt curves at five
demands. All three solvers qualify 100/105/110%; 90/95% remain unqualified after
bounded retries (9/15 combinations pass). Line 7–8 is additionally accounted for
under the explicit G5-trip/unloaded-bus8-disconnection assumption, validated on
the retained 13-bus network. This is conditional steady-state coverage, not
protection/dynamic certification or a qualified continuous demand envelope.
"""
    attach(ROOT/'docs/src/s2_14bus.md','S2_FROZEN_DEMAND_FOLLOWUP',note)
    attach(OUT/'REPORT.md','S2_FROZEN_DEMAND_FOLLOWUP',note.replace('(s2_14bus_followup.md)','(followup/REPORT.md)'))

followup_status=OUT/'followup/STATUS.json'
if followup_status.exists():
    status=json.loads((OUT/'STATUS.json').read_text())
    status['confirmed_followup']=json.loads(followup_status.read_text())
    (OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')

from control_figure_reporting import attach_s2_multidemand
attach_s2_multidemand(ROOT/'docs/src/s2_14bus.md',doc=True)
attach_s2_multidemand(OUT/'REPORT.md')
multi_status=OUT/'multidemand/STATUS.json'
if multi_status.exists():
    status=json.loads((OUT/'STATUS.json').read_text())
    status['confirmed_multidemand_followup']=json.loads(multi_status.read_text())
    (OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')

from control_figure_reporting import attach_s2_solver_designs
attach_s2_solver_designs(ROOT/'docs/src/s2_14bus.md',doc=True)
attach_s2_solver_designs(OUT/'REPORT.md')

from control_figure_reporting import attach_s2_ccopt_recovery
attach_s2_ccopt_recovery(ROOT/'docs/src/s2_14bus.md',doc=True)
attach_s2_ccopt_recovery(OUT/'REPORT.md')

from control_figure_reporting import attach_s2_current_results
attach_s2_current_results(ROOT/'docs/src/s2_14bus.md',kind='doc')
attach_s2_current_results(OUT/'REPORT.md',kind='report')
