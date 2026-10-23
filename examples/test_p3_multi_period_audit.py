"""Small adversarial checks for independent P3 replay, using the 3-bus witness."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from audit_p3_multi_period import audit_attempt

ROOT=Path(__file__).resolve().parents[1]/'artifacts/p3_multi_period_20261022_v2/3/design'
class ReplayChecks(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.folder=Path(self.tmp.name)/'attempt'
        shutil.copytree(ROOT,self.folder)
    def tearDown(self): self.tmp.cleanup()
    def change(self,name,fn):
        p=self.folder/name;d=json.loads(p.read_text());fn(d);p.write_text(json.dumps(d))
    def test_original(self): self.assertTrue(audit_attempt(self.folder)['valid'])
    def test_objective(self):
        self.change('result.json',lambda d:d.update(objective_mwh=d['objective_mwh']+1))
        self.assertFalse(audit_attempt(self.folder)['valid'])
    def test_ramp(self):
        self.change('contract.json',lambda d:d['ramp_limits'].update({'9':[0.,0.]}))
        self.assertFalse(audit_attempt(self.folder)['valid'])
    def test_durations(self):
        self.change('contract.json',lambda d:d.update(duration_hours=[2.]*5))
        self.assertFalse(audit_attempt(self.folder)['valid'])
    def test_physics(self):
        self.change('result.json',lambda d:d['periods'][1]['state']['qg'].__setitem__(0,.8))
        self.assertFalse(audit_attempt(self.folder)['valid'])
    def test_curves(self):
        self.change('result.json',lambda d:d['droops']['1'].update(slope=1.))
        self.assertFalse(audit_attempt(self.folder)['valid'])
    def test_native_failure(self):
        self.change('result.json',lambda d:d.update(termination_status='TIME_LIMIT'))
        self.assertFalse(audit_attempt(self.folder)['valid'])
if __name__=='__main__': unittest.main()
