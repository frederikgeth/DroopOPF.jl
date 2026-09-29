#!/usr/bin/env python3
import json, math, sys
from pathlib import Path

root=Path(sys.argv[1]).resolve()

def load(path):
    with open(path) as f:return json.load(f)

def report(path):
    if not path.exists():return None
    d=load(path); return d.get("data",d)

def state(r):
    if r is None:return 0
    if r.get("valid",False):return 3
    if r.get("physical_valid",False):return 2
    return 1

rows=[]
for n in (118,300):
  for solver in ("ipopt","madnlp","ccopt"):
    folder=root/f"ieee{n}-{solver}"
    direct=report(folder/"direct-report.json")
    fixed=report(folder/"fixed-report.json")
    staged=report(folder/"staged-report.json")
    if n==300:
      immediate=report(folder/"direct-immediate-report.json")
      settled=report(folder/"direct-settled-report.json")
      lineage="direct M9.1 anchor"
    else:
      stages=report(folder/"stages.json")
      immediate=None if stages is None else stages["immediate_report"]
      settled=None if stages is None else stages["settled_report"]
      lineage="staged M9.1 anchor"
    rows.append(dict(network=n,solver=solver,direct=direct,fixed=fixed,
      staged=staged,immediate=immediate,settled=settled,lineage=lineage))

expanded=[]
for path in sorted((root/"expanded").glob("*/summary.json")):
    x=load(path);x["path"]=str(path.relative_to(root))
    retry_path=path.parent/"warm-retry-summary.json"
    x["warm_retry"]=load(retry_path) if retry_path.exists() else None
    expanded.append(x)

payload={"kind":"DroopOPF.S2FrozenInitialScorecard","core":[{
    "network":r["network"],"solver":r["solver"],"m9_3_lineage":r["lineage"],
    **{k:None if r[k] is None else {"valid":r[k].get("valid",False),
      "physical_valid":r[k].get("physical_valid",False),
      "termination_status":r[k].get("termination_status")}
      for k in ("direct","fixed","staged","immediate","settled")}}
    for r in rows],"expanded":expanded,
    "acceptance":"Solver acceptance and independent physical replay are separate. Missing cells are not failures or passes.",
    "s1_scorecard_unchanged":True}
(root/"qualification_scorecard.json").write_text(json.dumps(payload,indent=2)+"\n")

colors=["#d1d5db","#dc2626","#f59e0b","#16a34a"]
def svg_heatmap(path,title,row_labels,col_labels,data,cell_w=145,cell_h=42):
    left,top=150,70;width=left+cell_w*len(col_labels)+20;height=top+cell_h*len(row_labels)+35
    s=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
       '<style>text{font-family:system-ui,sans-serif;fill:#111827}.small{font-size:12px}.label{font-size:13px}.title{font-size:18px;font-weight:600}</style>',
       f'<text x="{width/2}" y="25" text-anchor="middle" class="title">{title}</text>']
    for j,c in enumerate(col_labels):s.append(f'<text x="{left+j*cell_w+cell_w/2}" y="55" text-anchor="middle" class="small">{c}</text>')
    words=["—","invalid","physical","accepted"]
    for i,r in enumerate(row_labels):
      y=top+i*cell_h;s.append(f'<text x="{left-8}" y="{y+26}" text-anchor="end" class="label">{r}</text>')
      for j,v in enumerate(data[i]):
        x=left+j*cell_w;s.append(f'<rect x="{x}" y="{y}" width="{cell_w-3}" height="{cell_h-3}" rx="4" fill="{colors[v]}"/>')
        tc="white" if v in (1,3) else "#111827";s.append(f'<text x="{x+(cell_w-3)/2}" y="{y+25}" text-anchor="middle" class="small" fill="{tc}" style="fill:{tc}">{words[v]}</text>')
    s.append('</svg>');path.write_text("\n".join(s))

