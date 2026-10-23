"""Render anchor-only S1 public reports from saved validated matrix results."""
from pathlib import Path
import json, csv

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts'/'s1_anchor_only'
OUT.mkdir(parents=True,exist_ok=True)

def load(p): return json.loads(p.read_text())

def build_14():
    src=load(ROOT/'artifacts/s1_arpae14_gated/primary_matrix_summary.json')
    rows=[r for r in src if r.get('tags',{}).get('variant') in ('no_deadband','with_deadband')
          and r['tags'].get('family')=='fixed' and r['tags'].get('start')=='anchor']
    solver_order={'ipopt':0,'madnlp':1,'ccopt':2}
    variant_order={'no_deadband':0,'with_deadband':1}
    rows.sort(key=lambda r:(variant_order[r['tags']['variant']],r['tags']['factor'],solver_order[r['solver']]))
    if len(rows)!=18: raise RuntimeError(f'expected 18 anchor fixed-control cells, got {len(rows)}')
    (OUT/'arpae14_anchor_rows.json').write_text(json.dumps(rows,indent=2)+'\n')
    fields=['variant','demand_percent','solver','solver_status','gate_status','verified_point','objective','iterations','elapsed_seconds',
            'voltage_min_margin_pu','voltage_max_margin_pu','branch_thermal_min_margin_pu','generator_p_min_margin_pu','generator_p_max_margin_pu','generator_q_min_margin_pu','generator_q_max_margin_pu']
    flat=[]
    for r in rows:
        phys=r.get('point_checks',{}).get('physical',{})
        flat.append({'variant':r['tags']['variant'],'demand_percent':round(100*r['tags']['factor']),'solver':r['solver'],
          'solver_status':r.get('solver_status'),'gate_status':r.get('gate_status'),'verified_point':r.get('point_pass',False),
          'objective':r.get('objective'),'iterations':r.get('iterations'),'elapsed_seconds':r.get('elapsed_seconds'),
          'voltage_min_margin_pu':phys.get('voltage_min_margin'),'voltage_max_margin_pu':phys.get('voltage_max_margin'),
          'branch_thermal_min_margin_pu':phys.get('branch_thermal_min_margin'),'generator_p_min_margin_pu':phys.get('generator_p_min_margin'),
          'generator_p_max_margin_pu':phys.get('generator_p_max_margin'),'generator_q_min_margin_pu':phys.get('generator_q_min_margin'),
          'generator_q_max_margin_pu':phys.get('generator_q_max_margin')})
    with (OUT/'arpae14_anchor.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(flat)
    lines=['# S1 14-bus fixed-controls results — anchor initialization only','',
      'This report keeps the source OPF operating point as the sole initialization. The model has fixed transformer taps and shunts, fixed droop curves, no free control settings, and the original S1 demand scaling. Results are shown for 90%, 100%, and 110% demand with Ipopt, MadNLP, and CCOpt. The objective is the S1 squared dispatch-deviation objective, not fuel cost.','',
      '| Droop curve | Demand | Solver | Termination | Independent point gate | Verified point | Objective |','|---|---:|---|---|---|---:|---:|']
    for r in flat:
        obj='—' if r['objective'] is None else f"{r['objective']:.6f}"
        lines.append(f"| {r['variant'].replace('_',' ')} | {r['demand_percent']}% | {r['solver']} | {r['solver_status']} | {r['gate_status']} | {'yes' if r['verified_point'] else 'no'} | {obj} |")
    lines+=['','The independent gate checks AC balance, exact droop replay, generator limits, voltage limits, branch thermal limits and angle limits. An unresolved or locally infeasible solver termination is not a proof of network infeasibility. Flat-start outcomes are excluded from this report and figure.','',
      '## Verified point count','',
      '| Droop curve | Verified anchor points |','|---|---:|']
    for variant in ('no_deadband','with_deadband'):
        n=sum(x['verified_point'] for x in flat if x['variant']==variant)
        lines.append(f'| {variant.replace("_"," ")} | {n}/9 |')
    lines+=['','![Anchor-only S1 14-bus fixed-controls matrix](arpae14_anchor_matrix.svg)','']
    (OUT/'report.md').write_text('\n'.join(lines))
    # Matrix shows only the anchor start; red means no independently verified optimizer point.
    variants=('no_deadband','with_deadband'); factors=(.9,1.,1.1); solvers=('ipopt','madnlp','ccopt')
    width,height=1180,280;left,top,cellw,cellh=180,72,105,64
    svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
         '<rect width="100%" height="100%" fill="white"/>',
         '<style>text{font-family:Arial,sans-serif;fill:#18212b}.title{font-size:18px;font-weight:bold}.label{font-size:14px}.status{font-size:11px;fill:white;font-weight:bold}</style>',
         '<text x="24" y="30" class="title">14-bus fixed controls · anchor start only · independent point validation</text>']
    for j,f in enumerate(factors):
        for k,s in enumerate(solvers):
            x=left+(j*3+k)*cellw
            svg.append(f'<text x="{x+cellw/2}" y="58" text-anchor="middle" class="label">{int(f*100)}% · {s}</text>')
    colors={'yes':'#3d9678','no':'#d77a70'}
    for i,variant in enumerate(variants):
        y=top+i*cellh
        svg.append(f'<text x="{left-16}" y="{y+34}" text-anchor="end" class="label">{variant.replace("_"," ")}</text>')
        rr=[r for r in flat if r['variant']==variant]
        for j,r in enumerate(rr):
            x=left+j*cellw+5
            svg.append(f'<rect x="{x}" y="{y}" width="95" height="48" rx="5" fill="{colors["yes" if r["verified_point"] else "no"]}"/>')
            status=r['solver_status'] or 'NO RESULT'
            short={'LOCALLY_SOLVED':'VERIFIED','LOCALLY_INFEASIBLE':'LOCAL INFEAS.','ITERATION_LIMIT':'ITERATION LIMIT'}.get(status,status)
            svg.append(f'<text x="{x+47.5}" y="{y+29}" text-anchor="middle" class="status">{short}</text>')
    svg.append('</svg>')
    (OUT/'arpae14_anchor_matrix.svg').write_text('\n'.join(svg))
    return flat

if __name__=='__main__':
    build_14()
    print(f'Wrote anchor-only report and plot to {OUT}')
