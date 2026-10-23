"""Scientific operating/control envelopes of a qualified emergency controller."""
import copy
import csv
import json
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from s2_followup_physics import check_case

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'targeted_demand_diagnostics'
FIG=ROOT/'docs/src/assets/s2_500bus_targeted'
load=lambda p:json.loads(p.read_text())


def figures(summary):
    if not summary['qualified']:return []
    factor=summary['factor'];label=f'emergency-{round(factor*10000)}'
    group=next(r for r in summary['rounds'] if r['coverage'] and r['coverage']['accepted'])
    master=BASE/group['selected_path'];stage=group['selected_stage']
    study=load(master/f'controller-{stage}.json')['data']
    raw=load(master/f'point-{stage}.json')['states']
    base=next(r for r in raw if r['factor']==factor and r['id']=='base')
    scan=load(BASE/f"emergency_loadability/coverage/targeted-{label}-round-{group['round']}/summary.json")
    states=[base]
    witness_path=OUT/f'selected-operating-witnesses-{round(factor*10000)}.json'
    entries=load(witness_path)['entries'] if witness_path.exists() else scan['rows'][0]['rows']
    for entry in entries:
        assert entry['accepted']
        rows=load(BASE/'emergency_loadability'/entry['path']/f"point-{entry['stage']}.json")['states']
        states.append(next(r for r in rows if r['factor']==factor and r['id']==entry['event']))
    assert len(states)==390 and len({r['id'] for r in states})==390
    source=study['case'];angles=load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    gens=[(i,g) for i,g in enumerate(source['generators']) if g['available']]
    branches=[b for b in source['network']['branches'] if b['available']]
    bounds={g['id']:[g['p_min'],g['p_max'],g['q_min'],g['q_max']] for _,g in gens}
    for a in source['attachments']:
        cap=source['controls'][a['control_id']-1]['capability'];b=bounds[a['generator_id']]
        b[0]=max(b[0],cap['p_min']);b[1]=min(b[1],cap['p_max']);b[2]=max(b[2],cap['q_min']);b[3]=min(b[3],cap['q_max'])
    loading=[];p=[];q=[];voltages=[];taps=[];banks=[];control_rows=[]
    for r in states:
        case=copy.deepcopy(source);sid=r['id'];post=sid!='base'
        for l in case['loads']:
            oldp=l['p'];relief=r['dr'][str(l['id'])]+r['shed'][str(l['id'])]
            l['p']=oldp*factor-relief;l['q']=l['q']*factor-(l['q']/oldp*relief if oldp>0 else 0.)
        if sid.startswith('generator_'):
            next(g for g in case['generators'] if g['id']==int(sid.split('_')[1]))['available']=False
        if sid.startswith('branch_'):
            next(b for b in case['network']['branches'] if b['id']==int(sid.split('_')[1]))['available']=False
        if post:
            for b in case['network']['buses']:b['v_min']-=.05;b['v_max']+=.05
            for b in case['network']['branches']:b['thermal_limit']*=1.1
        check=check_case(case,r['state'],r['taps'],r['banks'],angles)
        assert check['valid'],sid
        flows=check['branch_max_terminal_s_pu']
        loading.append([flows.get(str(b['id']),np.nan)/b['thermal_limit'] for b in branches])
        p.append([r['state']['pg'][i]*source['base_power'] for i,g in gens])
        q.append([r['state']['qg'][i]*source['base_power'] for i,g in gens]);voltages.append(r['state']['vm'])
        taps.append([r['taps'].get(str(t['branch_id']),np.nan) for t in study['tap_controls']])
        banks.append([r['banks'][str(b['bank_id'])] for b in study['shunt_controls']])
        for family,settings,key in (('tap',r['taps'],'tap_controls'),('shunt',r['banks'],'shunt_controls')):
            idkey='branch_id' if family=='tap' else 'bank_id'
            for control in study[key]:
                value=settings.get(str(control[idkey]));control_rows.append(dict(factor=factor,scenario=sid,family=family,
                    id=control[idkey],available=value is not None,value=value,lower=control['lower'],upper=control['upper']))
    FIG.mkdir(exist_ok=True)
    fig,axes=plt.subplots(4,1,figsize=(15,13),constrained_layout=True)
    def envelope(ax,x,values):
        a=np.array(values);ax.fill_between(x,np.nanmin(a[1:],axis=0),np.nanmax(a[1:],axis=0),alpha=.3,label='All 389 corrective cases')
        ax.plot(x,a[0],color='black',lw=.8,label='Base case');ax.grid(alpha=.2)
    gids=[g['id'] for _,g in gens];scale=source['base_power']
    for ax,values,offset,ylabel in ((axes[0],p,0,'Active generation (MW)'),(axes[1],q,2,'Reactive generation (MVAr)')):
        envelope(ax,gids,values);ax.plot(gids,[bounds[i][offset]*scale for i in gids],'r--',lw=.8,label='Hard bounds')
        ax.plot(gids,[bounds[i][offset+1]*scale for i in gids],'r--',lw=.8);ax.set_ylabel(ylabel);ax.set_xlabel('Generator ID')
    buses=source['network']['buses'];ids=[b['id'] for b in buses]
    envelope(axes[2],ids,voltages)
    for sign in (-1,1):
        key='v_min' if sign<0 else 'v_max'
        axes[2].plot(ids,[b[key] for b in buses],color='gray',ls=':',lw=.8,label='Normal voltage bounds' if sign<0 else None)
        axes[2].plot(ids,[b[key]+sign*.05 for b in buses],'r--',lw=.8,label='Emergency voltage caps' if sign<0 else None)
    axes[2].set_ylabel('Voltage magnitude (pu)');axes[2].set_xlabel('Bus ID')
    envelope(axes[3],[b['id'] for b in branches],loading)
    axes[3].axhline(1.,color='gray',ls=':',label='Normal Rate A');axes[3].axhline(1.1,color='red',ls='--',label='Emergency study cap')
    axes[3].set_ylabel('Max terminal |S| / Rate A');axes[3].set_xlabel('Original branch / transformer ID')
    for ax in axes:ax.legend(loc='upper right',ncol=3,fontsize=8)
    fig.suptitle(f'{factor:.0%} emergency controller — original 500-bus network, base + 389 connected outages\nNative accepted witnesses; selected controller is not a completed loss optimum')
    names=[label+'-all-operating-states']
    fig.savefig(FIG/f'{names[-1]}.png',dpi=160);fig.savefig(FIG/f'{names[-1]}.pdf');plt.close(fig)
    fig,axes=plt.subplots(2,1,figsize=(15,8),constrained_layout=True)
    for ax,values,controls,idkey,ylabel in ((axes[0],taps,study['tap_controls'],'branch_id','Transformer tap ratio'),
        (axes[1],banks,study['shunt_controls'],'bank_id','Continuous shunt susceptance (pu)')):
        ids=[c[idkey] for c in controls];envelope(ax,ids,values)
        ax.plot(ids,[c['lower'] for c in controls],'r--',lw=.8,label='Confirmed bounds');ax.plot(ids,[c['upper'] for c in controls],'r--',lw=.8)
        ax.set_ylabel(ylabel);ax.set_xlabel('Original equipment ID');ax.legend(ncol=3)
    fig.suptitle(f'{factor:.0%} emergency corrective equipment — base + 389 connected outages\nOutaged taps excluded from operating envelopes; continuous shunts')
    names.append(label+'-all-equipment-states')
    fig.savefig(FIG/f'{names[-1]}.png',dpi=160);fig.savefig(FIG/f'{names[-1]}.pdf');plt.close(fig)
    with (OUT/f'{label}-equipment-values.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(control_rows[0]));writer.writeheader();writer.writerows(control_rows)
    (OUT/f'{label}-plot-validation.json').write_text(json.dumps(dict(original_network_states=390,
        all_states_physical_valid=True,equipment_rows=len(control_rows),figures=names,
        branch_metric='Both-terminal apparent flow / original Rate A; outaged devices excluded',
        optimizer_calls=0),indent=2)+'\n')
    return names
