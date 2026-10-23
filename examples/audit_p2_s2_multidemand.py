"""Cross-demand proof that independently solved dispatches use identical curves."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
load=lambda p:json.loads(Path(p).read_text())
folder=Path(sys.argv[1]);protocol=load(folder/'protocol.json');result=load(folder/'RESULTS.json')
source=Path(protocol['source']);curves=load(source/f"controller-{protocol.get('source_stage','solve')}.json")['data']['case']['controls']
accepted=[]
for row in result['rows']:
    if not row['result']['accepted']:continue
    p=folder/f"stage-{row['stage']}"/'500';audit=load(p/'final-cross-file-audit.json')
    assert audit['exhaustive_accepted'] and audit['accepted_outages']==389
    master=ROOT/row['result']['rounds'][-1]['master']['folder']
    assert load(master/'controller-solve.json')['data']['case']['controls']==curves
    c=load(master/'contract.json');assert c['factors']==[row['factor']] and c['fixed_controller']
    assert c['zero_shedding']==protocol['zero_shedding']
    accepted.append(row['factor'])
r=dict(accepted_factors=accepted,common_controller_verified=bool(accepted),connected_outages_per_demand=389,
       unique_validated_states=390*len(accepted),zero_shedding=protocol['zero_shedding'],
       controller_sha256=hashlib.sha256(json.dumps(curves,sort_keys=True).encode()).hexdigest(),
       physical_infeasibility_proven=False)
(folder/'cross-demand-audit.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))

# Optional coordinator checkpoint, only after saving the validated demand ledger.
if (folder/"checkpoint-after-demand").exists():
    print("Validated demand checkpoint saved; coordinator restart requested")
    sys.exit(75)
