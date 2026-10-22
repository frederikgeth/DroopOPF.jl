"""Recheck M10.1/M10.2 evidence without launching an optimization."""
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
from report_m10_1_reference import table,reference,ATOL,RTOL
from report_m10_2_matched import replay
from m10_2_fixedq_certificate import verify
from verify_m10_2_checks import checks

ROOT=Path(__file__).resolve().parents[1]

def verify_all(out):
    out.mkdir(parents=True,exist_ok=True)
    a=ROOT/'artifacts/m10_1_reference';b=ROOT/'artifacts/m10_2_matched';hashes=0
    manifests=[json.loads((a/'manifest.json').read_text())['hashes'],json.loads((b/'protocol.json').read_text())['source_hashes'],
        json.loads((b/'protocol.json').read_text())['code_environment_hashes'],json.loads((b/'closeout_manifest.json').read_text())]
    for manifest in manifests:
        for name,expected in manifest.items():
            assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected,('changed artifact',name)
            hashes+=1
    inputs=json.loads((a/'inputs.json').read_text())['snapshots'];actual=json.loads((a/'actual.json').read_text())['snapshots'];count=0
    for point,got in zip(inputs,actual):
        assert point['id']==got['id'];text=Path(point['case_path']).read_text()
        raw=reference(table(text,'bus'),table(text,'branch'),point['vm'],point['va'],100.)
        raw['from']=raw.pop('from_');raw['ybus_injection']=raw['injection']
        for key in ('from','to','shunts','injection','ybus_injection'):
            assert len(raw[key])==len(got[key])
            for exp,obs in zip(raw[key],got[key]):
                for x,y in zip(exp,obs):assert math.isfinite(y) and abs(x-y)<=ATOL+RTOL*abs(x);count+=1
    assert len(inputs)==len(actual)==3 and count==414
    nominal=json.loads((b/'nominal_replay.json').read_text());assert len(nominal)==16
    for r in nominal:assert replay(r['physical_case'],r['result'])['valid']
    attempts=json.loads((b/'attempts.json').read_text());assert len(attempts)==110;accepted=0
    for r in attempts:
        study=json.loads((b/r['case_file']).read_text())['data']
        check=replay(study['case'],r.get('result',{}),study['reactive_assignments'])
        native=r.get('result',{}).get('termination_status') in ('OPTIMAL','LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED')
        assert (check['valid'] and native)==r['valid'];accepted+=r['valid']
    assert accepted==108
    # Exercise the complete original report's coverage/settings checks in an
    # isolated copy. Its exit 1 is expected: the original all-feasible gate failed.
    with tempfile.TemporaryDirectory(prefix='m10-reproduce-') as temp:
        copy=Path(temp)/'matched';shutil.copytree(b,copy)
        command=[sys.executable,str(ROOT/'examples/report_m10_2_matched.py'),str(copy)]
        result=subprocess.run(command,capture_output=True,text=True)
        (out/'m10_2_report_reproduction.log').write_text(result.stdout+result.stderr)
        assert result.returncode==1 and 'Incomplete M10.2' in result.stderr,result.stderr
        regenerated=json.loads((copy/'RESULTS.json').read_text());original=json.loads((b/'RESULTS.json').read_text())
        assert regenerated==original,'Regenerated numerical report differs'
    certificate=verify(b/'cases/111-fixed_q-1.05.json',b/'fixedq_certificate/certificate.json')
    # Run negative controls into a copy so original artifacts stay unchanged.
    with tempfile.TemporaryDirectory(prefix='m10-checks-') as temp:
        copy=Path(temp)/'matched';shutil.copytree(b,copy);checks(copy)
        negative=json.loads((copy/'verification_tests.json').read_text())
        assert negative==json.loads((b/'verification_tests.json').read_text())
    result=dict(status='PASS',hash_checks=hashes,m10_1_scalar_checks=count,m10_2_saved_nominal_replays=16,
        m10_2_operating_state_replays=110,m10_2_accepted_operating_states=108,m10_2_expected_rejections=2,
        m10_2_numerical_report_reproduced_exactly=True,m10_2_original_all_feasible_gate_passed=False,
        certificate=certificate,negative_controls=len(negative),new_optimization_runs=0)
    (out/'reproducibility.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

if __name__=='__main__':verify_all(Path(sys.argv[1]).resolve())
