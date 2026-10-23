"""Report native reduced solves separately from original-network validation."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'network_reduction'
load=lambda p:json.loads(Path(p).read_text())


def report():
    rows=[]
    for p in sorted(OUT.glob('*/stages.json')):
        c=load(p.parent/'contract.json')
        for stage in load(p):
            ap=p.parent/f'network-audit-{stage["stage"]}.json'
            a=load(ap) if ap.exists() else {}
            fp=p.parent/f'audit-{stage["stage"]}.json'
            full=load(fp) if fp.exists() else {}
            reduced=c.get('model_label','full-network')!='full-network'
            rows.append(dict(name=p.parent.name,stage=stage['stage'],factors=c['factors'],solver=c['solver'],
                reduced=reduced,penalty_proxies=c.get('penalty_proxies',True),fixed_controller=c['fixed_controller'],zero_shedding=c['zero_shedding'],
                zero_dr=c['zero_dr'],outages=c['outages'],native_status=stage['status'],
                elapsed_seconds=stage['elapsed_seconds'],native_details=stage.get('native_details'),variables=stage['num_variables'],constraints=stage['num_constraints'],
                native_success=stage['native_success'],full_network_valid=a.get('original_full_network_valid',False) if reduced else full.get('physical_valid',False),
                retained_buses=a['checks'][0]['retained_buses'] if reduced and a.get('checks') else (None if reduced else 500),
                reconstruction_valid=a.get('reduction_valid',False) if reduced else None,accepted=a.get('accepted',False) if reduced else full.get('accepted',False),
                max_dr_mw=max((s['dr_mw'] for s in full.get('states',[])),default=None),
                max_shedding_mw=max((s['shedding_mw'] for s in full.get('states',[])),default=None),
                original_balance_max_pu=max((s['power_balance_max_pu'] for s in full.get('states',[])),default=None),
                max_reconstruction_error_pu=max((s['reconstruction_error_max_pu'] for s in a.get('checks',[])),default=None)))
    current=dict(reduced_scopf_tested=bool(rows),runs=rows,
        accepted_reduced_runs=sorted({r['name'] for r in rows if r['accepted'] and r['reduced']}),
        recovered_110pct_expanded_master=any(r['accepted'] and r['reduced'] and r['factors']==[1.1] and len(r['outages'])==5 for r in rows),
        original_buses=500,reduction_modes={'all':dict(retained_buses=377,eliminated_buses=123,admittance_nonzeros=2781),
            'independent-degree3':dict(retained_buses=430,eliminated_buses=70,admittance_nonzeros=1572)},
        every_original_line_rating_required=True,full_network_validation_required=True,
        exhaustive_qualified=False,full_n1_accepted=False)
    (OUT/'RESULTS.json').write_text(json.dumps(current,indent=2)+'\n')
    lines=['# 500-bus exact network-reduction numerical tests','',
        'This is an algebraic change of variables; source equipment, branch identities and capabilities are unchanged. Original-case physical certificates retain their original scope.','',
        '## Confirmed controls and reduction','',
        'The user requested use of network reduction after the proposed configuration: all 131 taps corrective at 0.95–1.05, all 11 continuous banks corrective at their previous individual bounds, no added movement budgets. Slopes/references remain common across each master. Base normal limits/full load and N−1 emergency voltage/110% Rate A, 1% DR and 10 MW shedding policies remain in force. Run contracts state any deliberately fixed controller or zero-relief restriction.','',
        'Exact elimination of 123 zero-injection buses leaves 377 explicit polar bus voltages. All generation, loads, control attachments, shunts, free-tap endpoints and reference buses are retained. Each outage uses its own admittance map. Free controls lie wholly in the retained block, so reconstruction remains exact across their bounds.','',
        'A second, sparse variant eliminates a greedily selected independent set of 70 degree-three zero-injection buses and retains 430 buses. Selection minimizes new neighbor connections before eliminating adjacent candidates. Python independently reconstructs the same selection. Base admittance nonzeros are 1,572 versus 1,660 originally and 2,781 for the larger reduction.','',
        'Every original in-service branch keeps its original two terminal MVA inequalities, including branches incident to eliminated buses. Every eliminated-bus voltage bound and every original angle bound remain enforced. Terminal powers use reconstructed original voltages, original impedances/charging, and optimized original taps. Equivalent edges receive no substitute generic rating. The six-state master has 27,324 variables versus 31,260 for the corresponding full model, while retaining the physical inequalities.','',
        '## Native convergence and full-network checks','',
        '| Attempt / stage | Buses | Demand | Solver | Native status | Optimize elapsed (s) | Full physics | Reconstruction | Accepted |',
        '| --- | ---: | --- | --- | --- | ---: | --- | --- | --- |']
    for r in rows:
        lines.append(f"| {r['name']} / {r['stage']} | {r['retained_buses']} | {', '.join(f'{100*f:g}%' for f in r['factors'])} | {r['solver']} | {r['native_status']} | {r['elapsed_seconds']:.3f} | {r['full_network_valid']} | {r['reconstruction_valid'] if r['reduced'] else 'Full model'} | {r['accepted']} |")
    lines+=['',
        'Elapsed times wrap `optimize!` and can include backend setup/JIT; they are not a repeated native-only performance benchmark. A native time allowance may be exceeded while a sparse factorization completes.','',
        'Accepted means native success **and** independent original 500-bus AC P/Q balance, exact droop, Pg/Qg, voltage/angle, both-end ratings, tap/bank bounds, preventive response and DR/shedding-budget validation, plus independent reduction-map reconstruction. A physical point at a native time limit remains rejected. The auditor also checks consistency between saved native stage records and primal records.','',
        'The retained three-critical-outage controller is deliberately fixed during the first comparison, while preventive Pg and corrective taps/banks remain free. The expanded master contains line 36, transformer 562, line 219, G14 and G60. Any later free-controller recovery has a separate contract and is not a matched fixed-controller comparison.','',
        'The historical full-network fixed-controller MadNLP 110% zero-shedding master timed out after 91.348 seconds and failed physical validation. Its coordinated-start Ipopt last-resort attempt timed out after 101.467 seconds and also failed physical validation. These are references, not a warmed, repeated runtime benchmark; source snapshots, native allowances and starts must be considered before attributing a timing difference to reduction.','',
        'Refined comparisons also fix identically zero affine relief auxiliaries directly, removing redundant equality/lower-bound pairs. This is an equivalent formulation cleanup, recorded separately from reduction. Compact feasibility-only comparisons omit auxiliary normal-limit departure proxies in **both** models. These proxies are unused under the constant feasibility objective; the true normal base limits and N−1 emergency caps remain in the AC model. Their omission is a separate formulation change, so any benefit must be distinguished from electrical reduction. Penalty-minimization stages retain the proxies.','',
        '## Decision and limits','']
    if current['recovered_110pct_expanded_master']:
        lines+=['An accepted reduced 110% expanded-master point has passed reconstruction and all original-network gates. This covers the five listed outages only; exhaustive 389-outage qualification and a shared multi-demand optimum are not implied.']
    else:
        lines+=['No accepted reduced 110% expanded-master recovery is currently established. Local failure or a native time limit is inconclusive about global feasibility.']
    refined=next((r for r in rows if r['name']=='refined-regression-1.05' and r['accepted']),None)
    if refined:
        lines+=['',f"The accepted 430-bus 105% expanded-master feasibility point uses at most {refined['max_dr_mw']:.6f} MW DR and {refined['max_shedding_mw']:.6f} MW shedding. This is a feasibility point, not a minimum-relief or multi-demand optimum. Its original-network worst power-balance residual is {refined['original_balance_max_pu']:.6g} pu."]
    if any(r['name']=='refined-free-last-resort-1.1' for r in rows):
        lines+=['','The final 110% retry releases the shared slope/reference parameters and permits the confirmed 10 MW shedding budget after bounded zero-shedding attempts. Its status and full-network gate remain separate from the fixed-controller comparisons.']
    lines+=['',
        'The saved-point [precheck](PRECHECK.md) retains 20 reconstruction tests: all 14 previously AC-valid states preserve validity; six rejected points remain invalid. It includes line 21, whose outage changes the eliminated block. Base admittance nonzeros grow under the larger reduction, so fewer variables need not mean faster factorization. A one-second Ipopt stack sample records substantial time in MUMPS factorization. No physical remedy has been introduced. Normal-limit infeasibility and island supply obstructions cannot be removed by exact constraint-preserving elimination. Overall 500-bus S2 remains open.','',
        '![Admittance sparsity](../../../../docs/src/assets/s2_500bus/network_reduction/admittance-sparsity.png)','',
        'The three native campaign drivers are `examples/s2_500bus_network_reduction_run.jl`, `examples/s2_500bus_network_reduction_compact.jl`, and `examples/s2_500bus_network_reduction_refine.jl`; the final driver produces the accepted refined point. Run them serially in a fresh output checkout to preserve the historical records. Audit saved stages with `examples/audit_s2_500bus_network_reduction.py RUN_DIRECTORY STAGE` in a NumPy environment. The latter invokes the independent original-network checker. Executed adapters and full primal points are saved per attempt. `examples/check_s2_500bus_reduction_derivatives.jl` and `examples/check_s2_500bus_reduction_audit.py` are optimizer-free derivative and acceptance-guard checks.','']
    (OUT/'REPORT.md').write_text('\n'.join(lines))
    doc=ROOT/'docs/src/s2_500bus.md'
    text=doc.read_text()
    followup='## Demand continuation and response-policy diagnostics'
    tail=('\n\n'+followup+text.split(followup,1)[1]) if followup in text else ''
    for heading in ('## Electrical network-reduction precheck','## Exact electrical network-reduction tests'):
        if heading in text:
            text=text.split(heading)[0].rstrip()+'\n\n';break
    section=['## Exact electrical network-reduction tests','',
        'Electrical reduction has now been tested in SCOPF solves. The exact full reduction eliminates 123 zero-injection buses (377 retained); a sparse partial variant eliminates 70 independent degree-three buses (430 retained). Every load, generator, control, shunt and free-tap endpoint is retained. Original outage identities remain explicit, and each topology has its own reconstruction map.','',
        '**Every original branch keeps both terminal MVA limits.** All original bus-voltage and branch-angle bounds remain enforced on reconstructed original voltages. Base Rate A and contingency 110% Rate A caps are unchanged. No equivalent-edge rating substitutes for original equipment constraints. All accepted candidates require native success and independent replay of the original 500-bus AC, exact-droop, generation, rating, voltage/angle, equipment, response and relief-budget gates, plus reconstruction-map verification.','',
        '![Original and reduced admittance sparsity](assets/s2_500bus/network_reduction/admittance-sparsity.png)','',
        '| Variant | Buses retained | Base admittance nonzeros |','| --- | ---: | ---: |',
        '| Original | 500 | 1,660 |','| Full elimination | 377 | 2,781 |','| Sparse partial elimination | 430 | 1,572 |','',
        'The larger reduction increases fill-in. An Ipopt stack sample shows substantial time in MUMPS factorization. The partial variant was chosen to limit fill-in rather than maximize eliminated buses. Compact feasibility models omit unused departure-penalty proxies in both full and reduced comparisons, while retaining hard physical caps. Refined runs additionally fix identically zero affine relief auxiliaries directly; these equivalent cleanups are distinct from reduction itself.','',
        '| Attempt / stage | Buses | Native status | Original physics | Reconstruction | Accepted |','| --- | ---: | --- | --- | --- | --- |']
    for r in rows:
        section.append(f"| {r['name']} / {r['stage']} | {r['retained_buses']} | {r['native_status']} | {r['full_network_valid']} | {r['reconstruction_valid'] if r['reduced'] else 'Full model'} | {r['accepted']} |")
    if current['accepted_reduced_runs']:
        section+=['','Accepted reduced attempts: '+', '.join('`'+n+'`' for n in current['accepted_reduced_runs'])+'. Constant-objective feasibility points do not establish minimum DR/shedding or an optimal multi-demand design.']
    if refined:
        section+=['',f"The accepted 105% expanded master uses at most {refined['max_dr_mw']:.6f} MW DR and exactly zero shedding across its five outages. All six reconstructed original-network states pass, with worst P/Q balance residual {refined['original_balance_max_pu']:.6g} pu. This is separate from the earlier three-critical-outage zero-relief 105% point."]
    section+=['',
        ('An accepted reduced 110% expanded-master point is available, for the five listed outages only.' if current['recovered_110pct_expanded_master'] else 'No accepted reduced 110% expanded-master recovery is currently established.'),
        'Unchecked outages remain unqualified. Exact constraint-preserving reduction cannot remove the normal-limit infeasibility certificate or island supply deficits. Overall 500-bus S2 remains open.','',
        'Detailed stage status, time/size measurements, full-network and reconstruction audits, prechecks and numerical comparisons are retained in `artifacts/s2_scopf/ieee500_native/network_reduction/REPORT.md` and `RESULTS.json`. Reproduce with the `s2_500bus_network_reduction*.jl` study adapters; validate saved stages with `examples/audit_s2_500bus_network_reduction.py`. The read-only precheck includes a line-21 outage that changes the eliminated block; a separate partial-map check verifies a line-14 outage against the original network. No physical remedy is introduced.','']
    doc.write_text(text+'\n'.join(section)+tail)
    print(json.dumps(dict(runs=len(rows),accepted=current['accepted_reduced_runs'],recovered_110pct=current['recovered_110pct_expanded_master'])))


if __name__=='__main__':report()
