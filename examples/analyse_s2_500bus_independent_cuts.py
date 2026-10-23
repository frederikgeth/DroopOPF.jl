"""Exact passive-network active-cut bounds; no AC or other optimizer calls."""
from collections import deque
from fractions import Fraction as F
from pathlib import Path
import hashlib
import json
import sys
sys.setrecursionlimit(3000)
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'

def cut(case,factor,event):
    buses=case['network']['buses'];ix={b['id']:i for i,b in enumerate(buses)};n=len(buses);s=n;t=n+1;graph=[[] for _ in range(n+2)]
    def edge(i,j,cap):
        a=[j,len(graph[j]),cap];b=[i,len(graph[i]),F(0)];graph[i].append(a);graph[j].append(b)
    kind,number=event.split('_');number=int(number)
    branch=[b for b in case['network']['branches'] if b['available'] and not(kind=='branch' and b['id']==number)]
    assert all(b['resistance']>=0 for b in branch)
    assert all(a['conductance']>=0 for a in case['network']['shunts'] if a['available'])
    assert all(min(a['step_conductances'])>=0 for a in case['network']['banks'])
    caps={g['id']:g['p_max'] for g in case['generators']}
    for a in case['attachments']:caps[a['generator_id']]=min(caps[a['generator_id']],case['controls'][a['control_id']-1]['capability']['p_max'])
    available=[g for g in case['generators'] if g['available'] and not(kind=='generator' and g['id']==number)]
    for g in available:edge(s,ix[g['bus_id']],F(caps[g['id']]))
    loads=[(l,F(l['p']*factor)) for l in case['loads']];demand=sum((p for _,p in loads if p>0),F(0))
    for l,p in loads:
        if p>0:edge(ix[l['bus_id']],t,p)
        elif p<0:edge(s,ix[l['bus_id']],-p)
    for b in branch:
        edge(ix[b['from_bus']],ix[b['to_bus']],F(b['thermal_limit']))
        edge(ix[b['to_bus']],ix[b['from_bus']],F(b['thermal_limit']))
    flow=F(0)
    while True:
        level=[-1]*(n+2);level[s]=0;q=deque([s])
        while q:
            i=q.popleft()
            for j,rev,cap in graph[i]:
                if cap>0 and level[j]<0:level[j]=level[i]+1;q.append(j)
        if level[t]<0:break
        cursor=[0]*(n+2)
        def send(i,amount):
            if i==t:return amount
            while cursor[i]<len(graph[i]):
                e=graph[i][cursor[i]];j,rev,cap=e
                if cap>0 and level[j]==level[i]+1:
                    moved=send(j,min(amount,cap))
                    if moved>0:e[2]-=moved;graph[j][rev][2]+=moved;return moved
                cursor[i]+=1
            return F(0)
        while True:
            moved=send(s,demand-flow)
            if moved<=0:break
            flow+=moved
        if flow==demand:break
    reach={s};q=deque([s])
    while q:
        for j,rev,cap in graph[q.popleft()]:
            if cap>0 and j not in reach:reach.add(j);q.append(j)
    region={b['id'] for b in buses if ix[b['id']] not in reach}
    boundary=[b for b in branch if (b['from_bus'] in region)!=(b['to_bus'] in region)]
    generation=[g for g in available if g['bus_id'] in region]
    deficit=sum((p for l,p in loads if l['bus_id'] in region),F(0))-sum((F(caps[g['id']]) for g in generation),F(0))-sum((F(b['thermal_limit']) for b in boundary),F(0))
    assert deficit<=demand-flow
    inactive=sum(g['bus_id'] in region and g not in available for g in case['generators'])
    tolerance=F(1e-6)*(len(region)+len(generation)+len(boundary))+F(1e-8)*inactive
    positive=deficit>tolerance
    return dict(factor=factor,event=event,certified_infeasible=positive,active_cut_deficit_mw=float(deficit)*case['base_power'],
        tolerance_robust_gap_mw=float(deficit-tolerance)*case['base_power'],deficit_exact_pu=str(deficit),tolerance_exact_pu=str(tolerance),
        cut_bus_ids=sorted(region) if positive else [],cut_branch_ids=[b['id'] for b in boundary] if positive else [],
        caveat='Only a positive tolerance-robust cut deficit is an infeasibility proof; no deficit is inconclusive. Original normal limits/full demand only.')

def main():
    source=BASE/'pilot_study.json';case=json.loads(source.read_text())['data']['case']
    rows=[cut(case,f,event) for f in (.9,.95,1.,1.025,1.05,1.1) for event in ('branch_36','branch_562','generator_14','generator_60')]
    report=dict(optimizer_calls=0,arithmetic='exact rational arithmetic on original IEEE-754 source and scaled-demand values',source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        criterion='Cut demand cannot exceed local effective generator Pmax plus original terminal Rate-A import bounds in a passive network.',checks=rows)
    dest=BASE/'solver_demand_qualification/active-cut-checks.json';dest.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(optimizer_calls=0,checks=len(rows),certificates=[r for r in rows if r['certified_infeasible']])))
if __name__=='__main__':main()
