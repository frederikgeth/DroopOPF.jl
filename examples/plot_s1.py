"""Render S1 evidence. Run from the repository root."""
from pathlib import Path
import json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

root=Path("artifacts")
before=root/"s1_convergence";after=root/"s1_exact_hessian";public=root/"s1_public118"
plt.rcParams.update({"font.size":10,"axes.spines.top":False,"axes.spines.right":False,"figure.dpi":140})
families={"000":"Fixed","001":"Droop","010":"Shunt","011":"Droop + shunt","100":"Tap","101":"Droop + tap","110":"Tap + shunt","111":"All"}
load=lambda p:json.loads(p.read_text())
def save(fig,path):
    fig.savefig(path.with_suffix(".png"),bbox_inches="tight")
    fig.savefig(path.with_suffix(".pdf"),bbox_inches="tight")
    plt.close(fig)

fig,axes=plt.subplots(2,3,figsize=(13,7),layout="constrained")
for row,n in enumerate((4,32)):
    for folder,label,style,color in [(before,"Before: limited-memory","--","#bd453e"),(after,"After: exact Hessian","-","#007a92")]:
        trace=load(folder/f"n{n}-111-diagnostics.json")["trace"]
        for col,(key,title) in enumerate([("unscaled_constraint_violation","NLP constraint violation"),("unscaled_stationarity","Stationarity"),("unscaled_complementarity","Complementarity")]):
            ax=axes[row,col]
            ax.plot([r["iteration"]+1 for r in trace],[max(r[key],1e-16) for r in trace],style,color=color,label=label)
            ax.set(xscale="log",yscale="log",xlabel="Iteration + 1",title=f"{3*n} buses · {title}")
            ax.grid(alpha=.18)
axes[0,0].legend(fontsize=9)
fig.suptitle("Joint droop, transformer and bank optimization · matched starts and equations")
save(fig,after/"convergence")

fig,axes=plt.subplots(1,2,figsize=(12,4.5),layout="constrained")
for ax,n in zip(axes,(4,32)):
    x=np.arange(8)
    old=[load(before/f"n{n}-{k}-diagnostics.json")["iterations"] for k in families]
    new=[load(after/f"n{n}-{k}-diagnostics.json")["iterations"] for k in families]
    ax.bar(x-.19,old,.38,color="#bd453e",label="Before")
    ax.bar(x+.19,new,.38,color="#007a92",label="Exact Hessian")
    ax.set(yscale="log",ylabel="Iterations (log scale)",title=f"{3*n} buses",xticks=x,xticklabels=list(families.values()),ylim=(1,2500))
    ax.tick_params(axis="x",rotation=60)
    for i,v in enumerate(old):
        if v==1000:ax.text(i-.19,1200,"limit",rotation=90,ha="center",fontsize=8,color="#bd453e")
    ax.grid(axis="y",alpha=.15)
axes[0].legend()
save(fig,after/"control_families")

d=load(after/"n32-111-diagnostics.json")
groups=[("tap_",.95,1.05,"Transformer ratio"),("design_",.04,.1,"Droop slope"),("shunt_B_",None,None,"Bank susceptance (pu)")]
fig,axes=plt.subplots(1,3,figsize=(12,3.4),layout="constrained")
for ax,(prefix,lo,hi,title) in zip(axes,groups):
    vals=[r["value"] for r in d["bounds"] if r["name"].startswith(prefix)]
    ax.hist(vals,bins=12,color="#007a92",alpha=.85)
    if lo is not None:
        ax.axvline(lo,color="#bd453e",ls="--");ax.axvline(hi,color="#bd453e",ls="--")
    ax.set(title=title,ylabel="Device count")
fig.suptitle("96-bus joint solution · full per-variable bounds are retained in JSON")
save(fig,after/"settings")

