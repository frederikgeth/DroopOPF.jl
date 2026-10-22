"""Generate the authoritative S1 closeout from validated saved artifacts; no solves."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s1_arpae14_closeout'
def read(name):
    return json.loads((OUT / name).read_text())
manifest = read('manifest.json')
for name, expected in manifest['hashes'].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, name
case = read('frozen-study.json')['data']['case']
ref = read('calibration_reference.json')
witnesses = read('demand_witnesses.json')
checks = read('replay_checks.json')['attempts']
assert len(checks) == 45 and sum(r['accepted'] for r in checks) == 42
assert len(witnesses) == 5 and all(r['accepted'] for r in witnesses)
lines = [
'# S1 14-bus closeout',
'',
'**Closed for the declared 14-bus, sampled-demand S1 study.** The selected design uses the nominal jointly loss-optimized reference with ±5% source tap bounds, then freezes its five droop curves, transformer taps and shunt setting. The 500-bus qualification remains the next S1 stage; this does not close the broader scaling milestone or S2.',
'',
'## Selected contract',
'',
'| Item | Final choice |', '|---|---|',
'| Network | ARPA-E Challenge 1 Network Model 01, Scenario 01; 14 active buses, 5 online generators, 20 online branches including 3 transformers |',
'| Generator limits | Study Pmin=0; symmetric Q bounds at the larger absolute original limit; originals preserved |',
'| Reference OPF | 100% demand; minimize total active losses with all three online transformer ratios and bank 3 free |',
'| Reference equipment limits | Multiplicative ±5% of imported source taps; bank 3 continuous B=0..0.4 pu; fixed shunts unchanged |',
'| Droop | Shifted-zero-Q; 8% voltage change over full Q range; no deadband; G1–G5 attached, G6 offline |',
'| Calibration | m=0.08/(Qmax−Qmin), Vref=Vopf+mQopf; exact saturated curve checked at the joint OPF point |',
'| Final free controls | None: curves, taps and shunts frozen across demands |',
'| Evaluation objective | Minimize active losses; generation cost reported separately |',
'| Demand / starts | 90/95/100/105/110%; demand-matched saved cost/loss OPFs and nominal joint OPF anchor; no flat starts |',
'| Solvers / budget | Ipopt, MadNLP, CCOpt; 600 iterations / 20 native solver seconds per attempt; smooth widths 1e-6 pu |',
'| Acceptance | Exact physical/policy witness and successful solver termination reported separately |',
'',
'±5% is an exploratory study envelope, not a verified hardware tap range. Shunt optimization is continuous susceptance, not discrete switching. In the packaged frozen case, bank 3 becomes an equivalent fixed shunt admittance; the original source bank metadata and reference policy remain in the source artifacts.',
'',
'## Frozen equipment and curves',
'',
'| Transformer | Source ratio | Reference lower | Reference upper | Final frozen ratio |', '|---|---:|---:|---:|---:|']
source_ratios = {19: .978, 20: .969, 21: .932}
for i, v in source_ratios.items():
    lines.append(f'| {i} | {v:.6f} | {v*.95:.6f} | {v*1.05:.6f} | {ref["taps"][str(i)]:.9f} |')
lines += ['', f'Bank 3 at bus 11 is frozen at **B={ref["susceptances"]["3"]:.9f} pu**. Its reactive injection depends on voltage: Q=B·V² on the 100-MVA base.', '', '| Generator | Bus | Vref (pu) | m (pu voltage / pu Q) | Study Qmin / Qmax (MVAr) |', '|---|---:|---:|---:|---:|']
for a in case['attachments']:
    d=case['controls'][a['control_id']-1]
    lines.append(f'| G{a["generator_id"]} | {a["location"]["bus_id"]} | {d["schedule"]["v_ref"]:.9f} | {d["slope"]:.9f} | {100*d["capability"]["q_min"]:.6f} / {100*d["capability"]["q_max"]:.6f} |')
lines += ['', 'The 8% definition is a full-Q-span droop; it is not ±8% on each side. Reference values above 1.1 pu are curve parameters, not bus-voltage limit violations.', '', '## Frozen-design results', '', 'Best accepted point at each demand; acceptance counts include all three starts and all three solvers. Source economic costs are not assigned a currency.', '', '| Demand | Accepted / attempts | Loss (MW) | Economic cost | Minimum voltage headroom (pu) | Minimum thermal headroom (MVA) |', '|---|---:|---:|---:|---:|---:|']
for r in witnesses:
    f=r['tags']['factor']; cs=[a for a in checks if a['factor']==f]
    vm=min(min(b['lower_margin'],b['upper_margin']) for b in r['buses'])
    tm=min(b['thermal_margin_mva'] for b in r['branches'] if b['thermal_margin_mva'] is not None)
    lines.append(f'| {100*f:.0f}% | {sum(a["accepted"] for a in cs)}/{len(cs)} | {r["loss_mw"]:.6f} | {r["economic_cost"]:.3f} | {vm:.3g} | {tm:.3g} |')
lines += ['', '**Demand coverage: 5/5 verified. Solver acceptance: 42/45.** Ipopt and MadNLP each accept 15/15; CCOpt accepts 12/15. All three rejected attempts are CCOpt iteration limits at 90% demand. They are retained, not replaced by another solver\'s success. The separate free-equipment comparator with these same calibrated curves accepts 45/45.', '', 'Near-zero margins represent binding constraints, not additional operating reserve. These are finite sampled-demand, local AC results; they do not prove continuous-range robustness, global optimality, dynamic stability or N-1 security.', '', '## Selection and retained limitations', '', '- The frozen ±5% joint-reference design reduces losses by 6.78–82.73% versus the previous fixed-equipment loss-objective baseline across the sampled demands.', '- The wider ±10%-of-source and absolute 0.9–1.1 references improve free-equipment losses further at 95–110%, but neither frozen design produces a verified point at 90/95%; frozen 110% losses worsen by 16.31%. Their failed searches remain unresolved, not globally infeasible.', '- The earlier source-equipment 8% baseline remains a regression comparator. Cost-optimal and variable-slope designs remain archived comparisons, not the selected closeout design.', '- Original-generator-limit compatibility was tested on earlier designs. The final joint-reference design has **not** been requalified under original limits; its closure applies only to Pmin=0/symmetric-Q study limits.', '- Only the retained public-case sequence contributes to this scorecard.', '', '## Reproduction and saved evidence', '', 'No optimization is needed to regenerate this closeout:', '', '```sh', 'julia --project=. examples/audit_s1_arpae14_joint_reference.jl', 'julia --project=. examples/finalize_s1_arpae14.jl', 'python3 examples/report_s1_arpae14_closeout.py', '```', '', 'The joint-reference audit replays 348 saved states with zero discrepancies. Finalization reloads the serialized frozen case and replays all 45 selected-design attempts, checks the nominal calibration, and saves one accepted witness per demand. The report generator verifies all manifest hashes before rendering.', '', 'The package is `artifacts/s1_arpae14_closeout/`: `frozen-study.json`, `angle_limits.json`, `calibration_reference.json`, `demand_witnesses.json`, `replay_checks.json`, and `manifest.json`. **Load the saved angle limits as well as the Study:** the experimental API keeps angle constraints outside the Study serialization. Witness records include every bus voltage, generator P/Q limit and output, and both-end branch/transformer flows, ratings and angle bounds.', '', 'Input, result, runner, relevant physics/validator code, and environment hashes are recorded in the manifest. Original raw cases, OPF/SCOPF solutions, and failed attempts are preserved. No broad Git cleanup, deletion of evidence, or new SCOPF run is part of this closeout.', '']
body='\n'.join(lines)
(OUT/'REPORT.md').write_text(body+'\nNext: [500-bus plan](../../docs/src/s1_500_plan.md).\n')
(ROOT/'docs/src/s1_14bus_closeout.md').write_text(body+'\nNext: [500-bus plan](s1_500_plan.md).\n')
print('Closeout report generated; manifest hashes verified.')
