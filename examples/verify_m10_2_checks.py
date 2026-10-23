"""Negative controls for M10.2 independent replay and rational proof verification."""
import copy
from fractions import Fraction
import json
from pathlib import Path
import tempfile
import sys
from report_m10_2_matched import replay
from m10_2_fixedq_certificate import verify

def checks(out):
    row=json.loads((out/'nominal_replay.json').read_text())[0]
    results={}
    bad=copy.deepcopy(row['result']);bad['state']['pg'][0]+=0.01
    assert not replay(row['physical_case'],bad)['valid'];results['corrupted_dispatch']='rejected'
    bad=copy.deepcopy(row['physical_case']);bad['controls'][1]['slope']*=2
    assert not replay(bad,row['result'])['valid'];results['altered_droop_curve']='rejected'
    study=json.loads((out/'cases/111-fixed_q-1.0.json').read_text())['data']
    row=next(x for x in json.loads((out/'attempts.json').read_text()) if x['group']=='111-fixed_q-1.0' and x['start']==1)
    assignments=copy.deepcopy(study['reactive_assignments']);assignments[0]['mode']['q_schedule']+=0.01
    assert not replay(study['case'],row['result'],assignments)['valid'];results['altered_fixed_q_target']='rejected'
    cert=json.loads((out/'fixedq_certificate/certificate.json').read_text());case=out/'cases/111-fixed_q-1.05.json'
    active=max(range(len(cert['psd_directions'])),key=lambda i:Fraction(cert['nonnegative_multipliers'][12+i]))
    assert Fraction(cert['nonnegative_multipliers'][12+active])>0
    with tempfile.TemporaryDirectory(prefix='m10-proof-negative-') as temp:
        path=Path(temp)/'certificate.json'
        for label in ('zero_weights','changed_input_hash','changed_active_direction'):
            bad=copy.deepcopy(cert)
            if label=='zero_weights':bad['nonnegative_multipliers']=['0']*len(bad['nonnegative_multipliers'])
            elif label=='changed_input_hash':bad['case_sha256']='0'*64
            else:bad['psd_directions'][active]=[['0','0']]*3
            path.write_text(json.dumps(bad))
            try:verify(case,path)
            except AssertionError:results[label]='rejected'
            else:raise AssertionError(label)
    (out/'verification_tests.json').write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps(results))

if __name__=='__main__':checks(Path(sys.argv[1]).resolve())