s=load(public/"summary.json")
fig,axes=plt.subplots(3,1,figsize=(11,9),layout="constrained")
axes[0].plot(s["bus_ids"],s["vm"],color="#007a92",lw=1,label="Solved voltage")
axes[0].plot(s["bus_ids"],s["vmin"],"--",color="#bd453e",label="Source limits")
axes[0].plot(s["bus_ids"],s["vmax"],"--",color="#bd453e")
axes[0].set(xlabel="Bus ID",ylabel="Voltage (pu)");axes[0].legend()
axes[1].plot(100*np.array(s["loading_from"]),label="From terminal",color="#007a92")
axes[1].plot(100*np.array(s["loading_to"]),label="To terminal",color="#dd9b3f",alpha=.8)
axes[1].axhline(100,color="#bd453e",ls="--");axes[1].set(xlabel="Branch row (zero-based)",ylabel="Rating used (%)");axes[1].legend()
axes[2].plot(s["angle_degrees"],color="#007a92",label="Solved angle difference")
axes[2].plot(s["angle_min_degrees"],"--",color="#bd453e",label="Source bounds (audited)")
axes[2].plot(s["angle_max_degrees"],"--",color="#bd453e")
axes[2].set(xlabel="Branch row (zero-based)",ylabel="Angle difference (degrees)");axes[2].legend()
fig.suptitle("PGLib v23.07 IEEE 118 · fixed equipment · project dispatch objective")
save(fig,public/"validation")

lines=["# S1 convergence diagnosis and numerical correction\n",
    "All eight fixed/free control combinations now converge locally and independently validate at 12 and 96 buses after restoring exact Hessian information. This resolves the reproduced stall on this declared matrix; the full S1 gate remains open.\n",
    "## Matched experiment\n",
    "Connected heterogeneous synthetic modules have two droops, one selected transformer and two simple banks per three buses. Each run starts from the same validated fixed-equipment solution for its network size, with supplied design settings. Slope bounds are [0.04, 0.10], ratio bounds [0.95, 1.05], and bank B stays within the legal-count envelope. Reference/deadband settings, dispatch objective, smoothing (1e-6), equipment limits and physical tolerances are unchanged.\n",
    "Ipopt uses adaptive barrier updates, no bound relaxation, tolerance 1e-8, 1000 iterations and 60 CPU seconds. All original failures remain here; [corrected results](../s1_exact_hessian/summary.json) are separate. The extra scaling experiment multiplies the whole objective by 1000.\n",
    "| Network | Free families | Before iterations/status | After iterations/status | Before physics/policy | After physics/policy |",
    "|---|---|---|---|---|---|"]
for n in (4,32):
    for key,label in families.items():
        a=load(before/f"n{n}-{key}-diagnostics.json");b=load(after/f"n{n}-{key}-diagnostics.json")
        lines.append(f"| {3*n} | {label} | {a['iterations']} / {a['status']} | {b['iterations']} / {b['status']} | {a['physical_valid']}/{a['policy_valid']} | {b['physical_valid']}/{b['policy_valid']} |")
lines+=["\n## Diagnosis\n",
    "The failing pair was optimized tap plus droop slope; free banks were not necessary for failure. Both original joint iterates passed independent AC, exact-droop, limit and policy checks, but stationarity/complementarity remained too large. The original 96-bus droop-only run reached acceptable-level stopping (ALMOST_LOCALLY_SOLVED), distinguished here from full convergence.\n",
    "The five-argument registered droop function removed Hessian availability from the legacy evaluator. Ipopt therefore selected limited-memory approximation. The fixed-droop model retained Hessians. The [first-order check](../s1_conditioning/first-order-before.log) found no errors at its tested points; this is not an exhaustive derivative proof.\n",
    "The corrected builder expresses the identical smoothed curve as two scalar softplus operators and ordinary arithmetic, allowing exact second derivatives. Equipment equations, smoothing, objective, ratings and bounds are unchanged. Regression tests compare values and finite-difference derivatives around deadband edges and saturation knees. See [JuMP derivative registration](https://jump.dev/JuMP.jl/stable/manual/nlp/).\n",
    "| Buses | Encoding | Iterations | NLP constraint violation | Stationarity | Complementarity | Original objective |",
    "|---|---|---|---|---|---|---|"]
for n in (4,32):
    for folder,label in [(before,"Before"),(after,"Exact Hessian")]:
        d=load(folder/f"n{n}-111-diagnostics.json");t=d["trace"][-1]
        lines.append(f"| {3*n} | {label} | {d['iterations']} | {t['unscaled_constraint_violation']:.3e} | {t['unscaled_stationarity']:.3e} | {t['unscaled_complementarity']:.3e} | {d['objective']:.10g} |")