def svg_bars(path,title,names,values,bar_colors,ylabel):
    width=max(650,90*len(names)+120);height=430;left,bottom,top=75,105,55
    finite=[v for v in values if v is not None];lo=min(finite) if finite else 0;hi=max(finite) if finite else 1
    pad=max((hi-lo)*.15,1e-8);lo=max(0,lo-pad);hi=hi+pad
    s=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
       '<style>text{font-family:system-ui,sans-serif;fill:#111827}.small{font-size:11px}.title{font-size:18px;font-weight:600}.axis{font-size:12px}</style>',
       f'<text x="{width/2}" y="25" text-anchor="middle" class="title">{title}</text>',
       f'<text x="18" y="{height/2}" transform="rotate(-90 18 {height/2})" text-anchor="middle" class="axis">{ylabel}</text>']
    plot_h=height-top-bottom;step=(width-left-20)/len(names)
    for i,(name,v,color) in enumerate(zip(names,values,bar_colors)):
      x=left+i*step+step*.18;bw=step*.64
      if v is None:s.append(f'<text x="{x+bw/2}" y="{top+plot_h-4}" text-anchor="middle" class="small">timeout</text>')
      else:
        h=(v-lo)/(hi-lo)*plot_h;y=top+plot_h-h;s.append(f'<rect x="{x}" y="{y}" width="{bw}" height="{h}" fill="{color}" rx="3"/>');s.append(f'<text x="{x+bw/2}" y="{max(y-5,42)}" text-anchor="middle" class="small">{v:.6g}</text>')
      parts=name.split("\n")
      for k,p in enumerate(parts):s.append(f'<text x="{x+bw/2}" y="{top+plot_h+18+13*k}" text-anchor="middle" class="small">{p}</text>')
    s.append('</svg>');path.write_text("\n".join(s))

# Figure 1: core scorecard.
labels=[f"IEEE-{r['network']} {r['solver']}" for r in rows]
cols=["direct","fixed","staged","immediate","settled"]
matrix=[[state(r[c]) for c in cols] for r in rows]
svg_heatmap(root/"scorecard.svg","S2 initial qualification: acceptance and physical replay",labels,["Direct M9.1","Fixed seed","Staged M9.1","M9.3 immediate","M9.3 settled"],matrix)

# Figure 2: expanded validity grid.
solvers=["ipopt","madnlp","ccopt"]
def config_name(x):return f"{x['reactive']} / {x['equipment']} / {x['timing']} / {x.get('profile','nominal')}"
configs=sorted({config_name(x) for x in expanded})
em=[[0 for _ in configs] for _ in solvers]
for x in expanded:
  i=solvers.index(x["solver"]);j=configs.index(config_name(x))
  em[i][j]=3 if x["result"]["valid"] else 2 if x["result"]["physical_valid"] else 1
svg_heatmap(root/"expanded_matrix.svg","Expanded IEEE-118 matrix (unrun cells shown as —)",solvers,configs,em,cell_w=120,cell_h=44)

# Figure 3: matched Ipopt objectives.
ip=[x for x in expanded if x["solver"]=="ipopt"]
ip.sort(key=lambda x:(x["reactive"],x["timing"],x["equipment"]))
names=[f"{x['reactive']}\n{x['equipment']}\n{x['timing'][0].upper()}" for x in ip]
vals=[x["result"]["objective"] for x in ip]
svg_bars(root/"expanded_objectives.svg","Expanded Ipopt objectives (P=preventive, C=corrective)",names,vals,["#2563eb" if x["reactive"]=="avr" else "#7c3aed" for x in ip],"Dispatch-deviation objective")

# Figure 4: Phase-I outcome.
phase=[]
for solver in solvers:
  p=root/f"ieee300-{solver}"/"phase1-fixed.json"
  phase.append(load(p)["slacks"] if p.exists() else None)
vals=[None if p is None else p["max_slack"] for p in phase]
svg_bars(root/"phase1_restoration.svg","IEEE-300 Phase-I restoration",solvers,vals,["#dc2626"]*3,"Maximum power-balance slack (pu)")

def cell(r,k):
    x=r[k]
    if x is None:return "not run"
    status=x.get("termination_status","unknown")
    return ("accepted" if x.get("valid") else "physical only" if x.get("physical_valid") else "invalid")+f" (`{status}`)"

