"""S1 extension tables and scientific plots; no failed attempts are discarded."""
from pathlib import Path
import json, shutil
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch

root=Path("artifacts")
load=lambda p:json.loads(p.read_text())
folders=["s1_robustness","s1_public_controls","s1_public_recovery","s1_public_polish"]
data={f:load(root/f/"summary.json") for f in folders}
out=root/"s1_extension";out.mkdir(exist_ok=True)
plt.rcParams.update({"font.size":10,"axes.spines.top":False,"axes.spines.right":False})
def save(fig,name):
    for ext in ("png","pdf"):fig.savefig(out/f"{name}.{ext}",dpi=160,bbox_inches="tight")
    plt.close(fig)
def status(r):
    return 2 if r["valid"] else 1 if r.get("physical_valid") and r.get("policy_valid") else 0
def annotation(r):
    s={"LOCALLY_SOLVED":"Local","ALMOST_LOCALLY_SOLVED":"Acceptable","ITERATION_LIMIT":"Iter limit","SLOW_PROGRESS":"Slow","LOCALLY_INFEASIBLE":"Infeas.","TIME_LIMIT":"Time limit"}.get(r.get("status"),"Error")
    return f"{s}\n{r.get('iterations','–')}"
cmap=ListedColormap(["#edaaa6","#f2cf88","#a6d5c8"])
legend=[Patch(facecolor=cmap(i),label=t) for i,t in enumerate(["Physical/policy check failed","Physical/policy pass; solver failed","Solver + physical/policy pass"])]

fig,axes=plt.subplots(2,3,figsize=(12,6),layout="constrained")
for col,(family,title) in enumerate([("droop_controls","Free droop slopes"),("tap_controls","Free ratios"),("shunt_controls","Free banks")]):
    rows=[r for r in data["s1_robustness"] if r["tags"].get("family")==family]
    rows.sort(key=lambda r:r["tags"]["count"])
    x=[r["tags"]["count"] for r in rows]
    axes[0,col].plot(x,[r["iterations"] for r in rows],"o-",color="#007a92")
    axes[1,col].plot(x,[1000*r["solve_seconds"] for r in rows],"o-",color="#007a92")
    axes[0,col].set(title=title,ylabel="Iterations")
    axes[1,col].set(xlabel="Number selected",ylabel="Observed solve phase (ms)")
    for ax in axes[:,col]:ax.grid(alpha=.2)
fig.suptitle("96 buses held fixed · other two control families fully free · all 15 runs validate")
save(fig,"control_counts")

fig,ax=plt.subplots(figsize=(12,5.4),layout="constrained")
matrix=[];labels=[];ordered=[]
for n in (118,300):
    for factor in (1.,1.05):
        rows=[next(r for r in data["s1_public_controls"] if r["buses"]==n and r["tags"].get("study")=="public_joint" and r["tags"]["load_factor"]==factor and r["solver"]==solver and r["tags"]["start"]==mode) for solver in ("ipopt","madnlp") for mode in ("anchor","flat_low","flat_high")]
        ordered.append(rows);matrix.append([status(r) for r in rows]);labels.append(f"{n} buses · load ×{factor:g}")
ax.imshow(matrix,cmap=cmap,vmin=0,vmax=2,aspect="auto")
ax.set(yticks=range(4),yticklabels=labels,xticks=range(6),
    xticklabels=["Ipopt\nanchor","Ipopt\nflat / low","Ipopt\nflat / high","MadNLP\nanchor","MadNLP\nflat / low","MadNLP\nflat / high"],
    title="Public joint-design pilot · native termination and iteration count")
for i,rows in enumerate(ordered):
    for j,r in enumerate(rows):ax.text(j,i,annotation(r),ha="center",va="center",fontsize=9)
ax.legend(handles=legend,loc="upper center",bbox_to_anchor=(.5,-.17),ncol=1,frameon=False)
save(fig,"public_matrix")

fig,ax=plt.subplots(figsize=(13,5.2),layout="constrained")
matrix=[];ordered=[];labels=[]
for n in (118,300):
    for solver in ("ipopt","madnlp"):
        rows=[r for r in data["s1_public_recovery"] if r["buses"]==n and r["solver"]==solver]
        assert len(rows)==7
        ordered.append(rows);matrix.append([status(r) for r in rows]);labels.append(f"{n} · {solver}")