lines+=["\n![Residual histories](../s1_exact_hessian/convergence.png)\n",
    "![Control-family comparison](../s1_exact_hessian/control_families.png)\n",
    "![Joint settings](../s1_exact_hessian/settings.png)\n",
    "Traces retain native unscaled residuals and scaled callback measures, barrier parameter, step lengths, line-search trials, regularization and restoration flags. Bound snapshots include each variable's value and limits. Proximity within 1e-6 is a diagnostic flag, not a multiplier-based active-set certificate. New runs also record model size and derivative availability.\n",
    "Whole-objective scaling did not rescue the original joint runs; its 12-bus result also failed physics validation. Both scaled runs pass after the derivative correction. Scaling is not promoted as the fix. Residuals must be interpreted with their saved scaling options; reported objectives retain original units.\n",
    "## Reproduction and limits\n",
    "Before data use the M7 droop encoding (commit 069bd80) plus the S1 measurement hook. Current code reproduces the corrected encoding. From the repository root:\n",
    "    julia --project=. examples/s1_convergence.jl artifacts/s1_exact_hessian\n    julia --project=. examples/s1_derivatives.jl artifacts/s1_conditioning_after\n    julia --project=. examples/s1_public_baseline.jl artifacts/s1_public118\n    python examples/plot_s1.py\n",
    "Elapsed time includes construction, solve and extraction and may include compilation. Julia allocated bytes are cumulative allocation, not peak memory. These results establish neither a scaling law nor a performance budget. Earlier phase/resource measurements in scaling_robustness remain historical evidence.\n",
    "S1 remains open for independently varied free-device counts, broader conditioning/start/solver comparisons, public controller overlays, 300-bus validation and performance acceptance. The [118-bus fixed-equipment baseline](../s1_public118/report.md) is ready. M9 stays downstream of S1.\n"]
(before/"report.md").write_text("\n".join(lines))
diag=load(public/"pglib118-fixed-diagnostics.json")
text=f"""# Public IEEE 118-bus fixed-equipment baseline

The unmodified [PGLib v23.07 IEEE 118 source]({s['source']}) imports as **118 buses, 54 generators, 186 branches and 14 fixed shunts**. Its preserved header contains attribution and CC BY 4.0 licensing. [Provenance](../../test/data/pglib/v23.07/provenance118.json) records SHA-256 {s['source_sha256']}.

The solve terminates **{s['status']}** and passes independent AC and operating-limit validation. No droops, adjustable banks or optimized ratios have been added. This is a public fixed-equipment baseline, not a public joint-design scalability result.

| Check | Result |
|---|---|
| Maximum AC balance residual | {s['physical']['power_balance_max']:.3e} pu |
| Minimum voltage lower/upper margin | {s['physical']['voltage_min_margin']:.3e} / {s['physical']['voltage_max_margin']:.3e} pu |
| Minimum both-terminal branch margin | {s['physical']['branch_thermal_min_margin']:.3e} pu |
| Post-solve source angle violation | {s['source_angle_violation_degrees']:.3e} degrees |
| Iterations | {diag['iterations']} |
| Objective | {s['objective']:.10g} |

The initial import retained only one generator: splitting on semicolons before removing line comments let an inline comment consume the next row. The parser now strips comments line by line before splitting records. Regression tests cover consecutive inline comments, comment-only lines, malformed row widths and the public component counts. The source file is unchanged.

The adapter omits costs and branch angle-difference constraints. This solve uses the project dispatch-deviation objective, not the published PGLib cost optimum. Source angle bounds are audited on the returned state and pass; they were not optimization constraints. Existing import logic clamps supplied dispatch to generator capability bounds and uses it as the objective reference. Source VM/VA are not fixed replay inputs: the numerical start is flat and the state is optimized.

![Voltage, terminal loading and source angle checks](validation.png)

[Diagnostics](pglib118-fixed-diagnostics.json), [result](pglib118-fixed-design.json), [study](study.json) and [plot data](summary.json) are retained. Reproduce using examples/s1_public_baseline.jl with output directory artifacts/s1_public118.
"""
(public/"report.md").write_text(text)

