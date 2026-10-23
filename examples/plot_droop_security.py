"""Generate static scientific figures from retained JSON; never infer missing passes."""
import json
import os
from pathlib import Path
import sys
os.environ.setdefault("MPLCONFIGDIR", "/tmp/droop-security-mpl")
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False,
                     "figure.dpi": 150, "savefig.facecolor": "white"})
BLUE, GREEN, RED, GRAY = "#2563eb", "#059669", "#dc2626", "#64748b"

def save(fig, path):
    fig.savefig(path.with_suffix(".png"), bbox_inches="tight")
    fig.savefig(path.with_suffix(".svg"), bbox_inches="tight")
    plt.close(fig)

def reference(root):
    result=json.loads((root/"result.json").read_text())["data"]
    metrics=json.loads((root/"metrics.json").read_text())
    rounds=result["iterations"]
    x=[r["iteration"] for r in rounds]
    fig, ax=plt.subplots(1,3,figsize=(13,3.8),layout="constrained")
    ax[0].plot(x,[r["design"]["result"]["objective"] for r in rounds],"o-",color=BLUE,label="Iterative design")
    ax[0].axhline(metrics["full_objective"],color=GREEN,ls="--",label="Full enumeration")
    ax[0].set(xlabel="Design round",ylabel="Base schedule-deviation objective",title="Matched objective")
    ax[0].legend(fontsize=8)
    ax[1].bar(np.array(x)-.18,[len(r["study"]["contingencies"]) for r in rounds],.36,label="Training",color=BLUE)
    ax[1].bar(np.array(x)+.18,[len(r["assessments"]) for r in rounds],.36,label="AC assessments",color=GREEN)
    ax[1].axhline(metrics["catalog_count"],color=GRAY,ls="--",label="Full catalog")
    ax[1].set(xlabel="Design round",ylabel="Outage count",title="Training and independent audit")
    ax[1].legend(fontsize=8)
    last=rounds[-1]
    names=[a["contingency"]["id"] for a in last["assessments"]]
    values=[]
    for a in last["assessments"]:
        report=a["report"];tol=report["tolerances"]
        ratios=[max(s["power_balance_max"]/tol["power_tolerance"],s["droop_residual_max"]/tol["droop_tolerance"])
                for s in report["scenarios"].values()]
        values.append(max(ratios,default=float("nan")))
    ax[2].scatter(values,range(len(names)),color=[GREEN if a["report"]["valid"] else RED for a in last["assessments"]],s=45)
    ax[2].set_yticks(range(len(names)),names)
    ax[2].set_xscale("log")
    ax[2].set_xlim(max(min(values)*.1,1e-12),2)
    for i,v in enumerate(values): ax[2].annotate(f"{v:.1e}",(v,i),xytext=(5,6),textcoords="offset points",fontsize=8)
    ax[2].axvline(1,color=RED,ls="--",label="Residual tolerance")
    ax[2].set(xlabel="Maximum balance / exact-droop residual ratio",title="Final independent AC audit")
    ax[2].legend(fontsize=8)
    ax[2].margins(y=.18)
    for a in ax[:2]: a.set_xticks(x)
    fig.suptitle("Three-bus shared-droop SCOPF · full N−1 reference",fontsize=14)
    save(fig,root/"progress")

def qualification(root):
    data=json.loads((root/"results.json").read_text())
    rows=data["rows"]
    families=["line","transformer","generator"]
    fig, axes=plt.subplots(1,2,figsize=(11,4.2),layout="constrained")
    for ax,split in zip(axes,["discovery","heldout"]):
        counts=[]
        for family in families:
            fs=[f for r in rows if r["split"]==split and r["valid_base"] for f in r["families"] if f["device_kind"]==family]
            counts.append([sum(f[k] for f in fs) for k in ["total","screened","unresolved","screened_unresolved"]])
        arr=np.array(counts)
        for i,(label,color) in enumerate(zip(["All outages","Screened","Unresolved","Missed unresolved"],[GRAY,BLUE,"#d97706",RED])):
            bars=ax.bar(np.arange(3)+(i-1.5)*.2,arr[:,i],.2,label=label,color=color)
            ax.bar_label(bars,fontsize=8,padding=2)
        ax.set(xticks=np.arange(3),xticklabels=families,ylabel="Outage count",title=split.capitalize())
        ax.set_ylim(0,max(arr[:,0])*1.25)
    axes[0].legend(fontsize=8)
    fig.suptitle("Frozen filtering policy · actual post-outage droop response",fontsize=14)
    save(fig,root/"coverage")
    fig,ax=plt.subplots(figsize=(8,3.8),layout="constrained")
    regimes=["deadband","proportional","saturation_qmax","saturation_qmin"]
    for offset,split,color in [(-.2,"discovery",BLUE),(.2,"heldout",GREEN)]:
        vals=[sum(r.get("accepted_regimes",{}).get(k,0) for r in rows if r["split"]==split and r["valid_base"]) for k in regimes]
        b=ax.bar(np.arange(4)+offset,vals,.4,label=split,color=color);ax.bar_label(b,padding=3)
    ax.set(xticks=np.arange(4),xticklabels=["Deadband","Sloping","Q-max saturation","Q-min saturation"],ylabel="Operating points in accepted outages",title="Control-regime coverage (rejected states excluded)")
    ax.legend();save(fig,root/"regimes")

    fig,axes=plt.subplots(1,2,figsize=(10,4),layout="constrained")
    budgets=np.linspace(0,1,101)
    for ax,split in zip(axes,["discovery","heldout"]):
        for family,color in zip(families,[BLUE,"#9333ea",GREEN]):
            fs=[f for r in rows if r["split"]==split and r["valid_base"] for f in r["families"] if f["device_kind"]==family]
            total=sum(f["unresolved"] for f in fs)
            if total:
                recall=[sum(f["ranking_budgets"][min(int(b*f["total"]),f["total"])]["found"] for f in fs)/total for b in budgets]
                ax.plot(budgets*100,np.array(recall)*100,label=f"{family} (n={total})",color=color)
        ax.plot([0,100],[0,100],ls=":",color=GRAY,label="Budget reference")
        ax.set(xlabel="Per-input evaluation budget (%)",ylabel="Unresolved outcomes found (%)",title=split.capitalize(),xlim=(0,100),ylim=(0,103))
        ax.legend(fontsize=8)
    fig.suptitle("Ranking diagnostic · mandatory routes first, then predicted loading",fontsize=12)
    save(fig,root/"ranking")