ax.imshow(matrix,cmap=cmap,vmin=0,vmax=2,aspect="auto")
ax.set(yticks=range(4),yticklabels=labels,xticks=range(7),
    xticklabels=["Small\nbound push","ε=1e−4","ε=1e−5","ε=1e−6","ε from\nerror bound","Load ×1.025","Load ×1.05"],
    title="Recovery probes · coarse smoothing is allowed to fail exact replay")
for i,rows in enumerate(ordered):
    for j,r in enumerate(rows):ax.text(j,i,annotation(r),ha="center",va="center",fontsize=8.5)
ax.legend(handles=legend,loc="upper center",bbox_to_anchor=(.5,-.16),ncol=1,frameon=False)
save(fig,"recovery_matrix")

fig,axes=plt.subplots(1,2,figsize=(11,4),layout="constrained")
scanrows=[]
for ax,n in zip(axes,(118,300)):
    for label,color in [("anchor","#007a92"),("validated","#c17827")]:
        s=load(root/"s1_conditioning_public"/f"public{n}-{label}.json")
        columns=[c["max_absolute_derivative"] for c in s["columns"] if c["name"].startswith("design_")]
        weak=sum(v<1e-12 for v in columns)
        ax.plot(range(1,len(columns)+1),np.maximum(sorted(columns),1e-12),"o",ms=3,color=color,label=f"{label}: {weak}/{len(columns)} <1e−12")
        nonzero=[v for v in s["row_max_absolute_derivative"] if v>0]
        scanrows.append((n,label,weak,len(columns),min(nonzero),max(nonzero)))
    ax.set(yscale="log",xlabel="Sorted droop-parameter column",ylabel="Max |constraint derivative|",title=f"{n} buses · raw variable units")
    ax.legend(fontsize=8)
fig.suptitle("Local droop sensitivity · values below 1e−12 shown at the plotting floor")
save(fig,"derivative_scales")

fig,axes=plt.subplots(2,2,figsize=(12,6),layout="constrained")
for col,n in enumerate((118,300)):
    for label,color in [("anchor","#007a92"),("validated","#c17827")]:
        profile=load(root/"s1_conditioning_public"/f"public{n}-{label}.json")["operating_point"]
        axes[0,col].plot(range(1,len(profile["vm"])+1),profile["vm"],color=color,label=label,lw=.9)
        axes[1,col].plot(range(1,len(profile["max_terminal_loading"])+1),100*np.array(profile["max_terminal_loading"]),color=color,lw=.8,label=label)
    axes[0,col].plot(range(1,len(profile["vmin"])+1),profile["vmin"],"--",color="#a44c48",lw=.8)
    axes[0,col].plot(range(1,len(profile["vmax"])+1),profile["vmax"],"--",color="#a44c48",lw=.8)
    axes[1,col].axhline(100,color="#a44c48",ls="--",lw=.8)
    axes[0,col].set(title=f"{n} buses",ylabel="Voltage (pu)",xlabel="Bus row")
    axes[1,col].set(ylabel="Maximum terminal loading (%)",xlabel="Branch row")
    axes[0,col].legend()
fig.suptitle("Nominal public operating points · fixed-equipment anchor and selected validated joint result")
save(fig,"operating_points")

def setting_spreads(folder,rows):
    designs=[load(root/folder/(r["name"]+"-design.json")) for r in rows]
    if len(designs)<2:return (None,None,None)
    ref=designs[0];spreads=[]
    for family in ("droop","tap","shunt"):
        values=[]
        if family=="droop":
            for c in ref["droop_controls"]:
                key=str(c["control_id"]);lo,hi=c["bounds"]["slope"]
                values.append(np.ptp([d["droops"][key]["slope"] for d in designs])/(hi-lo))
        elif family=="tap":
            for c in ref["tap_controls"]:
                key=str(c["branch_id"])
                values.append(np.ptp([d["taps"][key] for d in designs])/(c["upper"]-c["lower"]))
        else:
            for c in ref["shunt_controls"]:
                key=str(c["bank_id"])
                # Public study banks all have a +/-0.01 step and legal counts 0:4.
                values.append(np.ptp([d["susceptances"][key] for d in designs])/.04)
        spreads.append(max(values,default=0))
    return spreads

