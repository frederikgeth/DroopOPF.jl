"""Report saved solver/demand qualification; no optimization."""
from pathlib import Path
import csv
import hashlib
import json
import math
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from audit_s2_500bus_solver_demand import campaign
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'solver_demand_qualification'
FIG=ROOT/'docs/src/assets/s2_500bus/solver_demand_qualification'
load=lambda p:json.loads(Path(p).read_text())
data=lambda p:load(p)['data']

def operating_fig(summary,case,label):
    """Original-network envelopes across base and every connected outage."""
    import copy
    from s2_followup_physics import check_case
    directory=BASE/summary['selected'];factor=summary['factor']
    base=data(directory/f'result-{float(factor)}.json')
    scan=load(directory.parent/f'demand-{float(factor)}'/'scan.json')
    witness_solver={row['event']:row['final']['solver'] for row in scan['attempts']}
    witness_solver['base']=summary['solver']
    recourse=', '.join(sorted(set(witness_solver[sid] for sid in witness_solver if sid!='base')))
    states=[('base',base['states']['base'],base['tap_settings']['base'],base['shunt_settings']['base'],case)]
    for row in scan['attempts']:
        p=BASE/row['final']['name'];st=data(p/'input.json');res=data(p/'result.json');sid=row['event']
        c=copy.deepcopy(st['case']);event=st['contingencies'][0]
        for b in c['network']['branches']:
            if b['id'] in event['branch_ids']:b['available']=False
        for g in c['generators']:
            if g['id'] in event['generator_ids']:g['available']=False
        states.append((sid,res['states'][sid],res['tap_settings'][sid],res['shunt_settings'][sid],c))
    assert len(states)==390
    angles=load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    branches=[b for b in case['network']['branches'] if b['available']]
    flow=[]
    for sid,st,taps,banks,c in states:
        ck=check_case(c,st,taps,banks,angles);assert ck['valid']
        flow.append([ck['branch_max_terminal_s_pu'].get(str(b['id']),np.nan)/b['thermal_limit'] for b in branches])
    pg=np.array([st['pg'] for _,st,*_ in states])*case['base_power'];qg=np.array([st['qg'] for _,st,*_ in states])*case['base_power']
    vm=np.array([st['vm'] for _,st,*_ in states]);flow=np.array(flow)
    fig,axs=plt.subplots(2,2,figsize=(14,8),layout='constrained')
    gids=[g['id'] for g in case['generators']]
    for ax,values,lo,hi,ylabel in [(axs[0,0],pg,'p_min','p_max','Active generation (MW)'),(axs[0,1],qg,'q_min','q_max','Reactive generation (MVAr)')]:
        ax.fill_between(gids,values.min(0),values.max(0),alpha=.25,label='Base + 389-outage envelope')
        ax.plot(gids,values[0],lw=1,label='Base')
        for key in (lo,hi):ax.plot(gids,[g[key]*case['base_power'] if g['available'] else 0 for g in case['generators']],':',color='black',lw=.8,label='Equipment bounds' if key==hi else None)
        ax.set(xlabel='Original generator ID',ylabel=ylabel);ax.legend(fontsize=7)
    bids=[b['id'] for b in case['network']['buses']]
    axs[1,0].fill_between(bids,vm.min(0),vm.max(0),alpha=.25,label='Base + outage envelope');axs[1,0].plot(bids,vm[0],lw=.8,label='Base')
    for key in ('v_min','v_max'):axs[1,0].plot(bids,[b[key] for b in case['network']['buses']],':',color='black',label='Normal bounds' if key=='v_max' else None)
    axs[1,0].set(xlabel='Original bus ID',ylabel='Voltage (pu)');axs[1,0].legend(fontsize=7)
    ids=[b['id'] for b in branches]
    axs[1,1].fill_between(ids,np.nanmin(flow,0),np.nanmax(flow,0),alpha=.25,label='Online-device outage envelope');axs[1,1].plot(ids,flow[0],lw=.8,label='Base')
    axs[1,1].axhline(1,color='black',ls=':',label='Rate A');axs[1,1].set(xlabel='Original branch/transformer ID',ylabel='Largest terminal S / Rate A');axs[1,1].legend(fontsize=7)
    for ax in axs.flat:ax.grid(alpha=.2)
    fig.suptitle(label+' design · '+recourse+' outage witnesses · original 500-bus validation · 390 states')
    name=label.lower().replace(' ','-').replace('%','')+'-operating'
    for ext in ('png','pdf'):fig.savefig(FIG/f'{name}.{ext}',dpi=150)
    plt.close(fig)
    controls=data(directory/f'optimized-{float(factor)}.json')
    fig,axs=plt.subplots(2,1,figsize=(14,7),layout='constrained')
    equipment_rows=[]
    for ax,kind,key,idkey in [(axs[0],'tap','tap_controls','branch_id'),(axs[1],'shunt','shunt_controls','bank_id')]:
        cs=controls[key];ids=[c[idkey] for c in cs]
        values=np.array([[taps.get(str(i),np.nan) if kind=='tap' else banks.get(str(i),np.nan) for i in ids] for _,_,taps,banks,_ in states])
        ax.fill_between(ids,np.nanmin(values,0),np.nanmax(values,0),alpha=.3,label='Available-control outage envelope');ax.plot(ids,values[0],'.-',ms=3,lw=.7,label='Base')
        for k in ('lower','upper'):ax.plot(ids,[c[k] for c in cs],':',color='black',label='Confirmed bounds' if k=='upper' else None)
        ax.set(xlabel=f'Original {kind} ID',ylabel='Tap ratio' if kind=='tap' else 'Susceptance (pu)');ax.legend(fontsize=7);ax.grid(alpha=.2)
        for row,(sid,*_) in zip(values,states):
            for c,value in zip(cs,row):equipment_rows.append(dict(design_solver=summary['solver'],factor=factor,witness_solver=witness_solver[sid],outage=sid,kind=kind,id=c[idkey],value=None if not np.isfinite(value) else value,available=bool(np.isfinite(value)),lower=c['lower'],upper=c['upper']))
    fig.suptitle(label+' design · '+recourse+' corrective outage witnesses · 390 states')
    eqname=name.replace('-operating','-equipment')
    for ext in ('png','pdf'):fig.savefig(FIG/f'{eqname}.{ext}',dpi=150)
    plt.close(fig)
    with (OUT/(name.replace('-operating','')+'-equipment.csv')).open('w') as f:
        w=csv.DictWriter(f,fieldnames=list(equipment_rows[0]));w.writeheader();w.writerows(equipment_rows)
    return [name,eqname]