lines=["# S2 frozen initial scorecard and expansion","",
"This report is generated from retained JSON artifacts. Solver acceptance and independent physical replay are kept separate; an elastic Phase-I result never counts as an accepted SCOPF result.","",
"![Initial scorecard](scorecard.svg)","",
"## Core matrix","",
"| Network | Solver | Direct M9.1 | Fixed seed | Staged M9.1 | M9.3 immediate | M9.3 settled | M9.3 lineage |",
"|---:|---|---|---|---|---|---|---|"]
for r in rows:lines.append(f"| {r['network']} | {r['solver']} | {cell(r,'direct')} | {cell(r,'fixed')} | {cell(r,'staged')} | {cell(r,'immediate')} | {cell(r,'settled')} | {r['lineage']} |")
lines += ["","### How to read the core matrix","",
"- **Network** is the IEEE test-case bus count; **Solver** is the nonlinear or exact-complementarity backend.",
"- **Direct M9.1** solves the equipment-aware SCOPF directly from its declared starts, with the selected M9.1 preventive equipment policy.",
"- **Fixed seed** solves the corresponding fixed-equipment SCOPF, seeded only from the FreeQ base-case anchor. It is a staging prerequisite, not an M9.1 equipment result. (The column is *seed*, not speed.)",
"- **Staged M9.1** solves the same equipment-aware M9.1 study using every scenario state from an accepted fixed-seed result. It is reported separately from the direct path.",
"- **M9.3 immediate** assesses the saved M9.1 base with taps and shunts frozen in every contingency. **M9.3 settled** then permits only the declared bounded corrective equipment movement. Both are steady-state assessments, not transient simulations.",
"- **M9.3 lineage** identifies whether the paired assessment is anchored to the staged M9.1 result or, when that staging path is unavailable, an independently valid direct M9.1 result.",
"- **accepted** requires independent physical replay and an accepted solver termination; **physical only** passes replay but is status-rejected; **invalid** fails replay; **not run** means a required prior stage was not accepted.",
"","## Expanded IEEE-118 matrix","",
"The public case retains its supplied electrical state. Fixed shunt 34 at bus 34 (B=0.14 pu) is represented by an equivalent one-step bank at its supplied state, then continuously bounded to ±10% for this explicitly labelled overlay. Tap movement is limited to 0.005 pu and shunt movement to 0.014 pu in corrective cells. Mixed control replaces one of three AVRs with a Volt–VAr controller using a ±0.005 pu deadband, slope 0.05, and the FreeQ anchor output.","",
"Here **Reactive** selects AVR-only or mixed AVR/Volt–VAr assignments; **Equipment** selects the controlled tap, shunt, joint pair, or multi-location set; **Timing** is preventive or bounded corrective; **Profile** is nominal, held-out outage, or +3% load stress; and **Load** is the fixed demand multiplier. **Status** is the solver termination, **Physical** is independent replay validity, **Accepted** additionally requires an accepted status, and **Warm retry** reports a separately retained same-model scenario-state retry.","",
"![Expanded matrix](expanded_matrix.svg)","","![Matched objectives](expanded_objectives.svg)","",
"| Solver | Reactive | Equipment | Timing | Profile | Load | Status | Physical | Accepted | Warm retry | Objective |",
"|---|---|---|---|---|---:|---|---|---|---|---:|"]
for x in expanded:
  q=x["result"];retry=x.get("warm_retry")
  retry_cell="—" if retry is None else ("accepted" if retry["valid"] else f"retained failure (`{retry['termination_status']}`)")
  lines.append(f"| {x['solver']} | {x['reactive']} | {x['equipment']} | {x['timing']} | {x.get('profile','nominal')} | {x.get('load_factor',1.0)} | `{q['termination_status']}` | {q['physical_valid']} | {q['valid']} | {retry_cell} | {q['objective']} |")
passes=sum(x["result"]["valid"] for x in expanded)
retry_passes=sum(not x["result"]["valid"] and x.get("warm_retry") is not None and x["warm_retry"]["valid"] for x in expanded)
counts={s:(sum(x["result"]["valid"] for x in expanded if x["solver"]==s),sum(1 for x in expanded if x["solver"]==s)) for s in solvers}
lines += ["",f"Frozen direct acceptance: **{passes}/{len(expanded)}** completed cells: Ipopt **{counts['ipopt'][0]}/{counts['ipopt'][1]}**, MadNLP **{counts['madnlp'][0]}/{counts['madnlp'][1]}**, CCOpt **{counts['ccopt'][0]}/{counts['ccopt'][1]}**. A bounded same-model warm retry accepts **{retry_passes}** additional cell, for **{passes+retry_passes}/{len(expanded)}** with declared retries. The Ipopt holdout reaches `LOCALLY_SOLVED` from its retained scenario-state witness. Three stricter CCOpt retries remain invalid on exact-droop replay in the generator-outage scenario; its holdout and +3% stress multi-location direct cells pass.","",
"## Phase-I restoration","","![Phase-I restoration](phase1_restoration.svg)","",
"Ipopt returned a positive-slack local point (total slack 0.5464 pu, maximum component 0.001961 pu); its exact retry remained invalid. MadNLP and CCOpt reached the external 180-second wall limit without an artifact. These outcomes classify numerical paths only and are not infeasibility certificates.","",
"## Critical interpretation","",
"The initial scorecard is now frozen and reproducible, but it is not a universal SCOPF reliability claim. IEEE-300 staged M9.1 remains unresolved. The expansion is IEEE-118 only and uses a declared continuous shunt overlay. It now includes a second transformer, independent holdout outages, and +3% fixed-control stress, but it is still a targeted matrix rather than full N-1 enumeration."]
(root/"qualification_report.md").write_text("\n".join(lines)+"\n")
