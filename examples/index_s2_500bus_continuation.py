"""Index fully qualified continuation points without discarding direct attempts."""
import json
from pathlib import Path
from audit_s2_500bus_solver_demand import campaign,OUT,load
ROOT=OUT/'solver_demand_qualification'
def main():
    console=(ROOT/'recovery-and-independent-console.log').read_text()
    rows=[]
    for factor in (.9,.95,1.05):
        key=round(factor*10000);source=ROOT/f'summary-ipopt-{key}-continuation.json'
        if not source.exists() or not load(source)['accepted']:continue
        target=ROOT/f'summary-ipopt-{key}.json'
        if target.exists():
            old=load(target)
            if old.get('alias_of')==source.name or old['accepted']:continue
            if f'SDQ COMPLETE ipopt-{key} ' not in console:continue
            archive=ROOT/f'summary-ipopt-{key}-direct.json'
            if archive.exists():assert archive.read_bytes()==target.read_bytes()
            else:archive.write_bytes(target.read_bytes())
        elif (ROOT/f'protocol-ipopt-{key}.json').exists():
            continue
        assert campaign(source)['accepted']
        value=load(source);value['alias_of']=source.name
        value['index_note']='Canonical demand index reuses the qualified continuation design. No additional optimizer call. Direct-attempt history, if present, is preserved separately.'
        target.write_text(json.dumps(value,indent=2)+'\n')
        rows.append(dict(factor=factor,source=source.name,index=target.name))
    print(json.dumps(rows))
if __name__=='__main__':main()