lines=["# S1 robustness and public-network checkpoint\n",
    "**S1 remains open.** All 35 synthetic robustness attempts pass. The initial public matrix passes 13/30 attempts, including both fixed-equipment baselines and validated joint solutions at each network/load combination. Recovery is mixed; no solver configuration is promoted as universally reliable.\n",
    "## Study design and numerical budget\n",
    "The 12-/96-bus synthetic cases reuse the heterogeneous connected modules. At 96 buses, one family's free count changes while the other two remain fully free: slopes 0/1/16/32/64, taps 0/1/8/16/32, and banks 0/1/16/32/64. Three starts are used with both solvers: the validated fixed-equipment state with supplied settings, or flat voltage/angle with design settings at 20% or 80% of their allowed intervals.\n",
    "Every pilot attempt has a 1000-iteration budget, tolerance 1e-8 and zero bound relaxation. Ipopt uses adaptive barrier updates and a 60 CPU-second limit; MadNLP retains its default monotone barrier and a 60 wall-second limit. These are deliberately recorded configurations, not identical algorithms/time-limit semantics. Solver-native MadNLP residuals are scaled; they are not presented as equivalent to Ipopt's unscaled residuals. Independent physical checks use the same unchanged tolerances.\n",
    "### Explicit public overlays\n",
    "| Network | Buses / generators / branches | Droops | Candidate tap controls | Added simple banks |",
    "|---|---|---|---|---|",
    "| IEEE 118 | 118 / 54 / 186 | 37 | 11 | 12 |",
    "| IEEE 300 | 300 / 69 / 411 | 35 | 129 | 32 |\n",
    "Unmodified PGLib v23.07 source files and SHA-256 provenance are retained under test/data/pglib/v23.07. Both fixed-equipment imports solve and validate. Costs and branch angle constraints remain outside the adapter; objective values are project dispatch deviation, not PGLib economic optima. Source branch angle limits are audited separately on physically valid results.\n",
    "The overlays are synthetic, not measured equipment data. Available generators with more than 1e-3 pu Q headroom at the baseline receive a droop whose q0 and voltage reference reproduce that baseline; half-deadbands are 0.005 pu and nominal slope is 0.04/(Qmax−Qmin), with slope bounds 0.5–2 times nominal. Exclusions are listed. Tap candidates are branches with explicit nonzero source TAP, with an assumed ±5% range; source TAP alone does not establish actual adjustable hardware or its limits. Largest positive-Q load buses receive alternating capacitor/reactor banks with B step ±0.01 pu, G=0, counts 0:4 and initially zero admittance. Original branches, aggregate fixed shunts, generator bounds and dispatch references are unchanged.\n",
    "Nominal and 1.05-times P/Q demand are tested without recentering droops. Full original/overlay/stressed studies, numerical states, policy starts, designs, traces and failures are retained. Baseline anchoring creates a known feasible nominal witness; it is not a test of an arbitrary real operating point or evidence that every start is numerically reliable.\n",
    '## Public operating-point checks\n',
    '![Public operating points](operating_points.png)\n',
    'Fixed-equipment AC residuals are 1.28e-9 pu (118 buses) and 1.04e-9 pu (300 buses). Every validated pilot/recovery/polishing outcome passes the separate source-angle audit with zero violation. The selected 300-bus joint profile is the one valid nominal result in the initial pilot, not a certified best solution.\n',
    "## Synthetic robustness\n",
    "![Independent control counts](control_counts.png)\n",
    "| Network | Solver | Start | Iterations | Objective | Physical/policy valid |",
    "|---|---|---|---|---|---|"]
for r in data["s1_robustness"]:
    if r["tags"]["study"]=="starts":
        lines.append(f"| {r['buses']} | {r['solver']} | {r['tags']['start']} | {r['iterations']} | {r['objective']:.10g} | {r['physical_valid']}/{r['policy_valid']} |")
lines += ["\nAll count sweeps, the three direct smoothing probes, the three continuation stages and both staged-release solves pass. A small solver-dependent objective difference remains; passing tolerances do not imply identical settings or a unique design.\n",
    "## Public convergence and design variation\n","![Initial public matrix](public_matrix.png)\n",
    "| Network | Load | Valid joint attempts / 6 | Best / worst valid objective | Max slope / tap / bank spread (% of allowed interval) |",
    "|---|---|---|---|---|"]
