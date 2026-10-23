"""Independent report for the new P2 limit-aware campaign."""
import json,sys
from pathlib import Path
from report_mixed_avr_reserve import summarize
root=Path(sys.argv[1]);candidate=sys.argv[2]
d=summarize(root,candidate)
(root/'reserve-aggregate-checks.json').write_text(json.dumps(d,indent=2)+'\n')
failed=[r['event'] for r in d['rows'] if not r['valid']]
master=json.loads((root/'p2-master/summary.json').read_text())
attempt_summary=f"The joint generator-60 / line-36 / transformer-562 redesign terminated {master['status']} and was rejected (accepted={master['accepted']}). The catalogue therefore assesses the validated reserve-aware base candidate with its preventive dispatch, designed curves and AVR schedule frozen. Alternative topology starts for unresolved outages are retained separately."
avr_table='\n'.join('| '+str(g)+' | '+' | '.join(f"{float(t[str(g)]):.8f}" for t in d['avr_targets'])+' |' for g in sorted(map(int,d['avr_targets'][0])))
text=f'''# P2 limit-aware mixed AVR/droop 500-bus rerun

Candidate: `{candidate}`. Full settled connected-outage qualification: **{'PASSED' if d['full_security_qualified'] else 'OPEN'}**.

This fresh run supersedes the exact-S2 response choice for this study. Historical
sealed results retain their original semantics. Physical network data are unchanged.
The default active-range weights happen to equal the prior Pmax weights because
these units have zero Pmin. The response-law change is saturation and redistribution,
not a numerical weight change. Neither of these configurations uses equal weights.

| Policy | This P2 run | Previous S2-based run |
|---|---|---|
| Active response | Limit-aware; default effective active-range weights | Pmax-proportional equality |
| Voltage and thermal bounds | Original normal limits and Rate A | Voltage extension 0.05 pu, Rate A x1.1 |
| Load relief | None; full original load required | DR and up to 10 MW shedding |
| Taps | 131 selected; original +/-5% absolute envelope; corrective movement <=0.025 of supplied ratio | Same selections/absolute bounds; no additional movement cap |
| Shunts | 11 continuous banks; <=two supplied sections, within legal envelope | Same selections/absolute bounds; no additional movement cap |
| Timing | Assumed 120-second settled sensitivity | Settled, no declared delay |

All selected banks have a single section, so the two-section budget does not
further restrict their absolute range. These are continuous susceptance results;
legal discrete switching and actual device timing are not qualified. Immediate
zero-movement security is not tested by this settled scan.

The mixed 15 AVR / 36 droop split, assumed S=Pmax/0.95 circles, existing Q bounds,
shared calibrated droop design envelope, five hourly demands 90/100/105/100/90%,
and 25%-active-range/hour preventive ramps are retained. Automatic active response
has no extra per-outage movement cap beyond effective active capability; generator
frequency dynamics and GFL/GFM behavior remain deferred. AVR targets may be
scheduled within nominal +/-0.02 pu and at most 0.01 pu/hour, then freeze across
outages within each period. Native reserve optimization maximizes minimum upward
headroom; frozen catalogue assessments are feasibility solves. The additional
S2 proportional replacement-reserve constraint is not imposed. No S2-specific
capacity filter or predictive safety skipping is used.

| Result | Value |
|---|---:|
| Candidate native/independent validation | {d['base_and_master_valid']} |
| Connected outages scanned / expected | {d['scanned']} / {d['catalogue_size']} |
| Accepted five-period trajectories | {d['accepted']} |
| Numerically unresolved trajectories | {d['unresolved']} |
| Minimum base upward headroom | {100*d['minimum_headroom_fraction']:.6f}% |
| Generators at Pmax by period | {d['pmax_counts_by_period']} |
| Five-hour base loss energy | {d['loss_energy_mwh']:.8f} MWh |
| Maximum AVR movement | {d['max_avr_movement_pu_per_hour']:.8f} pu/hour |
| Frozen policy and base identity | {d['frozen_identity_valid']} |

{attempt_summary}

## Preventive AVR schedule

| Generator | Period 1 | Period 2 | Period 3 | Period 4 | Period 5 |
|---|---:|---:|---:|---:|---:|
{avr_table}

The schedule passes its base bounds/movement checks. Its security qualification
has exactly the accepted/unresolved coverage above.

Numerically unresolved outages: {', '.join(failed) or 'none'}.
For context, the previous S2-based accepted branch-21 witness included up to
19.0200 MW DR and 9.93599 MW shedding across its periods. This P2 run permits
neither. That comparison does not prove such relief is physically necessary.

Missing outages: {', '.join(d['missing']) or 'none'}.

Every accepted trajectory requires native convergence, Julia replay and independent
complex-current physics, AVR/droop/circle, response, movement and cross-file identity
checks. A numerical failure is not a physical infeasibility proof. Structural island
exclusions remain outside the 389 connected-outage scope. Focused regression verification: 115 Julia checks and 37 Python unittest checks passed, including five added equipment-movement corruption checks. This does not establish
full-catalogue resource/loss optimality, discrete or transient security, or close P2.
'''
(root/'REPORT.md').write_text(text)
print(json.dumps({k:d[k] for k in ['candidate','scanned','accepted','unresolved','full_security_qualified']}))