# Keep the rendered documentation gallery reproducible from the same evidence.
import shutil
gallery=Path("docs/src/assets/s1")
gallery.mkdir(parents=True,exist_ok=True)
for source in [after/"convergence",after/"control_families",after/"settings",public/"validation"]:
    for suffix in (".png",".pdf"):
        shutil.copy(source.with_suffix(suffix),gallery/source.with_suffix(suffix).name)
shutil.copy(after/"summary.json",gallery/"synthetic-summary.json")
shutil.copy(public/"summary.json",gallery/"public118-summary.json")
doc=["# S1 convergence evidence\n",
     'This is the first S1 checkpoint. See [extended public-case evidence](s1_extension.md) for the current reliability gate.\n\n',
     "The [implemented formulation](joint_formulation.md) retains the M7 equipment laws, smoothing and dispatch objective. The variable-droop encoding now preserves exact Hessians. All eight control combinations converge locally and independently validate at 12 and 96 buses; both full joint runs take 16 iterations instead of reaching the 1000-iteration limit.\n",
     "Full regression: **966/966 tests pass**. First/second derivative checks report no errors at their tested points. Unit checks cover smooth-curve values and derivatives at deadband edges and saturation knees. Failed pre-correction attempts and complete diagnostic records remain in artifacts/s1_convergence.\n",
     "| Buses | Free slopes / taps / banks in joint run | Before | After |",
     "|---|---|---|---|",
     "| 12 | 8 / 4 / 8 | 1000 iterations, iteration limit | 16 iterations, valid |",
     "| 96 | 64 / 32 / 64 | 1000 iterations, iteration limit | 16 iterations, valid |\n",
     "The former five-argument legacy operator removed Hessian availability. Equivalent scalar softplus composition supplies exact second derivatives without changing the response. Before/after runs use matched feasible fixed-control starts, smoothing 1e-6, adaptive Ipopt, no bound relaxation, tolerance 1e-8 and the same iteration budget. Broader robustness remains to be tested.\n"]
for title,name in [("Convergence","convergence"),("Control families","control_families"),("Joint settings","settings")]:
    doc += [f"![{title}](assets/s1/{name}.png)\n",f"[Download {title.lower()} PDF](assets/s1/{name}.pdf)\n"]
doc += ["[Synthetic summary data](assets/s1/synthetic-summary.json)\n",
        "## Public 118-bus baseline\n",
        "PGLib v23.07 IEEE 118 imports as 118 buses, 54 generators, 186 branches and 14 fixed shunts after correcting inline-comment parsing. The fixed-equipment solve converges locally and validates, with maximum AC-balance residual 1.28e-9 pu. Source branch angle bounds pass a separate post-solve audit.\n",
        "No droop or adjustable-bank overlays are included yet. The adapter omits economic costs and branch angle constraints; the objective is the project's dispatch deviation. This is not a reproduction of the published PGLib cost optimum or an operating-point replay with fixed P/Q/V.\n",
        "![118-bus validation](assets/s1/validation.png)\n",
        "[Download public-case figure PDF](assets/s1/validation.pdf) · [Public-case data](assets/s1/public118-summary.json)\n",
        "## Remaining S1 work\n",
        "Independent control-count sweeps, broader conditioning and state/design-start studies, medium-case Ipopt/MadNLP comparisons, explicit public controller overlays, 300-bus validation and performance acceptance remain. S1 is active and M9 stays downstream.\n",
        "## Reproduction\n",
        "    julia --project=. examples/s1_convergence.jl artifacts/s1_exact_hessian\n    julia --project=. examples/s1_derivatives.jl artifacts/s1_conditioning_after\n    julia --project=. examples/s1_public_baseline.jl artifacts/s1_public118\n    python examples/plot_s1.py\n",
        "Timing may include compilation and does not establish a scaling law. Native unscaled solver residuals must still be read with the recorded whole-objective scaling. Physical validation tolerances remain unchanged.\n"]
Path("docs/src/s1_evidence.md").write_text("\n".join(doc))
