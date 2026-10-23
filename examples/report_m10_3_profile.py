"""Verify fixed-equipment profile states and report serial warmed phase medians."""
import csv,hashlib,json,statistics,sys
from pathlib import Path
from report_m10_2_matched import replay
ROOT=Path(__file__).resolve().parents[1]

def report(out):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    protocol=json.loads((out/'protocol.json').read_text());rows=json.loads((out/'attempts.json').read_text())
    assert len(rows)==32
    for path,expected in protocol['hashes'].items():assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==expected,path
    groups=[];phasekeys=['build_seconds','solve_seconds','extraction_seconds','validation_seconds']
    for tag in protocol['tags']:
        rs=[r for r in rows if r['tag']==tag];assert {r['repetition'] for r in rs}=={0,1,2,3}
        for r in rs:
            assert json.loads((out/f'{tag}-{r["repetition"]}.json').read_text())==r
            c=json.loads((out/r['case_file']).read_text())['data']['case']
            audit=replay(c,r['result']);assert audit['valid'] and r['accepted']
            assert all(r[k]>=0 for k in phasekeys)
        timed=[r for r in rs if not r['warmup']]
        groups.append(dict(tag=tag,measured_repetitions=len(timed),accepted=len(timed),
            **{k:statistics.median(r[k] for r in timed) for k in phasekeys},
            julia_allocated_mib=statistics.median(r['julia_allocated_bytes']/1024**2 for r in timed),
            variables=timed[0]['variables'],constraints_including_variable_bounds=timed[0]['constraints_including_variable_bounds']))
    result=dict(status='PASS',accepted_attempts=32,warmups=8,measured_attempts=24,independent_replay_discrepancies=0,
        environment=protocol['environment'],statistics=groups,
        limitations=['Small synthetic fixed-equipment OPF; no SCOPF','Known-witness starts; no unseen-start success claim',
        'No performance-improvement threshold or solver ranking','Julia allocations exclude native allocations',
        'Phase medians need not sum to a median total; runtime/package startup excluded'])
    (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    with (out/'timings.csv').open('w') as f:
        writer=csv.DictWriter(f,fieldnames=list(groups[0]));writer.writeheader();writer.writerows(groups)
    fig,axes=plt.subplots(1,2,figsize=(11,4.2));xs=range(8);bottom=[0.]*8
    for key,label in zip(phasekeys,['Build','Solve','Extract','Validate']):
        values=[r[key]*1000 for r in groups];axes[0].bar(xs,values,bottom=bottom,label=label);bottom=[a+b for a,b in zip(bottom,values)]
    axes[0].set_xticks(list(xs),[r['tag'] for r in groups]);axes[0].set(xlabel='Source nominal design (T/S/D)',ylabel='Median phase time (ms)',title='Serial warmed fixed-equipment OPF');axes[0].legend(fontsize=8)
    axes[1].bar(xs,[r['julia_allocated_mib'] for r in groups]);axes[1].set_xticks(list(xs),[r['tag'] for r in groups]);axes[1].set(xlabel='Source nominal design (T/S/D)',ylabel='Julia allocations (MiB)',title='Optimizer build/solve/extraction allocations')
    fig.tight_layout();fig.savefig(out/'phases.png',dpi=160);plt.close(fig)
    print(json.dumps({k:v for k,v in result.items() if k not in ('statistics','limitations')}))
if __name__=='__main__':report(Path(sys.argv[1]).resolve())