for n in (118,300):
    for factor in (1.,1.05):
        rows=[r for r in data["s1_public_controls"] if r["buses"]==n and r["tags"].get("study")=="public_joint" and r["tags"]["load_factor"]==factor and r["valid"]]
        spread=setting_spreads("s1_public_controls",rows)
        fmt=lambda x:"not estimable" if x is None else f"{100*x:.2f}"
        lines.append(f"| {n} | {factor:g} | {len(rows)}/6 | {min(r['objective'] for r in rows):.9g} / {max(r['objective'] for r in rows):.9g} | {' / '.join(map(fmt,spread))} |")
lines += ["\nSpreads use validated outcomes only; every failed attempt is retained in the matrix and detailed tables. With one valid attempt, spread cannot be estimated. Lower objective values from infeasible or failed solves are not ranked as successful designs. Material objective variation, particularly under increased demand, prevents treating solver outputs as interchangeable research optima.\n",
    "## Recovery and smoothing\n","![Recovery outcomes](recovery_matrix.png)\n",
    "Reducing bound_push and bound_frac from the defaults to 1e-8 preserves the initial feasible point more closely. For nominal Ipopt, initial unscaled constraint violation changes from 0.2103 to 1.96e-7 at 118 buses and from 0.7034 to 3.51e-7 at 300 buses. The 300-bus small-push attempt validates with acceptable-level termination in 388 iterations. These are initialization options; no physical bounds change.\n",
    "Coarse smoothing can solve numerically while failing exact-droop validation. A conservative error budget follows from 0 ≤ softplusε(z)−max(z,0) ≤ ε log(2) and the 1-Lipschitz clipping map. With minimum allowed slope m and Q scale qscale, the smooth/exact response error is bounded by 2 ε log(2) (1/m + qscale). Selecting ε so this bound is at most 1e-6 leaves room within the existing 1e-5 exact-droop tolerance; NLP residuals still require independent validation. The public global ε values are about 7.14e-10 and 7.17e-10. This is conservative and can worsen numerical stiffness; it is not a new default or a convergence guarantee.\n",
    "Continuation uses prior solver-converged, policy-valid states, even if a coarse stage fails exact replay; final stages must pass all physical checks. Unsuccessful intermediate states are retained but not silently accepted. Demand continuation uses steps 1.025 and 1.05 with the installed controller references unchanged. Cross-solver polishing starts from the best validated original-matrix point and is explicitly dependent on that source attempt.\n",
    "### Polishing attempts\n",
    "| Attempt | Source | Status | Iterations | Valid |",
    "|---|---|---|---|---|"]
for r in data["s1_public_polish"]:
    lines.append(f"| {r['name']} | {r['tags']['source_attempt']} | {r.get('status','ERROR')} | {r.get('iterations','–')} | {r['valid']} |")
lines += ["\n## Derivative-scale findings\n","![Droop Jacobian columns](derivative_scales.png)\n",
    "| Network | Point | Droop columns below 1e-12 | Nonzero row-norm range |",
    "|---|---|---|---|"]
for n,label,weak,total,lo,hi in scanrows:lines.append(f"| {n} | {label} | {weak}/{total} | {lo:.3e}–{hi:.3e} |")
lines += ["\nThese are raw nonlinear-constraint Jacobian scales, not a KKT condition number or a proof of singularity. Locally weak droop columns are expected inside deadbands or saturation; the current objective has no direct droop-setting penalty. Parameter variation must therefore be reported alongside objective and feasibility. Adding a penalty would change the research problem and has not been done.\n",
    "## Decision and next work\n",
    "The experimental infrastructure and public fixtures are delivered, but the reliability gate is not passed. Next S1 work should test equivalent normalization of droop design variables and residual scales, preservation of primal/dual warm starts, and an explicit failure-aware restart policy. Keep the current failures as regression targets and evaluate any proposed numerical representation against unchanged equations/objective and exact physical validation. Do not begin M9 on the assumption that public joint optimization is already reliable.\n",
    "No practical performance acceptance budget is declared from these pilot data. Timings include diagnostic callbacks and sometimes compilation; jobs may overlap on the host. Julia allocation is cumulative allocation, and process_lifetime_peak_rss_bytes is a whole-process high-water mark, not per-case memory. An isolated, warmed acceptance run is still required after convergence is reliable.\n",
    "## Complete attempt ledger\n"]