def main():
    FIG.mkdir(parents=True,exist_ok=True)
    summaries=sorted(OUT.glob('summary-*.json'))
    cases=[];designs={}
    nominal=load(BASE/'qualification/summary-expanded-madnlp-reserve.json')
    designs['MadNLP qualified nominal']=data(BASE/nominal['selected']/'optimized-1.0.json')['case']
    for p in summaries:
        s=load(p)
        if s.get('alias_of'):continue
        a=campaign(p)
        attempts=[r for rd in s['rounds'] for r in rd['attempts']]
        row=dict(solver=s['solver'],factor=s['factor'],accepted=a['accepted'],selected=s['selected'],campaign=p.stem.removeprefix('summary-'),
                 intermediate=s.get('intermediate',False),native_attempts=sum(a['record'].get('native_optimizer_calls',1) for a in attempts),rounds=len(s['rounds']),attempts=attempts,
                 latest_scan=next((rd['scan'] for rd in reversed(s['rounds']) if rd['scan'] is not None),None))
        cases.append(row)
        if a['accepted']:
            key=f"{s['solver']} {s['factor']*100:g}%"
            designs.setdefault(key,data(BASE/s['selected']/f"optimized-{float(s['factor'])}.json")['case'])
    curves=[]
    for label,case in designs.items():
        for attach in case['attachments']:
            cid=attach['control_id'];d=case['controls'][cid-1]
            curves.append(dict(design=label,generator_id=attach['generator_id'],control_id=cid,slope=d['slope'],
                v_ref=d['schedule']['v_ref'],q_min=d['capability']['q_min'],q_max=d['capability']['q_max'],
                full_q_span_voltage_percent=100*d['slope']*(d['capability']['q_max']-d['capability']['q_min'])))
    if curves:
        with (OUT/'accepted-droop-designs.csv').open('w') as f:
            w=csv.DictWriter(f,fieldnames=list(curves[0]));w.writeheader();w.writerows(curves)
    master_curves=[]
    for c in cases:
        for a in c['attempts']:
            folder=BASE/a['record']['name']
            if not a['accepted'] or not load(folder/'independent-audit.json')['accepted']:continue
            study=data(folder/f"optimized-{float(c['factor'])}.json");case=study['case']
            for attach in case['attachments']:
                cid=attach['control_id'];d=case['controls'][cid-1]
                master_curves.append(dict(solver=c['solver'],factor=c['factor'],master=a['record']['name'],generator=attach['generator_id'],
                    control=cid,slope=d['slope'],v_ref=d['schedule']['v_ref'],q_min=d['capability']['q_min'],q_max=d['capability']['q_max'],
                    included_outages=len(study['contingencies']),exhaustively_qualified=c['accepted'] and c['selected']==a['record']['name'],
                    native_status=a['record']['solver_status'],base_loss_mw=a['record']['nominal_loss_mw']))
    if master_curves:
        with (OUT/'validated-master-droop-designs.csv').open('w') as f:
            w=csv.DictWriter(f,fieldnames=list(master_curves[0]));w.writeheader();w.writerows(master_curves)
    reference=next(iter(designs.values()))
    plot_designs={'Calibrated input':data(ROOT/'artifacts/s1_arpae500/calibrated-study.json')['case'],**designs}
    figures=[]
    plotted=set()
    for summary in cases:
        identity=(summary['solver'],summary['factor'])
        if summary['accepted'] and identity not in plotted:
            plotted.add(identity)
            case=data(BASE/summary['selected']/f"optimized-{float(summary['factor'])}.json")['case']
            figures.extend(operating_fig(summary,case,f"{summary['solver']} {summary['factor']*100:g}%"))
    for page in range(4):
        attachments=reference['attachments'][page*15:(page+1)*15]
        fig,axs=plt.subplots(math.ceil(len(attachments)/3),3,figsize=(13,math.ceil(len(attachments)/3)*2.5),layout='constrained',squeeze=False)
        for ax,attachment in zip(axs.flat,attachments):
            cid=attachment['control_id'];qs=[]
            refs=[c['controls'][cid-1]['schedule']['v_ref'] for c in plot_designs.values()]
            v=np.linspace(min(refs)-.055,max(refs)+.055,250)
            for label,case in plot_designs.items():
                d=case['controls'][cid-1];q=np.clip((d['schedule']['v_ref']-v)/d['slope'],d['capability']['q_min'],d['capability']['q_max'])*case['base_power']
                options=dict(color='0.5',ls='--') if label=='Calibrated input' else {}
                ax.plot(v,q,label=label,lw=1.1,**options)
            ax.set(title=f"G{attachment['generator_id']} · control {cid}",xlabel='Voltage (pu)',ylabel='Q (MVAr)');ax.grid(alpha=.2)
        for ax in list(axs.flat)[len(attachments):]:ax.set_visible(False)
        handles,labels=axs.flat[0].get_legend_handles_labels()
        fig.legend(handles,labels,loc='outside upper center',ncol=min(4,len(plot_designs)),fontsize=8)
        name=f'accepted-droop-curves-{page+1}'
        for ext in ('png','pdf'):fig.savefig(FIG/f'{name}.{ext}',dpi=150)
        plt.close(fig);figures.append(name)
    certificate=load(OUT/'normal-110-certificate.json') if (OUT/'normal-110-certificate.json').exists() else None
    model_count=sum(len(c['attempts']) for c in cases);call_count=sum(c['native_attempts'] for c in cases)
    qp_count=sum(load(p).get('initialization',{}).get('initialization_optimizer_calls',0) for p in OUT.glob('protocol-*.json'))
    separator_names={row[k]['name'] for p in OUT.rglob('scan.json') for row in load(p)['attempts'] for k in ('primary','final')}
    count_text=f"Recorded work: **{model_count} master models, {call_count} native SCOPF optimizer calls, {qp_count} numerical initialization QPs and {len(separator_names)} separator evaluation attempts**. One initial model-construction failure made no optimizer call."
    matrix=[];matrix_lines=['| Demand | Ipopt | MadNLP | CCOpt |','|---:|---|---|---|']
    for factor in (.9,.95,1.,1.05,1.1):
        cells=[];entry=dict(factor=factor,solvers={})
        for solver in ('ipopt','madnlp','ccopt'):
            group=[c for c in cases if c['factor']==factor and c['solver']==solver]
            qualified=any(c['accepted'] for c in group) or (solver=='madnlp' and factor==1 and nominal['accepted'])
            scans=[c['latest_scan'] for c in group if c['latest_scan'] is not None]
            if factor==1.1 and certificate:label='Certified infeasible';classification='certified_infeasible_original_policy'
            elif qualified:label='Qualified: 389/389';classification='qualified_connected_outages'
            elif scans:
                best=max(scans,key=lambda s:(s['exhaustive'],s['evaluated']-len(s['failed'])))
                label=f"{best['evaluated']-len(best['failed'])}/389; unresolved" if best['exhaustive'] else f"{best['evaluated']} checked; rest unchecked"
                classification='partial_connected_coverage'
            else:label='Unresolved';classification='numerically_unresolved'
            entry['solvers'][solver]=dict(classification=classification,qualified=qualified)
            cells.append(label)
        matrix.append(entry);matrix_lines.append(f"| {100*factor:g}% | "+' | '.join(cells)+' |')
    lines=['# 500-bus solver and individual-demand qualification','',
        'Joint design masters share 51 free slopes and 51 free references across the base and included outages. Contingency addition checks all 389 connected outages against a common preventive base and controller. Original-network physical replay and native convergence are both required. Islanding outages remain separate. Accepted objectives are local solutions, with no global-optimality claim.','',
        'This campaign uses original normal voltage and Rate-A limits at every demand, with no DR or shedding. Emergency/relief results remain a separate policy. Transformer taps and continuous shunts remain corrective within the user-confirmed bounds. Each demand has an independently designed controller; this is not a shared multi-demand solution.','',
        'Solver labels identify the native joint-design backend. New exhaustive outage witnesses use Ipopt with that design controller and preventive base fixed; their corrective settings need not reproduce the design backend\'s own master recourse values. Equipment CSVs identify both design and witness solvers. The historical nominal MadNLP witnesses retain their original backend.','',
        'Recovery combines exact reduction, droop-only scaling, feasibility-first models, exact-Hessian restarts and demand/backend-matched S1 starts. The reserve-start QP supplies an initial dispatch only; its heuristic 50 MW loss buffer is not imposed on the AC master. Smaller masters start with G14/G60 and add unresolved outages while keeping curves shared. All original terminal ratings and full-network acceptance gates are retained.','',
        count_text,'',
        *matrix_lines,'','## Bounded campaigns','',
        '| Solver | Demand | Native SCOPF calls | Exhaustive qualified | Last connected-outage scan |',
        '|---|---:|---:|---|---|']
    for c in cases:
        scan=c['latest_scan'];scantext='Not triggered' if scan is None else f"{scan['evaluated']}/389 evaluated; {len(scan['failed'])} unresolved"
        approach=c['campaign'].removeprefix(f"{c['solver']}-{round(c['factor']*10000)}").strip('-')
        label=c['solver']+(f" ({approach})" if approach else '')
        lines.append(f"| {label} | {100*c['factor']:g}% | {c['native_attempts']} | {'Yes' if c['accepted'] else 'No'} | {scantext} |")
    if certificate:
        lines.extend(['','At **110% demand**, the previously independently verified G60 active-loss certificate excludes the original normal-limit, full-demand problem for all three solvers. No redundant local optimization was launched to challenge that proof. This certificate does not cover the separately approved emergency/relief policy. A normal-limit five-demand shared target therefore remains infeasible.'])
    lines+=['','A master model can make two native calls when feasibility-first succeeds and is followed by loss minimization. Separator evaluations and numerical reserve-start QPs are separate from these counts. Intermediate continuation points are not exhaustively qualified.','',
        'One over-budget full-network Ipopt retry was externally stopped during sampled MUMPS factorization; it has no extracted iterate or native infeasibility claim. Exact active-cut checks at 24 demand/outage combinations produced no positive certificate and remain inconclusive. The independently reverified 110% active-loss certificate is the separate conclusive obstruction.','',
        '## Native attempts','','Raw generation minus demand at a rejected iterate is diagnostic; it is not an accepted network-loss objective. A native feasibility-stage success alone is not a successful loss design.','',
        '| Solver/demand | Attempt | Status | Native/model acceptance | Original-network replay | Raw ΣPg−ΣPd (MW) |','|---|---|---|---|---|---:|']
    for c in cases:
        for a in c['attempts']:
            r=a['record'];audit=load(BASE/r['name']/'independent-audit.json')
            loss=r.get('nominal_loss_mw');loss_text=f'{loss:.9f}' if isinstance(loss,(int,float)) and math.isfinite(loss) else '—'
            status=r['solver_status']
            if r.get('feasibility_stage'):
                status=f"feasibility: {r['feasibility_stage']['status']}; loss: "+(r['solver_status'] if r.get('native_optimizer_calls')==2 else 'not run')
            lines.append(f"| {c['solver']} {100*c['factor']:g}% | `{r['name']}` | {status} | {a['accepted']} | {audit['original_network_physical_valid']} | {loss_text} |")
    lines+=['','## Accepted droop designs','',
        'The CSV contains physical slopes, reference voltages and capability limits for every controlled online generator. Solid design curves and operating/equipment figures use qualified designs; the dashed calibrated input is a reference only. Unconverged iterates are excluded. The historical MadNLP nominal design is the comparison anchor.','']
    lines+=['`accepted-droop-designs.csv` retains exhaustively qualified designs. `validated-master-droop-designs.csv` additionally retains every native/physical accepted joint-master design, including intermediate or partially qualified demands; its explicit coverage flag prevents interpreting those rows as all-outage qualification.','',
            'Near-point recovery can initialize from a saved TIME_LIMIT iterate. That iterate is only a numerical start; a fresh native solve and full-network checks determine acceptance. Campaign seed/native fields and actual option records take precedence over inherited generic strategy/initialization labels.','',
            'Imported Julia implementations are retained under `loaded-process-sources/` and in `loaded_*.jl` files. Imports stay loaded across a process; later `executed_*` filesystem copies can reflect compatible source development during the campaign. Native stage records, independent audit hashes and the loaded source snapshots identify the actual run contract.','']
    for name in figures:
        lines.extend([f'![{name}](../../../../docs/src/assets/s2_500bus/solver_demand_qualification/{name}.png)','',f'[PDF](../../../../docs/src/assets/s2_500bus/solver_demand_qualification/{name}.pdf)',''])
    (OUT/'REPORT.md').write_text('\n'.join(lines)+'\n')
    nominal_solvers=['madnlp']+[s for s in ('ipopt','ccopt') if any(c['solver']==s and c['factor']==1 and c['accepted'] for c in cases)]
    status=dict(nominal_connected_qualified_solvers=nominal_solvers,
        independent_demands=[dict(solver=c['solver'],factor=c['factor'],qualified=c['accepted']) for c in cases if c['factor']!=1],
        normal_110_certified_infeasible=certificate is not None,normal_multi_demand_target_accepted=False,
        demand_matrix=matrix,full_n1_accepted=False,closed=False)
    (OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
    (OUT/'RESULTS.json').write_text(json.dumps(dict(cases=cases,demand_matrix=matrix,figures=figures,normal_110_certificate=certificate,full_n1_accepted=False),indent=2)+'\n')
    docs=ROOT/'docs/src/s2_500bus.md';text=docs.read_text();marker='## Solver qualification and independent-demand designs'
    if marker in text:text=text[:text.index(marker)].rstrip()+'\n'
    section=['',marker,'',
        'This follow-up starts from the accepted nominal MadNLP controller and freely redesigns all 51 slopes and references for Ipopt, then CCOpt, before independent-demand designs. Each joint master shares curves across outages and uses contingency addition. Every demand in this campaign retains original normal limits and no relief; emergency/relief studies remain separate. Acceptance requires native convergence and independent original-network replay of all 389 connected outages with a common controller and preventive dispatch.','',
        'Solver labels identify the joint-design backend. The new exhaustive corrective witnesses use Ipopt with the chosen controller and preventive base fixed. Equipment CSVs retain both design and witness solver labels.','',
        *matrix_lines,'',
        'Detailed attempts and selected physical parameters are retained in `artifacts/s2_scopf/ieee500_native/solver_demand_qualification/REPORT.md` and `accepted-droop-designs.csv`. Local numerical failures are unresolved; they do not establish physical infeasibility. No full N-1 or global-optimality claim follows.','']
    for name in figures:section.extend([f'![{name}](assets/s2_500bus/solver_demand_qualification/{name}.png)','',f'[PDF](assets/s2_500bus/solver_demand_qualification/{name}.pdf)',''])
    docs.write_text(text+'\n'.join(section)+'\n')
    if certificate:
        docs.write_text(docs.read_text()+'\nThe 110% normal-limit/full-demand design is excluded for every solver by the independently verified G60 certificate. This does not classify emergency/relief designs. The original normal-limit multi-demand target remains infeasible.\n')
    files=list(OUT.rglob('*.json'))+list(OUT.rglob('*.jl'))+list(OUT.rglob('*.py'))+list(OUT.rglob('*.log'))+list(OUT.glob('*.csv'))+[OUT/'REPORT.md',Path(__file__),ROOT/'examples/audit_s2_500bus_solver_demand.py',ROOT/'examples/s2_500bus_solver_demand_qualification.jl',ROOT/'examples/s2_arpae500_recovery.jl',ROOT/'examples/s2_500bus_independent_demands.jl',ROOT/'examples/check_s2_500bus_solver_demand_audit.py',ROOT/'examples/s2_500bus_independent_continuation.jl',ROOT/'examples/index_s2_500bus_continuation.py',ROOT/'examples/s2_500bus_scaled_mpcc.jl',ROOT/'examples/check_s2_500bus_scaled_mpcc.jl',ROOT/'examples/s2_500bus_network_reduction.jl',docs]+list(FIG.iterdir())
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file() and p.name!='source_manifest.json'}
    (OUT/'source_manifest.json').write_text(json.dumps(hashes,indent=2)+'\n')
    print(json.dumps(dict(cases=[{k:c[k] for k in ('solver','factor','accepted','native_attempts')} for c in cases],hashed_files=len(hashes))))
if __name__=='__main__':main()
