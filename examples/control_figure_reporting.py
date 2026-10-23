"""Idempotent links/figures for S1/S2 report regeneration."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
def attach_s2_current_results(path, *, kind='doc'):
    """Lead with accepted recovered designs while retaining historical reports."""
    import re
    directory=ROOT/'artifacts/s2_scopf/ieee14_native/current_results'
    fronts={'doc':'report_front_doc.md','report':'report_front_artifact.md','gallery':'gallery_front.md'}
    source=directory/fronts[kind]
    if not source.exists():return
    path=Path(path);text=path.read_text();start='<!-- S2_CURRENT_RESULTS -->';end='<!-- /S2_CURRENT_RESULTS -->'
    block=start+'\n'+source.read_text().rstrip()+'\n'+end
    if start in text:
        a=text.index(start);b=text.index(end,a)+len(end);text=text[:a]+block+text[b:]
    else:
        history=re.sub(r'^(#{1,5}) ',lambda m:'#'+m[1]+' ',text,flags=re.M)
        history=re.sub(r'^## [^\n]+','## Historical nominal-demand figures' if kind=='gallery' else '## Historical nominal-demand campaign',history,count=1)
        text=block+'\n\n'+history
    path.write_text(text.rstrip()+'\n')
    status_path=ROOT/'artifacts/s2_scopf/ieee14_native/STATUS.json'
    if kind=='report' and status_path.exists():
        status=json.loads(status_path.read_text());status['current_results']=json.loads((directory/'CURRENT_RESULTS.json').read_text())
        review=ROOT/'artifacts/s2_scopf/ieee14_native/14bus_review/STATUS.json'
        if review.exists():status['declared_14bus_review']=json.loads(review.read_text())
        status_path.write_text(json.dumps(status,indent=2)+'\n')

def attach(path,tag,body):
    path=Path(path);start=f'<!-- {tag} -->';end=f'<!-- /{tag} -->'
    text=path.read_text()
    if start in text:
        a=text.index(start);b=text.index(end,a)+len(end);text=text[:a]+text[b:]
    path.write_text(text.rstrip()+f'\n\n{start}\n'+body.rstrip()+f'\n{end}\n')

def attach_s2_multidemand(path, *, doc=False):
    """Keep the latest shared-demand result attached when historical reports regenerate."""
    directory=ROOT/'artifacts/s2_scopf/ieee14_native/multidemand'
    if not (directory/'STATUS.json').exists():return
    status=json.loads((directory/'STATUS.json').read_text())
    link='s2_14bus_multidemand.md' if doc else 'multidemand/REPORT.md'
    count=status.get('accepted_evaluation_lanes',0);total=status.get('evaluation_lanes',0)
    result=f'{count}/{total} frozen solver–demand combinations accepted' if total else 'No accepted shared design under the declared budgets'
    attach(path,'S2_MULTIDEMAND',f'''## Shared multi-demand design follow-up

**{result}.** The new campaign shares one controller across five training demands and 24 connected outages, followed by four held-out demand checks. Corrective taps and the continuous bank retain their confirmed bounds. See the [multi-demand report]({link}). Historical scores and S1 closure remain unchanged.''')

def attach_s2_solver_designs(path, *, doc=False, link=None):
    directory=ROOT/'artifacts/s2_scopf/ieee14_native/multidemand/solver_design_comparison'
    if not (directory/'STATUS.json').exists():return
    status=json.loads((directory/'STATUS.json').read_text())
    backends=['ipopt']+status['accepted_design_backends']
    link=link or ('s2_14bus_solver_designs.md' if doc else 'multidemand/solver_design_comparison/REPORT.md')
    attach(path,'S2_SOLVER_DESIGNS',f'''## Independent MadNLP and CCOpt shared-design follow-up

Accepted free multi-demand designs: **{', '.join(backends)}**. The new attempts optimize their own shared slopes/references from the accepted Ipopt full witness; they are not fixed-curve verification runs. See the [solver design comparison]({link}) for parameter/curve differences and held-out results. Original campaign scores, failed attempts and S1 closure remain unchanged.''')

def attach_s2_ccopt_recovery(path, *, doc=False, link=None):
    directory=ROOT/'artifacts/s2_scopf/ieee14_native/multidemand/solver_design_comparison/ccopt_recovery'
    if not (directory/'STATUS.json').exists():return
    status=json.loads((directory/'STATUS.json').read_text())
    outcome='CCOpt recovered an accepted free multi-demand design.' if status['selected'] else 'CCOpt remains unqualified after the declared recovery attempts.'
    link=link or ('s2_14bus_ccopt_recovery.md' if doc else 'multidemand/solver_design_comparison/ccopt_recovery/REPORT.md')
    attach(path,'S2_CCOPT_RECOVERY',f'''## Targeted CCOpt convergence recovery

**{outcome}** The recovery uses the accepted MadNLP full primal witness and retains the physical contract and stopping tolerances. See the [CCOpt recovery report]({link}) for endpoint diagnostics, curves and held-out outcomes. Historical attempts and S1 closure remain unchanged.''')
    attach_s2_review(path,doc=doc)

def attach_s2_review(path, *, doc=False):
    from os.path import relpath
    directory=ROOT/'artifacts/s2_scopf/ieee14_native/14bus_review'
    if not (directory/'STATUS.json').exists():return
    status=json.loads((directory/'STATUS.json').read_text())
    closed=status['status']=='closed_declared_14bus_scope'
    decision='The declared sampled 14-bus scope is closed.' if closed else 'The 14-bus review retains an open CCOpt convergence item.'
    link='s2_14bus_review.md' if doc else relpath(directory/'REPORT.md',Path(path).parent)
    attach(path,'S2_14BUS_REVIEW',f'''## 14-bus S2 review decision

{decision} See the [14-bus review]({link}). Broader S2 remains open; S1 remains closed.''')

def attach_s1(path,*,doc=False,figures=False):
    directory=ROOT/'artifacts/s1_14bus_control_plots'
    if not (directory/'validation.json').exists():return
    link='s1_14bus_control_figures.md' if doc else '../s1_14bus_control_plots/REPORT.md'
    text=f'''## S1 14-bus free-control solution figures

The focused visual follow-up uses 15 saved, matched joint-anchor designs:
90/95/100/105/110% demand and Ipopt/MadNLP/CCOpt, with slopes, references,
all three taps and bank 3 free. All 15 points pass independent replay with zero
discrepancies; no new optimization was run. CCOpt freely designed the curves
in S1, unlike the fixed-curve S2 verification. Demand points are independent
redesigns, not a single frozen-controller qualification. Historical scores and
the closed S1 numerical scope are unchanged.

[All 12 operating/control comparison figures]({link}).
'''
    if figures and not doc:
        text+='\n'
        for p in sorted(directory.glob('*.png')):
            text+=f'\n![{p.stem}](../s1_14bus_control_plots/{p.name})\n'
    attach(path,'S1_CONTROL_FIGURES',text)

def attach_s2(path,*,doc=False):
    if not (ROOT/'docs/src/s2_14bus_figures.md').exists():return
    link='s2_14bus_figures.md' if doc else 'plots/README.md'
    current=ROOT/'artifacts/s2_scopf/ieee14_native/current_results/CURRENT_RESULTS.json'
    if current.exists():
        attach(path,'S2_CONTROL_FIGURES',f'''## Complete S2 figure gallery

The [complete gallery]({link}) leads with 14 current accepted-design figures for Ipopt, MadNLP and the recovered free CCOpt design, followed by the 18 historical nominal-campaign figures. Current operating plots retain all nine demands and 25 connected states per demand; the historical CCOpt verification keeps its original fixed-curve meaning. Conditional line 7–8/G5-trip coverage and all scope qualifications are documented in the current report.''')
        return
    attach(path,'S2_CONTROL_FIGURES',f'''## Historical nominal S2 figure gallery

[All 18 operating-state and controller-comparison figures]({link}) are now
included in the S2 documentation. They cover original/optimized-curve operating
states for each solver, original-versus-optimized curves, and individual
five-generator, three-tap and one-bank overlays. Equipment plots retain all 25
states and bounds. CCOpt uses Ipopt-designed curves exactly; it independently
reoptimizes the scenario states and corrective equipment. The 7–8 islanding
outage remains excluded; these plots do not extend security coverage.
''')
