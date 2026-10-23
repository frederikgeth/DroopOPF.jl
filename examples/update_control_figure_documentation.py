"""Copy verified figure assets into documentation and update S1/S2 reports."""
from pathlib import Path
import json,re,shutil,hashlib
from control_figure_reporting import attach_s1,attach_s2
ROOT=Path(__file__).resolve().parents[1]
S1=ROOT/'artifacts/s1_14bus_control_plots'
S2=ROOT/'artifacts/s2_scopf/ieee14_native/plots'
validation=json.loads((S1/'validation.json').read_text())
assert validation['selected_attempts']==15 and validation['discrepancies']==0
assets=ROOT/'docs/src/assets'
s1assets=assets/'s1_14bus_control_figures';s2assets=assets/'s2_14bus_figures'
s1assets.mkdir(exist_ok=True);s2assets.mkdir(exist_ok=True)
for p in sorted(S1.glob('*')):
    if p.suffix in ('.png','.svg'):shutil.copyfile(p,s1assets/p.name)
text=(S1/'REPORT.md').read_text().replace('# S1 14-bus all-free-control solver comparison','# S1 14-bus free-control figures',1)
text=re.sub(r'!\[([^]]+)\]\(([^)]+\.png)\)',lambda m:f'![{m[1]}](assets/s1_14bus_control_figures/{m[2]})\n\n[SVG](assets/s1_14bus_control_figures/{Path(m[2]).stem}.svg)',text)
(ROOT/'docs/src/s1_14bus_control_figures.md').write_text(text)
lines=['# S2 14-bus complete figure gallery','','All 18 figures from the [native 14-bus S2 study](s2_14bus.md) are embedded here. Every operating dashboard retains the base case plus all 24 connected eligible contingencies, along with generator/voltage/branch/tap/shunt bounds. Line 11 (7–8) islanding remains excluded. No limit violations beyond tolerance were found.','','The original-curve arm freezes the calibrated S1 8% curves while equipment remains corrective. The designed arm shares one optimized curve per generator across states. Ipopt and MadNLP independently design curves. **CCOpt verifies the Ipopt-designed curves exactly; it does not redesign them**, although its operating/equipment values can differ. The black/gray base reference in individual-control overlays is the original S1 calibration, not an additional N-1 solution.','']
count=0
for solver,label in [('ipopt','Ipopt'),('madnlp','MadNLP'),('ccopt','CCOpt exact verification')]:
    lines += [f'## {label}','']
    for suffix,title in [('frozen_all_states','Original curves: generation, voltages, branch flow, taps and bank'),('designed_all_states','Optimized curves: generation, voltages, branch flow, taps and bank'),('droop_curves','Original versus optimized curves and all operating points')]:
        name=f'{solver}_{suffix}';count+=1
        for ext in ['png','svg']:shutil.copyfile(S2/f'{name}.{ext}',s2assets/f'{name}.{ext}')
        lines += [f'### {title}','',f'![{label}: {title}](assets/s2_14bus_figures/{name}.png)','',f'[SVG](assets/s2_14bus_figures/{name}.svg)','']
lines += ['## Direct solver overlays for each control','','Each droop figure compares the original S1 curve with Ipopt, MadNLP and CCOpt (identical curve settings to Ipopt). The tap/bank figures compare every saved state and include difference-from-Ipopt panels.','']
for p in sorted((S2/'comparisons').glob('*.png')):
    count+=1;target='compare_'+p.name
    shutil.copyfile(p,s2assets/target);shutil.copyfile(p.with_suffix('.svg'),s2assets/('compare_'+p.stem+'.svg'))
    title=p.stem.replace('_solver_comparison','').replace('_',' ')
    lines += [f'### {title}','',f'![{title}](assets/s2_14bus_figures/{target})','',f'[SVG](assets/s2_14bus_figures/compare_{p.stem}.svg)','']
assert count==18
lines += ['Exact plotted values, source hashes, figure-generation scripts and PNG/SVG archives are retained under `artifacts/s2_scopf/ieee14_native/plots/`. No optimization was needed for these figures.','']
(ROOT/'docs/src/s2_14bus_figures.md').write_text('\n'.join(lines))
for relative,doc,figures in [('artifacts/s1_free_droop/REPORT.md',False,True),('docs/src/s1_free_droop_results.md',True,False),('docs/src/s1_summary.md',True,False),('docs/src/s1_closeout.md',True,False),('artifacts/s1_closeout/REPORT.md',False,False)]:attach_s1(ROOT/relative,doc=doc,figures=figures)
attach_s2(ROOT/'docs/src/s2_14bus.md',doc=True);attach_s2(ROOT/'artifacts/s2_scopf/ieee14_native/REPORT.md')
manifest={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in list(s1assets.glob('*'))+list(s2assets.glob('*'))}
(S1/'documentation_assets.json').write_text(json.dumps(dict(s1_figures=12,s2_figures=18,hashes=manifest),indent=2)+'\n')
print('Embedded 12 S1 and all 18 S2 figures in documentation; S1 report includes all 12 figures.')

from control_figure_reporting import attach_s2_current_results
attach_s2_current_results(ROOT/'docs/src/s2_14bus_figures.md',kind='gallery')
attach_s2_current_results(ROOT/'docs/src/s2_14bus.md',kind='doc')
attach_s2_current_results(ROOT/'artifacts/s2_scopf/ieee14_native/REPORT.md',kind='report')