for folder,rows in data.items():
    lines += [f"\n### {folder}\n","| Attempt | Status | Valid | Iterations | Build / solve / extraction / validation seconds |","|---|---|---|---|---|"]
    for r in rows:
        times=" / ".join(f"{r.get(k,0):.4g}" for k in ("build_seconds","solve_seconds","extract_seconds","validate_seconds"))
        lines.append(f"| [{r['name']}](../{folder}/{r['name']}-diagnostics.json) | {r.get('status','ERROR')} | {r['valid']} | {r.get('iterations','–')} | {times} |")
lines += ["\n## Reproduction\n",
    "    julia --project=. examples/s1_robustness.jl artifacts/s1_robustness\n    julia --project=. examples/s1_public_controls.jl artifacts/s1_public_controls\n    julia --project=. examples/s1_public_recovery.jl artifacts/s1_public_recovery\n    julia --project=. examples/s1_public_polish.jl artifacts/s1_public_polish\n    julia --project=. examples/s1_conditioning_scan.jl artifacts/s1_conditioning_public\n    python examples/plot_s1_extension.py\n"]
(out/"report.md").write_text("\n".join(lines))

gallery=Path("docs/src/assets/s1_extension");gallery.mkdir(parents=True,exist_ok=True)
for name in ("control_counts","public_matrix","recovery_matrix","derivative_scales","operating_points"):
    for ext in ("png","pdf"):shutil.copy(out/f"{name}.{ext}",gallery/f"{name}.{ext}")
for folder in folders:shutil.copy(root/folder/"summary.json",gallery/f"{folder}.json")
doc=["# S1 extended robustness and public cases\n",
    "**The S1 reliability gate remains open.** The synthetic matrix passes 35/35 attempts; the initial public matrix passes 13/30. Both imported baselines and at least one joint solution at each tested network/loading condition validate, but solver/start reliability and solution quality are inconsistent.\n",
    "The studies use 37 droops, 11 candidate taps and 12 banks at 118 buses; 35 droops, 129 candidate taps and 32 banks at 300 buses. These controls are explicit synthetic overlays, not measured hardware. Source data and capability limits remain unchanged. Added banks start disconnected. Loads are tested at 1.0 and 1.05 times nominal with controller references held fixed.\n",
    "All attempts retain starts, settings, traces, phase times, allocation and independently checked results. Failed statuses are not hidden. Native solver residual scales differ; physical acceptance tolerances do not.\n"]
for title,name in [("Independent 96-bus control counts","control_counts"),("Initial public solver/start matrix","public_matrix"),("Recovery experiments","recovery_matrix"),("Raw derivative scales","derivative_scales"),("Public operating points","operating_points")]:
    doc += [f"## {title}\n",f"![{title}](assets/s1_extension/{name}.png)\n",f"[PDF figure](assets/s1_extension/{name}.pdf)\n"]
doc += ["## Interpretation and next work\n",
    "Smaller bound pushes preserve feasible starting points better. Coarse smoothing can satisfy the numerical model but fail exact-droop replay; the example runner now computes a conservative smoothing-error budget from allowed slopes and Q capability. Very small smoothing can also increase stiffness. Continuation and cross-solver polishing are mixed remedies, not promoted defaults.\n",
    "Weak local droop-parameter Jacobian columns occur in deadband/saturated regions; this is a sensitivity observation, not a KKT condition number. Validated objectives and settings vary across starts/backends. The full attempt ledger and spread tables are in artifacts/s1_extension/report.md.\n",
    "Next: equivalent parameter/residual normalization, primal/dual warm-start preservation and a declared restart policy, followed by isolated performance acceptance. No equipment equations, hidden objective penalties or validation tolerances have changed. M9 remains downstream of this gate.\n",
    "## Machine-readable summaries\n"]
for folder in folders:doc += [f"- [{folder}](assets/s1_extension/{folder}.json)"]
Path("docs/src/s1_extension.md").write_text("\n".join(doc)+"\n")