def public(root):
    data=json.loads((root/"summary.json").read_text())
    rows=data["families"]
    if data.get("branch_only",False):
        rows=[r for r in rows if r["device_kind"]!="generator"]
    fig,ax=plt.subplots(figsize=(8,4),layout="constrained")
    for i,(key,label,color) in enumerate([("total","All",GRAY),("screened","Screened",BLUE),("unresolved","Unresolved",RED),("screened_unresolved","Missed", "#d97706")]):
        b=ax.bar(np.arange(len(rows))+(i-1.5)*.2,[r[key] for r in rows],.2,label=label,color=color)
        ax.bar_label(b,padding=2,fontsize=9)
    scope="branch-only" if data.get("branch_only",False) else "droop"
    ax.set(xticks=np.arange(len(rows)),xticklabels=[r["device_kind"] for r in rows],ylabel="Outage count",title=f"IEEE-{data['buses']} · fixed-base {scope} filter qualification")
    ax.legend(ncol=4);save(fig,root/"coverage")

def design_progress(root):
    data=json.loads((root/"summary.json").read_text())
    design=json.loads((root/"design"/"result.json").read_text())["data"]
    rounds=design["iterations"]
    x=np.array([r["iteration"] for r in rounds])
    fig,axes=plt.subplots(1,3,figsize=(12,3.8),layout="constrained")
    objectives=[r["design"]["result"]["objective"] for r in rounds]
    axes[0].plot(x,objectives,color=GRAY)
    for valid,color,label in [(True,GREEN,"Valid master"),(False,RED,"Rejected master")]:
        selected=[i for i,r in enumerate(rounds) if (r["policy_valid"] and r["report"]["valid"])==valid]
        axes[0].scatter(x[selected],[objectives[i] for i in selected],color=color,label=label,zorder=3)
    axes[0].set(ylabel="Base schedule-deviation objective",title="Master trajectory (local solves)")
    axes[0].legend(fontsize=8)
    accepted=np.array([sum(a["report"]["valid"] for a in r["assessments"]) for r in rounds])
    rejected=np.array([sum(not a["report"]["valid"] for a in r["assessments"])+len(r["errors"]) for r in rounds])
    axes[1].bar(x-.18,[len(r["study"]["contingencies"]) for r in rounds],.36,color=BLUE,label="Training")
    axes[1].bar(x+.18,accepted,.36,color=GREEN,label="Audit accepted")
    axes[1].bar(x+.18,rejected,.36,bottom=accepted,color=RED,label="Audit unresolved")
    eligible=data["outages"]-data["excluded_islands"]
    axes[1].axhline(eligible,color=GRAY,ls="--",label=f"Eligible branches: {eligible}")
    axes[1].set(ylabel="Outages",title="Training and independent audits")
    axes[1].legend(fontsize=8)
    for key,tolkey,label,color in [("power_balance_max","power_tolerance","AC balance",BLUE),("droop_residual_max","droop_tolerance","Exact droop",GREEN)]:
        vals=[max(1e-14,max(s[key] for s in r["report"]["scenarios"].values())/r["report"]["tolerances"][tolkey]) for r in rounds]
        axes[2].plot(x,vals,"o-",label=label,color=color)
    axes[2].axhline(1,color=RED,ls="--",label="Tolerance")
    axes[2].set(yscale="log",ylabel="Maximum residual / tolerance",title="Independent master replay")
    axes[2].legend(fontsize=8)
    for ax in axes: ax.set(xticks=x,xlabel="Design round")
    fig.suptitle(f"IEEE-{data['buses']} · branch-only shared-droop design · {design['status']}")
    save(fig,root/"design-progress")

if __name__=="__main__":
    mode, path=sys.argv[1:]
    {"reference":reference,"qualification":qualification,"public":public,"design":design_progress}[mode](Path(path))
